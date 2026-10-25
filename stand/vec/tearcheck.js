#!/usr/bin/env node
// Разрывы по лучу: луч проходит строки объекта, пока объект перерисовывается (от входа в do_N до выхода
// из кода объекта). Строки объекта — [OE-24, OE] старого и нового положения (OE = строка памяти y).
// Луч: строка = такт кадра / 192, картинка со строки 40, строка картинки p -> строка памяти 255 - p.
//   node stand/vec/tearcheck.js build/proto/proto.r0m build/proto/proto.sym <кадров>
"use strict";
const fs = require("fs"), vm = require("vm");
const base = process.env.V06JS || require("path").join(require("os").homedir(), "projects/vector06js");
const [ROM, SYM, NF] = process.argv.slice(2);
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

const N = +NF || 300, OSZ = 21, O_OE = 16, O_DRAWN = 17;
const DO = [0, 1, 2, 3, 4, 5].map(i => S['do_' + i]);
const LO = S.do_0, HI = S.bgf || S.code_end, TD0 = S.tick_done, TD1 = S.blit;
let frc = 0, frames = 0, tacc = 0, cur = -1, r0 = 0, r1 = 0, hit = false;
const events = [], frameHit = new Set();
while (frames < N) {
  if (frc >= 59904) { frc -= 59904; frames++; v06c.irq = true; v06c.checkInterrupt(); }
  const pc = cpu.pc;
  const k = DO.indexOf(pc);
  if (k >= 0) {
    if (cur >= 0 && hit) events.push(frames);
    const o = S.objs + k * OSZ;
    cur = k; hit = false;
    const oe = rd(o + O_OE);
    if (rd(o + O_DRAWN)) { r0 = oe - 24; r1 = oe; } else { r0 = 999; r1 = -999; }
  } else if (cur >= 0 && (pc < LO || pc >= HI || (pc >= TD0 && pc < TD1))) {
    if (hit) events.push(frames);
    cur = -1;
  }
  const c = (cpu.instruction(), cpu.vcycles); frc += c; tacc += c;
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (cpu.last_opcode === 0xd3) io.commit();
  if (cur >= 0) {
    const oe = rd(S.objs + cur * OSZ + O_OE);
    const lo = Math.min(r0, oe - 24), hi = Math.max(r1, oe);
    const line = Math.floor(frc / 192) - 40;
    if (line >= 0 && line < 256) { const row = 255 - line; if (row >= lo && row <= hi) { hit = true; if (frames > 40) frameHit.add(frames); } }
  }
}
const ev = events.filter(f => f > 40).length;
console.log(`кадров ${N - 40} (после загрузки): с разрывом ${frameHit.size}, чистых ${N - 40 - frameHit.size}; разрывов объектов ${ev}`);
