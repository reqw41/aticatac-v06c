#!/usr/bin/env node
// Какие места страницы 0 CPC (0x0100..code_end) нужны логике: прогон JS-модели по эталонам, учёт всех
// чтений и записей; нужной считается вся метка (от неё до следующей), если тронут хоть один её байт.
// Дыра = метка, которую Z80 исполнял как код (прогоны сценариев на модели CPC, вместе с меню и
// прерываниями) и к которой логика не обращалась как к данным. Неисполнявшееся остаётся (это данные).
//   node tools/holes.js build/golden/*.json.gz [--min 64]
'use strict';
const fs = require('fs'), zlib = require('zlib');
const { S, Mem } = require('../src/model/core');
const game = require('../src/model/game'), state = require('../src/model/state');
const args = process.argv.slice(2); let min = 64; const files = [];
for (let i = 0; i < args.length; i++) { if (args[i] === '--min') min = +args[++i]; else files.push(args[i]); }
const used = new Uint8Array(0x4000);
const TASK = { [S.game_tasks]: game.game_tasks, [S.falling_tasks]: game.falling_tasks, [S.end_tasks]: state.end_tasks };
for (const f of files) {
  const g = JSON.parse(zlib.gunzipSync(fs.readFileSync(f)));
  const ram = new Uint8Array(0x20000);
  g.regions.forEach(([a], k) => ram.set(Buffer.from(g.first[k], 'base64'), a));
  const mark = (fa) => { if (fa < 0x4000) used[fa] = 1; };
  for (const tk of g.ticks) {
    const fn = TASK[tk.task];
    for (const [a, v] of tk.pk || []) ram[a] = v;
    if (fn) {
      const M = new Mem(ram, ram[S.memory_bank] & 7);
      M.owned = new Set(g.owned);
      for (const [a, v] of tk.rd) { let q = M.q.get(a); if (!q) M.q.set(a, q = []); q.push(v); }
      M.rq = tk.r.slice();
      const rd = M.rd.bind(M), wr = M.wr.bind(M);
      M.rd = (a) => { mark(M.flat(a)); return rd(a); };
      M.wr = (a, v) => { mark(M.flat(a)); wr(a, v); };
      try { fn(M); } catch (e) { if (!e.notModeled) throw e; }
      if (tk === g.ticks[0]) { const M2 = new Mem(ram.slice(), 0); M2.rq = []; M2.ldar = () => 0;
        const r2 = M2.rd.bind(M2), w2 = M2.wr.bind(M2); M2.rd = (a) => { mark(M2.flat(a)); return r2(a); }; M2.wr = (a, v) => { mark(M2.flat(a)); w2(a, v); }; state.select_game(M2); }
    }
    for (const [a, v] of tk.d) ram[a] = v;
  }
}
// исполнявшийся код: прогоны сценариев эталонов на модели CPC
const exec = new Uint8Array(0x4000);
{
  const scenario = require('./scenario');
  for (const f of files) {
    const name = require('path').basename(f, '.json.gz');
    const sc = JSON.parse(fs.readFileSync('research/scenarios/' + name + '.json', 'utf8'));
    sc.ticks = Math.min(sc.ticks || 1e9, 4000);
    const { m, keysFor } = scenario.start(sc, { step: (mm) => { if (mm.pc < 0x4000) exec[mm.pc] = 1; mm.step(); } });
    for (let t = 0; ; t++) {
      const keys = keysFor(t); if (!keys) break;
      m.keysOnly(keys); m.step();
      while (m.pc !== scenario.SYM.current_game_state) { if (m.pc < 0x4000) exec[m.pc] = 1; m.step(); }
    }
  }
}
const labs = Object.entries(S).filter(([k, v]) => v >= 0x100 && v < S.code_end).sort((a, b) => a[1] - b[1]);
const keep = new Uint8Array(0x4000);
for (let i = 0; i < labs.length; i++) {
  const a = labs[i][1], b = i + 1 < labs.length ? labs[i + 1][1] : S.code_end;
  let any = false, code = false;
  for (let p = a; p < b; p++) { if (used[p]) any = true; if (exec[p]) code = true; }
  if (any || !code) for (let p = a; p < b; p++) keep[p] = 1;
}
const holes = []; let st = -1;
for (let p = 0x100; p <= S.code_end; p++) {
  const free = p < S.code_end && !keep[p];
  if (free && st < 0) st = p;
  if (!free && st >= 0) { holes.push([st, p]); st = -1; }
}
const big = holes.filter(([a, b]) => b - a >= min);
let tot = 0; for (const [a, b] of holes) tot += b - a;
let totBig = 0; for (const [a, b] of big) totBig += b - a;
console.log(`нужно логике: ${0x4000 - 0x100 - tot - (0x4000 - S.code_end)} Б; дыр всего ${tot} Б, из них >= ${min}: ${big.length} шт., ${totBig} Б`);
for (const [a, b] of big.sort((x, y) => (y[1] - y[0]) - (x[1] - x[0])).slice(0, 25)) {
  const nm = labs.filter(([k, v]) => v >= a && v < b).map(([k]) => k);
  console.log(`  ${a.toString(16)}..${b.toString(16)}  ${String(b - a).padStart(5)}  ${nm.slice(0, 4).join(' ')}${nm.length > 4 ? ' …' : ''}`);
}
fs.writeFileSync('build/l80/holes.json', JSON.stringify({ holes: big, keep: Buffer.from(keep).toString('base64') }));
