#!/usr/bin/env node
// Стенд отрисовки комнат (proto/room.asm): квазидиск стр. 1..N заранее заполняется build/room/items<N>.bin,
// на каждой метке rv_done снимаются 3 плоскости 0x8000..0xDFFF и такты от предыдущей комнаты.
//   node stand/vec/roomrun.js build/room/room.r0m build/room/room.sym <выход.bin>
// Выход: на каждую комнату 1 байт номера + 0x6000 байт плоскостей; такты — в stdout.
// Самостоятельный образ (-DDEMO): NOPRELOAD=1 DONE=dm_done MAXROOMS=<n> — квазидиск не заполняется.
"use strict";
const fs = require("fs"), vm = require("vm");
const base = process.env.V06JS || require("path").join(require("os").homedir(), "projects/vector06js");
const [ROM, SYM, OUT] = process.argv.slice(2);
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

const path = require("path");
const DONE = S[process.env.DONE || "rv_done"], MAXROOMS = +process.env.MAXROOMS || 1e9;
for (let p = 1; p <= 3 && !process.env.NOPRELOAD; p++) {
  const f = path.join(path.dirname(ROM), "items" + p + ".bin");
  if (!fs.existsSync(f)) continue;
  const d = fs.readFileSync(f);
  for (let i = 0; i < d.length; i++) memory.bytes[memory.tobank(((p + 1) << 16) + i)] = d[i];
}
let frc = 0, tacc = 0, total = 0, last = 0, n = 0;
const chunks = [], per = [];
for (;;) {
  if (frc >= 59904) { frc -= 59904; v06c.irq = true; v06c.checkInterrupt(); }
  if (cpu.pc === DONE) {
    const room = rd(S.rv_room), buf = Buffer.alloc(1 + 0x6000);
    buf[0] = room;
    for (let a = 0; a < 0x6000; a++) buf[1 + a] = rd(0x8000 + a);
    chunks.push(buf); per.push([room, total - last]);
    n++;
    if (n >= MAXROOMS) break;
  }
  if (cpu.pc === S.rv_loop) last = total;
  if (cpu.pc === S.rv_end || total > 59904 * 50 * 120) break;
  const c = (cpu.instruction(), cpu.vcycles); frc += c; total += c; tacc += c;
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (cpu.last_opcode === 0xd3) io.commit();
}
fs.writeFileSync(OUT, Buffer.concat(chunks));
const t = per.map(x => x[1]);
const avg = t.reduce((a, b) => a + b, 0) / t.length;
console.log(`комнат ${n}; тактов на комнату: сред ${avg.toFixed(0)} (${(avg / 59904).toFixed(2)} кадра), мин ${Math.min(...t)}, макс ${Math.max(...t)} (комната ${per[t.indexOf(Math.max(...t))][0]})`);
