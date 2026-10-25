#!/usr/bin/env node
// Прогон JS-модели по эталону без процессора (docs/LOGIC_PLAN.md): начальное состояние — снимок эталона
// (first), на каждом шаге — очереди чтений адресов прерывания (rd) и ld a,r (r) из эталона; модель
// выполняет задачу шага (game_tasks / falling_tasks / end_tasks) и сравнивает изменения с эталоном (d)
// и звуки (sfx). Адреса вывода (index.drawOnly) не сверяются.
//   node tools/model_run.js build/golden/<имя>.json.gz [...]
'use strict';
const fs = require('fs');
const zlib = require('zlib');
const { S, Mem } = require('../src/model/core');
const model = require('../src/model');
const game = require('../src/model/game');
const state = require('../src/model/state');

const TASK = { [S.game_tasks]: game.game_tasks, [S.falling_tasks]: game.falling_tasks, [S.end_tasks]: state.end_tasks };

function runOne(file) {
  const g = JSON.parse(zlib.gunzipSync(fs.readFileSync(file)));
  const ram = new Uint8Array(0x20000);
  g.regions.forEach(([a], k) => ram.set(Buffer.from(g.first[k], 'base64'), a));
  const owned = new Set(g.owned);
  const real = new Uint8Array(ram);                // эталонное состояние (по изменениям d)
  let bad = 0, run = 0, skipped = 0, shown = 0;
  const STACK_LO = 0x3e00, STACK_HI = 0x4000;
  const inRegions = (f) => g.regions.some(([a, b]) => f >= a && f < b);
  for (let t = 0; t < g.ticks.length; t++) {
    const tk = g.ticks[t];
    const fn = TASK[tk.task];
    for (const [a, v] of tk.pk || []) { real[a] = v; ram[a] = v; }
    for (const [a, v] of tk.d) real[a] = v;
    if (!fn) { ram.set(real); skipped++; continue; }    // меню: состояние берётся из эталона
    // memory_bank и окно на начало шага: банк, выбранный в конце прошлого шага (на CPC он сохраняется)
    const mem = new Mem(ram, ram[S.memory_bank] & 7);
    mem.owned = owned;
    for (const [a, v] of tk.rd) { let q = mem.q.get(a); if (!q) mem.q.set(a, q = []); q.push(v); }
    mem.rq = tk.r.slice();
    mem.writes = new Set();
    try { fn(mem); } catch (e) {
      if (e.notModeled) { ram.set(real); skipped++; continue; }
      throw e;
    }
    run++;
    const diffs = [];
    const check = new Set([...mem.writes, ...tk.d.map((x) => x[0])]);
    for (const f of check) {
      if (!inRegions(f) || owned.has(f) || model.drawOnly.has(f) || (f >= STACK_LO && f < STACK_HI)) continue;
      if (ram[f] !== real[f]) diffs.push([f, real[f], ram[f]]);
    }
    if (mem.sfx.join(',') !== tk.sfx.join(',')) diffs.push(['звуки', tk.sfx.join(','), mem.sfx.join(',')]);
    if (diffs.length) {
      bad++;
      if (shown++ < 5) console.log(`  шаг ${t}: ` + diffs.slice(0, 6).map(([f, r, m]) => `${typeof f === 'number' ? f.toString(16) : f}: CPC ${r} модель ${m}`).join('; '));
    }
    ram.set(real);                                   // дальше — с эталонного состояния
  }
  console.log(`${g.name}: шагов ${g.ticks.length}, модель ${run}, расхождений ${bad}, без модели ${skipped}`);
  return bad === 0;
}

let ok = true;
for (const f of process.argv.slice(2)) ok = runOne(f) && ok;
process.exit(ok ? 0 : 1);
