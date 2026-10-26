; main.asm: запуск и главный цикл игры на Векторе (этап 3, docs/LOGIC_PLAN.md).
; Темп — кадровое прерывание (ei; halt; di в начале шага), остальное время прерывания запрещены.

start:			di
				ld		sp, 0x4000
				call	ay_detect
				call	snd_mute
				call	snd_stop				; плеер: пустая песня (прерывание запустит akg_init)
				ld		a, 0xff
				out		(0x03), a
				call	set_palette
				ld		a, 0x30					; ВИ53 счётчик 0: режим 0 (перезаряжает ISR)
				out		(0x08), a
				ld		a, 0xff
				out		(0x0B), a
				out		(0x0B), a
				call	clear_screen
	IFDEF DEBUGB
				ld		a, 10
				call	dbg_border	; этап	; этап
	ENDIF
				ei
				call	splash					; только при включении
				jp		menu
new_game:		di
				call	snd_stop				; в игре музыки нет (NoMusic CPC), только эффекты
				call	hero_setup
	IFDEF DEBUGB
				ld		a, 6
				call	dbg_border	; этап
	ENDIF
				call	select_game
	IFDEF DEBUGB
				ld		a, 8
				call	dbg_border	; этап
	ENDIF
				call	clear_screen
	IFDEF DEBUGB
				ld		a, 10
				call	dbg_border	; этап
	ENDIF
				call	forget_all
				call	panel_init

main_loop:		call	wait_frame				; A = сколько кадров прошло (1 или больше)
				cp		5
				jp		c, ml_n
				ld		a, 4					; не больше 4 шагов подряд (после долгой отрисовки комнаты)
ml_n:			ld		(ml_pend), a			; шагов логики за прошедшие кадры — ровно 50 в секунду
				call	apply_events			; сразу после прерывания — вывод (луч ещё над картинкой)
				ld		hl, (C_current_game_state + 1)	; итоги: спрайтов нет
				ld		a, l
				cp		low C_end_tasks
				jp		nz, ml_play
				ld		a, h
				cp		high C_end_tasks
				jp		z, ml_end
ml_play:
				call	render_sprites			; по состоянию прошлого шага; пока объект ждёт луч, вывод
				call	panel_update			; сам делает шаг логики (logic_pend)
ml_l:			call	logic_pend
				jp		nz, ml_l
				jp		ml_echk
ml_end:			call	logic_pend				; итоги: только логика (end_task_v уводит в меню)
				jp		nz, ml_end
ml_echk:
	IFDEF ECHK
				ld		hl, (echk_n)			; проверка стенда: после ECHK шагов стереть всё и встать
				inc		hl
				ld		(echk_n), hl
				ld		a, h
				cp		high ECHK
				jp		nz, main_loop
				ld		a, l
				cp		low ECHK
				jp		nz, main_loop
				call	erase_all
echk_stop:		jp		echk_stop
echk_n:			DW		0
	ENDIF
				jp		main_loop

; шаг логики, если ещё должны (ml_pend); NZ — шаг сделан
logic_pend:		ld		a, (ml_pend)
				or		a
				ret		z
				dec		a
				ld		(ml_pend), a
				call	logic_step
				ld		a, (god)
				or		a
				jp		z, lp_1
				ld		a, max_health
				ld		(C_health), a
lp_1:			call	collect_events
				or		1
				ret
ml_pend:		DB		0
; шаг логики: ввод, heartbeat, часы, звук, задача состояния
logic_step:		call	read_input
				ld		a, (C_heartbeat)		; switch_screens CPC: счётчик шагов 0..49
				inc		a
				cp		50
				jp		nz, ml_1
				xor		a
ml_1:			ld		(C_heartbeat), a
				cp		45						; interrupt_clock CPC
				jp		nz, ml_2
				ld		a, (C_game_paused)
				or		a
				call	z, update_clock
ml_2:			ld		a, (C_sound_guard)		; service_sound_system CPC
				or		a
				jp		z, ml_3
				dec		a
				ld		(C_sound_guard), a
ml_3:			ld		a, (C_room_changed)
				ld		(was_rc), a
				ld		hl, (C_current_game_state + 1)
				ld		(was_task), hl
				jp		run_task
was_rc:			DB		0
was_task:		DW		0

	MACRO JPHL val, target
				ld		a, l
				cp		low val
				jp		nz, .no
				ld		a, h
				cp		high val
				jp		z, target
.no:
	ENDM
run_task:		ld		hl, (C_current_game_state + 1)
				JPHL	C_game_tasks, game_tasks
				JPHL	C_falling_tasks, falling_tasks
				JPHL	C_end_tasks, end_task_v
				ret
; конец игры (end_tasks CPC): задержка, потом по клавише — меню (state_menu у Вектора — src/vec/menu.asm)
end_task_v:		ld		a, (C_end_key_delay)
				or		a
				jp		nz, end_tasks
				ld		a, (C_keys_pressed)
				or		a
				ret		z
				jp		menu					; стек меню ставит само

; события вывода: собираются после каждого шага логики (их признаки логика сбрасывает на следующем
; шаге, а догоняющий шаг идёт без вывода), применяются один раз перед выводом спрайтов
collect_events:	ld		hl, (was_task)
				ld		a, (was_rc)
				or		a
				jp		z, ce_1
				JPHL	C_game_tasks, ce_room	; draw_room в этом шаге
ce_1:			ld		hl, (was_task)
				JPHL	C_end_tasks, ce_ret		; итоги уже на экране
				ld		hl, (C_current_game_state + 1)
				JPHL	C_end_tasks, ce_toend
				ld		hl, (was_task)
				JPHL	C_falling_tasks, ce_fall
				ld		hl, (C_current_game_state + 1)
				JPHL	C_falling_tasks, ce_tofall
				jp		ce_items
ce_fall:		ld		hl, (C_current_game_state + 1)
				JPHL	C_game_tasks, ce_room	; падение кончилось — комната
				ret
ce_tofall:		ld		a, 1					; только что начали падать — очистить поле
				ld		(ev_clear), a
ce_ret:			ret
ce_toend:		ld		a, 1					; конец игры — экран итогов
				ld		(ev_end), a
				ret
ce_room:		ld		a, 1
				ld		(ev_room), a
				ret
ce_items:		ld		hl, (C_door_to_toggle)
				ld		a, h
				or		l
				ld		de, ev_doors
				call	nz, ev_push
				ld		hl, (C_erase_food_with_index)
				ld		a, h
				or		l
				ld		de, ev_foods
				call	nz, ev_push
				ld		hl, (C_draw_tombstone_with_index)
				ld		a, h
				or		l
				jp		z, ce_2
				ld		(ev_tomb), hl
ce_2:			ld		a, (C_do_pockets)
				cp		2
				ret		nz
				jp		ce_room					; предмет взят/брошен — перерисовать комнату (пока так)
; DE = список (счётчик, 4 слова), HL — в конец
ev_push:		ld		a, (de)
				cp		4
				ret		nc
				inc		a
				ld		(de), a
				dec		a
				add		a, a
				inc		a
				add		a, e
				ld		e, a
				jp		nc, ep_1
				inc		d
ep_1:			ex		de, hl
				ld		(hl), e
				inc		hl
				ld		(hl), d
				ret
ev_room:		DB		0
ev_end:			DB		0
ev_clear:		DB		0
ev_tomb:		DW		0
ev_doors:		DB		0
				DW		0, 0, 0, 0
ev_foods:		DB		0
				DW		0, 0, 0, 0

apply_events:	ld		a, (ev_end)
				or		a
				jp		z, ae_0
				call	erase_all
				ld		a, (C_game_over)		; мелодия: победа (4) или конец игры (2)
				cp		game_completed
				ld		a, SND_DONE
				jp		z, ae_tune
				ld		a, SND_OVER
ae_tune:		call	snd_play
				call	end_draw
				call	forget_all
				call	ev_reset
				jp		resync
ae_0:			ld		a, (ev_room)
				or		a
				jp		z, ae_1
				call	render_room				; долго под DI: прерывания терялись —
				call	forget_all
room_drawn:		call	ev_reset					; (метка — стенду: экран = фон комнаты)
resync:			ei								; дождаться прерывания (счётчик перезарядится)
				halt
				ld		a, (frames)
				ld		(wf_last), a
				ret
ae_1:			ld		a, (ev_clear)
				or		a
				jp		z, ae_2
				call	clear_room
				call	forget_all
				call	ev_reset
				jp		resync
ae_2:			ld		a, (ev_doors)
				ld		b, a
				ld		a, (ev_foods)
				or		b
				ld		hl, (ev_tomb)
				or		h
				or		l
				ret		z
				call	erase_all
				ld		a, (ev_doors)
				or		a
				jp		z, ae_4
				ld		b, a
				ld		hl, ev_doors + 1
ae_3:			push	bc
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				push	hl
				ex		de, hl
				call	draw_list_item
				pop		hl
				pop		bc
				dec		b
				jp		nz, ae_3
ae_4:			ld		a, (ev_foods)
				or		a
				jp		z, ae_6
				ld		b, a
				ld		hl, ev_foods + 1
ae_5:			push	bc
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				push	hl
				ex		de, hl
				call	erase_food_item
				pop		hl
				pop		bc
				dec		b
				jp		nz, ae_5
ae_6:			ld		hl, (ev_tomb)
				ld		a, h
				or		l
				call	nz, draw_food_item
bg_changed:		nop								; (метка — стенду: спрайты стёрты, экран = фон)
ev_reset:		xor		a
				ld		(ev_end), a
				ld		(ev_room), a
				ld		(ev_clear), a
				ld		(ev_doors), a
				ld		(ev_foods), a
				ld		hl, 0
				ld		(ev_tomb), hl
				ret

; выбранный герой (hero: 0 рыцарь, 1 маг, 2 серв) -> переменные CPC, как save_selection в menu.asm CPC
hero_setup:		ld		a, (hero)
				ld		l, a
				add		a, a
				add		a, a
				add		a, l
				add		a, a
				add		a, l					; * 11
				ld		l, a
				ld		h, 0
				ld		de, hero_tab
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(C_selected_player), hl
				ex		de, hl
				ld		a, (hl)
				inc		hl
				ld		(C_selected_player_height), a
				ld		a, (hl)
				inc		hl
				ld		(C_player_character), a
				ld		a, (hl)
				inc		hl
				ld		(C_magic_door), a
				ld		a, (hl)
				inc		hl
				ld		(C_weapon_rotates), a
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		(C_weapon_type), hl
				ret
hero_tab:		DW		C_knight_frames_table
				DB		knight_height, character_knight, item_clock, 1
				DW		C_sword_data
				DB		0, 0, 0
				DW		C_wizard_frames_table
				DB		wizard_height, character_wizard, item_bookcase, 0
				DW		C_spell_data
				DB		0, 0, 0
				DW		C_serf_frames_table
				DB		serf_height, character_serf, item_barrel, 0
				DW		C_axe_data
				DB		0, 0, 0
hero:			DB		0

; ---- темп: кадровое прерывание (ISR по 0x38) считает кадры и перезаряжает счётчик 0 ВИ53 (режим 0, FFFF):
;      по нему видно, сколько осталось до конца кадра (di_guard). Прерывание под DI теряется (MiSTer, Emu80).
FRAME_HI		equ		29952 / 256				; кадр в старших байтах счётчика (117)
isr:			push	af
				ld		a, 0x30					; счётчик 0: режим 0, младший+старший
				out		(0x08), a
				ld		a, 0xff
				out		(0x0B), a
				out		(0x0B), a
				ld		a, (frames)
				inc		a
				ld		(frames), a
				call	kbd_scan				; клавиатура — в гашении
				push	bc
				push	de
				push	hl
				call	snd_tick				; кадр звука
				pop		hl
				pop		de
				pop		bc
				pop		af
				ei
				ret
; -> A = кадров с прошлого вызова (>= 1); ждёт с разрешёнными прерываниями
wait_frame:		ei
wf_l:			ld		a, (frames)
				ld		hl, wf_last
				sub		(hl)
				jp		nz, wf_got
				halt
				jp		wf_l
wf_got:			push	af
				ld		a, (frames)
				ld		(hl), a
				pop		af
				ret
; перед выводом под DI: A = стоимость в старших байтах счётчика (256 отсчётов = 512 тактов);
; не хватает до конца кадра — дождаться прерывания. Возврат с DI.
di_guard:		ld		(dg_cost), a
				di
				xor		a
				out		(0x08), a				; защёлка счётчика 0
				in		a, (0x0B)
				in		a, (0x0B)				; старший байт: FF -> 0 за ~1,1 кадра
				cpl								; прошло (в старших)
				cp		FRAME_HI
				jp		nc, dg_lost				; кадр кончился, а прерывания не было — потеряно
				ld		b, a
				ld		a, FRAME_HI - 2			; запас: округление вниз и перезарядка в обработчике позже прерывания
				sub		b						; осталось
				jp		c, dg_wait
				ld		hl, dg_cost
				cp		(hl)
				ret		nc
dg_wait:		ei								; не успеем — подождать прерывание
				halt
				di
				ret
dg_lost:		ld		a, 0x30					; потерянное прерывание: перезарядить и засчитать кадр
				out		(0x08), a
				ld		a, 0xff
				out		(0x0B), a
				out		(0x0B), a
				ld		hl, frames
				inc		(hl)
				ld		hl, (lost_frames)
				inc		hl
				ld		(lost_frames), hl
				ret
dg_cost:		DB		0
frames:			DB		0
wf_last:		DB		0
lost_frames:	DW		0

; ---- клавиатура Вектора -> keys_pressed / fire_direction / keys_fire2 (read_keys CPC) ----
; ряд 0: б4 влево, б5 вверх, б6 вправо, б7 вниз; ряд 7: б7 пробел (огонь 1), б2 Z (огонь 2); ряд 6: б1 Q/Я — как Z
kbd_scan:		ld		a, 0x8a					; порт B — вход
				out		(0x00), a
				ld		a, 0xfe
				out		(0x03), a
				in		a, (0x02)
				cpl
				ld		(kb_row0), a
				ld		a, 0x7f
				out		(0x03), a
				in		a, (0x02)
				cpl
				ld		(kb_row7), a
				ld		a, 0xfd					; ряд 1: F1 (б3), F3 (б5) — старт в god mode из меню
				out		(0x03), a
				in		a, (0x02)
				cpl
				ld		(kb_row1), a
				ld		a, 0xbf					; ряд 6: Q (б1) — на русской раскладке Я, на месте Z:
				out		(0x03), a				; дублирует Z (взять/бросить) — в бит 2 ряда 7
				in		a, (0x02)
				cpl
				and		0x02
				add		a, a
				push	hl						; из прерывания: регистры сохраняются позже
				ld		hl, kb_row7
				or		(hl)
				ld		(hl), a
				pop		hl
				ld		a, 0x88					; порт B — выход (бордюр 0), прокрутка FF
				out		(0x00), a
				xor		a
				out		(0x02), a
				ld		a, 0xff
				out		(0x03), a
				ret
kb_row0:		DB		0
kb_row7:		DB		0
kb_row1:		DB		0
god:			DB		0						; 1 — god mode (F1+F3 в меню): здоровье после каждого шага полное
read_input:		ld		a, (kb_row0)
				ld		c, a
				ld		a, (kb_row7)
				ld		d, a
				ld		b, 0
				ld		a, c
				and		0x10
				jp		z, ri_1
				ld		b, 1 << player_left_bit
ri_1:			ld		a, c
				and		0x40
				jp		z, ri_2
				ld		a, b
				or		1 << player_right_bit
				ld		b, a
ri_2:			ld		a, c
				and		0x20
				jp		z, ri_3
				ld		a, b
				or		1 << player_up_bit
				ld		b, a
ri_3:			ld		a, c
				and		0x80
				jp		z, ri_4
				ld		a, b
				or		1 << player_down_bit
				ld		b, a
ri_4:			ld		a, d
				and		0x80
				jp		z, ri_5
				ld		a, b
				or		1 << player_fire1_bit
				ld		b, a
ri_5:			ld		a, d
				and		0x04
				jp		z, ri_6
				ld		a, b
				or		1 << player_fire2_bit
				ld		b, a
ri_6:			ld		a, 0xff
				ld		(C_keyboard_state + 4), a	; M и H не нажаты
				ld		(C_keyboard_state + 5), a
				ld		a, (C_keys_fire2)
				ld		c, a
				ld		a, b
				ld		(C_keys_pressed), a
				and		0x0f
				jp		z, ri_7
				ld		(C_fire_direction), a
ri_7:			ld		a, b
				and		1 << player_fire2_bit
				ld		(C_keys_fire2), a
				ret		z
				cp		c
				ret		nz
				ld		a, b
				and		~(1 << player_fire2_bit)
				ld		(C_keys_pressed), a
				ret

; ---- часы (update_clock CPC, прерывание раз в 50 шагов) ----
update_clock:	ld		a, 1
				ld		(C_tell_time), a
				ld		(C_second_only), a
				ld		hl, C_game_time + 5
				inc		(hl)
				ld		a, (hl)
				cp		'9' + 1
				ret		nz
				xor		a
				ld		(C_second_only), a
				ld		(hl), '0'
				dec		hl
				inc		(hl)
				ld		a, (hl)
				cp		'6'
				ret		nz
				ld		(hl), '0'
				dec		hl
				dec		hl
				inc		(hl)
				ld		a, (hl)
				cp		'9' + 1
				ret		nz
				ld		(hl), '0'
				dec		hl
				inc		(hl)
				ld		a, (hl)
				cp		'9' + 1
				ret		nz
				ld		(hl), '0'
				dec		hl
				inc		(hl)
				ld		a, (hl)
				cp		'9' + 1
				ret		nz
				ld		a, game_finished
				ld		(C_game_over), a
				ret

; ---- экран и палитра ----
clear_screen:	ld		hl, 0
				add		hl, sp
				ld		(clr_ssp), hl
				ld		hl, 0xE000				; 3 плоскости; в 0xE000.. — код
				ld		sp, hl
				ld		de, 0
				ld		b, 0
clr_l:			REPT	32
				push	de
				ENDR
				ld		hl, 0
				add		hl, sp
				ld		a, h
				cp		0x80
				jp		nz, clr_l
				ld		hl, (clr_ssp)
				ld		sp, hl
				ret
clr_ssp:			DW		0
set_palette:	ld		hl, pal_data + 15
set_palette_hl:	ld		(sp_src), hl			; HL = последний байт палитры (16 байт)
				ld		b, 3					; три кадра подряд: палитра пишется в обратном ходе
sp_f:			push	bc
				call	sp_once
				pop		bc
				dec		b
				jp		nz, sp_f
				ret
sp_once:		ei								; дождаться прерывания кадра (ISR — по 0x38)
				halt
				di
				ld		a, 0x88					; порт B — выход (номер цвета палитры)
				out		(0x00), a
				ld		hl, (sp_src)
				ld		c, 15
sp_l:			ld		a, c
				out		(0x02), a
				ld		a, (hl)
				dec		hl
				out		(0x0C), a
				out		(0x0C), a
				out		(0x0C), a
				out		(0x0C), a
				dec		c
				jp		p, sp_l
				xor		a
				out		(0x02), a
				ld		a, 0xff
				out		(0x03), a
				ret
sp_src:			DW		0

	IFDEF DEBUGB
dbg_border:		push	af
				ld		a, 0x88
				out		(0x00), a
				pop		af
				out		(0x02), a
				ld		a, 0x8a
				out		(0x00), a
				ld		a, 0xff
				out		(0x03), a
				ret
	ENDIF
