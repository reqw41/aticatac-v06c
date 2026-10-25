#!/usr/bin/env node
// Покадровая съёмка «как видит луч»: ядро vector06js с построчной отрисовкой (oneInterrupt(true)).
//   node stand/vec/frames.js <образ.r0m> <кадров> <пропустить> <out.raw>
// out.raw: кадры подряд, 576x288 RGBA (как bmp ядра), первые <пропустить> кадров не пишутся.
// out.raw.mem: плоскости 0x8000..0xFFFF (32К) на конец каждого записанного кадра и одна копия перед первым.
"use strict";
const fs = require("fs"), vm = require("vm");
const base = process.env.V06JS || require("path").join(require("os").homedir(), "projects/vector06js");
const [ROM, NF, SKIP, OUT] = process.argv.slice(2);
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
const planes = () => { const b = Buffer.alloc(0x8000); for (let a = 0; a < 0x8000; a++) b[a] = rd(0x8000 + a); return b; };
const fd = fs.openSync(OUT, "w"), fm = fs.openSync(OUT + ".mem", "w");
for (let f = 0; f < +NF; f++) {
  if (f === +SKIP) fs.writeSync(fm, planes());
  v06c.oneInterrupt(true);
  if (f >= +SKIP) { fs.writeSync(fd, Buffer.from(v06c.bmp.buffer)); fs.writeSync(fm, planes()); }
}
fs.closeSync(fd); fs.closeSync(fm);
