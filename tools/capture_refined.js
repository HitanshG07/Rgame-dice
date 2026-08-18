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
                clientInfo: { name: 'CaptureScript', version: '1.0' }
            }
        }) + '\n');
    });
}

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function execLuau(code) {
    return await callTool('execute_luau', {
        code,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });
}

async function takeScreenshot(filename) {
    const res = await callTool('screen_capture', {
        capture_id: filename.replace('.png', ''),
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });
    if (res.result && res.result.content && res.result.content[0] && res.result.content[0].data) {
        const buf = Buffer.from(res.result.content[0].data, 'base64');
        const outPath = path.join('C:\\RGame\\screenshots', filename);
        fs.writeFileSync(outPath, buf);
        console.log('Saved:', filename, `(${buf.length} bytes)`);
    } else {
        console.error('Failed capture for', filename, JSON.stringify(res));
    }
}

async function main() {
    await initialize();

    // 1. Qualified State
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local mod = lp.PlayerScripts.Client:FindFirstChild("UIMockPreview")
        if mod then
            local loaded = require(mod:Clone())
            loaded.show()
        end
    `);
    await sleep(400);
    await takeScreenshot('ascend_sovereign_vault_qualified.png');

    // 2. Locked State
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local cg = pg:FindFirstChild("UIMockPreview")
        if cg then
            local backdrop = cg:FindFirstChild("Backdrop")
            local vault = backdrop:FindFirstChild("SovereignVaultMaster")
            local left = vault:FindFirstChild("BodyRow"):FindFirstChild("LeftCommandCol")
            local rew = left:FindFirstChild("AscendReward")
            local prog = left:FindFirstChild("AscendProgress")
            local fill = left:FindFirstChild("MeterTrack"):FindFirstChild("MeterFill")
            local btn = left:FindFirstChild("AscendButton")
            local st = left:FindFirstChild("AscendStatus")
            local pod = left:FindFirstChild("LifetimeMetricsPod")
            
            rew.Text = "+0 ♦ DIAMONDS"
            rew.TextColor3 = Color3.fromRGB(140, 130, 120)
            fill.Size = UDim2.fromScale(0.35, 1)
            fill.BackgroundColor3 = Color3.fromRGB(220, 38, 38)
            prog.Text = "Run Basis: $350.0K / $1.00M"
            
            pod.PostVaultVal.Text = "2 ♦ (+0)"
            pod.NextTierVal.Text = "at $1.00M"
            pod.CareerAscendVal.Text = "1 Completed"
            
            btn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
            btn.TextColor3 = Color3.fromRGB(140, 130, 120)
            btn.Text = "UNAVAILABLE // INSUFFICIENT CASH"
            
            st.Text = "Threshold not met: Earn $650,000 more cash this run to unlock."
            st.TextColor3 = Color3.fromRGB(248, 113, 113)
        end
    `);
    await sleep(400);
    await takeScreenshot('ascend_sovereign_vault_locked.png');

    // 3. Armed Confirm State
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local cg = pg:FindFirstChild("UIMockPreview")
        if cg then
            local backdrop = cg:FindFirstChild("Backdrop")
            local vault = backdrop:FindFirstChild("SovereignVaultMaster")
            local left = vault:FindFirstChild("BodyRow"):FindFirstChild("LeftCommandCol")
            local rew = left:FindFirstChild("AscendReward")
            local prog = left:FindFirstChild("AscendProgress")
            local fill = left:FindFirstChild("MeterTrack"):FindFirstChild("MeterFill")
            local btn = left:FindFirstChild("AscendButton")
            local st = left:FindFirstChild("AscendStatus")
            local pod = left:FindFirstChild("LifetimeMetricsPod")
            
            rew.Text = "+2 ♦ DIAMONDS"
            rew.TextColor3 = Color3.fromRGB(244, 114, 182)
            fill.Size = UDim2.fromScale(1, 1)
            fill.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
            prog.Text = "Run Basis: $4.50M / $1.00M"
            
            pod.PostVaultVal.Text = "10 ♦ (+2)"
            pod.NextTierVal.Text = "at $10.00M"
            pod.CareerAscendVal.Text = "3 Completed"
            
            btn.BackgroundColor3 = Color3.fromRGB(220, 38, 38)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Text = "CONFIRM SETTLEMENT? (NO UNDO)"
            
            st.Text = "WARNING: Press again to confirm. Cash, dice & slots will be wiped permanently."
            st.TextColor3 = Color3.fromRGB(248, 113, 113)
        end
    `);
    await sleep(400);
    await takeScreenshot('ascend_sovereign_vault_armed.png');

    // 4. Restore Qualified for User Screen
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local mod = lp.PlayerScripts.Client:FindFirstChild("UIMockPreview")
        if mod then
            local loaded = require(mod:Clone())
            loaded.show()
        end
    `);

    console.log('Finished capturing all states!');
    child.kill();
    process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
