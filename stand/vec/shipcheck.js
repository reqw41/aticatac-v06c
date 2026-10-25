#!/usr/bin/env node
// Сверка боевого образа с JS-моделью (docs/LOGIC_PLAN.md, урок Indy ship_vs_model): игра build/game/aticatac.r0m
// идёт на ядре vector06js с клавишами сценария; на каждом шаге логики (run_task) JS-модель выполняет ту же
// задачу на своей копии состояния — с вводом, каким его видит игра, и случайными числами её ldar. После шага
// сравниваются все адреса, записанные игрой или моделью (страница 0 CPC, банк комнат, еда). Расхождение —
// печать и пересинхронизация с игрой.
//   node stand/vec/shipcheck.js <кадров> "кадр:клавиши,..." [--max N]
"use strict";
const fs = require("fs"), vm = require("vm");
const base = process.env.V06JS || require("path").join(require("os").homedir(), "projects/vector06js");
const [NF, SCRIPT] = process.argv.slice(2); const MAXSHOW = process.argv.includes('--max') ? +process.argv[process.argv.indexOf('--max') + 1] : 6;
const ROOTD = require('path').join(__dirname, '../..');
const ROM = ROOTD + '/build/game/aticatac.rom', SYM = ROOTD + '/build/game/aticatac.sym';
const S = {};
for (const l of fs.readFileSync(SYM, "latin1").split("\n")) {
  const m = l.match(/^(\w+):\s+EQU\s+0x([0-9A-F]+)/i); if (m) S[m[1]] = parseInt(m[2], 16);
}
const g = {}; g.window = g;
g.document = { createElement: () => fc(), getElementById: () => fc() };
function fcx() { return { createImageData: () => ({ data: new Uint8ClampedArray(4) }), putImageData() {}, getImageData: () => ({ data: new Uint8ClampedArray(4) }), fillRect() {}, drawImage() {} }; }
function fc() { return { width: 0, height: 0, style: {}, getContext: () => fcx() }; }
g.requestAnimationFrame = () => 0; g.setTimeout = () => 0; g.print = () => 0;
g.console = { log() {}, debug() {}, warn() {}, error() {}, info() {} };
const ctx = vm.createContext(g);
for (const f of ["i8080-js/i8080_trace.js", "i8080-js/i8080_disasm.js", "i8080-js/i8080.js", "src/fili.js", "src/ay.js", "src/fd1793.js", "src/fddimage.js", "src/i8253.js", "src/io.js", "src/keyboard.js", "src/memory.js", "src/sound.js", "src/tv.js"])
  vm.runInContext(fs.readFileSync(base + "/" + f, "utf8"), ctx, { filename: f });
const memory = new ctx.Memory(), keyboard = new ctx.Keyboard(), timer = new ctx.I8253(), ay = new ctx.AY(),
  floppy = new (ctx.Floppy().FD1793)(), io = new ctx.IO(keyboard, timer, memory, ay, floppy);
const cpu = new ctx.I8080(memory, io), tape = { advance: () => {}, sample: 0, reset: () => {} },
  v06c = new ctx.Vector06c(cpu, memory, io, ay, tape);
v06c.bmp = new Uint32Array(576 * 288); v06c.displayFrame = () => {}; v06c.check_breakpoint = () => false; v06c.dbg = null;
memory.init_from_array(new Uint8Array(fs.readFileSync(ROM)).subarray(0, 0x10000), 0);
memory.detach_boot && memory.detach_boot();
cpu.pc = 0; cpu.sp = 0; cpu.iff = false;
const rd = a => memory.bytes[memory.tobank(a & 0xffff)];
const rw = a => rd(a) | rd(a + 1) << 8;

const edd = fs.readFileSync(ROOTD + '/build/game/aticatac.edd');
for (let p = 0; p < 4; p++) for (let a = 0; a < 0x10000; a++) memory.bytes[memory.tobank(((p + 1) << 16) + a)] = edd[p * 0x10000 + a];
const KEYS = { left: [0, 0x10], up: [0, 0x20], right: [0, 0x40], down: [0, 0x80], space: [7, 0x80], z: [7, 0x04] };
const plan = (SCRIPT || '').split(',').filter(Boolean).map((x) => { const [f, k] = x.split(':'); return [+f, k ? k.split('+') : []]; });
const { S: MS, Mem } = require(ROOTD + '/src/model/core');
const model = require(ROOTD + '/src/model');
const game = require(ROOTD + '/src/model/game'), state = require(ROOTD + '/src/model/state');
const TASK = { [MS.game_tasks]: game.game_tasks, [MS.falling_tasks]: game.falling_tasks, [MS.end_tasks]: state.end_tasks };
const FOOD80 = S.FOOD80, FOODC = 0x10000 + (MS.food_items - 0x4000), FOODN = MS.food_items_end - MS.food_items;
// адрес игры -> плоский адрес модели (или -1)
const flatOf = (a) => (a >= 0x0100 && a < 0x3800 ? a : a >= FOOD80 && a < FOOD80 + FOODN ? FOODC + a - FOOD80 : a >= 0x4000 && a < 0x8000 ? a - 0x4000 + 0x14000 : -1);
const vecOf = (f) => (f >= 0x0100 && f < 0x3800 ? f : f >= FOODC && f < FOODC + FOODN ? FOOD80 + f - FOODC : f >= 0x14000 && f < 0x18000 ? f - 0x14000 + 0x4000 : -1);
const foodPtr = (v) => (v >= FOOD80 && v < FOOD80 + FOODN ? v - FOOD80 + MS.food_items : v);   // игра -> модель
const PTRS = [MS.erase_food_with_index, MS.draw_tombstone_with_index]; for (let i = 0; i < MS.max_food; i++) PTRS.push(MS.this_rooms_food_list + 2 * i);
const ptrWord = new Map(); for (const p of PTRS) { ptrWord.set(p, p); ptrWord.set(p + 1, p); }
// значения, которые модель видит как ввод (их на CPC пишет прерывание, здесь — главный цикл игры)
const INPUTS = ['keys_pressed', 'fire_direction', 'keys_fire2', 'heartbeat', 'tell_time', 'second_only', 'sound_guard', 'hidden_screen_base_address'].map((n) => MS[n]);
for (let i = 0; i < 10; i++) INPUTS.push(MS.keyboard_state + i);
for (let i = 0; i < 6; i++) INPUTS.push(MS.game_time + i);
const SKIP = new Set([MS.memory_bank, MS.previous_memory_bank, MS.frame_ready, MS.interrupt_index]);
const OURS = new Uint8Array(0x10000);                // код и переменные игры Вектора (куски tools/layout.py)
for (const [a, b] of JSON.parse(fs.readFileSync(ROOTD + '/build/game/ranges.json'))) for (let p = a; p < b; p++) OURS[p] = 1;
const jsRam = new Uint8Array(0x20000);
const B = ROOTD + '/build/cpcnew/';
jsRam.set(fs.readFileSync(B + 'items.bin'), 0x4000);
jsRam.set(fs.readFileSync(B + 'heroes.bin'), 0x10000);
jsRam.set(fs.readFileSync(B + 'rooms.bin'), 0x14000);
function syncFromGame() {
  for (let a = 0x0100; a < 0x3800; a++) jsRam[a] = rd(a);
  for (let a = 0x4000; a < 0x8000; a++) jsRam[a - 0x4000 + 0x14000] = rd(a);
  for (let i = 0; i < FOODN; i++) jsRam[FOODC + i] = rd(FOOD80 + i);
  for (const p of PTRS) { const w = foodPtr(rd(p) | rd(p + 1) << 8); jsRam[p] = w & 255; jsRam[p + 1] = w >> 8; }
}
let preTask = 0; let gw = new Set(), inTick = false, tickRet = -1, tickSp = -1, rq = [], ldRet = -1, ldSp = -1, synced = false;
const mw = memory.write.bind(memory);
memory.write = function (addr, v, st) { if (inTick && !st) { const f = flatOf(addr & 0xffff); if (f >= 0) gw.add(f); } return mw(addr, v, st); };
let frc = 0, frames = 0, tacc = 0, irqUntil = -1;
let ticks = 0, bad = 0, shown = 0, skipped = 0;
const symOf = Object.entries(MS).filter(([k, v]) => v >= 0x100 && v < 0x4000).sort((a, b) => a[1] - b[1]);
const nm = (f) => { if (typeof f !== 'number') return f; if (f < 0x4000) { let r = '?', rv = 0; for (const [k, v] of symOf) { if (v <= f) { r = k; rv = v; } else break; } return r + '+' + (f - rv) + '(' + f.toString(16) + ')'; } return 'flat ' + f.toString(16); };
while (frames < +NF) {
  if (frc >= 59904) {
    frc -= 59904; frames++; irqUntil = 64;
    for (const [f, ks] of plan) if (f === frames) { keyboard.matrix.fill(0); for (const k of ks) { const [r, b] = KEYS[k]; keyboard.matrix[r] |= b; } }
  }
  if (irqUntil >= 0) { if (cpu.iff) { v06c.irq = true; v06c.checkInterrupt(); irqUntil = -1; } else if (frc >= irqUntil) irqUntil = -1; }
  const pc = cpu.pc;
  if (pc === S.run_task && !inTick) {
    if (!synced) { syncFromGame(); synced = true; }
    for (const a of INPUTS) jsRam[a] = rd(a);         // ввод — как у игры
    if (process.env.SHIPBREAK && frames > 300) jsRam[MS.keys_pressed] ^= 1 << MS.player_right_bit;   // негативный контроль
    inTick = true; gw = new Set(); rq = [];
    tickSp = cpu.sp; tickRet = rd(cpu.sp) | rd(cpu.sp + 1) << 8;
    preTask = rd(S.C_current_game_state + 1) | rd(S.C_current_game_state + 2) << 8;
  }
  if (inTick && pc === S.ldar && ldRet < 0) { ldRet = rd(cpu.sp) | rd(cpu.sp + 1) << 8; ldSp = cpu.sp; }
  const c = (cpu.instruction(), cpu.vcycles); frc += c; tacc += c;
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (cpu.last_opcode === 0xd3) io.commit();
  if (ldRet >= 0 && cpu.pc === ldRet && cpu.sp === ((ldSp + 2) & 0xffff)) { rq.push(cpu.regs[7]); ldRet = -1; }
  if (inTick && cpu.pc === tickRet && cpu.sp === ((tickSp + 2) & 0xffff)) {
    inTick = false;
    const fn = TASK[preTask];
    if (!fn) { syncFromGame(); skipped++; continue; }
    const M = new Mem(jsRam, 0); M.rq = rq.slice(); const jw = new Set(); M.writes = jw;
    try { fn(M); } catch (e) { if (e.notModeled) { syncFromGame(); skipped++; continue; } throw e; }
    ticks++;
    const diffs = [];
    for (const f of new Set([...gw, ...jw])) {
      const v = vecOf(f); if (v < 0 || OURS[v]) continue;
      if (model.drawOnly.has(f) || SKIP.has(f) || INPUTS.includes(f)) continue;
      let gv = rd(v);
      if (ptrWord.has(f)) { const p = ptrWord.get(f); const w = foodPtr(rd(p) | rd(p + 1) << 8); gv = f === p ? w & 255 : w >> 8; }
      if (gv !== jsRam[f]) diffs.push([f, gv, jsRam[f]]);
    }
    if (diffs.length) {
      bad++;
      if (shown++ < MAXSHOW) { console.log(`кадр ${frames} шаг ${ticks}: ${diffs.length} расхождений`); for (const [f, g, j] of diffs.slice(0, 8)) console.log(`   ${nm(f)}: игра ${g} модель ${j}`); }
      syncFromGame();
    }
  }
}
console.log(`шагов логики сверено ${ticks}, с расхождениями ${bad}, без модели ${skipped}`);
if (!ticks) { console.log('СВЕРЕНО 0 — ПРОВАЛ'); process.exit(1); }
process.exit(bad ? 1 : 0);
