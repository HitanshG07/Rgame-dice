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
                clientInfo: { name: 'DetailedInspector', version: '1.0' }
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
        local asc = menu:FindFirstChild("Overlay_ascend")
        local panel = asc:FindFirstChild("Panel")
        local body = panel:FindFirstChild("Body")
        local bodyRow = body:FindFirstChild("BodyRow")
        local left = bodyRow:FindFirstChild("LeftCommandCol")
        local right = bodyRow:FindFirstChild("RightLedgerCol")
        
        local leftChildren = {}
        for _, c in ipairs(left:GetChildren()) do
            if c:IsA("GuiObject") then
                table.insert(leftChildren, { name = c.Name, class = c.ClassName, size = { X = c.AbsoluteSize.X, Y = c.AbsoluteSize.Y }, pos = { X = c.AbsolutePosition.X, Y = c.AbsolutePosition.Y } })
            end
        end

        local rightChildren = {}
        for _, c in ipairs(right:GetChildren()) do
            if c:IsA("GuiObject") then
                table.insert(rightChildren, { name = c.Name, class = c.ClassName, size = { X = c.AbsoluteSize.X, Y = c.AbsoluteSize.Y }, pos = { X = c.AbsolutePosition.X, Y = c.AbsolutePosition.Y } })
            end
        end

        return {
            left = leftChildren,
            right = rightChildren
        }
    `;

    const res = await callTool('execute_luau', {
        code: inspectCode,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });

    console.log('Left & Right Breakdown:', JSON.stringify(res.result, null, 2));
    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
