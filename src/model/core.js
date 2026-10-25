// Ядро JS-модели логики Atic Atac (docs/LOGIC_PLAN.md, этап 1).
//
// Память — в раскладке модели CPC (tools/cpc6128.js): ram 128 КБ, страницы 0..3 линейно, 4..7 с 0x10000;
// окно 0x4000..0x7FFF — страница выбранного банка (SELECT_BANK, как в игре). Адреса — метки CPC (S.x).
// Адреса прерывания (owned) читаются из очередей (по адресу, по порядку; кончилась — последнее значение
// или текущее в памяти): их значения посреди шага знает только эталон.
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '../..');
const S = {};
for (const l of fs.readFileSync(path.join(ROOT, 'build/cpcsrc/rasmoutput.sym'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+) #([0-9A-F]+)/); if (m) S[m[1].toLowerCase()] = parseInt(m[2], 16);
}

class Mem {
  constructor(ram, cfg) {
    this.ram = ram;                   // Uint8Array(0x20000), владеет вызывающий
    this.setCfg(cfg);
    this.owned = null;                // Set плоских адресов прерывания
    this.q = new Map();               // плоский адрес -> [значения]
    this.rq = [];                     // очередь ld a,r
    this.sfx = [];                    // номера звуков
    this.writes = null;               // Set плоских адресов, записанных моделью (для сверки)
  }
  setCfg(c) { this.cfg = c & 7; this.win = this.cfg >= 4 ? 0x10000 + (this.cfg - 4) * 0x4000 : 0x4000; }
  flat(a) { a &= 0xffff; return (a & 0xc000) === 0x4000 ? this.win + (a & 0x3fff) : a; }
  rd(a) {
    const f = this.flat(a);
    if (this.owned && this.owned.has(f)) {
      const q = this.q.get(f);
      if (q && q.length) { const v = q.length > 1 ? q.shift() : q[0]; this.ram[f] = v; return v; }
    }
    return this.ram[f];
  }
  wr(a, v) { const f = this.flat(a); this.ram[f] = v & 0xff; if (this.writes) this.writes.add(f); }
  rd16(a) { return this.rd(a) | this.rd(a + 1) << 8; }
  wr16(a, v) { this.wr(a, v); this.wr(a + 1, v >> 8); }
  bank(c) { this.wr(S.memory_bank, c); this.setCfg(c); }   // SELECT_BANK
  ldar() { if (!this.rq.length) throw new Error('модель: нет значения ld a,r'); return this.rq.shift(); }
}

module.exports = { S, Mem, ROOT };
