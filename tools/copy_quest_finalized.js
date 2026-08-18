const fs = require('fs');
const src = 'C:\\RGame\\screenshots\\quest_variant_a_machinist.png';
const dst = 'C:\\RGame\\artifacts\\quests_option_a_finalized.png';
fs.copyFileSync(src, dst);
console.log('Copied finalized Option A capture to artifacts');
