#!/usr/bin/env node
// Покрытие кода игры сценариями: какие метки страницы 0 (0x100..code_end) ни разу не выполнялись игрой
// (не обработчиком прерываний) в шагах после старта.  node tools/coverage.js <сценарий.json>...
'use strict';
const fs = require('fs');
const scenario = require('./scenario');
const { SYM } = scenario;
const hit = new Uint8Array(0x10000);
for (const f of process.argv.slice(2)) {
  const sc = JSON.parse(fs.readFileSync(f, 'utf8'));
  const { m, keysFor } = scenario.start(sc);
  for (let t = 0; ; t++) {
    const keys = keysFor(t);
    if (!keys) break;
    m.keysOnly(keys);
    m.step();
    while (!(m.pc === SYM.current_game_state && !m.inIsr)) { if (!m.inIsr && m.pc < 0x4000) hit[m.pc] = 1; m.step(); }
  }
}
const labs = Object.entries(SYM).filter(([k, v]) => v >= 0x100 && v < SYM.code_end).sort((a, b) => a[1] - b[1]);
const miss = [];
for (let i = 0; i < labs.length; i++) {
  const [k, a] = labs[i], end = i + 1 < labs.length ? labs[i + 1][1] : SYM.code_end;
  let any = false; for (let p = a; p < end; p++) if (hit[p]) { any = true; break; }
  if (!any) miss.push(k);
}
console.log('не выполнялись (' + miss.length + ' из ' + labs.length + '):\n' + miss.join(' '));
