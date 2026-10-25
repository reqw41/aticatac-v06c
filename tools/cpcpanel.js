#!/usr/bin/env node
// Снимок панели CPC в начале игры (модель tools/cpc6128.js): видимый экран после первых шагов игры ->
// build/game/panel_cpc.bin (16 КБ экрана с 0xC000/0x8000 по R12 + 17 цветов + режим + R1/R6/R9).
// Нужен tools/mkgame.py: неподвижная часть панели (свиток, курица, жизни, надписи) для Вектора.
'use strict';
const path = require('path');
const scenario = require('./scenario');
const { shot } = require('./cpcboot');
const sc = { menu: [{ frames: 150, keys: [] }, { frames: 10, keys: ['SPACE'] }, { frames: 5, keys: [] }], ticks: 30, steps: [{ ticks: 30, keys: [] }] };
const { m, keysFor } = scenario.start(sc);
for (let t = 0; t < 30; t++) { m.keysOnly(keysFor(t)); m.step(); while (m.pc !== scenario.SYM.current_game_state) m.step(); }
shot(m, path.join(__dirname, '../build/game/panel_cpc.bin'));
console.log('панель: экран 0x' + ((m.crtc[12] & 0x30) << 10).toString(16));
