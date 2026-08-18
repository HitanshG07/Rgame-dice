const { spawn } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

const logFile = path.join(__dirname, 'mcp_proxy.log');
function log(msg) {
    try {
        fs.appendFileSync(logFile, `[${new Date().toISOString()}] ${msg}\n`);
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

const rlClient = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});

const rlServer = readline.createInterface({
    input: child.stdout,
    terminal: false
});

let pendingCaptureId = null;

rlServer.on('line', (line) => {
    if (line.trim()) {
        if (pendingCaptureId) {
            try {
                const resp = JSON.parse(line);
                if (resp.result && resp.result.content) {
                    for (const item of resp.result.content) {
                        if (item.type === 'image' && item.data) {
                            const buffer = Buffer.from(item.data, 'base64');
                            const dir1 = path.join('C:', 'RGame', 'screenshots');
                            const dir2 = path.join('C:', 'RGame', 'screensots');
                            if (!fs.existsSync(dir1)) fs.mkdirSync(dir1, { recursive: true });
                            if (!fs.existsSync(dir2)) fs.mkdirSync(dir2, { recursive: true });
                            const filename = pendingCaptureId.endsWith('.png') ? pendingCaptureId : (pendingCaptureId + '.png');
                            fs.writeFileSync(path.join(dir1, filename), buffer);
                            fs.writeFileSync(path.join(dir2, filename), buffer);
                            log('Saved screenshot to: ' + path.join(dir1, filename));
                        }
                    }
                }
            } catch (e) {
                log('Error saving screenshot: ' + e);
            }
            pendingCaptureId = null;
        }
        process.stdout.write(line + '\n');
    }
});

child.stderr.on('data', (data) => {
    log('SERVER STDERR: ' + data.toString().trim());
});

child.on('exit', (code) => {
    log('StudioMCP exited with code ' + code);
    process.exit(code || 0);
});

rlClient.on('line', (line) => {
    if (!line.trim()) return;
    try {
        const msg = JSON.parse(line);
        if (msg.method === 'tools/call' && msg.params && msg.params.name === 'screen_capture') {
            pendingCaptureId = (msg.params.arguments && msg.params.arguments.capture_id) ? msg.params.arguments.capture_id : ('capture_' + Date.now());
            log('Screen capture requested with ID: ' + pendingCaptureId);
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
            process.stdout.write(JSON.stringify(resp) + '\n');
            return;
        }
        if (msg.method === 'initialize') {
            isInitialized = true;
        }
    } catch (e) {
        log('Error parsing JSON from client: ' + e);
    }
    child.stdin.write(line + '\n');
});
