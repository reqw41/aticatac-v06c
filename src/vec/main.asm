; main.asm: запуск и главный цикл игры на Векторе (этап 3, docs/LOGIC_PLAN.md).
; Темп — кадровое прерывание (ei; halt; di в начале шага), остальное время прерывания запрещены.

start:			di
				ld		sp, 0x4000
				ld		a, 0xff
				out		(0x03), a
				call	set_palette
				ld		a, 0x34					; ВИ53 счётчик 0: режим 2, делитель 29952 = кадр
				out		(0x08), a
				xor		a
				out		(0x0B), a
				ld		a, high 29952
				out		(0x0B), a
				call	clear_screen
	IFDEF DEBUGB
				ld		a, 10
				call	dbg_border	; этап	; этап
	ENDIF
new_game:		call	hero_setup
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

main_loop:
	IFDEF DEBUGB
				ld		a, 12				; главный цикл
				call	dbg_border
	ENDIF
				call	wait_frame
				call	read_input
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
				call	run_task
				call	post_events
				call	render_sprites
				jp		main_loop
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
; конец игры: задержка, потом по клавише — новая игра (меню у Вектора своё; пока сразу рыцарь)
end_task_v:		ld		a, (C_end_key_delay)
				or		a
				jp		nz, end_tasks
				ld		a, (C_keys_pressed)
				or		a
				ret		z
				pop		hl						; из run_task
				jp		new_game

; события вывода после шага логики
post_events:	ld		hl, (was_task)
				ld		a, (was_rc)
				or		a
				jp		z, pe_1
				JPHL	C_game_tasks, pe_room	; draw_room в этом шаге
pe_1:			ld		hl, (was_task)
				JPHL	C_falling_tasks, pe_fall
				ld		hl, (C_current_game_state + 1)
				JPHL	C_falling_tasks, pe_tofall
				jp		pe_items
pe_fall:		ld		hl, (C_current_game_state + 1)
				JPHL	C_game_tasks, pe_room	; падение кончилось — комната
				ret
pe_tofall:		ld		hl, (was_task)			; только что начали падать — поле пустое
				JPHL	C_falling_tasks, pe_ret
				call	clear_room
				jp		forget_all
pe_ret:			ret
pe_room:		call	render_room
				jp		forget_all
pe_items:		ld		hl, (C_door_to_toggle)
				ld		a, h
				or		l
				jp		z, pe_2
				push	hl
				call	erase_all
				pop		hl
				call	draw_list_item
pe_2:			ld		hl, (C_erase_food_with_index)
				ld		a, h
				or		l
				jp		z, pe_3
				push	hl
				call	erase_all
				pop		hl
				call	erase_food_item
pe_3:			ld		hl, (C_draw_tombstone_with_index)
				ld		a, h
				or		l
				jp		z, pe_4
				push	hl
				call	erase_all
				pop		hl
				call	draw_food_item
pe_4:			ld		a, (C_do_pockets)
				cp		2
				ret		nz
				call	erase_all				; предмет взят/брошен — перерисовать комнату (пока так)
				call	render_room
				jp		forget_all

; герой — пока рыцарь (save_selection CPC)
hero_setup:		xor		a
				ld		(hero), a
				ld		hl, C_knight_frames_table
				ld		(C_selected_player), hl
				ld		a, knight_height
				ld		(C_selected_player_height), a
				ld		a, character_knight
				ld		(C_player_character), a
				ld		a, item_clock
				ld		(C_magic_door), a
				ld		a, 1
				ld		(C_weapon_rotates), a
				ld		hl, C_sword_data
				ld		(C_weapon_type), hl
				ret
hero:			DB		0

; ---- темп: шаг начинается с кадрового прерывания (обработчик 0x38 — ret; таймер ВИ53 в Emu80 так не читался)
wait_frame:		ei
				halt
				di
				ret

; ---- клавиатура Вектора -> keys_pressed / fire_direction / keys_fire2 (read_keys CPC) ----
; ряд 0: б4 влево, б5 вверх, б6 вправо, б7 вниз; ряд 7: б7 пробел (огонь 1), б2 Z (огонь 2)
read_input:		ld		a, 0x8a					; порт B — вход
				out		(0x00), a
				ld		a, 0xfe
				out		(0x03), a
				in		a, (0x02)
				cpl
				ld		c, a
				ld		a, 0x7f
				out		(0x03), a
				in		a, (0x02)
				cpl
				ld		d, a
				ld		a, 0xff
				out		(0x03), a				; порт 3 — ещё и прокрутка
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
set_palette:	ld		b, 3					; три кадра подряд: палитра пишется в обратном ходе
sp_f:			push	bc
				call	sp_once
				pop		bc
				dec		b
				jp		nz, sp_f
				ret
sp_once:		ei								; дождаться прерывания кадра
				halt
				di
				ld		a, 0x88					; порт B — выход (номер цвета палитры)
				out		(0x00), a
				ld		hl, pal_data + 15
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
				ld		a, 0x8a
				out		(0x00), a
				ld		a, 0xff
				out		(0x03), a
				ret

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
