-- Трасса инструкций CPC за 50 кадров игры (идём вправо), для профиля по процедурам.
local m = manager.machine
local dbg = m.debugger
local frame = 0
local k9 = m.ioport.ports[":kbrow.9"].fields
local space = m.ioport.ports[":kbrow.5"].fields["Space"]
local T0 = 3000
emu.register_frame_done(function()
  frame = frame + 1
  if frame == 100 then m.natkeyboard:post('run"atic\n') end
  for _, t in ipairs({1800, 2100, 2400, 2700}) do
    if frame == t then space:set_value(1) elseif frame == t + 10 then space:set_value(0) end
  end
  if frame == T0 then k9["P1 Right"]:set_value(1) end
  if frame == T0 + 100 then dbg:command('trace trace.txt,maincpu,noloop') end
  if frame == T0 + 150 then dbg:command('trace off'); m.video:snapshot(); m:exit() end
end)
