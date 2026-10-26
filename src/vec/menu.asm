; menu.asm: меню выбора героя (menu.asm CPC). Фон — из квазидиска (снимок CPC tools/cpcmenu.js,
; tools/mkgame.py: логотип, надписи, указатель), палитра меню pal_menu. Три героя — спрайтами (объекты 0..2,
; маг, рыцарь, серв через CHAR_GAP), выбирается стоящий у указателя. Стрелки — сдвиг (update_menu,
; check_keys CPC), огонь — старт через MN_START кадров; F1 + F3 — старт в god mode (бессмертие).

MN_KV			equ		0x10					; квазидиск стр. 0, стековый режим
CHAR_LEFT		equ		20						; character_left/mid/right/gap CPC
CHAR_MID		equ		40
CHAR_RIGHT		equ		60
CHAR_GAP		equ		20
CHAR_Y			equ		0x7a					; character_select_y
MN_START		equ		175						; кадров от огня до игры (start_the_game CPC — мелодия старта)

menu:			di
				ld		sp, 0x4000
				call	clear_screen
				call	menu_bg
				ld		hl, pal_menu + 15
				call	set_palette_hl
				ld		hl, bgraw				; поле чёрное — герои замещаются на месте
				ld		bc, 24 * 24
mn_bg0:			ld		(hl), 0
				inc		hl
				dec		bc
				ld		a, b
				or		c
				jp		nz, mn_bg0
				call	forget_all
				ld		a, SND_MENU
				call	snd_play
				xor		a
				ld		(C_menu_state), a
				ld		(ml_pend), a
				ld		a, CHAR_MID
				ld		(C_player_select_x), a
				ld		(C_characters_target), a
				ld		a, player_is_going_left
				ld		(C_player_orientation), a
				ld		a, 1
				ld		(C_characters_moving), a
mn_rel:			call	wait_frame				; клавиши с прошлой игры — дождаться отпускания
				call	read_input
				ld		a, (C_keys_pressed)
				or		a
				jp		nz, mn_rel
mn_loop:		call	wait_frame
				call	read_input
				ld		a, (C_menu_state)
				or		a
				jp		nz, mn_starting
				call	mn_update
				ld		a, (kb_row1)			; F1 + F3 — старт в god mode
				and		0x28
				cp		0x28
				ld		a, 1
				jp		z, mn_go_god
				ld		a, (C_keys_pressed)
				and		(1 << player_fire1_bit) | (1 << player_fire2_bit)
				jp		z, mn_draw
				xor		a
mn_go_god:		ld		(god), a
				ld		a, MN_START
				ld		(C_menu_state), a
				ld		a, SND_START
				call	snd_play
mn_draw:		call	mn_heroes
				call	render_objs
				jp		mn_loop
mn_starting:	dec		a
				ld		(C_menu_state), a
				jp		nz, mn_draw
				jp		new_game

; сдвиг героев к цели (update_menu CPC); дошли — выбран герой у указателя -> hero
mn_update:		ld		a, (C_characters_moving)
				or		a
				jp		z, mn_keys
				ld		a, (C_characters_target)
				ld		b, a
				ld		a, (C_player_select_x)
				ld		e, 0xff
				cp		b
				jp		nc, mn_r
				ld		e, 1
mn_r:			add		a, e
				ld		(C_player_select_x), a
				ld		c, a
				ld		a, (C_player_frame)
				inc		a
				and		0x0f
				ld		(C_player_frame), a
				ld		a, c
				cp		b
				ret		nz
				ld		c, 0					; у указателя: середина — рыцарь,
				ld		a, b
				cp		CHAR_MID
				jp		z, mn_sel
				ld		c, 2					; цель слева — серв, справа — маг (как в CPC)
				cp		CHAR_LEFT
				jp		z, mn_sel
				ld		c, 1
mn_sel:			xor		a
				ld		(C_characters_moving), a
				ld		a, default_frame
				ld		(C_player_frame), a
				ld		a, c
				ld		(hero), a
				ret
; стрелки (check_keys CPC)
mn_keys:		ld		a, (C_keys_pressed)
				and		1 << player_left_bit
				jp		z, mn_kr
				ld		a, (C_player_select_x)
				cp		CHAR_LEFT
				ret		z
				cp		CHAR_MID
				ld		a, CHAR_LEFT
				jp		z, mn_pl
				ld		a, CHAR_MID
mn_pl:			ld		(C_characters_target), a
				ld		a, player_is_going_left
				jp		mn_go
mn_kr:			ld		a, (C_keys_pressed)
				and		1 << player_right_bit
				ret		z
				ld		a, (C_player_select_x)
				cp		CHAR_RIGHT
				ret		z
				cp		CHAR_MID
				ld		a, CHAR_RIGHT
				jp		z, mn_pr
				ld		a, CHAR_MID
mn_pr:			ld		(C_characters_target), a
				ld		a, player_is_going_right
mn_go:			ld		(C_player_orientation), a
				ld		a, 1
				ld		(C_characters_moving), a
				ret

; новые состояния объектов: маг, рыцарь, серв (update_heroes CPC); 3..5 скрыты
mn_heroes:		ld		a, (C_player_select_x)
				ld		(mn_x), a
				ld		hl, objs + OB_NEW
				ld		a, 1
				call	mn_one
				ld		hl, objs + OBSZ + OB_NEW
				xor		a
				call	mn_one
				ld		hl, objs + 2 * OBSZ + OB_NEW
				ld		a, 2
				call	mn_one
				xor		a
				ld		(objs + 3 * OBSZ + OB_NEW), a
				ld		(objs + 4 * OBSZ + OB_NEW), a
				ld		(objs + 5 * OBSZ + OB_NEW), a
				ret
; HL -> поле OB_NEW, A = герой: кадр hero_frames[герой * 16 + ориентация / 2 + шаг], x = mn_x (+ CHAR_GAP)
mn_one:			push	hl
				add		a, a
				add		a, a
				add		a, a
				add		a, a
				ld		b, a
				ld		a, (C_player_orientation)
				or		a
				rra
				add		a, b
				ld		b, a
				ld		a, (C_player_frame)
				rrca
				rrca
				and		3
				add		a, b
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, hero_frames
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				pop		hl
				ld		a, (mn_x)
				ld		b, a
				add		a, CHAR_GAP
				ld		(mn_x), a
				ld		c, CHAR_Y
				ld		a, 1
				jp		ob_put
mn_x:			DB		0

; фон меню: квазидиск MENU_ADDR -> 3 плоскости x 32 столбца x 192 строки (как panel_init)
menu_bg:		di
				ld		hl, 0
				add		hl, sp
				ld		(pn_ssp), hl
				ld		a, MN_KV
				out		(0x10), a
				ld		hl, MENU_ADDR
				ld		sp, hl
				ld		de, 0x8000 + ROW0
mb_col:			ld		h, d
				ld		l, e
				ld		a, 96
mb_l:			pop		bc
				ld		(hl), c
				dec		l
				ld		(hl), b
				dec		l
				dec		a
				jp		nz, mb_l
				inc		d
				ld		a, d
				cp		0xe0
				jp		nz, mb_col
				xor		a
				out		(0x10), a
				ld		hl, (pn_ssp)
				ld		sp, hl
				ei
				ret
