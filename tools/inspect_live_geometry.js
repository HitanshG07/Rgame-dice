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
                clientInfo: { name: 'Inspector', version: '1.0' }
            }
        }) + '\n');
    });
}

async function main() {
    await initialize();

    const inspectCode = `
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local menu = pg:FindFirstChild("V7MenuGui")
        if not menu then return "NO_V7MENUGUI" end
        
        local asc = menu:FindFirstChild("Overlay_ascend")
        if not asc then return "NO_OVERLAY_ASCEND" end
        
        local panel = asc:FindFirstChild("Panel")
        if not panel then return "NO_PANEL" end
        
        local body = panel:FindFirstChild("Body")
        if not body then return "NO_BODY" end
        
        local bodyRow = body:FindFirstChild("BodyRow")
        if not bodyRow then return "NO_BODYROW" end
        
        local left = bodyRow:FindFirstChild("LeftCommandCol")
        local right = bodyRow:FindFirstChild("RightLedgerCol")
        
        return {
            panel_abs = { X = panel.AbsoluteSize.X, Y = panel.AbsoluteSize.Y },
            body_abs = { X = body.AbsoluteSize.X, Y = body.AbsoluteSize.Y },
            bodyRow_abs = if bodyRow then { X = bodyRow.AbsoluteSize.X, Y = bodyRow.AbsoluteSize.Y } else nil,
            left_abs = if left then { X = left.AbsoluteSize.X, Y = left.AbsoluteSize.Y } else nil,
            right_abs = if right then { X = right.AbsoluteSize.X, Y = right.AbsoluteSize.Y } else nil,
        }
    `;

    const res = await callTool('execute_luau', {
        code: inspectCode,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    console.log('Inspection result:', JSON.stringify(res.result));
    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
