#!/usr/bin/env node
// Теневая проверка JS-модели (docs/LOGIC_PLAN.md): игра идёт на модели CPC (tools/cpc6128.js) по сценарию;
// на входе в подпрограмму, которая есть в модели (src/model/index.js), снимается память и регистры,
// настоящий Z80 доходит до возврата (пишутся его записи, чтения адресов прерывания, ld a,r, звуки),
// затем модель выполняет ту же подпрограмму на снимке, и сравниваются все записанные кем-либо адреса
// (кроме адресов прерывания, стека и экранов) и выходные регистры. Вложенные вызовы проверяются отдельно.
//
//   node tools/shadow.js <сценарий.json> [имя,имя,...] [--ticks N] [--max 5]
'use strict';
const fs = require('fs');
const path = require('path');
const scenario = require('./scenario');
const { SYM } = scenario;
const model = require('../src/model');
const { Mem } = require('../src/model/core');

const args = process.argv.slice(2);
const sc = JSON.parse(fs.readFileSync(args[0], 'utf8'));
let only = null, maxShow = 5;
for (let i = 1; i < args.length; i++) {
  if (args[i] === '--ticks') sc.ticks = +args[++i];
  else if (args[i] === '--max') maxShow = +args[++i];
  else only = new Set(args[i].split(','));
}
const names = Object.keys(model.routines).filter((n) => !only || only.has(n));
const entry = new Map();
for (const n of names) {
  if (SYM[n] === undefined) throw new Error('нет метки ' + n);
  entry.set(SYM[n], n);
}

// адреса прерывания: предварительный прогон
const { run } = require('./cpc_trace');
const learn = new Set();
run(Object.assign({}, sc, { ticks: Math.min(sc.ticks || 1e9, 1500) }), null, learn);
const STACK_LO = 0x3e00, STACK_HI = 0x4000;
const m0page = (n) => n < 4 ? n * 0x4000 : 0x10000 + (n - 4) * 0x4000;   // страница 6 — состояние звукового плеера
const owned = new Set([...learn].filter((a) => !(a >= STACK_LO && a < STACK_HI)));
const PAGE6 = m0page(6);
const skipCmp = (f) => model.drawOnly.has(f) || owned.has(f) || (f >= STACK_LO && f < STACK_HI) || (f >= 0x8000 && f < 0x10000) || (f >= PAGE6 && f < PAGE6 + 0x4000);

const active = [];                       // стек проверок
let m = null;
const onCreate = (mm) => {
  m = mm;
  m.onWrite = (a, v, isr) => { if (!isr && active.length) { const f = m._map(a); for (const c of active) c.w.add(f); } };
  m.onRead = (a, v, isr) => {
    if (isr || !active.length) return;
    const f = m._map(a);
    if (!owned.has(f)) return;
    for (const c of active) { let q = c.q.get(f); if (!q) c.q.set(f, q = []); q.push(v); }
  };
};
const stat = {};
for (const n of names) stat[n] = { calls: 0, bad: 0, skip: 0 };
let shown = 0, tick = 0;
const regNames = ['a', 'b', 'c', 'd', 'e', 'h', 'l'];

function finish(c) {
  const st = stat[c.name]; st.calls++;
  const mem = new Mem(c.ram, c.cfg);
  mem.owned = owned; mem.q = c.q; mem.rq = c.r.slice(); mem.writes = new Set();
  let out;
  try {
    out = model.routines[c.name](mem, c.regs);
  } catch (e) {
    if (e.notModeled) { st.skip++; return; }
    throw e;
  }
  const diffs = [];
  const all = new Set([...c.w, ...mem.writes]);
  for (const f of all) {
    if (skipCmp(f)) continue;
    if (m.ram[f] !== c.ram[f]) diffs.push([f, m.ram[f], c.ram[f]]);
  }
  const want = model.routines[c.name].out || [];
  const cs = want.length ? m.cpu.getState() : null;
  for (const r of want) {
    const real = r === 'ix' || r === 'iy' ? cs[r] : r[0] === 'f' ? cs.flags[r[1].toUpperCase()] : cs[r];
    if (!out || out[r] !== real) diffs.push(['рег ' + r, real, out && out[r]]);
  }
  const msfx = mem.sfx.join(','), rsfx = c.sfx.join(',');
  if (msfx !== rsfx) diffs.push(['звуки', rsfx, msfx]);
  if (diffs.length) {
    st.bad++;
    if (shown++ < maxShow) {
      const nm = (f) => {
        if (typeof f !== 'number') return f;
        if (f < 0x4000) { let best = '?', bv = -1; for (const [k, v] of Object.entries(SYM)) if (v <= f && v > bv && v >= 0x100) { best = k; bv = v; } return best + (f - bv ? '+' + (f - bv) : '') + '(' + f.toString(16) + ')'; }
        return 'стр' + (f < 0x10000 ? f >> 14 : 4 + ((f - 0x10000) >> 14)) + ':' + (0x4000 | (f & 0x3fff)).toString(16);
      };
      console.log(`шаг ${tick} ${c.name}: ${diffs.length} расхождений; вход ${JSON.stringify(c.regs)}`);
      for (const [f, r, mm] of diffs.slice(0, 8)) console.log(`   ${nm(f)}: CPC ${r} модель ${mm}`);
    }
  }
}

// один шаг машины с проверками: вход в смоделированную подпрограмму, ld a,r, звуки, возвраты
function shadowStep(mm) {
  const pc = m.pc;
  // на этом шаге подаётся прерывание — команда по pc не выполняется (выполнится после возврата)
  if (m.intPending && m.cpu.get_iff1()) { m.step(); return; }
  if (!m.inIsr) {
    const n = entry.get(pc);
    if (n) {
      const s = m.cpu.getState();
      const regs = { a: s.a, b: s.b, c: s.c, d: s.d, e: s.e, h: s.h, l: s.l, ix: s.ix, iy: s.iy,
        fz: s.flags.Z, fc: s.flags.C };
      active.push({ name: n, ram: m.ram.slice(), cfg: m.cfg, regs, sp: s.sp, ret: m.peek(s.sp) | m.peek(s.sp + 1) << 8,
        w: new Set(), q: new Map(), r: [], sfx: [] });
    }
    if (pc === SYM.ply_akg_playsoundeffect && active.length) { const a = m.cpu.get_a(); for (const c of active) c.sfx.push(a); }
  }
  const isLdAR = !m.inIsr && active.length && m.peek(pc) === 0xed && m.peek(pc + 1) === 0x5f;
  m.step();
  if (isLdAR) { const a = m.cpu.get_a(); for (const c of active) c.r.push(a); }
  while (active.length && !m.inIsr) {
    const c = active[active.length - 1];
    if (m.pc === c.ret && m.cpu.get_sp() === ((c.sp + 2) & 0xffff)) { active.pop(); finish(c); } else break;
  }
}

const { keysFor } = scenario.start(sc, { onCreate, step: shadowStep });
for (let t = 0; ; t++) {
  tick = t;
  const keys = keysFor(t);
  if (!keys) break;
  m.keysOnly(keys);
  shadowStep(m);
  while (!(m.pc === SYM.current_game_state && !m.inIsr)) shadowStep(m);
}
let ok = true;
for (const n of names) {
  const s = stat[n];
  if (s.bad) ok = false;
  console.log(`${n.padEnd(28)} вызовов ${String(s.calls).padStart(6)}  расхождений ${String(s.bad).padStart(5)}  не смоделировано ${s.skip}`);
}
process.exit(ok ? 0 : 1);
