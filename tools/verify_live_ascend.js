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
                clientInfo: { name: 'FullVerifier', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    // 1. Re-instantiate V7MenuPanel in PlayerGui to ensure clean layout initialization
    const verifyCode = `
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        
        -- Clean existing
        local oldMenu = pg:FindFirstChild("V7MenuGui")
        if oldMenu then oldMenu:Destroy() end
        local mock = pg:FindFirstChild("UIMockPreview")
        if mock then mock:Destroy() end

        -- Require updated V7MenuPanel and init
        local V7MenuPanel = require(lp.PlayerScripts.Client.V7MenuPanel)
        local controller = V7MenuPanel.new(pg)
        
        -- Apply mock qualified state to test render
        controller:applyState({
            cash = 4500000,
            ascensions = 3,
            diamonds = 8,
            dieSlots = 2,
        })

        -- Open Ascend overlay
        controller.overlays["ascend"].Visible = true

        local panel = controller.overlays["ascend"]:FindFirstChild("Panel")
        local body = panel:FindFirstChild("Body")
        local bodyRow = body:FindFirstChild("BodyRow")
        local left = bodyRow:FindFirstChild("LeftCommandCol")
        local right = bodyRow:FindFirstChild("RightLedgerCol")
        local kept = right:FindFirstChild("KeptCard")
        local lost = right:FindFirstChild("LostCard")

        return {
            status = "INITIALIZED_AND_OPENED",
            panel_size = { X = panel.AbsoluteSize.X, Y = panel.AbsoluteSize.Y },
            body_size = { X = body.AbsoluteSize.X, Y = body.AbsoluteSize.Y },
            bodyRow_size = { X = bodyRow.AbsoluteSize.X, Y = bodyRow.AbsoluteSize.Y },
            left_size = { X = left.AbsoluteSize.X, Y = left.AbsoluteSize.Y },
            right_size = { X = right.AbsoluteSize.X, Y = right.AbsoluteSize.Y },
            kept_size = { X = kept.AbsoluteSize.X, Y = kept.AbsoluteSize.Y },
            lost_size = { X = lost.AbsoluteSize.X, Y = lost.AbsoluteSize.Y },
        }
    `;

    const res = await callTool('execute_luau', {
        code: verifyCode,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    console.log('Verification Geometry Data:', JSON.stringify(res.result, null, 2));

    await sleep(500);

    const capRes = await callTool('screen_capture', {
        capture_id: 'verified_live_ascend_overlay',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        const outPath = 'C:\\RGame\\screenshots\\verified_live_ascend_overlay.png';
        fs.writeFileSync(outPath, buf);
        console.log('Saved verified screenshot to', outPath, `(${buf.length} bytes)`);
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
