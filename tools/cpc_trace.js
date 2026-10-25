#!/usr/bin/env node
// Эталонный прогон Atic Atac на модели CPC 6128 (tools/cpc6128.js) — по шагам игры (docs/LOGIC_PLAN.md, этап 0).
//
// Шаг = вызов задачи состояния из главного цикла (PC = current_game_state, call game_tasks / menu_tasks /
// falling_tasks / end_tasks). На каждом шаге пишется:
//   task   — адрес задачи (какое состояние игры);
//   d      — изменения состояния к концу шага: [плоский адрес, байт] по страницам 0 (код и переменные),
//            1 (банк предметов), 4 (еда) и 5 (банк комнат), без адресов прерывания и стека;
//   rd     — чтения игрой (не обработчиком) адресов прерывания, по порядку: [адрес, байт] — вход модели
//            (клавиши, часы, счётчик шагов — их пишет обработчик посреди шага);
//   r      — значения `ld a,r` (случайность);
//   sfx    — номера звуков (A на входе PLY_AKG_PlaySoundEffect: play_sfx и play_lowpriority_sfx);
//   fr     — сколько кадров прошло за шаг;
//   pk     — записи сценария в память перед шагом (телепорт), если были.
// Адреса прерывания = всё, что пишет обработчик (узнаётся предварительным прогоном того же сценария).
// Плоский адрес: страница*0x4000 + смещение (страницы 4..7 — 0x10000 + (n-4)*0x4000, как в ram модели).
//
//   node tools/cpc_trace.js <сценарий.json> [выход.json.gz]
// Сценарий: { "name", "menu": [{"frames": n, "keys": [...]}...], "ticks": N,
//             "steps": [{"ticks": n, "keys": [...]}...], "random": {"seed", "keys": [...], "hold": [a, b]} }
// menu — до первого game_tasks (по кадрам); steps и random — по шагам игры, клавиши меняются на границе шага.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const CPC = require('./cpc6128');
const scenario = require('./scenario');
const { SYM, ROOT } = scenario;
const STACK_LO = 0x3e00, STACK_HI = 0x4000;    // стек игры (sp = 0x4000)

function regions(m) {                           // плоские диапазоны сравниваемого состояния
  // страница 4 — еда и могилы (food_items в банке героев)
  return [[0x0000, 0x4000], [m.page(1), m.page(1) + 0x4000], [m.page(4), m.page(4) + 0x4000], [m.page(5), m.page(5) + 0x4000]];
}

// прогон сценария; learn = Set адресов, записанных обработчиком (заполняется), owned = Set для записи
function run(sc, owned, learn) {
  const { m, keysFor, N, applied } = scenario.start(sc);
  const flat = (a) => m._map(a);
  m.onWrite = (a, v, isr) => { if (isr && learn) learn.add(flat(a)); };
  let cur = null;
  // чтения, которые модели не нужны: ожидание кадра, экраны (вывод не моделируется), банки, служебное
  const skip = new Set();
  for (const n of ['frame_ready', 'visible_screen_base_address', 'memory_bank',
    'previous_memory_bank', 'interrupt_index', 'interrupt_call', 'pen_delay']) skip.add(SYM[n]);
  skip.add(SYM.scr_addr_table); skip.add(SYM.scr_addr_table + 1); skip.add(SYM.interrupt_call + 1);
  m.onRead = (a, v, isr) => {
    if (!isr && cur && owned && a < 0x4000 && !skip.has(a) && owned.has(a)) cur.rd.push([a, v]);
    else if (!isr && cur && owned && a >= 0x4000 && owned.has(flat(a))) cur.rd.push([flat(a), v]);
  };
  const CGS = SYM.current_game_state;
  const regs = regions(m);
  const snap = () => regs.map(([a, b]) => m.ram.slice(a, b));
  const ticks = [];
  let prev = snap();
  const first = prev.map((r) => Buffer.from(r).toString('base64'));
  for (let t = 0; t < N; t++) {
    const keys = keysFor(t);
    if (!keys) break;
    const pk = applied.slice();                   // телепорт сценария — до шага, в эталоне отдельно
    for (const [a, v] of pk) for (let k = 0; k < regs.length; k++)
      if (a >= regs[k][0] && a < regs[k][1]) prev[k][a - regs[k][0]] = v;
    m.keysOnly(keys);
    const task = m.peek(CGS + 1) | m.peek(CGS + 2) << 8;
    cur = { task, rd: [], r: [], sfx: [], keys };
    if (pk.length) cur.pk = pk;
    const f0 = m.frames;
    m.step();                                   // сам call
    for (;;) {
      const pc = m.pc;
      if (pc === CGS && !m.inIsr) break;
      if (m.intPending && m.cpu.get_iff1()) { m.step(); continue; }   // подача прерывания, команда — потом
      if (pc === SYM.ply_akg_playsoundeffect && !m.inIsr) cur.sfx.push(m.cpu.get_a());
      const isLdAR = !m.inIsr && m.peek(pc) === 0xed && m.peek(pc + 1) === 0x5f;
      m.step();
      if (isLdAR) cur.r.push(m.cpu.get_a());
      if (m.frames - f0 > 1000) throw new Error('шаг не кончается, pc ' + pc.toString(16));
    }
    cur.fr = m.frames - f0;
    const now = snap();
    const d = [];
    regs.forEach(([a0], k) => {
      const p = prev[k], n = now[k];
      for (let i = 0; i < n.length; i++) {
        if (p[i] === n[i]) continue;
        const fa = a0 + i;
        if (owned && owned.has(fa)) continue;
        if (fa >= STACK_LO && fa < STACK_HI) continue;
        d.push([fa, n[i]]);
      }
    });
    cur.d = d;
    ticks.push(cur);
    prev = now;
  }
  return { m, ticks, first };
}

if (require.main === module) {
  const scFile = process.argv[2];
  const sc = JSON.parse(fs.readFileSync(scFile, 'utf8'));
  const out = process.argv[3] || path.join(ROOT, 'build/golden', sc.name + '.json.gz');
  const learn = new Set();
  run(sc, null, learn);                         // предварительный прогон: адреса обработчика
  const owned = new Set([...learn].filter((a) => !(a >= STACK_LO && a < STACK_HI)));
  const t0 = Date.now();
  const { ticks, first, m } = run(sc, owned, null);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const doc = { name: sc.name, scenario: sc, owned: [...owned].sort((a, b) => a - b), regions: regions(m), first, ticks };
  fs.writeFileSync(out, zlib.gzipSync(JSON.stringify(doc)));
  const tasks = {};
  for (const t of ticks) { const n = Object.keys(SYM).find((k) => SYM[k] === t.task && /tasks$/.test(k)) || t.task.toString(16); tasks[n] = (tasks[n] || 0) + 1; }
  const fr = ticks.reduce((s, t) => s + t.fr, 0);
  console.log(`${sc.name}: шагов ${ticks.length}, кадров ${fr} (${(fr / ticks.length).toFixed(2)} на шаг), ` +
    `задачи ${JSON.stringify(tasks)}, адресов прерывания ${owned.size}, ldar ${ticks.reduce((s, t) => s + t.r.length, 0)}, ` +
    `звуков ${ticks.reduce((s, t) => s + t.sfx.length, 0)}, ${Date.now() - t0} мс -> ${path.relative(ROOT, out)}`);
}
module.exports = { run, SYM };
