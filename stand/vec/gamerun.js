#!/usr/bin/env node
// Стенд игры: build/game/aticatac.rom с 0x0000 + квазидиск build/game/aticatac.edd на ядре vector06js.
//   node stand/vec/gamerun.js <кадров> <каталог снимков> [сценарий клавиш]
// Сценарий: "0:right,120:up+space,300:" — с кадра N держать клавиши (left right up down space z).
// Снимки (для stand/vec/shot.py) — каждые 50 кадров: <каталог>/fNNNN.raw; в stdout — шаги и такты.
"use strict";
const fs = require("fs"), vm = require("vm");
const base = process.env.V06JS || require("path").join(require("os").homedir(), "projects/vector06js");
const [NF, OUTDIR, SCRIPT] = process.argv.slice(2);
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
let upd = null, updN = 0, updTear = 0, updDepth = 0;
const mw = memory.write.bind(memory);
memory.write = function (addr, v, st) {
  if (upd && !st && addr >= 0x8000 && addr < 0xe000) { const r = addr & 0xff; if (r < upd.r0) upd.r0 = r; if (r > upd.r1) upd.r1 = r; }
  return mw(addr, v, st);
};
const beamRow = () => { const l = Math.floor(frc / 192) - 40; return l >= 0 && l < 256 ? 255 - l : -1; };
const KEYS = { left: [0, 0x10], up: [0, 0x20], right: [0, 0x40], down: [0, 0x80], space: [7, 0x80], z: [7, 0x04] , f1: [1, 0x08], f3: [1, 0x20] , q: [6, 0x02] };
const plan = (SCRIPT || '').split(',').filter(Boolean).map((x) => { const [f, k] = x.split(':'); return [+f, k ? k.split('+') : []]; });
// меню (src/vec/menu.asm): по умолчанию огонь на 40-м кадре (заставка) и на 90-м (меню) — рыцарь; MENU="10:left,14:,60:space,64:" — свой выбор
for (const x of (process.env.MENU || '40:space,44:,90:space,94:').split(',').filter(Boolean).reverse()) { const [f, k] = x.split(':'); plan.unshift([+f, k ? k.split('+') : []]); }
fs.mkdirSync(OUTDIR, { recursive: true });
let frc = 0, frames = 0, tacc = 0, total = 0;
const N = +NF;
let lastTicks = 0, lastT = 0;
const tk = S.main_loop;
let loops = 0, tickT = []; let updRet = -1, updSp = -1; let nRep = 0, nXor = 0, nNew = 0, nRend = 0; let bgSnap = null, rooms = 0, echkDone = false; let irqUntil = -1, irqOk = 0, irqLost = 0; const hist = []; let seq = [], seqLast = '', seqN = 0; const prof = {}, profCache = new Map(); let spBad = false, spOn = false; const spHist = [];
const exS = new Set(fs.readFileSync(ROOTD + '/build/l80/cpcsym.inc', 'utf8').split('\n').map((l) => l.split(/\s/)[0]));
const labsS = Object.entries(S).filter(([k]) => !exS.has(k) && !/^(ROW0|NITEMT|KV_|FOOD|SKEL|ROOM_BANK|FD_N|TOMB|FOODI|SPR_LEN|BS|FHS|FVS|S_PERSIST|ST_|NOBJ|OB|MAXPAIRS|BX_PAIR|DR_PAIR|RS_PAIR|ck)/.test(k)).sort((a,b)=>a[1]-b[1]);
const nmOf = (p) => { let r='?'; for (const [k,v] of labsS) { if (v<=p) r=k+'+'+(p-v); else break; } return r; };
const STK = ['blit_x', 'draw_item', 'clear_room', 'ol_pass', 'clear_screen'];
const inStackCode = (pc) => { const n = nmOf(pc).split('+')[0]; return STK.includes(n) || /^(bx_|dt_|cr_|ol_|clr_)/.test(n); };
const okpc = new Uint8Array(0x10000); okpc[0] = okpc[1] = okpc[2] = okpc[3] = 1;
for (const [a, b] of JSON.parse(fs.readFileSync(ROOTD + '/build/game/ranges.json'))) for (let p = a; p < b; p++) okpc[p] = 1;
let pcPrev = 0; const wPrev = {}; let lastDg = 0, lastDgT = 0; const lostAt = {}, deferN = {}, lpc = {}; let oneN = 0, oneP = {}; let rtCur = null; const rtList = [], rtAll = [];
const streak = [0,0,0,0,0,0], maxStreak = [0,0,0,0,0,0], maxAt = [0,0,0,0,0,0];
let mtl = 0, seqFL = ''; const seqF = [];
const viLog = [], viB = [[], [], []]; const sndOut = {}, ayShadow = new Array(14).fill(0), ayLog = []; let ayReg = 0;
const fnAt = {}, fnOpen = {}, fnSum = {}, fnHist = {}, loopH = [], loopH2 = []; let loopT0 = 0, loopRoom = false, loopFn = {};
for (const n of ['wait_frame', 'logic_step', 'collect_events', 'apply_events', 'render_sprites', 'panel_update']) if (S[n] !== undefined) fnAt[S[n]] = n;
while (frames < N) {
  if (frc >= 59904) {
    frc -= 59904; frames++; if (process.env.SNDLOG) ayLog.push(ayShadow.slice()); irqUntil = +(process.env.IRQW || 64);          // как на железе и в Emu80: под DI прерывание теряется
    for (const x of (process.env.POKE || '').split(',').filter(Boolean)) { const [f, av] = x.split(':'); const [a, v] = av.split('='); if (+f === frames) memory.bytes[memory.tobank(S[a] !== undefined ? S[a] : +a)] = +v; }
    for (const [f, ks] of plan) if (f === frames) { keyboard.matrix.fill(0); for (const k of ks) { const [r, b] = KEYS[k]; keyboard.matrix[r] |= b; } }
    if (frames % (+process.env.SHOTN || 50) === 0) {
      const buf = Buffer.alloc(0x8000 + 16);
      for (let a = 0; a < 0x8000; a++) buf[a] = rd(0x8000 + a);
      { const ps = S.sp_src !== undefined ? ((rd(S.sp_src) | rd(S.sp_src + 1) << 8) - 15) & 0xffff : S.pal_data; for (let i = 0; i < 16; i++) buf[0x8000 + i] = rd((ps > 0 ? ps : S.pal_data) + i); }
      fs.writeFileSync(OUTDIR + '/f' + String(frames).padStart(4, '0') + '.raw', buf);
    }
  }
  if (process.env.PATH1 && seqN < 400) { const n = nmOf(cpu.pc).split('+')[0]; if (n !== seqLast) { seq.push(n + '@' + cpu.sp.toString(16)); seqLast = n; seqN++; if (seqN === 400) { console.log(seq.join(' ')); process.exit(0); } } }
  if (process.env.SPTRACE) {
    const sp = cpu.sp;
    if (cpu.pc === S.new_game) spOn = true;
    if (spOn && !spBad && (sp < 0x3c00 || sp > 0x4000) && !inStackCode(cpu.pc)) { spBad = true; console.log('SP ' + sp.toString(16) + ' при pc ' + cpu.pc.toString(16) + ' ' + nmOf(cpu.pc) + '; до этого: ' + spHist.map((q) => q.toString(16) + ' ' + nmOf(q)).join(' | ')); process.exit(1); }
    spHist.push(cpu.pc); if (spHist.length > 12) spHist.shift();
  }
  if (process.env.TRACE) { hist.push(cpu.pc + 0x10000 * cpu.sp); if (hist.length > 60) hist.shift(); if (!okpc[cpu.pc]) { const ex = new Set(fs.readFileSync(ROOTD + '/build/l80/cpcsym.inc', 'utf8').split('\n').map((l) => l.split(/\s/)[0])); const labs = Object.entries(S).filter(([k]) => !ex.has(k) && !/^(ROW0|NITEMT|KV_|FOOD|SKEL|ROOM_BANK|FD_N|TOMB|FOODI|SPR_LEN|BS|FHS|FVS|S_PERSIST|ST_|NOBJ|OB|MAXPAIRS|BX_PAIR|DR_PAIR|RS_PAIR|ck)/.test(k)).sort((a,b)=>a[1]-b[1]); const nm = (p) => { let r='?'; for (const [k,v] of labs) { if (v<=p) r=k+'+'+(p-v); else break; } return r; }; console.log(hist.map((q)=>{const p=q&0xffff, sp=Math.floor(q/0x10000); return p.toString(16)+' sp '+sp.toString(16)+' '+nm(p);}).join('\n')); process.exit(1); } }
  if (S.room_drawn !== undefined && (cpu.pc === S.room_drawn || cpu.pc === S.bg_changed)) { bgSnap = Buffer.alloc(0x6000); for (let a = 0; a < 0x6000; a++) bgSnap[a] = rd(0x8000 + a); rooms++; }
  if (S.echk_stop !== undefined && cpu.pc === S.echk_stop && !echkDone) {
    echkDone = true; let bad = 0, first = -1;
    for (let a = 0; a < 0x6000; a++) if (((a >> 8) & 31) < 24 && rd(0x8000 + a) !== bgSnap[a]) { bad++; if (first < 0) first = a; }
    console.log(`ECHK (кадр ${frames}): смен комнаты ${rooms}, отличий от фона (поле, без панели) ${bad}` + (bad ? ` (первое: плоскость ${first >> 13} столбец ${(first >> 8) & 31} строка ${first & 255})` : ''));
  }
  if (process.env.RTRACE) {
    if (cpu.pc === S.render_sprites) rtCur = { t0: total, f: frames, b: beamRow(), u: [], lg: 0 };
    if (rtCur && cpu.pc === S.logic_step) rtCur.lg++;
    if (rtCur && cpu.pc === S.panel_update) { rtCur.d = total - rtCur.t0; if ((rtCur.d > 59904 - 9000 && (rtList.length < 40 || rtCur.d > 100000)) || (process.env.RTALL && rtCur.f >= +process.env.RTALL.split('-')[0] && rtCur.f <= +process.env.RTALL.split('-')[1])) rtList.push(rtCur); rtAll.push(rtCur); rtCur = null; }
    if (upd && cpu.pc === S.zero_leftover) upd.kind = 'R'; else if (upd && cpu.pc === S.ou_xor) upd.kind = 'X'; else if (upd && cpu.pc === S.ou_newonly && !upd.kind) upd.kind = 'N';
  }
  if (process.env.ONE && upd && oneN < 3) { const n = nmOf(cpu.pc).split('+')[0]; oneP[n] = (oneP[n] || 0) + 1; }
  if (cpu.pc === S.obj_update && !upd) { upd = { t0: total, kind: '', r0: 999, r1: -1, b0: beamRow(), f0: frames, rows: new Set() }; updRet = memory.bytes[memory.tobank(cpu.sp)] | memory.bytes[memory.tobank((cpu.sp + 1) & 0xffff)] << 8; updSp = cpu.sp; }
  if (upd) { const b = beamRow(); if (b >= 0) upd.rows.add(b); }
  if (upd && cpu.pc === updRet && cpu.sp === ((updSp + 2) & 0xffff)) {
    if (process.env.ONE && oneN < 3) { if (upd.kind === 'X' && (rd(S.ou_obj) | rd(S.ou_obj + 1) << 8) === S.objs && frames > 200) { oneN++; console.log('X героя', total - upd.t0, JSON.stringify(oneP)); } oneP = {}; }
    if (process.env.RTRACE && rtCur) { const o = (rd(S.ou_obj) | rd(S.ou_obj + 1) << 8) - S.objs >> 4; rtCur.u.push(o + ':' + upd.kind + ':' + (total - upd.t0)); }
    if (upd.r1 >= 0) { updN++; let hit = false; for (const r of upd.rows) if (r >= upd.r0 && r <= upd.r1) { hit = true; break; } if (hit) updTear++; }
    upd = null;
  }
  if (process.env.WATCH) { for (const o of [3, 5]) { const v = rd(S.objs + o * 32); if (v !== wPrev[o]) { if (frames > 280 && frames < 300) console.log('объект', o, 'нарисован', wPrev[o], '->', v, 'кадр', frames, 'pc', nmOf(pcPrev), 'sp', cpu.sp.toString(16)); wPrev[o] = v; } } pcPrev = cpu.pc; }
  if (process.env.LONGLOOP && (cpu.pc === S.add_to_score || cpu.pc === S.kill_sprite)) console.log(cpu.pc === S.kill_sprite ? 'УБИТ кадр' : 'ОЧКИ кадр', frames);
  if (cpu.pc === S.render_sprites) { for (let o = 0; o < 6; o++) { const l = rd(S.objs + o * 32 + 16); streak[o] = l ? streak[o] + 1 : 0; if (process.env.STRK && o === 5 && streak[o] > 3 && streak[o] < 12) console.log('объект 5 кадр', frames, 'late', l, 'obj', [...Array(16).keys()].map((i) => rd(S.objs + 160 + i)).join(','), 'pc', nmOf(cpu.pc)); if (streak[o] > maxStreak[o]) { maxStreak[o] = streak[o]; maxAt[o] = frames; } } }
  if (process.env.MTRACE && (cpu.pc === S.menu || cpu.pc === S.new_game || cpu.pc === S.mn_loop && !mtl || cpu.pc === S.mn_starting)) { if (cpu.pc === S.mn_loop) mtl = 1; if (cpu.pc === S.menu) mtl = 0; console.log('МЕНЮ', nmOf(cpu.pc), 'кадр', frames, 'keys', rd(S.C_keys_pressed), 'state', rd(S.C_menu_state)); }
  if (process.env.SEQF && frames >= +process.env.SEQF && seqF.length < 80) { const n = nmOf(cpu.pc).split('+')[0]; if (n !== seqFL) { seqF.push(n); seqFL = n; } if (seqF.length === 80) console.log('ПУТЬ', seqF.join(' ')); }
  if (cpu.pc === S.render_sprites) nRend++;
  if (cpu.pc === S.di_guard) { lastDg = frc; lastDgT = total; }
  if (process.env.LONGPC && frames >= +process.env.LONGPC && frames < +process.env.LONGPC + 4) { const n = nmOf(cpu.pc).split('+')[0]; lpc[n] = (lpc[n] || 0) + 1; }
  if (S.rs_defer !== undefined && cpu.pc === S.rs_defer) { const o = (cpu.hl() - S.objs) >> 5; deferN[o] = (deferN[o] || 0) + 1; }
  if (process.env.LOOPST) {
    if (fnAt[cpu.pc] && !fnOpen[cpu.pc]) fnOpen[cpu.pc] = { t: total, ret: memory.bytes[memory.tobank(cpu.sp)] | memory.bytes[memory.tobank((cpu.sp + 1) & 0xffff)] << 8, sp: (cpu.sp + 2) & 0xffff };
    for (const k in fnOpen) { const o = fnOpen[k]; if (o && cpu.pc === o.ret && cpu.sp === o.sp) { const d = total - o.t; const n = fnAt[k]; if (n !== 'wait_frame') loopFn[n] = (loopFn[n] || 0) + d; fnSum[n] = (fnSum[n] || 0) + d; (fnHist[n] = fnHist[n] || []).push(d); fnOpen[k] = null; if (n === 'wait_frame') { if (loopT0) { loopH.push(o.t - loopT0); if (process.env.LONGLOOP && o.t - loopT0 > 90000) console.log('ДОЛГИЙ ЦИКЛ кадр', frames, 'тактов', o.t - loopT0, 'комната', loopRoom, JSON.stringify(loopFn)); loopFn = {}; if (!loopRoom) loopH2.push(o.t - loopT0); } loopT0 = total; loopRoom = false; } if (n === 'apply_events' && d > 20000) { loopRoom = true; if (process.env.LONGEV) console.log('долгий apply_events: кадр', frames, 'тактов', d, 'ev_room', rd(S.ev_room), 'ev_clear', rd(S.ev_clear)); }
      if (process.env.LONGEV && d > 3 * 59904 && n !== 'apply_events') console.log('долгий', n, 'кадр', frames, 'тактов', d); } }
  }
  if (cpu.pc === S.zero_leftover) nRep++; else if (cpu.pc === S.ou_xor) nXor++; else if (cpu.pc === S.ou_newonly) nNew++;
  if (cpu.pc === S.logic_step) { loops++; if (lastT) tickT.push(total - lastT); lastT = total; }
  if (irqUntil >= 0) {
    if (cpu.iff) { v06c.irq = true; v06c.checkInterrupt(); irqUntil = -1; irqOk++; }
    else if (frc >= irqUntil) { irqUntil = -1; irqLost++; const n = nmOf(cpu.pc).split('+')[0]; lostAt[n] = (lostAt[n] || 0) + 1; if (process.env.LOSTDBG && /^bx_|^bo_|^zf_/.test(n)) console.log('потеря в', n, 'кадр', frames, 'di_guard был при такте кадра', lastDg, 'стоимость', rd(S.dg_cost), 'прошло с него', total - lastDgT); }
  }
  const pc0 = cpu.pc;
  const c = (cpu.instruction(), cpu.vcycles); frc += c; total += c; tacc += c;
  if (process.env.PROF && (!process.env.PROFR || (process.env.PROFR === '1' ? fnOpen[S.render_sprites] : upd))) { let n = profCache.get(pc0); if (!n) { n = nmOf(pc0).split('+')[0]; profCache.set(pc0, n); } prof[n] = (prof[n] || 0) + c; }
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (cpu.last_opcode === 0xd3) { if (process.env.SNDT) { const port = memory.bytes[memory.tobank((cpu.pc - 1) & 0xffff)]; sndOut[port] = (sndOut[port] || 0) + 1; if (port === 0x15) ayReg = cpu.a() & 15; else if (port === 0x14) ayShadow[ayReg] = cpu.a(); else if (port === 0x0A || port === 0x09) { const k = port === 0x0A ? 1 : 2; viB[k].push(cpu.a()); if (viB[k].length === 2) { viLog.push([frames, k, viB[k][0] | viB[k][1] << 8]); viB[k] = []; } } else if (port === 8) { const v = cpu.a(); if ((v & 0xc0) === 0x40 || (v & 0xc0) === 0x80) { const k = v >> 6; viB[k] = []; if ((v & 0x0e) === 0) viLog.push([frames, k, 0]); } } } io.commit(); }
}
if (process.env.PROF) { const tot = Object.values(prof).reduce((a, b) => a + b, 0); for (const [k, v] of Object.entries(prof).sort((a, b) => b[1] - a[1]).slice(0, +process.env.PROFN || 18)) console.log(k.padEnd(22), (v / tot * 100).toFixed(1) + '%', (v / 59904).toFixed(1) + ' кадра'); }
if (process.env.LOOPST) {
  const q = (a, f) => { a = a.slice().sort((x, y) => x - y); return a[Math.min(a.length - 1, Math.floor(a.length * f))]; };
  for (const n in fnHist) { const a = fnHist[n]; console.log(n.padEnd(16), 'вызовов', a.length, 'среднее', Math.round(fnSum[n] / a.length), 'медиана', q(a, 0.5), '90%', q(a, 0.9), '99%', q(a, 0.99)); }
  const b = [0, 0, 0, 0, 0]; for (const d of loopH) b[Math.min(4, Math.floor(d / 59904))]++;
  { const n2 = loopH2.length, over = loopH2.filter((d) => d > 59904).length; console.log(`без смен комнаты: циклов ${n2}, дольше кадра ${over} (${(over / n2 * 100).toFixed(1)}%)`); }
  console.log('работа цикла (без ожидания), кадров: <1', b[0], '1..2', b[1], '2..3', b[2], '3..4', b[3], '>=4', b[4], 'медиана', q(loopH, 0.5), '90%', q(loopH, 0.9));
}
if (process.env.RTRACE) {
  for (const r of rtList) console.log('кадр', r.f, 'луч', r.b, 'вывод', r.d, 'логики', r.lg, r.u.join(' '));
  const st = {}; for (const r of rtAll) for (const u of r.u) { const [o, k, d] = u.split(':'); const key = o + k; (st[key] = st[key] || []).push(+d); }
  for (const k of Object.keys(st).sort()) { const a = st[k].sort((x, y) => x - y); console.log('объект', k, 'раз', a.length, 'медиана', a[a.length >> 1], 'макс', a[a.length - 1]); }
}
tickT.sort((a, b) => a - b);
console.log(`обновлений: замещение на месте ${nRep}, XOR ${nXor}, появление ${nNew}; луч прошёл по строкам объекта во время обновления: ${updTear} из ${updN} (${(updTear / updN * 100).toFixed(1)}%)`);
console.log('потеряны в', JSON.stringify(lostAt));
console.log(`прерываний: дошло ${irqOk}, потеряно ${irqLost}; игра заметила потерянных ${rd(S.lost_frames) | rd(S.lost_frames + 1) << 8}`);
if (process.env.LONGPC) console.log('метки', JSON.stringify(Object.entries(lpc).sort((a, b) => b[1] - a[1]).slice(0, 25)));
console.log('подряд отложен (макс, кадр)', maxStreak.map((v, i) => v + '@' + maxAt[i]).join(' '));
if (process.env.SNDLOG) fs.writeFileSync(process.env.SNDLOG, JSON.stringify(ayLog));
if (process.env.VILOG) fs.writeFileSync(process.env.VILOG, JSON.stringify(viLog));
if (process.env.SNDT) console.log('звук: записей в порты', JSON.stringify(Object.fromEntries(Object.entries(sndOut).filter(([p]) => [8,9,10,0x14,0x15].includes(+p)))), 'AY найден', rd(S.snd_ay));
console.log('здоровье', rd(S.C_health), 'жизней', rd(S.C_num_lives), 'god', rd(S.god), 'keys_pressed', rd(S.C_keys_pressed).toString(2), 'keys_fire2', rd(S.C_keys_fire2));
console.log('отложено бюджетом по объектам', JSON.stringify(deferN));
console.log(`выводов картинки ${nRend} (${(nRend / frames * 50).toFixed(1)} в с)`);
console.log(`кадров ${frames}, шагов ${loops} (${(loops / frames * 50).toFixed(1)} в с), шаг: медиана ${tickT[tickT.length >> 1]} тактов, 90% ${tickT[Math.floor(tickT.length * 0.9)]}, макс ${tickT[tickT.length - 1]}`);
console.log('pc', cpu.pc.toString(16), 'objs', [...Array(72).keys()].map((i) => rd(S.objs + i).toString(16)).join(' '));
console.log('player_growing', rd(0xF8C), 'sprite1 state', rd(0x29BC + 10), 'x', rd(0x29BC), 'y', rd(0x29BD));
