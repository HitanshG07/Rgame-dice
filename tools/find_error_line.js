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

const fileLines = fs.readFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', 'utf8').split('\n');

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
            params: { name: name, arguments: args }
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
                clientInfo: { name: 'BinarySearch', version: '1.0' }
            }
        }) + '\n');
    });
}

async function testRange(numLines) {
    const src = fileLines.slice(0, numLines).join('\n') + '\nreturn UIMockPreview';
    const code = `
        local lp = game:GetService("Players").LocalPlayer
        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
        local mod = Instance.new("ModuleScript")
        mod.Source = ${JSON.stringify(src)}
        mod.Parent = ps
        local ok, err = pcall(function() return require(mod) end)
        mod:Destroy()
        return { ok = ok, err = tostring(err) }
    `;
    const res = await callTool('execute_luau', {
        code: code,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });
    return res;
}

async function main() {
    await initialize();
    console.log('Testing line ranges...');
    
    for (let count = 10; count <= 150; count += 10) {
        const res = await testRange(count);
        console.log(`Lines 0..${count}:`, JSON.stringify(res.result));
    }
    const fullRes = await testRange(fileLines.length);
    console.log(`Full file (${fileLines.length} lines):`, JSON.stringify(fullRes.result));
    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
