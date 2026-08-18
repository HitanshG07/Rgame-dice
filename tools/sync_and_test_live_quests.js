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
                clientInfo: { name: 'SyncAndTestQuests', version: '1.0' }
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
        local lp = game:GetService("Players").LocalPlayer or game:GetService("Players"):GetPlayers()[1]
        local pg = lp:WaitForChild("PlayerGui")
        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")

        -- Clean any old menu guis
        for _, c in ipairs(pg:GetChildren()) do
            if c.Name == "V7MenuGui" or c.Name == "UIMockPreview" or c.Name == "V7AscendPreview" then
                c:Destroy()
            end
        end

        -- Update source of V7MenuPanel in PlayerScripts.Client
        local targetMod = ps:WaitForChild("V7MenuPanel")
        local cloneMod = targetMod:Clone()
        cloneMod.Name = "V7MenuPanel_Prod_Live"
        cloneMod.Source = ${JSON.stringify(menuContent)}
        cloneMod.Parent = ps

        local menuModule = require(cloneMod)
        local menuCtrl = menuModule.new()

        local sampleState = {
            quests = {
                { id = "roll100", progress = 100, target = 100, claimed = false, ready = true },
                { id = "forge10", progress = 4, target = 10, claimed = false, ready = false },
                { id = "streak15", progress = 8, target = 15, claimed = false, ready = false },
            },
            loginStreak = { count = 4, forgivenessLeft = 1, claimedToday = false },
        }

        menuCtrl:applyState(sampleState)
        menuCtrl:openOverlay("quests")

        return "SUCCESS_MOUNTED_PROD_QUESTS"
    `;

    const res = await callTool('execute_luau', { code, datamodel_type: 'Client' });
    console.log('Execute result:', res);
    await sleep(600);

    const capRes = await callTool('screen_capture', { capture_id: 'live_quests_production_verified' });
    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        fs.writeFileSync('C:\\RGame\\screenshots\\live_quests_production_verified.png', buf);
        fs.writeFileSync('C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\live_quests_production_verified.png', buf);
        console.log('Saved live production quests verification capture to artifacts');
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
