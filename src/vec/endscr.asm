; endscr.asm: экран итогов (init_endgame CPC): поле очищено, надписи game_over_*_text шрифтом
; font_data_mode0 (перекодирован tools/mkgame.py, квазидиск стр. 0 с FONT_ADDR: на символ 3 плоскости x 8 строк,
; два набора — маска цвета 0x03 и остальные). Тексты (время, счёт, процент) заполняет select_end.

end_draw:		call	clear_room
				ld		a, (C_game_over)
				cp		game_completed
				jp		nz, ed_over
				ld		hl, C_game_over_congrats_text
				call	draw_text
				ld		hl, C_game_over_escaped_text
				call	draw_text
				jp		ed_rest
ed_over:		ld		hl, C_game_over_text
				call	draw_text
ed_rest:		ld		hl, C_game_over_time_text
				call	draw_text
				ld		hl, C_game_over_score_text
				call	draw_text
				ld		hl, C_game_over_percentage_text
				jp		draw_text

; HL = текст CPC: байт x (байты режима 0: столбец Вектора = x / 2), строка экрана, маска цвета, символы до 0
draw_text:		ld		a, (hl)
				or		a
				rra
				add		a, 0x80
				ld		(tx_col), a
				inc		hl
				ld		a, (hl)
				cpl
				add		a, ROW0 + 1				; строка памяти = ROW0 - y
				ld		(tx_row), a
				inc		hl
				ld		a, (hl)
				inc		hl
				ld		de, FONT_ADDR
				cp		0x03
				jp		z, dx_ch
				ld		de, FONT_ADDR + FONT_N * 24
dx_ch:			ld		a, (hl)
				or		a
				ret		z
				push	hl
				push	de
				sub		' '						; глиф = набор + (символ - 32) * 24
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		b, h
				ld		c, l
				add		hl, hl
				add		hl, bc
				add		hl, de
				ld		de, dx_buf
				ld		c, 12
				ld		a, 0x10					; шрифт — стр. 0
				ld		(kr_pg), a
				call	kv_read
				ld		a, PN_KV
				ld		(kr_pg), a
				ld		hl, dx_buf
				ld		a, (tx_col)
				ld		d, a
				ld		c, 3
dx_pl:			ld		a, (tx_row)
				ld		e, a
				ld		b, 8
dx_l:			ld		a, (hl)
				ld		(de), a
				inc		hl
				dec		e
				dec		b
				jp		nz, dx_l
				ld		a, d
				add		a, 0x20
				ld		d, a
				dec		c
				jp		nz, dx_pl
				ld		hl, tx_col
				inc		(hl)
				pop		de
				pop		hl
				inc		hl
				jp		dx_ch
tx_col:			DB		0
tx_row:			DB		0
dx_buf:			DS		24
