const { spawn } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

const studioMcpPath = 'C:\\Users\\Hitansh Gogri\\AppData\\Local\\Roblox\\Versions\\version-d679641ad17741aa\\StudioMCP.exe';
const studioId = 'f2e30777-e3b1-4ad2-b76a-71b8e9dabd25';

const dir1 = path.join('C:', 'RGame', 'screenshots');
const dir2 = path.join('C:', 'RGame', 'screensots');
if (!fs.existsSync(dir1)) fs.mkdirSync(dir1, { recursive: true });
if (!fs.existsSync(dir2)) fs.mkdirSync(dir2, { recursive: true });

async function main() {
    console.log('Spawning StudioMCP at:', studioMcpPath);
    const child = spawn(studioMcpPath, [], { stdio: ['pipe', 'pipe', 'pipe'] });

    let reqId = 1;
    const callbacks = new Map();

    const rl = readline.createInterface({ input: child.stdout, terminal: false });
    rl.on('line', (line) => {
        if (!line.trim()) return;
        try {
            const msg = JSON.parse(line);
            if (msg.id && callbacks.has(msg.id)) {
                const cb = callbacks.get(msg.id);
                callbacks.delete(msg.id);
                cb(null, msg);
            }
        } catch (e) {
            console.error('Error parsing server line:', e);
        }
    });

    child.stderr.on('data', (d) => console.error('StudioMCP STDERR:', d.toString()));

    function sendRequest(method, params) {
        return new Promise((resolve, reject) => {
            const id = reqId++;
            callbacks.set(id, (err, res) => {
                if (err) reject(err);
                else resolve(res);
            });
            const payload = JSON.stringify({ jsonrpc: '2.0', id, method, params });
            child.stdin.write(payload + '\n');
        });
    }

    // 1. Initialize
    console.log('Sending initialize...');
    await sendRequest('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'CaptureClient', version: '1.0' }
    });
    console.log('StudioMCP initialized!');

    function execLuau(code, datamodel_type = 'Client') {
        return sendRequest('tools/call', {
            name: 'execute_luau',
            arguments: { code, datamodel_type, studio_id: studioId }
        });
    }

    async function takeScreenshot(filename, camera_position, look_at_position) {
        console.log('Capturing:', filename);
        const args = {
            capture_id: filename,
            studio_id: studioId
        };
        if (camera_position && look_at_position) {
            args.camera_position = camera_position;
            args.look_at_position = look_at_position;
        }

        const res = await sendRequest('tools/call', {
            name: 'screen_capture',
            arguments: args
        });

        if (res.result && res.result.content) {
            for (const item of res.result.content) {
                if (item.type === 'image' && item.data) {
                    const buf = Buffer.from(item.data, 'base64');
                    fs.writeFileSync(path.join(dir1, filename), buf);
                    fs.writeFileSync(path.join(dir2, filename), buf);
                    console.log(` -> Saved ${filename} (${buf.length} bytes) to C:\\RGame\\screenshots`);
                    return true;
                }
            }
        }
        console.warn(' -> No image data found in response for', filename);
        return false;
    }

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));

    // ==========================================
    // CAPTURE ALL UI PAGES AND OVERLAYS
    // ==========================================

    // 1. Main Gameplay HUD
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = false end
        end
        pg.V7ForgeGui.Frame.Visible = false
        pg.V7HUDGui.Enabled = true
    `);
    await sleep(200);
    await takeScreenshot('01_main_gameplay_hud.png');

    // 2. Forge Panel
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = false end
        end
        pg.V7ForgeGui.Frame.Visible = true
    `);
    await sleep(200);
    await takeScreenshot('02_forge_panel.png');

    // 3. Shapes Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_shapes") end
        end
    `);
    await sleep(200);
    await takeScreenshot('03_overlay_shapes.png');

    // 4. Slots Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_slots") end
        end
    `);
    await sleep(200);
    await takeScreenshot('04_overlay_slots.png');

    // 5. Ascension Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_ascend") end
        end
    `);
    await sleep(200);
    await takeScreenshot('05_overlay_ascension.png');

    // 6. Shop Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_shop") end
        end
    `);
    await sleep(200);
    await takeScreenshot('06_overlay_shop.png');

    // 7. Leaderboards Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_boards") end
        end
    `);
    await sleep(200);
    await takeScreenshot('07_overlay_leaderboards.png');

    // 8. Quests Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_quests") end
        end
    `);
    await sleep(200);
    await takeScreenshot('08_overlay_quests.png');

    // 9. Vault Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_vault") end
        end
    `);
    await sleep(200);
    await takeScreenshot('09_overlay_vault.png');

    // 10. Settings Overlay
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        pg.V7ForgeGui.Frame.Visible = false
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = (ov.Name == "Overlay_settings") end
        end
    `);
    await sleep(200);
    await takeScreenshot('10_overlay_settings.png');

    // Hide all overlays and HUD for 3D dice captures
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        local pg = lp.PlayerGui
        for _, ov in ipairs(pg.V7MenuGui:GetChildren()) do
            if ov:IsA("Frame") then ov.Visible = false end
        end
        pg.V7ForgeGui.Frame.Visible = false
        pg.V7HUDGui.Enabled = false
    `);

    // ==========================================
    // CAPTURE ALL 12 PROCEDURAL 3D DICE MODELS
    // ==========================================
    const dice = [
        { name: '11_die_D2.png', x: -46.2 },
        { name: '12_die_D3.png', x: -37.8 },
        { name: '13_die_D4.png', x: -29.4 },
        { name: '14_die_D5.png', x: -21.0 },
        { name: '15_die_D6.png', x: -12.6 },
        { name: '16_die_D7.png', x: -4.2 },
        { name: '17_die_D8.png', x: 4.2 },
        { name: '18_die_D10.png', x: 12.6 },
        { name: '19_die_D12.png', x: 21.0 },
        { name: '20_die_D14.png', x: 29.4 },
        { name: '21_die_D16.png', x: 37.8 },
        { name: '22_die_D20.png', x: 46.2 },
    ];

    for (const d of dice) {
        const camPos = [d.x + 5.5, 4.0 + 4.5, 5.5];
        const lookPos = [d.x, 4.0, 0.0];
        await takeScreenshot(d.name, camPos, lookPos);
    }

    // 23. Full 12-Dice Set Overview
    await takeScreenshot('23_all_dice_set_overview.png', [0, 24, 60], [0, 4, 0]);

    // Restore HUD
    await execLuau(`
        local lp = game:GetService("Players").LocalPlayer
        lp.PlayerGui.V7HUDGui.Enabled = true
    `);

    console.log('All screenshots captured and saved successfully!');
    child.kill();
    process.exit(0);
}

main().catch(err => {
    console.error('Fatal error in capture script:', err);
    process.exit(1);
});
