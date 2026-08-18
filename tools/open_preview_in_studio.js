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

if (!studioMcpPath) {
    console.error('StudioMCP.exe not found');
    process.exit(1);
}

const fileContent = fs.readFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', 'utf8');

async function runOnce() {
    return new Promise((resolve) => {
        const child = spawn(studioMcpPath, [], { stdio: ['pipe', 'pipe', 'pipe'] });
        const rl = readline.createInterface({ input: child.stdout, terminal: false });

        let reqId = 0;
        const pending = new Map();

        rl.on('line', (line) => {
            try {
                const msg = JSON.parse(line);
                if (msg.id && pending.has(msg.id)) {
                    const cb = pending.get(msg.id);
                    pending.delete(msg.id);
                    cb(msg);
                }
            } catch (e) {}
        });

        function callTool(name, args) {
            return new Promise((res) => {
                reqId++;
                pending.set(reqId, res);
                child.stdin.write(JSON.stringify({
                    jsonrpc: '2.0',
                    id: reqId,
                    method: 'tools/call',
                    params: { name, arguments: args }
                }) + '\n');
            });
        }

        function init() {
            return new Promise((res) => {
                reqId++;
                pending.set(reqId, res);
                child.stdin.write(JSON.stringify({
                    jsonrpc: '2.0',
                    id: reqId,
                    method: 'initialize',
                    params: {
                        protocolVersion: '2024-11-05',
                        capabilities: {},
                        clientInfo: { name: 'AutoOpener', version: '1.0' }
                    }
                }) + '\n');
            });
        }

        (async () => {
            await init();
            const listRes = await callTool('list_roblox_studios', {});
            
            if (listRes.isError || !listRes.result || !listRes.result.content || !listRes.result.content[0] || !listRes.result.content[0].text) {
                child.kill();
                return resolve({ ok: false, error: 'Studio not connected' });
            }

            const rawText = listRes.result.content[0].text;
            let studios = [];
            try { studios = JSON.parse(rawText); } catch (e) {
                child.kill();
                return resolve({ ok: false, error: rawText });
            }

            if (!Array.isArray(studios) || studios.length === 0) {
                child.kill();
                return resolve({ ok: false, error: 'No open places' });
            }

            const studioId = studios[0].studio_id;
            console.log('Connected to Studio Place ID:', studioId, 'Title:', studios[0].place_title);

            // Sync to StarterPlayerScripts in Edit mode or Client
            const syncScript = `
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
                local targetParent = game:GetService("CoreGui")
                if lp then
                    local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
                    local mod = ps:FindFirstChild("UIMockPreview")
                    if not mod then
                        mod = Instance.new("ModuleScript")
                        mod.Name = "UIMockPreview"
                        mod.Parent = ps
                    end
                    mod.Source = ${JSON.stringify(fileContent)}
                end
                
                -- Display UI Preview
                local fn = loadstring(${JSON.stringify(fileContent)})
                if fn then
                    local mod = fn()
                    if mod and mod.show then
                        mod.show()
                        return "SUCCESSFULLY_OPENED_PREVIEW"
                    end
                end
                return "LOADED_MODULE_DIRECTLY"
            `;

            // Try Client mode first (if in play mode)
            let execRes = await callTool('execute_luau', {
                code: syncScript,
                datamodel_type: 'Client',
                studio_id: studioId
            });

            // If Client not available, try Edit mode
            if (execRes.isError) {
                execRes = await callTool('execute_luau', {
                    code: syncScript,
                    datamodel_type: 'Edit',
                    studio_id: studioId
                });
            }

            console.log('Execute Result:', JSON.stringify(execRes.result));
            child.kill();
            resolve({ ok: !execRes.isError, result: execRes.result });
        })().catch((err) => {
            child.kill();
            resolve({ ok: false, error: err.message });
        });
    });
}

async function main() {
    console.log('Attempting to open Ascend Preview in Roblox Studio...');
    for (let i = 1; i <= 3; i++) {
        const res = await runOnce();
        if (res.ok) {
            console.log('Successfully opened UIMockPreview in Roblox Studio!');
            process.exit(0);
        }
        console.log(`Attempt ${i}/3 failed (${res.error}). Retrying in 1s...`);
        await new Promise(r => setTimeout(r, 1000));
    }
    console.log('Roblox Studio is currently waiting for a place to be active.');
    process.exit(0);
}

main();
