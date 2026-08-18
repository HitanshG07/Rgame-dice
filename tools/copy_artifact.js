const fs = require('fs');
const src = 'C:\\RGame\\screenshots\\studio_fresh_ascend.png';
const dst = 'C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\sovereign_vault_live_perfect.png';
fs.copyFileSync(src, dst);
console.log('Copied verified capture to artifacts');
