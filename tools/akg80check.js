#!/usr/bin/env node
// Сверка проигрывателя akg80 (i8080, tools/mkakg.py) с записями регистров AY модели CPC (tools/cpcsound.js):
// мелодии — akg_init(песня), эффекты — akg_init(NoMusic) + akg_playsfx(эффект, канал 1, громкость 0); на каждом
// кадре akg_play -> регистры 0..10 (R7 — младшие 6 бит) против состояния CPC того же кадра.
//   node tools/akg80check.js            (VERBOSE=1 — первые расхождения подробно)
'use strict';
const fs = require('fs');
const path = require('path');
const CPU80 = require('./cpu80');
const D = path.join(__dirname, '../build/sound/akg');
const S = {};
for (const l of fs.readFileSync(path.join(D, 'akg80.sym'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+):\s+EQU\s+0x([0-9A-Fa-f]+)/); if (m) S[m[1]] = parseInt(m[2], 16);
}
for (const l of fs.readFileSync(path.join(D, 'data.inc'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+)\s+equ\s+0x([0-9A-Fa-f]+)/); if (m) S[m[1]] = parseInt(m[2], 16);
}
const blob = fs.readFileSync(path.join(D, 'akg_kv.bin'));
const snd = JSON.parse(fs.readFileSync(path.join(__dirname, '../build/sound/sound.json'), 'utf8'));

function machine() { const c = new CPU80(); c.mem.set(blob, 0xa000); return c; }
function expected(frames) {
  const r = new Array(14).fill(0);
  return frames.map((f) => { for (const [k, v] of f) r[k] = v; return r.slice(); });
}
function run(name, setup, frames) {
  const c = machine();
  setup(c);
  const exp = expected(frames);
  let bad = 0, first = -1, maxT = 0, sumT = 0;
  for (let i = 0; i < exp.length; i++) {
    const t = c.call(S.akg_play); maxT = Math.max(maxT, t); sumT += t;
    const got = [...c.mem.slice(S.akg_regs, S.akg_regs + 11)];
    got[7] = c.reg('a');
    const e = exp[i];
    const diff = [];
    for (let r = 0; r <= 10; r++) if ((r === 7 ? got[r] & 0x3f : got[r]) !== (r === 7 ? e[r] & 0x3f : e[r])) diff.push(r);
    if (diff.length) { bad++; if (first < 0) { first = i; if (process.env.VERBOSE) console.log('  кадр', i, 'регистры', diff.join(','), 'i8080', got.join(' '), 'CPC', e.slice(0, 11).join(' ')); } }
  }
  console.log(`${name.padEnd(6)} кадров ${exp.length}, расхождений ${bad}${bad ? ' (первое — кадр ' + first + ')' : ''}, такты: среднее ${Math.round(sumT / exp.length)}, макс ${maxT}`);
  return bad;
}
let total = 0;
for (const [name, song] of [['menu', 0], ['start', 1], ['over', 2], ['done', 4]]) {
  total += run(name, (c) => { c.call(S.akg_init, { h: S.AKG_ATIC_START >> 8, l: S.AKG_ATIC_START & 255, a: song }); c.call(S.akg_initsfx, { h: S.AKG_SOUNDEFFECTS >> 8, l: S.AKG_SOUNDEFFECTS & 255 }); }, snd.tunes[name].frames);
}
snd.sfx.forEach((s, i) => {
  total += run('sfx' + (i + 1), (c) => {
    c.call(S.akg_init, { h: S.AKG_NOMUSIC_START >> 8, l: S.AKG_NOMUSIC_START & 255, a: 0 });
    c.call(S.akg_initsfx, { h: S.AKG_SOUNDEFFECTS >> 8, l: S.AKG_SOUNDEFFECTS & 255 });
    c.call(S.akg_playsfx, { a: i + 1, b: 0, c: 1 });
  }, s.frames);
});
// эффекты через akg_quiet (в игре пустая песня не проигрывается) — то же, что akg_play с NoMusic
const playSave = S.akg_play;
S.akg_play = S.akg_quiet;
snd.sfx.forEach((s, i) => {
  total += run('q-sfx' + (i + 1), (c) => {
    c.call(S.akg_init, { h: S.AKG_NOMUSIC_START >> 8, l: S.AKG_NOMUSIC_START & 255, a: 0 });
    c.call(S.akg_initsfx, { h: S.AKG_SOUNDEFFECTS >> 8, l: S.AKG_SOUNDEFFECTS & 255 });
    c.call(S.akg_playsfx, { a: i + 1, b: 0, c: 1 });
  }, s.frames);
});
S.akg_play = playSave;
console.log(total ? 'РАСХОЖДЕНИЯ: ' + total : 'akg80 = CPC: все мелодии и эффекты без расхождений');
process.exit(total ? 1 : 0);
