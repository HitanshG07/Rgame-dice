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
                clientInfo: { name: 'LiveOverlayTester', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    // Trigger open live ascend overlay in V7MenuGui
    const execRes = await callTool('execute_luau', {
        code: `
            local lp = game:GetService("Players").LocalPlayer
            local pg = lp:WaitForChild("PlayerGui")
            
            -- Destroy preview if open
            local mock = pg:FindFirstChild("UIMockPreview")
            if mock then mock:Destroy() end

            local menu = pg:FindFirstChild("V7MenuGui")
            if menu then
                menu.Enabled = true
                -- Find Overlay_ascend
                for _, child in ipairs(menu:GetChildren()) do
                    if child:IsA("Frame") and child.Name:find("Overlay_") then
                        child.Visible = (child.Name == "Overlay_ascend")
                    end
                end
                return "OPENED_LIVE_OVERLAY_ASCEND"
            end
            return "V7MENUGUI_NOT_FOUND"
        `,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    console.log('Open Result:', JSON.stringify(execRes.result));
    await sleep(400);

    const res = await callTool('screen_capture', {
        capture_id: 'live_ascend_integrated',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });
    if (res.result && res.result.content && res.result.content[0] && res.result.content[0].data) {
        const buf = Buffer.from(res.result.content[0].data, 'base64');
        const outPath = 'C:\\RGame\\screenshots\\live_ascend_integrated.png';
        fs.writeFileSync(outPath, buf);
        console.log('Saved live integrated screenshot to', outPath, `(${buf.length} bytes)`);
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
