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

let step = 0;
rl.on('line', (line) => {
    step++;
    if (step === 1) {
        // Sync the disk file content to StarterPlayer and inspect
        const code = `
            local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
            if sp then
                local mod = sp:FindFirstChild("UIMockPreview")
                local oldSourcePreview = if mod then string.sub(mod.Source, 1, 150) else "NIL"
                
                if not mod then
                    mod = Instance.new("ModuleScript")
                    mod.Name = "UIMockPreview"
                    mod.Parent = sp
                end
                mod.Source = ${JSON.stringify(fileContent)}
                
                return "UPDATED_STARTER_PLAYER. PREVIOUS_HEADER: " .. oldSourcePreview
            end
            return "NO_CLIENT_FOLDER"
        `;
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: 2,
            method: 'tools/call',
            params: {
                name: 'execute_luau',
                arguments: {
                    code: code,
                    datamodel_type: 'Edit',
                    studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
                }
            }
        }) + '\n');
    } else if (step === 2) {
        console.log('Result in Edit datamodel:', line);
        
        // Also check/update Client datamodel if in Play solo
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
                local ps = lp:FindFirstChild("PlayerScripts")
                if ps then
                    local cl = ps:FindFirstChild("Client")
                    if cl then
                        local mod = cl:FindFirstChild("UIMockPreview")
                        if not mod then
                            mod = Instance.new("ModuleScript")
                            mod.Name = "UIMockPreview"
                            mod.Parent = cl
                        end
                        mod.Source = ${JSON.stringify(fileContent)}
                    end
                end
            end
            return "SYNCED_TO_CLIENT_AND_STARTER_PLAYER"
        `;
        child.stdin.write(JSON.stringify({
            jsonrpc: '2.0',
            id: 3,
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
    } else if (step === 3) {
        console.log('Result in Client datamodel:', line);
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
        clientInfo: { name: 'Syncer', version: '1.0' }
    }
}) + '\n');
