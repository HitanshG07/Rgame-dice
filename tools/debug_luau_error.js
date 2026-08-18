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

const fileContent = fs.readFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', 'utf8');

rl.on('line', (line) => {
    let msg;
    try { msg = JSON.parse(line); } catch (e) { return; }
    
    if (msg.id === 1) {
        const code = `
            local fn, compileErr = loadstring(${JSON.stringify(fileContent)})
            if not fn then
                return "COMPILE_ERR: " .. tostring(compileErr)
            end
            local ok, runErr = pcall(fn)
            if not ok then
                return "RUNTIME_ERR: " .. tostring(runErr)
            end
            return "MODULE_LOADED_OK"
        `;
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: 2,
            method: 'tools/call',
            params: {
                name: 'execute_luau',
                arguments: {
                    code: code,
                    datamodel_type: 'Client',
                    studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
                }
            }
        }) + '\n');
    } else if (msg.id === 2) {
        console.log('Error details:', JSON.stringify(msg.result));
        child.kill();
        process.exit(0);
    }
});

child.stdin.write(JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'Debugger', version: '1.0' }
    }
}) + '\n');
