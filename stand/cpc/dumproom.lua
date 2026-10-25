-- Снимок фона первой комнаты: при первом входе в calculate_collision_grid (0x082B) комната нарисована
-- в обоих экранах, спрайтов ещё нет. Сохраняем 0x8000..0xFFFF и переменные экрана.
local m = manager.machine
local dbg = m.debugger
local space = m.ioport.ports[":kbrow.5"].fields["Space"]
dbg:command('bpset 0x82B,1,{save bg8000.bin,8000,8000; save vars.bin,56B,2; logerror "DUMP\\n"; bpclear; g}')
local frame = 0
emu.register_frame_done(function()
  frame = frame + 1
  if frame == 100 then m.natkeyboard:post('run"atic\n') end
  for _, t in ipairs({1800, 2100, 2400, 2700}) do
    if frame == t then space:set_value(1) elseif frame == t + 10 then space:set_value(0) end
  end
  if frame == 3000 then m.video:snapshot(); m:exit() end
end)
