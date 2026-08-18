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
                clientInfo: { name: 'TestLiveQuests', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    const menuContent = fs.readFileSync('C:\\RGame\\src\\Client\\V7MenuPanel.luau', 'utf8');

    const code = `
        local lp = game:GetService("Players").LocalPlayer
        if not lp then
            lp = game:GetService("Players"):GetPlayers()[1]
        end
        local pg = lp:WaitForChild("PlayerGui")

        -- Clean any old mock previews
        for _, c in ipairs(pg:GetChildren()) do
            if c.Name == "UIMockPreview" or c.Name == "V7AscendPreview" or c.Name == "AscendMockPreview" or c.Name == "V7MenuGui" then
                c:Destroy()
            end
        end

        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
        local mod = Instance.new("ModuleScript")
        mod.Name = "V7MenuPanel_Live"
        mod.Source = ${JSON.stringify(menuContent)}
        mod.Parent = ps

        local menuModule = require(mod)
        local menuCtrl = menuModule.new()

        -- Trigger refreshQuests with sample live data
        local sampleState = {
            quests = {
                { id = "roll100", progress = 100, target = 100, claimed = false, ready = true },
                { id = "forge10", progress = 4, target = 10, claimed = false, ready = false },
                { id = "streak15", progress = 8, target = 15, claimed = false, ready = false },
            },
            loginStreak = { count = 4, forgivenessLeft = 1, claimedToday = false },
        }
        menuCtrl.questRefresh(sampleState)
        menuCtrl:openOverlay("quests")

        return "SUCCESS_OPENED_QUESTS"
    `;

    const res = await callTool('execute_luau', { code, datamodel_type: 'Client' });
    console.log('Execute result:', res);
    await sleep(700);

    const capRes = await callTool('screen_capture', { capture_id: 'live_quests_production_final' });
    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        fs.writeFileSync('C:\\RGame\\screenshots\\live_quests_production_final.png', buf);
        fs.writeFileSync('C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\live_quests_production_final.png', buf);
        console.log('Saved production live quests capture to artifacts');
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
