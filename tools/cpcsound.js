#!/usr/bin/env node
// Звук CPC (Arkos Tracker 2, PlayerAkg) с модели tools/cpc6128.js: покадровые записи регистров AY
// -> build/sound/sound.json: { tunes: { имя: { frames, loop } }, sfx: [ { frames } ] }, кадр = [[рег, знач], ...]
// (только изменившиеся регистры 0..13; R13 — при каждой записи: она перезапускает огибающую).
// Мелодии: menu (песня 0 atic_Start), start (1), over (2), done (4) — через init_sound_system; эффекты 1..12 —
// вызовом play_sfx в игре (музыки там нет). Вызов — подмена PC на границе шага (адрес возврата на стек).
'use strict';
const fs = require('fs');
const path = require('path');
const CPC = require('./cpc6128');
const scenario = require('./scenario');
const S = scenario.SYM;
const OUT = path.join(__dirname, '../build/sound');

function call(m, addr, regs) {                     // «call addr» из текущего места
  const st = m.cpu.getState();
  st.sp = (st.sp - 2) & 0xffff;
  m.poke(st.sp, st.pc & 0xff); m.poke(st.sp + 1, st.pc >> 8);
  st.pc = addr;
  Object.assign(st, regs);
  m.cpu.setState(st);
}
// кадры: на каждом — записи PSG этого кадра, сведённые к последним значениям (R13 — всегда, если писался)
function record(m, n, stopSilent) {
  const frames = [];
  let prev = new Array(14).fill(-1), silent = 0;
  for (let f = 0; f < n; f++) {
    m.psgLog = [];
    m.runFrames(1);
    const last = new Map();
    let r13 = false;
    for (const [, r, v] of m.psgLog) { last.set(r, v); if (r === 13) r13 = true; }
    const fr = [];
    for (let r = 0; r < 14; r++) if (last.has(r) && (last.get(r) !== prev[r] || (r === 13 && r13))) { fr.push([r, last.get(r)]); prev[r] = last.get(r); }
    frames.push(fr);
    const vol = (r) => (prev[r] < 0 ? 0 : prev[r] & 0x1f);
    const mixer = prev[7] < 0 ? 0xff : prev[7];
    const quiet = [8, 9, 10].every((r, i) => vol(r) === 0 || ((mixer >> i) & 1) && ((mixer >> (i + 3)) & 1));
    silent = quiet ? silent + 1 : 0;
    if (stopSilent && f > 10 && silent >= 10) { frames.length -= 9; break; }
  }
  m.psgLog = null;
  return frames;
}
// повтор: наименьший период p (от 64 кадров), начиная с t0, при котором полные состояния регистров
// (R7 без битов портов) совпадают на всём остатке записи
function findLoop(frames) {
  const r = new Array(14).fill(0);
  const key = frames.map((f) => { for (const [k, v] of f) r[k] = v; const q = r.slice(); q[7] &= 0x3f; return q.join(','); });
  for (let t0 = 0; t0 < key.length / 2; t0 += 1)
    for (let p = 64; t0 + p + 1000 <= key.length; p++) {         // совпадение — на всём остатке, не короче 1000 кадров
      let ok = true;
      for (let i = t0; i + p < key.length && ok; i++) if (key[i] !== key[i + p]) ok = false;
      if (ok) return { start: t0, len: p };
    }
  return null;
}

fs.mkdirSync(OUT, { recursive: true });
const out = { tunes: {}, sfx: [] };
// мелодии: машина в меню (музыка меню уже идёт), затем init_sound_system(hl = atic_Start, d = песня)
for (const [name, song, n] of [['menu', 0, 9000], ['start', 1, 175], ['over', 2, 1500], ['done', 4, 1500]]) {
  const m = new CPC(path.join(__dirname, '../build/cpcnew'));
  m.runFrames(60);
  m.runUntilPc(S.menu_tasks, CPC.T_FRAME * 10);
  call(m, S.init_sound_system, { h: S.atic_start >> 8, l: S.atic_start & 0xff, d: song });
  m.runUntilPc(S.menu_tasks, CPC.T_FRAME * 10);
  // меню перезапускает мелодию 0 только в init_menu — дальше menu_tasks её не трогает
  const frames = record(m, n, name !== 'menu' && name !== 'start');
  const loop = name === 'menu' ? findLoop(frames) : null;
  out.tunes[name] = { frames: loop ? frames.slice(0, loop.start + loop.len) : frames, loop: loop ? loop.start : -1 };
  console.log('мелодия', name, 'кадров', out.tunes[name].frames.length, 'повтор с', out.tunes[name].loop);
}
// эффекты: игра (рыцарь), на каждом эффекте — своя машина
for (let e = 1; e <= 12; e++) {
  const { m } = scenario.start({ menu: [{ frames: 150, keys: [] }, { frames: 10, keys: ['SPACE'] }, { frames: 5, keys: [] }], ticks: 1, steps: [{ ticks: 1, keys: [] }] });
  m.runFrames(250);                               // после звука появления героя
  m.runUntilPc(S.current_game_state, CPC.T_FRAME * 10);
  m.poke(S.sound_guard, 0);
  call(m, S.play_sfx, { e });
  const frames = record(m, 400, true);
  out.sfx.push({ frames });
  console.log('эффект', e, 'кадров', frames.length);
}
fs.writeFileSync(path.join(OUT, 'sound.json'), JSON.stringify(out));
