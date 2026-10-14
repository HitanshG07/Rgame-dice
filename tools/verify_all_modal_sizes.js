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
                clientInfo: { name: 'VerifyAllModalSizes', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    // Start play mode if not running
    await callTool('start_stop_play', { action: 'start' });
    await sleep(2500);

    const menuContent = fs.readFileSync('C:\\RGame\\src\\Client\\V7MenuPanel.luau', 'utf8');

    // Measure and capture Quests
    const testQuestsCode = `
        local lp = game:GetService("Players").LocalPlayer or game:GetService("Players"):GetPlayers()[1]
        local pg = lp:WaitForChild("PlayerGui")
        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")

        -- Clean old
        for _, c in ipairs(pg:GetChildren()) do
            if c.Name == "V7MenuGui" or c.Name == "UIMockPreview" or c.Name == "V7AscendPreview" then
                c:Destroy()
            end
        end

        local targetMod = ps:WaitForChild("V7MenuPanel")
        local cloneMod = Instance.new("ModuleScript")
        cloneMod.Name = "V7MenuPanel_SizeTest"
        cloneMod.Source = ${JSON.stringify(menuContent)}
        cloneMod.Parent = ps

        local menuModule = require(cloneMod)
        local menuCtrl = menuModule.new()

        local sampleState = {
            cash = 104400, gems = 0, diamonds = 28,
            quests = {
                { id = "roll100", progress = 100, target = 100, claimed = false, ready = true },
                { id = "forge10", progress = 4, target = 10, claimed = false, ready = false },
                { id = "streak15", progress = 8, target = 15, claimed = false, ready = false },
            },
            loginStreak = { count = 4, forgivenessLeft = 1, claimedToday = false },
        }
        menuCtrl:applyState(sampleState)
        menuCtrl:openOverlay("quests")

        local qOverlay = pg.V7MenuGui.Overlay_quests
        local panel = qOverlay:FindFirstChild("Panel") or qOverlay:FindFirstChildOfClass("Frame")
        return "Quests Panel Size: " .. tostring(panel.Size) .. " | AbsoluteSize: " .. tostring(panel.AbsoluteSize)
    `;

    const qRes = await callTool('execute_luau', { code: testQuestsCode, datamodel_type: 'Client' });
    console.log('Quests Result:', qRes);
    await sleep(600);

    const capRes = await callTool('screen_capture', { capture_id: 'unified_quests_verified' });
    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        fs.writeFileSync(path.join('C:', 'RGame', 'screenshots', 'unified_quests_verified.png'), buf);
        const artifactDir = path.join(process.env.USERPROFILE || '', '.gemini', 'antigravity-ide', 'brain', 'cbe5a261-05be-4b9b-a450-a0a97c7eb194');
        if (fs.existsSync(artifactDir)) {
            fs.writeFileSync(path.join(artifactDir, 'unified_quests_verified.png'), buf);
        }
        console.log('Saved unified Quests capture to artifacts');
    }

    // Measure Ascend
    const testAscendCode = `
        local lp = game:GetService("Players").LocalPlayer or game:GetService("Players"):GetPlayers()[1]
        local pg = lp:WaitForChild("PlayerGui")
        local menuGui = pg:WaitForChild("V7MenuGui")
        local overlays = menuGui:FindFirstChild("Overlays")
        for _, c in ipairs(menuGui:GetChildren()) do
            if string.find(c.Name, "Overlay_") then
                c.Visible = (c.Name == "Overlay_ascend")
            end
        end
        local aOverlay = menuGui.Overlay_ascend
        local panel = aOverlay:FindFirstChild("Panel") or aOverlay:FindFirstChildOfClass("Frame")
        return "Ascend Panel Size: " .. tostring(panel.Size) .. " | AbsoluteSize: " .. tostring(panel.AbsoluteSize)
    `;
    const aRes = await callTool('execute_luau', { code: testAscendCode, datamodel_type: 'Client' });
    console.log('Ascend Result:', aRes);

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
