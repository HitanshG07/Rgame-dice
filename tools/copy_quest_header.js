const fs = require('fs');
const src = 'C:\\RGame\\screenshots\\quest_variant_a_machinist.png';
const dst = 'C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\quests_header_updated.png';
fs.copyFileSync(src, dst);
console.log('Copied updated QUESTS capture to artifacts');
