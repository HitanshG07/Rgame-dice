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

if (!studioMcpPath) {
    console.error('Could not find StudioMCP.exe in', versionsDir);
    process.exit(1);
}

const child = spawn(studioMcpPath, [], { stdio: ['pipe', 'pipe', 'pipe'] });
const rl = readline.createInterface({ input: child.stdout, terminal: false });

const sourceContent = fs.readFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', 'utf8');

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
            params: {
                name: name,
                arguments: args
            }
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
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function execLuau(code) {
    return await callTool('execute_luau', {
        code: code,
        datamodel_type: 'Client',
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });
}

async function takeScreenshot(filename) {
    console.log('Capturing:', filename);
    const res = await callTool('screen_capture', {
        studio_id: '0f7b2089-5fef-47fd-a4da-2c28f1ad3a6d'
    });
    if (res.result && res.result.content && res.result.content[0] && res.result.content[0].data) {
        const buf = Buffer.from(res.result.content[0].data, 'base64');
        const outPath = path.join('C:\\RGame\\screenshots', filename);
        fs.writeFileSync(outPath, buf);
        console.log(' -> Saved', filename, `(${buf.length} bytes)`);
    } else {
        console.error('Failed to capture screenshot for', filename, JSON.stringify(res));
    }
}

async function main() {
    await initialize();
    console.log('StudioMCP initialized!');

    // Setup and show UIMockPreview
    const setupCode = `
        local sp = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
        if sp then
            local mod = sp:FindFirstChild("UIMockPreview")
            if not mod then
                mod = Instance.new("ModuleScript")
                mod.Name = "UIMockPreview"
                mod.Parent = sp
            end
            mod.Source = ${JSON.stringify(sourceContent)}
        end

        local lp = game:GetService("Players").LocalPlayer
        assert(lp, "LocalPlayer must exist")
        local ps = lp:WaitForChild("PlayerScripts"):WaitForChild("Client")
        local mod = ps:FindFirstChild("UIMockPreview")
        if not mod then
            mod = Instance.new("ModuleScript")
            mod.Name = "UIMockPreview"
            mod.Parent = ps
        end
        mod.Source = ${JSON.stringify(sourceContent)}
        
        local loaded = require(mod:Clone())
        loaded.show()
    `;

    console.log('Setting up and displaying UIMockPreview in Client datamodel...');
    const execRes = await execLuau(setupCode);
    console.log('Exec result:', JSON.stringify(execRes));
    await sleep(400);

    // Capture Design 1 (Executive Folio)
    await takeScreenshot('ascend_design_1_executive_folio.png');

    // Switch to Design 2 (Sovereign Vault)
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local cg = pg:FindFirstChild("UIMockPreview")
        if cg then
            local backdrop = cg:FindFirstChild("Backdrop")
            if backdrop then
                local d1 = backdrop:FindFirstChild("Design_1_ExecutiveFolio")
                local d2 = backdrop:FindFirstChild("Design_2_SovereignVault")
                local d3 = backdrop:FindFirstChild("Design_3_PrestigeTierSheet")
                local pill = backdrop:FindFirstChild("CarouselControlBar"):FindFirstChild("IndicatorPill"):FindFirstChild("IndicatorLabel")
                if d1 and d2 and d3 and pill then
                    d1.Visible = false
                    d2.Visible = true
                    d3.Visible = false
                    pill.Text = "DESIGN 2: SOVEREIGN VAULT (2 / 3)"
                end
            end
        end
    `);
    await sleep(300);
    await takeScreenshot('ascend_design_2_sovereign_vault.png');

    // Switch to Design 3 (Prestige Tier Sheet)
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local cg = pg:FindFirstChild("UIMockPreview")
        if cg then
            local backdrop = cg:FindFirstChild("Backdrop")
            if backdrop then
                local d1 = backdrop:FindFirstChild("Design_1_ExecutiveFolio")
                local d2 = backdrop:FindFirstChild("Design_2_SovereignVault")
                local d3 = backdrop:FindFirstChild("Design_3_PrestigeTierSheet")
                local pill = backdrop:FindFirstChild("CarouselControlBar"):FindFirstChild("IndicatorPill"):FindFirstChild("IndicatorLabel")
                if d1 and d2 and d3 and pill then
                    d1.Visible = false
                    d2.Visible = false
                    d3.Visible = true
                    pill.Text = "DESIGN 3: PRESTIGE TIER SHEET (3 / 3)"
                end
            end
        end
    `);
    await sleep(300);
    await takeScreenshot('ascend_design_3_prestige_tier_sheet.png');

    // Capture Design 2 in "ARMED CONFIRM" State
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local cg = pg:FindFirstChild("UIMockPreview")
        if cg then
            local backdrop = cg:FindFirstChild("Backdrop")
            if backdrop then
                local d1 = backdrop:FindFirstChild("Design_1_ExecutiveFolio")
                local d2 = backdrop:FindFirstChild("Design_2_SovereignVault")
                local d3 = backdrop:FindFirstChild("Design_3_PrestigeTierSheet")
                local pill = backdrop:FindFirstChild("CarouselControlBar"):FindFirstChild("IndicatorPill"):FindFirstChild("IndicatorLabel")
                if d1 and d2 and d3 and pill then
                    d1.Visible = false
                    d2.Visible = true
                    d3.Visible = false
                    pill.Text = "DESIGN 2: SOVEREIGN VAULT (ARMED CONFIRM)"
                    
                    local leftCol = d2:FindFirstChild("BodyRow"):FindFirstChild("LeftCommandCol")
                    if leftCol then
                        local btn = leftCol:FindFirstChild("AscendButton")
                        local st = leftCol:FindFirstChild("AscendStatus")
                        btn.BackgroundColor3 = Color3.fromRGB(220, 38, 38)
                        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                        btn.Text = "CONFIRM SETTLEMENT?"
                        st.Text = "WARNING: Press again to confirm. Cash, dice & slots will be wiped permanently."
                        st.TextColor3 = Color3.fromRGB(248, 113, 113)
                    end
                end
            end
        end
    `);
    await sleep(300);
    await takeScreenshot('ascend_design_2_armed_state.png');

    // Capture Design 1 in "LOCKED" State
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp:WaitForChild("PlayerGui")
        local cg = pg:FindFirstChild("UIMockPreview")
        if cg then
            local backdrop = cg:FindFirstChild("Backdrop")
            if backdrop then
                local d1 = backdrop:FindFirstChild("Design_1_ExecutiveFolio")
                local d2 = backdrop:FindFirstChild("Design_2_SovereignVault")
                local d3 = backdrop:FindFirstChild("Design_3_PrestigeTierSheet")
                local pill = backdrop:FindFirstChild("CarouselControlBar"):FindFirstChild("IndicatorPill"):FindFirstChild("IndicatorLabel")
                if d1 and d2 and d3 and pill then
                    d1.Visible = true
                    d2.Visible = false
                    d3.Visible = false
                    pill.Text = "DESIGN 1: EXECUTIVE FOLIO (LOCKED STATE)"
                    
                    local banner = d1:FindFirstChild("DividendBanner")
                    if banner then
                        local rew = banner:FindFirstChild("AscendReward")
                        local prog = banner:FindFirstChild("AscendProgress")
                        if rew and prog then
                            rew.Text = "+0 DIAMONDS (THRESHOLD NOT MET)"
                            rew.TextColor3 = Color3.fromRGB(140, 130, 120)
                            prog.Text = "Settlement Basis: $350.0K / $1.00M Run Cash  ·  1 Settled Ascension"
                        end
                    end
                    local actRow = d1:FindFirstChild("ActionRow")
                    if actRow then
                        local btn = actRow:FindFirstChild("AscendButton")
                        local st = actRow:FindFirstChild("AscendStatus")
                        btn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
                        btn.TextColor3 = Color3.fromRGB(140, 130, 120)
                        btn.Text = "UNAVAILABLE // INSUFFICIENT CASH"
                        st.Text = "Threshold not met: Earn $650,000 more cash this run to unlock."
                        st.TextColor3 = Color3.fromRGB(248, 113, 113)
                    end
                end
            end
        end
    `);
    await sleep(300);
    await takeScreenshot('ascend_design_1_locked_state.png');

    console.log('All 3 new designs captured successfully!');
    child.kill();
    process.exit(0);
}

main().catch(err => {
    console.error('Fatal error in capture script:', err);
    process.exit(1);
});
