// Общие помощники модели: RANDOM_IN_A (macros.asm), сложение BCD с DAA, ANIMATE_SPRITE.
'use strict';
const { S } = require('./core');

function notModeled(n) { const e = new Error('не смоделировано: ' + n); e.notModeled = true; throw e; }

// RANDOM_IN_A: b = seed; a = rrc^3(seed) xor 0x1f; a = a + b; a = a - 255 - перенос -> seed
function random(M) {
  const b = M.rd(S.random_seed);
  let a = ((b >> 3) | (b << 5)) & 0xff;
  a ^= 0x1f;
  const s = a + b;
  const c = s > 0xff ? 1 : 0;
  a = (s - 0xff - c) & 0xff;
  M.wr(S.random_seed, a);
  return a;
}

// a + v + cin, затем DAA (сложение). -> [результат, перенос]
function addBcd(a, v, cin) {
  const h = ((a & 0x0f) + (v & 0x0f) + cin) > 0x0f;
  let r = a + v + cin;
  let c = r > 0xff;
  r &= 0xff;
  let corr = 0;
  if (h || (r & 0x0f) > 9) corr |= 0x06;
  if (c || r > 0x99) { corr |= 0x60; c = true; }
  return [(r + corr) & 0xff, c ? 1 : 0];
}

const neg = (v) => (-v) & 0xff;
const s8 = (v) => (v & 0x80 ? v - 256 : v);

function animate(M, ix) { M.wr(ix + S.spr_frame, (M.rd(ix + S.spr_frame) + 1) & 0x0f); }

module.exports = { notModeled, random, addBcd, neg, s8, animate };
