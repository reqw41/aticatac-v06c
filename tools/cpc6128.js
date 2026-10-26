// cpc6128.js — минимальная модель Amstrad CPC 6128 для эталонных прогонов Atic Atac (docs/LOGIC_PLAN.md).
//
// Только то, что нужно игре (она не пользуется прошивкой): Z80 (tools/vendor/Z80.js, MIT), 128 КБ ОЗУ с
// банками gate array (0x7Fxx, C0/C4..C7: окно 0x4000 = страница 1/4..7), CRTC (R12/R13 — база экрана),
// PPI + PSG (опрос клавиатуры: регистр 14, строка — младшие биты порта C; порт B бит 0 — VSYNC),
// прерывания gate array каждые 52 строки (6 на кадр; первое — через 2 строки после начала VSYNC),
// ждут подтверждения при DI. Кадр 312 строк x 256 тактов = 79872 такта (4 МГц); такты команд
// округляются вверх до 4 (CPC растягивает каждую команду до целых «NOP»).
//
// Загрузка без дискеты: собранные файлы (build/cpcnew) кладутся туда же, куда их кладёт loader.asm,
// старт с 0x100. Ячейка 0x38 = JP (вектор пишет install_interrupts).
'use strict';
const fs = require('fs');
const path = require('path');
const Z80 = require('./vendor/Z80.js');

const T_LINE = 256, LINES = 312, T_FRAME = T_LINE * LINES;
const INT_LINES = [2, 54, 106, 158, 210, 262];
const VSYNC_LINES = 8;

// матрица клавиатуры CPC: имя -> [строка, бит]
const KEYS = {
  UP: [0, 0], RIGHT: [0, 1], DOWN: [0, 2], LEFT: [1, 0], SPACE: [5, 7], Z: [8, 7],
  P: [3, 3], M: [4, 6], H: [5, 4], ESC: [8, 2], ENTER: [0, 6], RETURN: [2, 2],
  '1': [8, 0], '2': [8, 1], '3': [7, 1], '4': [7, 0], '5': [6, 1], '6': [6, 0],
  J_UP: [9, 0], J_DOWN: [9, 1], J_LEFT: [9, 2], J_RIGHT: [9, 3], J_FIRE1: [9, 4], J_FIRE2: [9, 5],
};

class CPC6128 {
  constructor(buildDir) {
    this.ram = new Uint8Array(0x20000);       // страницы 0..7 по 16 КБ
    this.cfg = 0;                             // RAM-конфигурация (0, 4..7)
    this.win = 0x4000;                        // смещение страницы окна 0x4000 в ram
    this.keyMatrix = new Uint8Array(16).fill(0xff);
    this.psgReg = 0; this.psgBus = 0; this.psgCtl = 0; this.kbRow = 0;
    this.psgRegs = new Uint8Array(16);
    this.crtcReg = 0; this.crtc = new Uint8Array(18);
    this.pens = new Uint8Array(17); this.pen = 0; this.mode = 0;
    this.t = 0;                               // такт от начала кадра
    this.frames = 0; this.total = 0;
    this.intPending = false; this.nextInt = 0;
    this.inIsr = false; this.isrRet = -1; this.isrSp = -1;
    this.onRead = null;                       // (addr, value, inIsr) — для учёта чтений
    this.onWrite = null;
    this.psgLog = null;                       // массив [такт, рег, значение] при записи PSG, если задан
    const self = this;
    this.cpu = new Z80({
      mem_read: (a) => {
        const v = self.ram[self._map(a)];
        if (self.onRead) self.onRead(a, v, self.inIsr);
        return v;
      },
      mem_write: (a, v) => {
        if (self.onWrite) self.onWrite(a, v, self.inIsr);
        self.ram[self._map(a)] = v & 0xff;
      },
      io_read: (p) => self._in(p & 0xffff),
      io_write: (p, v) => self._out(p & 0xffff, v & 0xff),
    });
    if (buildDir) this.load(buildDir);
  }

  _map(a) {
    a &= 0xffff;
    return (a & 0xc000) === 0x4000 ? this.win + (a & 0x3fff) : a;
  }
  page(n) { return n < 4 ? n * 0x4000 : 0x10000 + (n - 4) * 0x4000; }
  peek(a) { return this.ram[this._map(a)]; }
  poke(a, v) { this.ram[this._map(a)] = v & 0xff; }
  peekPage(n, a) { return this.ram[this.page(n) + (a & 0x3fff)]; }

  load(dir) {
    const put = (f, off) => { const d = fs.readFileSync(path.join(dir, f)); this.ram.set(d, off); };
    put('heroes.bin', this.page(4));
    put('baddies.bin', this.page(7));
    put('rooms.bin', this.page(5));
    put('sounds.bin', this.page(6));
    put('items.bin', this.page(1));
    put('gamecode.bin', 0x100);
    this.ram[0x38] = 0xc3;
    this.cpu.set_imode(1);
    this.cpu.set_pc(0x100);
    this.cpu.set_sp(0xc000);
  }

  _setCfg(c) {
    this.cfg = c & 7;
    const p = this.cfg >= 4 ? this.cfg : 1;   // C0..C3 считаем C0 (игра их не ставит)
    this.win = this.page(p);
  }

  _in(p) {
    const hi = p >> 8;
    if ((p & 0x0800) === 0) {
      if (hi === 0xf4) {
        if (this.psgCtl === 1 && this.psgReg === 14) return this.keyMatrix[this.kbRow];
        return 0xff;
      }
      if (hi === 0xf5) {
        const line = (this.t / T_LINE) | 0;
        return 0x1e | (line < VSYNC_LINES ? 1 : 0);
      }
      if (hi === 0xf6) return this.kbRow;
    }
    return 0xff;
  }

  _out(p, v) {
    const hi = p >> 8;
    if ((p & 0xc000) === 0x4000) {             // gate array
      const top = v & 0xc0;
      if (top === 0x00) this.pen = v & 0x1f;
      else if (top === 0x40) this.pens[(this.pen & 0x10) ? 16 : (this.pen & 15)] = v & 0x1f;
      else if (top === 0x80) this.mode = v & 3;
      else this._setCfg(v);
      return;
    }
    if (hi === 0xbc) { this.crtcReg = v & 0x1f; return; }
    if (hi === 0xbd) { if (this.crtcReg < 18) this.crtc[this.crtcReg] = v; return; }
    if ((p & 0x0800) === 0) {
      if (hi === 0xf4) { this.psgBus = v; if (this.psgCtl === 3) this.psgReg = v & 15; return; }   // режим выбора держится — AY перехватывает номер (приём Madram, PlayerAkg)
      if (hi === 0xf6) {
        this.kbRow = v & 0x0f;
        this.psgCtl = (v >> 6) & 3;
        if (this.psgCtl === 3) this.psgReg = this.psgBus & 15;
        else if (this.psgCtl === 2 && this.psgReg < 14) {
          this.psgRegs[this.psgReg] = this.psgBus;
          if (this.psgLog) this.psgLog.push([this.total, this.psgReg, this.psgBus]);
        }
        return;
      }
      if (hi === 0xf7) {                        // управляющее слово PPI / установка бита порта C
        if (!(v & 0x80)) {
          const bit = (v >> 1) & 7, on = v & 1;
          let c = (this.psgCtl << 6) | this.kbRow;
          c = on ? c | (1 << bit) : c & ~(1 << bit);
          this.kbRow = c & 15; this.psgCtl = (c >> 6) & 3;
        }
      }
    }
  }

  keyDown(name) { const k = KEYS[name]; if (!k) throw new Error('клавиша ' + name); this.keyMatrix[k[0]] &= ~(1 << k[1]); }
  keyUp(name) { const k = KEYS[name]; this.keyMatrix[k[0]] |= (1 << k[1]); }
  keysOnly(names) { this.keyMatrix.fill(0xff); for (const n of names) this.keyDown(n); }

  get pc() { return this.cpu.get_pc(); }

  // одна команда (или подача прерывания); возвращает такты
  step() {
    const cpu = this.cpu;
    if (this.intPending && cpu.get_iff1()) {
      this.intPending = false;
      this.isrSp = cpu.get_sp(); this.isrRet = cpu.get_pc(); this.inIsr = true;
      cpu.interrupt(false, 0xff);
      const c = 16; this._tick(c); return c;
    }
    let c = cpu.run_instruction();
    c = (c + 3) & ~3;
    if (this.inIsr && cpu.get_pc() === this.isrRet && cpu.get_sp() === this.isrSp) this.inIsr = false;
    this._tick(c);
    return c;
  }

  _tick(c) {
    this.t += c; this.total += c;
    if (this.t >= T_FRAME) { this.t -= T_FRAME; this.frames++; this.nextInt = 0; }
    const line = (this.t / T_LINE) | 0;
    while (this.nextInt < INT_LINES.length && line >= INT_LINES[this.nextInt]) {
      this.intPending = true; this.nextInt++;
    }
  }

  runFrames(n) { const f = this.frames + n; while (this.frames < f) this.step(); }
  runUntilPc(pc, maxT) {
    const lim = this.total + (maxT || T_FRAME * 500);
    while (this.total < lim) { if (this.cpu.get_pc() === pc) return true; this.step(); }
    return false;
  }

  screenBase() { return ((this.crtc[12] & 0x30) << 10) | 0; }
}

CPC6128.T_FRAME = T_FRAME;
CPC6128.KEYS = KEYS;
module.exports = CPC6128;
