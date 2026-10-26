#!/usr/bin/env node
// Снимок панели CPC в начале игры (модель tools/cpc6128.js): видимый экран после первых шагов игры ->
// build/game/panel_cpc.bin (16 КБ экрана с 0xC000/0x8000 по R12 + 17 цветов + режим + R1/R6/R9).
// Нужен tools/mkgame.py: неподвижная часть панели (свиток, курица, жизни, надписи) для Вектора.
'use strict';
const path = require('path');
const scenario = require('./scenario');
const { shot } = require('./cpcboot');
// герои: рыцарь (огонь сразу) -> panel_cpc.bin, маг (вправо) -> panel_cpc_1.bin, серв (влево) -> panel_cpc_2.bin
for (const [key, name] of [['', ''], ['RIGHT', '_1'], ['LEFT', '_2']]) {
  const menu = [{ frames: 150, keys: [] }];
  if (key) menu.push({ frames: 4, keys: [key] }, { frames: 60, keys: [] });
  menu.push({ frames: 10, keys: ['SPACE'] }, { frames: 5, keys: [] });
  const { m, keysFor } = scenario.start({ menu, ticks: 30, steps: [{ ticks: 30, keys: [] }] });
  for (let t = 0; t < 30; t++) { m.keysOnly(keysFor(t)); m.step(); while (m.pc !== scenario.SYM.current_game_state) m.step(); }
  shot(m, path.join(__dirname, '../build/game/panel_cpc' + name + '.bin'));
}
