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
                clientInfo: { name: 'GeometryInspector', version: '1.0' }
            }
        }) + '\n');
    });
}

async function main() {
    await initialize();

    const code = `
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local gui = pg:FindFirstChild("V7MenuGui")
        if not gui then return "NO_GUI" end

        local ascendOverlay = gui:FindFirstChild("Overlay_The Sovereign Ascension Vault") or gui:FindFirstChild("The Sovereign Ascension Vault")
        if not ascendOverlay then
            for _, c in ipairs(gui:GetChildren()) do
                if c.Name:find("Ascension") or c.Name:find("Vault") or c.Name:find("ascend") then
                    ascendOverlay = c
                    break
                end
            end
        end

        local panel = ascendOverlay and ascendOverlay:FindFirstChild("Panel")
        local body = panel and panel:FindFirstChild("Body")
        local bodyRow = body and body:FindFirstChild("BodyRow")
        local leftCol = bodyRow and bodyRow:FindFirstChild("LeftCommandCol")
        local rightCol = bodyRow and bodyRow:FindFirstChild("RightLedgerCol")
        local keptCard = rightCol and rightCol:FindFirstChild("KeptCard")
        local lostCard = rightCol and rightCol:FindFirstChild("LostCard")

        return {
            panelSize = panel and tostring(panel.AbsoluteSize) or "nil",
            bodySize = body and tostring(body.AbsoluteSize) or "nil",
            bodyCanvasSize = body and tostring(body.AbsoluteCanvasSize) or "nil",
            bodyRowSize = bodyRow and tostring(bodyRow.AbsoluteSize) or "nil",
            leftColSize = leftCol and tostring(leftCol.AbsoluteSize) or "nil",
            rightColSize = rightCol and tostring(rightCol.AbsoluteSize) or "nil",
            keptCardSize = keptCard and tostring(keptCard.AbsoluteSize) or "nil",
            lostCardSize = lostCard and tostring(lostCard.AbsoluteSize) or "nil",
        }
    `;

    const res = await callTool('execute_luau', {
        code: code,
        datamodel_type: 'Client'
    });

    console.log('Geometry:', JSON.stringify(res, null, 2));

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
