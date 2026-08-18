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
                clientInfo: { name: 'CaptureTester', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    const code = `
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        
        local oldMenu = pg:FindFirstChild("V7MenuGui")
        if oldMenu then oldMenu:Destroy() end

        local V7MenuPanel = require(lp.PlayerScripts.Client.V7MenuPanel)
        local controller = V7MenuPanel.new(pg)
        
        controller:applyState({
            cash = 350000,
            ascensions = 7,
            diamonds = 28,
            dieSlots = 2,
        })

        controller.overlays["ascend"].Visible = true
        return "SUCCESS_OPENED"
    `;

    const res = await callTool('execute_luau', {
        code: code,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    console.log('Execute Result:', JSON.stringify(res.result));
    await sleep(400);

    const capRes = await callTool('screen_capture', {
        capture_id: 'perfect_live_ascend',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        const outPath = 'C:\\RGame\\screenshots\\perfect_live_ascend.png';
        fs.writeFileSync(outPath, buf);
        console.log('Saved screenshot to', outPath, `(${buf.length} bytes)`);
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
