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
                clientInfo: { name: 'QuestCapture', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function captureVariant(idx, name) {
    const code = `
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local fileContent = ${JSON.stringify(fs.readFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', 'utf8'))}

        local old = pg:FindFirstChild("UIMockPreview")
        if old then old:Destroy() end

        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
        local mod = Instance.new("ModuleScript")
        mod.Name = "UIMockPreview_Fresh"
        mod.Source = fileContent
        mod.Parent = ps

        local preview = require(mod)
        local gui = preview.show(pg)

        local vHolder = gui:FindFirstChild("VariantHolder")
        if vHolder then
            local children = vHolder:GetChildren()
            for i, child in ipairs(children) do
                child.Visible = (i == ${idx})
            end
        end

        local topBar = gui:FindFirstChild("CarouselTopBar")
        if topBar then
            local title = topBar:FindFirstChildOfClass("TextLabel")
            if title then
                local names = {
                    "VARIANT A // MACHINIST PRECISION CONTRACT TERMINAL",
                    "VARIANT B // CASINO LEDGER & GENTLEMAN'S BOUNTY BOARD",
                    "VARIANT C // BRUTALIST OPERATIONS DOSSIER",
                }
                title.Text = names[${idx}]
            end
        end

        return "RENDERED_" .. tostring(${idx})
    `;

    await callTool('execute_luau', { code, datamodel_type: 'Client' });
    await sleep(600);

    const capRes = await callTool('screen_capture', { capture_id: `quest_variant_${idx}` });
    if (capRes.result && capRes.result.content && capRes.result.content[0] && capRes.result.content[0].data) {
        const buf = Buffer.from(capRes.result.content[0].data, 'base64');
        const outPath = `C:\\RGame\\screenshots\\quest_variant_${name}.png`;
        fs.writeFileSync(outPath, buf);
        const artPath = `C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\quest_variant_${name}.png`;
        fs.writeFileSync(artPath, buf);
        console.log(`Saved capture to ${outPath}`);
    }
}

async function main() {
    await initialize();

    await captureVariant(1, 'a_machinist');
    await captureVariant(2, 'b_casino_ledger');
    await captureVariant(3, 'c_brutalist');

    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
