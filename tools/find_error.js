const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const readline = require('readline');

const versionsDir = path.join(process.env.LOCALAPPDATA, 'Roblox', 'Versions');
let studioMcpPath = null;
let newestTime = 0;
for (const entry of fs.readdirSync(versionsDir)) {
    const full = path.join(versionsDir, entry, 'StudioMCP.exe');
    if (fs.existsSync(full)) {
        const stat = fs.statSync(full);
        if (stat.mtimeMs > newestTime) {
            newestTime = stat.mtimeMs;
            studioMcpPath = full;
        }
    }
}

const child = spawn(studioMcpPath, [], { stdio: ['pipe', 'pipe', 'pipe'] });
const rl = readline.createInterface({ input: child.stdout, terminal: false });

let reqId = 0;
const pending = new Map();

rl.on('line', (line) => {
    try {
        const msg = JSON.parse(line);
        if (msg.id && pending.has(msg.id)) {
            const resolve = pending.get(msg.id);
            pending.delete(msg.id);
            resolve(msg);
        }
    } catch (e) {}
});

function callTool(name, args) {
    return new Promise((resolve) => {
        reqId++;
        pending.set(reqId, resolve);
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: reqId,
            method: 'tools/call',
            params: { name, arguments: args }
        }) + '\n');
    });
}

function initialize() {
    return new Promise((resolve) => {
        reqId++;
        pending.set(reqId, resolve);
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: reqId,
            method: 'initialize',
            params: {
                protocolVersion: '2024-11-05',
                capabilities: {},
                clientInfo: { name: 'FindError', version: '1.0' }
            }
        }) + '\n');
    });
}

async function main() {
    await initialize();

    const fullSrc = fs.readFileSync('C:\\RGame\\src\\Client\\V7MenuPanel.luau', 'utf8');

    // Create a server script in Workspace to get the compile error message from Studio!
    const testCode = `
        local s = Instance.new("Script")
        s.Name = "TestCompileScript"
        s.Source = ${JSON.stringify(fullSrc)}
        s.Parent = workspace
        return "Script created in workspace"
    `;

    const res = await callTool('execute_luau', { code: testCode, datamodel_type: 'Server' });
    console.log('Server result:', res);

    const checkLogCode = `
        local logs = game:GetService("LogService"):GetLogHistory()
        local errs = {}
        for _, entry in ipairs(logs) do
            if entry.messageType == Enum.MessageType.MessageError or entry.messageType == Enum.MessageType.MessageWarning then
                table.insert(errs, entry.message)
            end
        end
        return table.concat(errs, "\\n")
    `;
    const logRes = await callTool('execute_luau', { code: checkLogCode, datamodel_type: 'Server' });
    console.log('Log history:', logRes);

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
