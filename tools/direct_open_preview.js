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

                -- Dismiss any existing old GUI
                local pg = lp:FindFirstChildOfClass("PlayerGui")
                if pg then
                    local oldV7 = pg:FindFirstChild("V7MenuGui")
                    if oldV7 and oldV7:IsA("ScreenGui") then
                        oldV7.Enabled = false
                    end
                    local oldMock = pg:FindFirstChild("UIMockPreview")
                    if oldMock then oldMock:Destroy() end
                end

                local loaded = require(mod:Clone())
                local gui = loaded.show()
                return "OPENED_SUCCESSFULLY: " .. tostring(gui.Name)
            end
            return "NO_LOCAL_PLAYER"
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
        console.log('Studio Live Open Result:', JSON.stringify(msg.result));
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
        clientInfo: { name: 'DirectOpener', version: '1.0' }
    }
}) + '\n');
