const { spawn } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

// --- Logging budget -------------------------------------------------------
// This proxy previously logged every message in both directions verbatim with
// fs.appendFileSync. Screen captures travel through as multi-megabyte base64
// strings, so each one was buffered as a JS string, concatenated into a
// template literal and written synchronously on the main thread. The live
// copy's log reached 56MB and the cost of producing it contributed to the
// out-of-memory crashes of 2026-08-13, -18 and -19.
//
// Logging is kept, because it is what made those crashes diagnosable. It is
// bounded instead: every entry is truncated, base64 payloads are summarised
// rather than written, and the file rotates so it cannot grow without limit.
const MAX_LOG_LINE = 2048;             // characters per entry
const MAX_LOG_BYTES = 5 * 1024 * 1024; // rotate at 5MB, keeping one old file

const logFile = path.join(__dirname, 'mcp_proxy.log');
const logFilePrev = logFile + '.1';

function rotateIfNeeded() {
    try {
        const stat = fs.statSync(logFile);
        if (stat.size < MAX_LOG_BYTES) return;
        try {
            fs.unlinkSync(logFilePrev);
        } catch (e) {
            if (e.code !== 'ENOENT') throw e;
        }
        fs.renameSync(logFile, logFilePrev);
    } catch (e) {
        // ENOENT just means the log does not exist yet. Any other failure is
        // swallowed deliberately: the transport matters, the diary does not.
    }
}

// Replaces long base64 blobs with a summary so image data never lands in the
// log as literal characters. Matches the "data" field of an MCP image item.
function summarisePayloads(text) {
    return text.replace(
        /"data"\s*:\s*"([A-Za-z0-9+/=]{256,})"/g,
        (match, blob) => '"data":"<' + blob.length + ' base64 chars omitted>"'
    );
}

function truncate(text) {
    if (text.length <= MAX_LOG_LINE) return text;
    return text.slice(0, MAX_LOG_LINE) + ' … <truncated, ' + text.length + ' chars total>';
}

function log(msg) {
    try {
        rotateIfNeeded();
        const safe = truncate(summarisePayloads(String(msg)));
        fs.appendFileSync(logFile, `[${new Date().toISOString()}] ${safe}\n`);
    } catch (e) {}
}

log('Proxy process started');

// Find the newest StudioMCP.exe
const versionsDir = path.join(process.env.LOCALAPPDATA, 'Roblox', 'Versions');
let studioMcpPath = null;
let newestTime = 0;

try {
    const entries = fs.readdirSync(versionsDir);
    for (const entry of entries) {
        const full = path.join(versionsDir, entry, 'StudioMCP.exe');
        if (fs.existsSync(full)) {
            const stat = fs.statSync(full);
            if (stat.mtimeMs > newestTime) {
                newestTime = stat.mtimeMs;
                studioMcpPath = full;
            }
        }
    }
} catch (err) {
    log('Error reading versions directory: ' + err);
}

if (!studioMcpPath) {
    log('StudioMCP.exe could not be found');
    process.exit(1);
}

log('Using latest StudioMCP at: ' + studioMcpPath);

const child = spawn(studioMcpPath, [], {
    stdio: ['pipe', 'pipe', 'pipe']
});

let isInitialized = false;

// --- Child lifecycle ------------------------------------------------------
// Antigravity logged "McpServers (unknown): failed to stop existing instance"
// nine times because the proxy could exit without killing StudioMCP.exe. Each
// orphan held its own buffers, so restarts accumulated processes rather than
// replacing them. Every exit path now takes the child with it.
let childExited = false;

child.on('exit', (code) => {
    childExited = true;
    log('StudioMCP exited with code ' + code);
    process.exit(code || 0);
});

function killChild() {
    if (childExited) return;
    try {
        child.kill();
    } catch (e) {
        log('Error killing StudioMCP: ' + e);
    }
}

function shutdown(reason) {
    log('Proxy shutting down: ' + reason);
    killChild();
    process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGHUP', () => shutdown('SIGHUP'));
process.on('exit', killChild);

const rlClient = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});

const rlServer = readline.createInterface({
    input: child.stdout,
    terminal: false
});

// Screenshots are written to exactly one directory. The previous version also
// wrote every image a second time to a misspelled "screensots" folder, which
// doubled both the decode cost and the disk write for no benefit.
const screenshotDir = path.join('C:', 'RGame', 'screenshots');

// Capture requests are tracked BY REQUEST ID, not as a single "pending" slot.
// A lone pending variable is claimed by whichever reply arrives next — during
// testing the `initialize` response consumed the capture and the screenshot was
// silently never written. JSON-RPC replies carry the id of their request, so
// matching on it is what makes the save reliable when responses interleave.
const pendingCaptures = new Map();

rlServer.on('line', (line) => {
    if (!line.trim()) return;

    if (pendingCaptures.size > 0) {
        try {
            const resp = JSON.parse(line);
            const captureId = (resp.id !== undefined) ? pendingCaptures.get(resp.id) : undefined;
            if (captureId !== undefined) {
                pendingCaptures.delete(resp.id);
                if (resp.result && resp.result.content) {
                    for (const item of resp.result.content) {
                        if (item.type === 'image' && item.data) {
                            const buffer = Buffer.from(item.data, 'base64');
                            if (!fs.existsSync(screenshotDir)) {
                                fs.mkdirSync(screenshotDir, { recursive: true });
                            }
                            const filename = captureId.endsWith('.png') ? captureId : (captureId + '.png');
                            fs.writeFileSync(path.join(screenshotDir, filename), buffer);
                            log('Saved screenshot to: ' + path.join(screenshotDir, filename));
                        }
                    }
                }
            }
        } catch (e) {
            log('Error saving screenshot: ' + e);
        }
    }

    log('SERVER -> CLIENT: ' + line);
    process.stdout.write(line + '\n');
});

child.stderr.on('data', (data) => {
    log('SERVER STDERR: ' + data.toString().trim());
});

// --- Backpressure ---------------------------------------------------------
// child.stdin.write() returns false when the pipe buffer is full. The previous
// version ignored that, so while StudioMCP was unresponsive — it hit four
// three-minute timeouts on 2026-08-19 — Node queued every pending message in
// memory with no ceiling. Writes now pause the client reader until the pipe
// drains, propagating the stall backwards instead of absorbing it into RAM.
let clientPaused = false;

child.stdin.on('drain', () => {
    if (clientPaused) {
        clientPaused = false;
        rlClient.resume();
        log('StudioMCP stdin drained — resuming client reader');
    }
});

child.stdin.on('error', (err) => {
    log('Error writing to StudioMCP stdin: ' + err);
});

function writeToChild(line) {
    const ok = child.stdin.write(line + '\n');
    if (!ok && !clientPaused) {
        clientPaused = true;
        rlClient.pause();
        log('StudioMCP stdin backpressure — pausing client reader until drain');
    }
}

rlClient.on('line', (line) => {
    if (!line.trim()) return;
    log('CLIENT -> SERVER: ' + line);
    try {
        const msg = JSON.parse(line);
        if (msg.method === 'tools/call' && msg.params && msg.params.name === 'screen_capture' && msg.id !== undefined) {
            const captureId = (msg.params.arguments && msg.params.arguments.capture_id) ? msg.params.arguments.capture_id : ('capture_' + Date.now());
            pendingCaptures.set(msg.id, captureId);
            log('Screen capture requested with ID: ' + captureId + ' (request ' + msg.id + ')');
        }
        // Antigravity IDE sends 'server/discover' before initialization as a probe.
        // StudioMCP strictly requires 'initialize' as the first request and crashes if it receives custom requests before initialization.
        if (msg.method === 'server/discover' && !isInitialized) {
            const resp = {
                jsonrpc: '2.0',
                id: msg.id,
                error: {
                    code: -32601,
                    message: 'Method not found'
                }
            };
            log('PROXY INTERCEPT -> CLIENT: ' + JSON.stringify(resp));
            process.stdout.write(JSON.stringify(resp) + '\n');
            return;
        }
        if (msg.method === 'initialize') {
            isInitialized = true;
        }
    } catch (e) {
        log('Error parsing JSON from client: ' + e);
    }
    writeToChild(line);
});

// When the client's stdin closes, the host is done sending requests — but
// replies may still be in flight, and a slow execute_luau can take minutes.
// Closing the child's stdin signals end-of-input without discarding those
// replies; the proxy then exits via the child's own 'exit' handler once it
// finishes. A bounded grace period guarantees termination if the child hangs,
// so this can never become the orphan it was written to prevent.
const SHUTDOWN_GRACE_MS = 10000;

rlClient.on('close', () => {
    log('Client stdin closed — ending child input, awaiting pending replies');
    try {
        child.stdin.end();
    } catch (e) {
        log('Error ending StudioMCP stdin: ' + e);
    }
    const timer = setTimeout(() => {
        log('Grace period elapsed with child still running — forcing shutdown');
        shutdown('grace period elapsed');
    }, SHUTDOWN_GRACE_MS);
    if (typeof timer.unref === 'function') timer.unref();
});
