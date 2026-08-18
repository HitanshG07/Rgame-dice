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
                clientInfo: { name: 'FreshLoader', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function main() {
    await initialize();

    const fileContent = fs.readFileSync('C:\\RGame\\src\\Client\\V7MenuPanel.luau', 'utf8');

    // Load fresh Module via cloned ModuleScript
    const renderCode = `
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")

        -- Clean up existing menu instances
        local oldGui = pg:FindFirstChild("V7MenuGui")
        if oldGui then oldGui:Destroy() end

        -- Create a fresh clone module to bypass require cache
        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
        local newMod = Instance.new("ModuleScript")
        newMod.Name = "V7MenuPanel_Fresh_" .. tostring(os.clock())
        newMod.Source = ${JSON.stringify(fileContent)}
        newMod.Parent = ps

        local V7MenuPanel = require(newMod)
        local controller = V7MenuPanel.new(pg)

        controller:applyState({
            cash = 99000,
            ascensions = 7,
            diamonds = 28,
            dieSlots = 2,
        })

        -- Show the ascend overlay
        for name, overlay in pairs(controller.overlays) do
            overlay.Visible = (name == "ascend")
        end

        return "RENDERED_FRESH_SUCCESSFULLY"
    `;

    const renderRes = await callTool('execute_luau', {
        code: renderCode,
        datamodel_type: 'Client'
    });
    console.log('Render Result:', JSON.stringify(renderRes));

    await sleep(600);

    // Screen capture
    const capRes = await callTool('screen_capture', {
        capture_id: 'studio_fresh_ascend'
    });

    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        const outPath = 'C:\\RGame\\screenshots\\studio_fresh_ascend.png';
        fs.writeFileSync(outPath, buf);
        console.log('Saved capture to', outPath, `(${buf.length} bytes)`);
    } else {
        console.log('Capture error or empty:', JSON.stringify(capRes));
    }

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
