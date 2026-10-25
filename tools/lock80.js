#!/usr/bin/env node
// Сверка логики i8080 (src/i8080/logic.asm -> build/l80/logic.bin) с JS-моделью (docs/LOGIC_PLAN.md, этап 2).
//
// JS-модель идёт непрерывно по эталону (build/golden/*.json.gz) с фиксированным вводом на шаг (последнее
// значение каждого адреса прерывания из rd), общей очередью ld a,r и телепортами сценария. Функции модели,
// у которых в сборке i8080 есть одноимённая метка, обёрнуты: на каждом вызове та же подпрограмма i8080
// выполняется на зеркале памяти (то же состояние), и сравниваются все записанные кем-либо адреса, звуки,
// число взятых случайных чисел и выходные регистры. Записи i8080 после проверки откатываются.
//
// Память i8080 (раскладка на время сверки): страница 0 CPC — по своим адресам (0x0000..0x3FFF), банк
// комнат — 0x4000, еда (food_items, банк героев CPC 0x5FD8) — FOOD80, таблица предметов (ширина, высота)
// и код — в сборке. Указатели на еду переводятся.
//   node tools/lock80.js build/golden/<имя>.json.gz [--ticks N] [--max 5] [имя,имя]
'use strict';
const fs = require('fs');
const zlib = require('zlib');
const path = require('path');
const CPU80 = require('./cpu80');
const { S, Mem, ROOT } = require('../src/model/core');
const model = require('../src/model');

const args = process.argv.slice(2);
let maxTicks = 1e9, maxShow = 5, only = null;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--ticks') maxTicks = +args[++i];
  else if (args[i] === '--max') maxShow = +args[++i];
  else if (args[i].endsWith('.gz')) files.push(args[i]);
  else only = new Set(args[i].split(','));
}

// --- сборка i8080
const SYM80 = {};
for (const l of fs.readFileSync(path.join(ROOT, 'build/l80/logic.sym'), 'latin1').split('\n')) {
  const m = l.match(/^(\w+):\s+EQU\s+0x([0-9A-F]+)/i); if (m) SYM80[m[1]] = parseInt(m[2], 16);
}
const code = fs.readFileSync(path.join(ROOT, 'build/l80/logic.bin'));
const CODE0 = SYM80.CODE80, FOOD80 = SYM80.FOOD80, R_BUF = SYM80.r_buf, R_IDX = SYM80.r_idx,
  SFX_BUF = SYM80.sfx_buf, SFX_N = SYM80.sfx_n;
const FOODC = 0x10000 + (S.food_items - 0x4000), FOODN = S.food_items_end - S.food_items;

// плоский адрес модели -> адрес i8080 (или -1)
function vecOf(f) {
  if (f >= 0x0100 && f < 0x3e00) return f;
  if (f >= 0x14000 && f < 0x18000) return f - 0x14000 + 0x4000;
  if (f >= FOODC && f < FOODC + FOODN) return FOOD80 + (f - FOODC);
  return -1;
}
const foodPtr = (v) => (v >= S.food_items && v < S.food_items_end ? v - S.food_items + FOOD80 : v);
const PTRS = [S.erase_food_with_index, S.draw_tombstone_with_index];
for (let i = 0; i < S.max_food; i++) PTRS.push(S.this_rooms_food_list + 2 * i);
const ptrByte = new Map();                       // адрес байта указателя -> адрес слова
for (const p of PTRS) { ptrByte.set(p, p); ptrByte.set(p + 1, p); }

// --- регистрация проверяемых подпрограмм: модуль, функция, регистры входа, выход
const R = {};
function reg(name, mod, fn, regs, out) { R[name] = { mod: require('../src/model/' + mod), fn: fn || name, regs, out }; }
const hl = (v) => ({ h: v >> 8, l: v & 0xff });
reg('check_corner_collision', 'playermove', null, (M, y, x) => ({ a: y, b: x }), (r) => ({ a: r.a, b: r.b }));
reg('check_collision', 'playermove', null, null, (r) => ({ a: r }));
reg('check_collision_squares', 'playermove');
reg('move_player', 'playermove');
reg('update_sprite', 'sprite', null, (M, ix) => hl(ix));
reg('kill_sprite', 'sprite', null, (M, ix) => hl(ix));
reg('reset_sprites', 'sprite');
reg('random_sprite_action', 'sprite', null, (M, ix) => hl(ix));
reg('fire_weapon', 'weapon');
reg('move_weapon', 'weapon');
reg('draw_weapon', 'weapon');
reg('check_weapon_hit', 'weapon');
reg('add_to_score', 'score', null, (M, bc) => ({ b: bc >> 8, c: bc & 0xff }));
reg('update_boss', 'boss', null, (M, ix) => hl(ix));
reg('init_boss', 'boss');
reg('try_teleport_dracula', 'boss');
reg('init_doors', 'doors');
reg('check_doors', 'doors');
reg('update_doors', 'doors');
reg('update_collision_grid_for_items', 'doors');
reg('draw_items', 'items');
reg('draw_room', 'room');
reg('check_player_hit_baddie', 'player');
reg('make_player_disappear', 'player');
reg('update_chicken', 'chicken');
reg('check_food_collision', 'food', null, (M, n) => ({ a: n }));
reg('replen_food', 'food');
reg('add_tombstone', 'food');
reg('pickup_tapped', 'collectables');
reg('game_tasks', 'game');
reg('falling_tasks', 'game');
reg('end_tasks', 'state');
reg('init_collectables', 'collectables');
reg('init_food', 'food');
reg('select_game', 'state');
reg('switch_game_state', 'state', null, (M, b) => ({ b }));

// --- зеркало памяти i8080
const cpu = new CPU80();
cpu.mem.set(code, CODE0);
let jsRam = null;                                // ram модели (Uint8Array 128 КБ)
const wlog = [];                                 // журнал записей модели (плоские адреса)
let synced = 0;
const activeChecks = [];                         // проверки, у которых идёт модель (для них — значения до вызова)
function setMirror(v, x) {
  if (cpu.mem[v] === x) return;
  for (const c of activeChecks) if (!c.pre.has(v)) c.pre.set(v, cpu.mem[v]);
  cpu.mem[v] = x;
}
function syncMirror() {
  for (; synced < wlog.length; synced++) {
    const f = wlog[synced], v = vecOf(f);
    if (v >= 0) setMirror(v, jsRam[f]);
  }
  for (const p of PTRS) { const w = foodPtr(jsRam[p] | jsRam[p + 1] << 8); setMirror(p, w & 0xff); setMirror(p + 1, w >> 8); }
}
function loadMirror() {
  for (let f = 0x0100; f < 0x3e00; f++) cpu.mem[f] = jsRam[f];
  for (let f = 0x14000; f < 0x18000; f++) cpu.mem[f - 0x14000 + 0x4000] = jsRam[f];
  for (let i = 0; i < FOODN; i++) cpu.mem[FOOD80 + i] = jsRam[FOODC + i];
  cpu.mem.set(code, CODE0);
  synced = wlog.length;
  syncMirror();
}

// --- общая очередь случайных чисел
const rstream = { v: [], i: 0 };

const stat = {};
let shown = 0, tickNo = 0, curFile = '';
const SYMNAME = Object.entries(S).filter(([k, v]) => v >= 0x100 && v < 0x4000).sort((a, b) => a[1] - b[1]);
function nm(f) {
  if (typeof f !== 'number') return f;
  if (f < 0x4000) { let b = '?', bv = 0; for (const [k, v] of SYMNAME) { if (v <= f) { b = k; bv = v; } else break; } return `${b}+${f - bv}(${f.toString(16)})`; }
  return 'flat ' + f.toString(16);
}

function wrap(name, spec) {
  const orig = spec.mod[spec.fn];
  if (typeof orig !== 'function') throw new Error('нет функции модели ' + spec.fn);
  stat[name] = { calls: 0, bad: 0, t: 0, tmax: 0 };
  spec.mod[spec.fn] = function (M, ...a) {
    const st = stat[name];
    syncMirror();
    // i8080 на зеркале
    const ri = rstream.i;
    for (let k = 0; k < 64; k++) cpu.mem[R_BUF + k] = rstream.v[ri + k] || 0;
    cpu.mem[R_IDX] = 0; cpu.mem[SFX_N] = 0;
    const undo = new Map();
    cpu.onWrite = (addr) => { if (!undo.has(addr)) undo.set(addr, cpu.mem[addr]); };
    const regs = spec.regs ? spec.regs(M, ...a) : {};
    const t = cpu.call(SYM80[name], regs);
    cpu.onWrite = null;
    const outV = spec.out ? { a: cpu.reg('a'), b: cpu.reg('b') } : null;
    const sfx80 = []; for (let k = 0; k < cpu.mem[SFX_N]; k++) sfx80.push(cpu.mem[SFX_BUF + k]);
    const r80 = cpu.mem[R_IDX];
    const res80 = new Map();                   // результат i8080, затем сразу откат (вложенные проверки — на чистом)
    for (const [v, old] of undo) { res80.set(v, cpu.mem[v]); cpu.mem[v] = old; }
    // модель
    const w0 = wlog.length, s0 = M.sfx.length;
    const chk = { pre: new Map() };
    activeChecks.push(chk);
    let res;
    try { res = orig.call(this, M, ...a); } finally { activeChecks.pop(); }
    st.calls++; st.t += t; if (t > st.tmax) st.tmax = t;
    // сравнение
    const diffs = [];
    const addrs = new Set();
    for (let k = w0; k < wlog.length; k++) addrs.add(wlog[k]);
    const back = new Map();                    // адрес i8080 -> плоский
    for (const f of addrs) { const v = vecOf(f); if (v >= 0) back.set(v, f); }
    for (const v of res80.keys()) if (!back.has(v)) {
      if (v >= 0x4000 && v < 0x8000) back.set(v, v - 0x4000 + 0x14000);
      else if (v >= FOOD80 && v < FOOD80 + FOODN) back.set(v, FOODC + v - FOOD80);
      else if (v < 0x3e00) back.set(v, v);
      else if (v < CODE0 && !(v >= R_BUF && v < R_BUF + 64) && v !== R_IDX && v !== SFX_N && !(v >= SFX_BUF && v < SFX_BUF + 16) && v < 0xff00)
        diffs.push(['запись i8080 вне состояния ' + v.toString(16), '', '']);
    }
    for (const [v, f] of back) {
      if (model.drawOnly.has(f) || ownedSet.has(f) || f === S.memory_bank) continue;
      if (f >= 0x3e00 && f < 0x4000) continue;
      let jv = jsRam[f];
      if (ptrByte.has(f)) { const p = ptrByte.get(f); const w = foodPtr(jsRam[p] | jsRam[p + 1] << 8); jv = f === p ? w & 0xff : w >> 8; }
      const e = res80.has(v) ? res80.get(v) : chk.pre.has(v) ? chk.pre.get(v) : cpu.mem[v];
      if (e !== jv) diffs.push([f, jv, e]);
    }
    const msfx = M.sfx.slice(s0).join(',');
    if (msfx !== sfx80.join(',')) diffs.push(['звуки', msfx, sfx80.join(',')]);
    if (rstream.i - ri !== r80) diffs.push(['ld a,r взято', rstream.i - ri, r80]);
    if (spec.out) {
      const want = spec.out(res);
      for (const k of Object.keys(want)) if (want[k] !== outV[k]) diffs.push(['рег ' + k, want[k], outV[k]]);
    }
    if (diffs.length) {
      st.bad++;
      if (shown++ < maxShow) {
        console.log(`${curFile} шаг ${tickNo} ${name}(${a.map((x) => typeof x === 'number' ? x.toString(16) : '').join(',')}): ${diffs.length} расхождений`);
        for (const [f, j, e] of diffs.slice(0, 8)) console.log(`   ${nm(f)}: модель ${j} i8080 ${e}`);
      }
    }
    return res;
  };
}
for (const [name, spec] of Object.entries(R)) if (SYM80[name] !== undefined && (!only || only.has(name))) wrap(name, spec);

// --- прогон
const game = require('../src/model/game');
const state = require('../src/model/state');
let ownedSet = new Set();
const TASK = { [S.game_tasks]: () => game.game_tasks, [S.falling_tasks]: () => game.falling_tasks, [S.end_tasks]: () => state.end_tasks };
// задача шага — из состояния модели (current_game_state + 1), не из эталона: модель с фиксированным вводом
// идёт своей дорогой
for (const file of files) {
  curFile = path.basename(file, '.json.gz');
  const g = JSON.parse(zlib.gunzipSync(fs.readFileSync(file)));
  jsRam = new Uint8Array(0x20000);
  g.regions.forEach(([a], k) => jsRam.set(Buffer.from(g.first[k], 'base64'), a));
  ownedSet = new Set(g.owned);
  wlog.length = 0;
  rstream.v = [].concat(...g.ticks.map((t) => t.r)); rstream.i = 0;
  loadMirror();
  {                                                 // каждый эталон — с новой игры (select_game и init_*)
    const M = new Mem(jsRam, jsRam[S.memory_bank] & 7);
    M.writes = { add: (f) => wlog.push(f) };
    M.ldar = () => rstream.v[rstream.i++] || 0;
    state.select_game(M);
  }
  let n = 0;
  for (let t = 0; t < g.ticks.length && n < maxTicks; t++, n++) {
    tickNo = t;
    const tk = g.ticks[t];
    const fnGet = TASK[jsRam[S.current_game_state + 1] | jsRam[S.current_game_state + 2] << 8];
    if (!fnGet) break;                             // меню — дальше состояние разошлось бы с эталоном
    const M = new Mem(jsRam, jsRam[S.memory_bank] & 7);
    M.writes = { add: (f) => wlog.push(f) };
    M.ldar = () => rstream.v[rstream.i++] || 0;
    for (const [a, v] of tk.pk || []) { jsRam[a] = v; wlog.push(a); }
    // раз в 2000 шагов — падение (люк) в другую комнату: модель с фиксированным вводом сама в люки не ходит
    if (t % 2000 === 1000 && fnGet === TASK[S.game_tasks]) {
      jsRam[S.room_number] = (t * 7) % 140 + 1; wlog.push(S.room_number);
      state.switch_game_state(M, S.state_falling);
      continue;
    }
    const last = new Map(); for (const [a, v] of tk.rd) last.set(a, v);
    for (const [a, v] of last) { jsRam[a] = v; wlog.push(a); }
    try { fnGet()(M); } catch (e) { if (e.notModeled) break; throw e; }
  }
  console.log(`${curFile}: шагов ${n}`);
}
let ok = true;
for (const [k, s] of Object.entries(stat)) {
  if (s.bad) ok = false;
  console.log(`${k.padEnd(32)} вызовов ${String(s.calls).padStart(6)}  расхождений ${String(s.bad).padStart(5)}  тактов сред ${s.calls ? (s.t / s.calls).toFixed(0).padStart(6) : '     -'} макс ${s.tmax}`);
}
process.exit(ok ? 0 : 1);
