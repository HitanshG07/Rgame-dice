const fs = require('fs');
const filePath = 'C:\\RGame\\src\\Client\\V7MenuPanel.luau';
const content = fs.readFileSync(filePath, 'utf8');
const lines = content.split('\n');

console.log('Total lines:', lines.length);
// Line 3045 in 1-based indexing is index 3044
console.log('Line 3045 is:', lines[3044]);
// Line 4004 in 1-based indexing is index 4003
console.log('Line 4004 is:', lines[4003]);
console.log('Line 4005 is:', lines[4004]);

if (lines[3044].includes('5. QUESTS OVERLAY') && lines[4004].includes('local vaultOverlay')) {
    const before = lines.slice(0, 3044);
    const replacement = [
        '\t-- 5. QUESTS OVERLAY (Approved Master Design: Dual-Column Quests & Progression)',
        '\tlocal refreshQuests = buildQuestsOverlay(screenGui, overlays)',
        ''
    ];
    const after = lines.slice(4004);
    const newContent = before.concat(replacement).concat(after).join('\n');
    fs.writeFileSync(filePath, newContent, 'utf8');
    console.log('Successfully replaced inline quests section with buildQuestsOverlay call!');
} else {
    console.error('Line markers did not match!');
}
