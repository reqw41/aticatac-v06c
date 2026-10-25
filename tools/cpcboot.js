// Общие помощники стендов CPC: снимок экрана для tools/cpcshot.py, старт игры из меню.
'use strict';
const fs = require('fs');
function shot(m, file) {
  const b = Buffer.alloc(0x4015);
  const base = (m.crtc[12] & 0x30) << 10;
  for (let i = 0; i < 0x4000; i++) b[i] = m.ram[(base + i) & 0xffff];
  for (let i = 0; i < 17; i++) b[0x4000 + i] = m.pens[i];
  b[0x4011] = m.mode; b[0x4012] = m.crtc[1]; b[0x4013] = m.crtc[6]; b[0x4014] = m.crtc[9];
  fs.writeFileSync(file, b);
}
module.exports = { shot };
