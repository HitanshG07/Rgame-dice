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

rl.on('line', (line) => {
    let msg;
    try { msg = JSON.parse(line); } catch (e) { return; }
    
    if (msg.id === 1) {
        // initialize done, send screen capture
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: 2,
            method: 'tools/call',
            params: {
                name: 'screen_capture',
                arguments: {
                    studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
                }
            }
        }) + '\n');
    } else if (msg.id === 2) {
        if (msg.result && msg.result.content) {
            for (const item of msg.result.content) {
                if (item.data) {
                    fs.writeFileSync('C:\\RGame\\screenshots\\studio_live_screen.png', Buffer.from(item.data, 'base64'));
                    console.log('SAVED SCREENSHOT TO screenshots/studio_live_screen.png, size:', item.data.length);
                }
            }
        }
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
        clientInfo: { name: 'Test', version: '1.0' }
    }
}) + '\n');
