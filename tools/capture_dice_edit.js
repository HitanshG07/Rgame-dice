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
    console.log('Spawning StudioMCP for Edit Mode dice captures...');
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
        clientInfo: { name: 'DiceCaptureClient', version: '1.0' }
    });

    async function takeScreenshot(filename, camera_position, look_at_position) {
        console.log('Capturing:', filename);
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
                    console.log(` -> Saved ${filename} (${buf.length} bytes) to C:\\RGame\\screenshots`);
                    return true;
                }
            }
        }
        console.warn(' -> No image data found in response for', filename);
        return false;
    }

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));

    const dice = [
        { name: '11_die_D2.png', x: -46.20 },
        { name: '12_die_D3.png', x: -37.80 },
        { name: '13_die_D4.png', x: -29.40 },
        { name: '14_die_D5.png', x: -21.00 },
        { name: '15_die_D6.png', x: -12.60 },
        { name: '16_die_D7.png', x: -4.20 },
        { name: '17_die_D8.png', x: 4.20 },
        { name: '18_die_D10.png', x: 12.60 },
        { name: '19_die_D12.png', x: 21.00 },
        { name: '20_die_D14.png', x: 29.40 },
        { name: '21_die_D16.png', x: 37.80 },
        { name: '22_die_D20.png', x: 46.20 },
    ];

    for (const d of dice) {
        // Position camera ~6.5 studs away angled from top-front-right
        const camPos = [d.x + 3.8, 4.0 + 3.2, 4.5];
        const lookPos = [d.x, 4.0, 0.0];
        await takeScreenshot(d.name, camPos, lookPos);
        await sleep(150);
    }

    // 23. Full Set Overview
    await takeScreenshot('23_all_dice_set_overview.png', [0, 22, 55], [0, 4, 0]);

    console.log('All individual dice captured successfully in Edit mode!');
    child.kill();
    process.exit(0);
}

main().catch(err => {
    console.error('Fatal error in capture script:', err);
    process.exit(1);
});
