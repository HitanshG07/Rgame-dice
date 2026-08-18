const fs = require('fs');
const src = 'C:\\RGame\\screenshots\\quest_variant_a_machinist.png';
const dst = 'C:\\Users\\Hitansh Gogri\\.gemini\\antigravity-ide\\brain\\cbe5a261-05be-4b9b-a450-a0a97c7eb194\\quest_option_a_readable.png';
fs.copyFileSync(src, dst);
console.log('Copied readable Option A to artifacts');
