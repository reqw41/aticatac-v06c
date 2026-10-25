#!/usr/bin/env node
// Профиль по меткам: доля тактов по ближайшей метке ниже PC (после 20 кадров).
// Считает такты между приращениями vt_ticks (тик = все объекты стёрты и нарисованы) и снимает экран.
//   node stand/vec/run.js build/proto/proto.r0m build/proto/proto.sym <кадров> [снимок.raw]
// Снимок: 32К плоскостей 0x8000..0xFFFF + 16 байт палитры (pal_data) — рисует stand/vec/shot.py.
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

const N = +NF || 300;
const labs = Object.entries(S).filter(([k,v]) => v < 0x8000 && !/^(KVAZ|MAXP|ROW0|O_|OSZ|NOBJ|STACK|FRAME_U|OFS_U|HU|WIN_U|BL_PAIR|DR_PAIR|RS_PAIR|t_|d_)/.test(k)).sort((a,b)=>a[1]-b[1]);
const prof = {}; let frc = 0, frames = 0, tacc = 0, total = 0;
function lab(pc){ let r='?'; for (const [k,v] of labs) { if (v<=pc) r=k; else break; } return r; }
const cache = new Map();
while (frames < N) {
  if (frc >= 59904) { frc -= 59904; frames++; v06c.irq = true; v06c.checkInterrupt(); }
  const pc = cpu.pc;
  const c = (cpu.instruction(), cpu.vcycles); frc += c; tacc += c; if (frames > 20) total += c;
  if (tacc > 1) { const tn = tacc >> 1; tacc -= tn * 2; timer.Count(tn); }
  if (cpu.last_opcode === 0xd3) io.commit();
  if (frames > 20) { let l = cache.get(pc); if (!l) { l = lab(pc); cache.set(pc, l); } prof[l] = (prof[l]||0) + c; }
}

for (const [k,v] of Object.entries(prof).sort((a,b)=>b[1]-a[1])) console.log(k.padEnd(14), (v/total*100).toFixed(1).padStart(5)+'%');

