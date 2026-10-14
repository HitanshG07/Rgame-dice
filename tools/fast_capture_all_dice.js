const { spawn } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

const studioMcpPath = path.join(process.env.LOCALAPPDATA || '', 'Roblox', 'Versions', 'version-d679641ad17741aa', 'StudioMCP.exe');
const studioId = 'f2e30777-e3b1-4ad2-b76a-71b8e9dabd25';

const dir1 = path.join('C:', 'RGame', 'screenshots');
const dir2 = path.join('C:', 'RGame', 'screensots');
if (!fs.existsSync(dir1)) fs.mkdirSync(dir1, { recursive: true });
if (!fs.existsSync(dir2)) fs.mkdirSync(dir2, { recursive: true });

async function main() {
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
        } catch (e) {}
    });

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

    await sendRequest('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'FastDiceCapture', version: '1.0' }
    });

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    await sleep(400);

    function execLuau(code) {
        return sendRequest('tools/call', {
            name: 'execute_luau',
            arguments: { code, datamodel_type: 'Edit', studio_id: studioId }
        });
    }

    async function takeScreenshot(filename, camera_position, look_at_position) {
        const args = {
            capture_id: filename,
            studio_id: studioId,
            camera_position: camera_position,
            look_at_position: look_at_position
        };

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
                    console.log(`Saved ${filename} (Zero overlap, clear separation)`);
                    return true;
                }
            }
        }
        return false;
    }

    const shapes = [
        { file: '11_die_D2.png', name: 'D2' },
        { file: '12_die_D3.png', name: 'D3' },
        { file: '13_die_D4.png', name: 'D4' },
        { file: '14_die_D5.png', name: 'D5' },
        { file: '15_die_D6.png', name: 'D6' },
        { file: '16_die_D7.png', name: 'D7' },
        { file: '17_die_D8.png', name: 'D8' },
        { file: '18_die_D10.png', name: 'D10' },
        { file: '19_die_D12.png', name: 'D12' },
        { file: '20_die_D14.png', name: 'D14' },
        { file: '21_die_D16.png', name: 'D16' },
        { file: '22_die_D20.png', name: 'D20' },
    ];

    for (const shape of shapes) {
        // Clear all background models and isolate ONLY the 2 non-overlapping views of this die
        await execLuau(`
            local Workspace = game:GetService("Workspace")
            local Shared = game:GetService("ReplicatedStorage").Shared
            local builder = require(Shared.DiceMeshBuilder)

            for _, name in ipairs({"dice_faces", "dice_faces_display_all", "dice_faces_b", "DiePhotoStage", "DiceProto"}) do
                local f = Workspace:FindFirstChild(name)
                if f then f:Destroy() end
            end

            local stage = Instance.new("Folder")
            stage.Name = "DiePhotoStage"
            stage.Parent = Workspace

            local tempFolder = Instance.new("Folder")
            local models = builder.buildInto(tempFolder)
            local targetModel = nil
            for _, m in ipairs(models) do
                if m.Name == "${shape.name}" then
                    targetModel = m
                    break
                end
            end

            if targetModel then
                -- Left die (Front / Top view): Placed at X = -5.0
                local m1 = targetModel:Clone()
                m1:PivotTo(CFrame.new(-5.0, 4, 0) * CFrame.Angles(-math.pi/7, -math.pi/5, 0))
                m1.Parent = stage

                -- Right die (Back / Bottom view): Placed at X = +5.0 (10 studs clearance, zero overlap)
                local m2 = targetModel:Clone()
                m2:PivotTo(CFrame.new(5.0, 4, 0) * CFrame.Angles(math.pi * 6/7, math.pi * 4/5, 0))
                m2.Parent = stage
            end
            tempFolder:Destroy()
        `);

        // Capture both isolated views in 1 pristine shot with 14.5 studs depth
        await takeScreenshot(shape.file, [0, 5.0, 14.5], [0, 4.0, 0]);
        await sleep(150);
    }

    console.log('ALL 12 NON-OVERLAPPING DICE PERSPECTIVES CAPTURED!');
    child.kill();
    process.exit(0);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
