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

rl.on('line', async (line) => {
    let msg;
    try { msg = JSON.parse(line); } catch (e) { return; }
    
    if (msg.id === 1) {
        // initialize response
        const code = `
            local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
            if sp then
                local mod = sp:FindFirstChild("UIMockPreview")
                if not mod then
                    mod = Instance.new("ModuleScript")
                    mod.Name = "UIMockPreview"
                    mod.Parent = sp
                end
                mod.Source = ${JSON.stringify(fileContent)}
            end
            
            local lp = game:GetService("Players").LocalPlayer
            if lp then
                local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
                local mod = ps:FindFirstChild("UIMockPreview")
                if not mod then
                    mod = Instance.new("ModuleScript")
                    mod.Name = "UIMockPreview"
                    mod.Parent = ps
                end
                mod.Source = ${JSON.stringify(fileContent)}
                
                local m = require(mod:Clone())
                m.show()
            end
            return "SUCCESSFULLY_SHOWN"
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
        console.log('Execute Result:', JSON.stringify(msg.result));
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: 3,
            method: 'tools/call',
            params: {
                name: 'screen_capture',
                arguments: {
                    studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
                }
            }
        }) + '\n');
    } else if (msg.id === 3) {
        if (msg.result && msg.result.content) {
            for (const item of msg.result.content) {
                if (item.data) {
                    fs.writeFileSync('C:\\RGame\\screenshots\\studio_live_screen.png', Buffer.from(item.data, 'base64'));
                    console.log('Successfully saved screenshots/studio_live_screen.png!');
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
        clientInfo: { name: 'ShowTester', version: '1.0' }
    }
}) + '\n');
