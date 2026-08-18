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
                clientInfo: { name: 'ShowPreview', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    const fileContent = fs.readFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', 'utf8');

    const code = `
        local lp = game:GetService("Players").LocalPlayer
        if not lp then
            lp = game:GetService("Players"):GetPlayers()[1]
        end
        local pg = lp:WaitForChild("PlayerGui")

        -- Clean up any and all existing preview / menu modals
        for _, c in ipairs(pg:GetChildren()) do
            if c.Name == "UIMockPreview" or c.Name == "V7AscendPreview" or c.Name == "AscendMockPreview" or c.Name == "V7MenuGui" then
                c:Destroy()
            end
        end

        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
        local mod = Instance.new("ModuleScript")
        mod.Name = "UIMockPreview_LiveActive"
        mod.Source = ${JSON.stringify(fileContent)}
        mod.Parent = ps

        local preview = require(mod)
        local gui = preview.show(pg)
        gui.DisplayOrder = 100000

        return "MOUNTED_QUESTS_PREVIEW_SUCCESS"
    `;

    const res = await callTool('execute_luau', { code, datamodel_type: 'Client' });
    console.log('Execute result:', res);
    await sleep(600);

    const capRes = await callTool('screen_capture', { capture_id: 'live_quests_screen' });
    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        fs.writeFileSync('C:\\RGame\\screenshots\\live_quests_screen.png', buf);
        fs.writeFileSync('C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\live_quests_screen.png', buf);
        console.log('Saved live screen capture');
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
