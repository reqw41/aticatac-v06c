; panel.asm: панель справа (столбцы 24..31) — неподвижная часть из квазидиска (снимок CPC в начале игры,
; tools/mkgame.py), дальше по изменениям в логике: время и счёт (цифры шрифта CPC), курица-здоровье
; (по строке, как update_chicken), жизни (remove_life), карманы (draw_pockets). Тени — что нарисовано.

PN_KV			equ		0x10 | (2 << 2)			; квазидиск стр. 2, стековый режим
PN_TIME_Y		equ		0x41					; строки CPC текста (textstrings.asm)
PN_SCORE_Y		equ		0x51
PN_CHICK_Y		equ		91						; строка курицы a — строка экрана 91 + a (байт 50)
PN_LIFE_Y		equ		123
PN_POCKET_Y		equ		0x22

; ---- неподвижная часть панели и тени (новая игра) ----
panel_init:		di
				ld		hl, 0
				add		hl, sp
				ld		(pn_ssp), hl
				ld		a, PN_KV
				out		(0x10), a
				ld		hl, PANEL_ADDR
				ld		sp, hl
				ld		de, 0x8000 + 24 * 256 + ROW0	; плоскость 0, столбец 24
pi_col:			ld		h, d
				ld		l, e
				REPT	96
				pop		bc
				ld		(hl), c
				dec		l
				ld		(hl), b
				dec		l
				ENDR
				inc		d
				ld		a, d
				and		0x1f
				jp		nz, pi_col				; столбцы 24..31 (32 -> 0 в младших 5 битах)
				ld		a, d
				add		a, 0x20 - 8
				ld		d, a
				cp		0xe0 + 24
				jp		nz, pi_col
				xor		a
				out		(0x10), a
				ld		hl, (pn_ssp)
				ld		sp, hl
				ei
				ld		hl, C_game_time			; тени = что на снимке
				ld		de, pn_time
				ld		c, 6
				call	pn_copy
				ld		hl, C_score_text + 3
				ld		de, pn_score
				ld		c, 6
				call	pn_copy
				ld		a, (C_drawn_health)
				ld		(pn_health), a
				ld		a, (C_num_lives)
				ld		(pn_lives), a
				ld		a, 0xff
				ld		(pn_pockets), a
				ld		(pn_pockets + 1), a
				ld		(pn_pockets + 2), a
				ret
pn_copy:		ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, pn_copy
				ret

; ---- изменения ----
panel_update:	ld		hl, C_game_time
				ld		de, pn_time
				ld		b, PN_TIME_Y
				call	pn_text
				ld		hl, C_score_text + 3
				ld		de, pn_score
				ld		b, PN_SCORE_Y
				call	pn_text
				call	pn_chicken
				call	pn_lives_upd
				jp		pn_pockets_upd

; HL = строка (6 символов), DE = тень, B = строка CPC: перерисовать изменившиеся символы (столбцы 25..30)
pn_text:		ld		c, 25
ptx_l:			ld		a, (de)
				cp		(hl)
				jp		z, ptx_n
				ld		a, (hl)
				ld		(de), a
				push	hl
				push	de
				push	bc
				call	pn_glyph
				pop		bc
				pop		de
				pop		hl
ptx_n:			inc		hl
				inc		de
				inc		c
				ld		a, c
				cp		31
				jp		nz, ptx_l
				ret
; A = символ ('0'..'9', ':'), C = столбец, B = строка CPC
pn_glyph:		sub		'0'
				cp		11
				ret		nc
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, de					; * 24
				ld		de, glyphs
				add		hl, de
				ex		de, hl					; DE = символ
				ld		a, b
				cpl
				add		a, ROW0 + 1
				ld		l, a
				ld		a, c
				add		a, 0x80
				ld		h, a
				ld		c, 3
pg_pl:			push	hl
				ld		b, 8
pg_r:			ld		a, (de)
				ld		(hl), a
				inc		de
				dec		l
				dec		b
				jp		nz, pg_r
				pop		hl
				ld		a, h
				add		a, 0x20
				ld		h, a
				dec		c
				jp		nz, pg_pl
				ret

; курица: по единице до drawn_health (вверх — строка 30 - h + 1 полной, вниз — строка 30 - h пустой)
pn_chicken:		ld		a, (C_drawn_health)
				ld		hl, pn_health
				cp		(hl)
				ret		z
				jp		c, pc_down
				inc		(hl)
				ld		a, 31
				sub		(hl)
				cp		30
				jp		z, pn_chicken
				ld		c, 0					; полная
				call	pn_chick_row
				jp		pn_chicken
pc_down:		dec		(hl)
				ld		a, 30
				sub		(hl)
				cp		30
				jp		z, pn_chicken
				ld		c, 30					; пустая
				call	pn_chick_row
				jp		pn_chicken
; A = строка курицы (0..29), C = 0 полная / 30 пустая: 18 байт из квазидиска -> столбцы 25..30, 3 плоскости
pn_chick_row:	ld		(pcr_a), a
				add		a, c
				ld		l, a
				ld		h, 0
				add		hl, hl					; * 18
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, hl
				add		hl, hl
				add		hl, de
				ld		de, CHICK_ADDR
				add		hl, de
				ld		de, pn_buf
				ld		c, 9
				call	kv_read
				ld		a, (pcr_a)
				add		a, PN_CHICK_Y
				cpl
				add		a, ROW0 + 1
				ld		l, a
				ld		de, pn_buf
				ld		h, 0x80 + 25
				ld		c, 3
pcr_pl:			push	hl
				ld		b, 6
pcr_c:			ld		a, (de)
				ld		(hl), a
				inc		de
				inc		h
				dec		b
				jp		nz, pcr_c
				pop		hl
				ld		a, h
				add		a, 0x20
				ld		h, a
				dec		c
				jp		nz, pcr_pl
				ret
pcr_a:			DB		0
pn_buf:			DS		18

; HL = адрес в квазидиске (стр. 2), DE = куда, C = слов
kv_read:		di
				ex		de, hl
				ld		(kr_dst), hl
				ld		hl, 0
				add		hl, sp
				ld		(pn_ssp), hl
				ex		de, hl
				ld		a, PN_KV
				out		(0x10), a
				ld		sp, hl
				ld		hl, (kr_dst)
kr_l:			pop		de
				ld		(hl), e
				inc		hl
				ld		(hl), d
				inc		hl
				dec		c
				jp		nz, kr_l
				xor		a
				out		(0x10), a
				ld		hl, (pn_ssp)
				ld		sp, hl
				ei
				ret
kr_dst:			DW		0

; жизни: убывает — стереть фигурку life_table[новое число] (2 столбца, высота героя)
pn_lives_upd:	ld		a, (C_num_lives)
				ld		hl, pn_lives
				cp		(hl)
				ret		nc
				dec		(hl)
				ld		a, (hl)
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, C_life_table
				add		hl, de
				ld		a, (hl)					; x байт
				or		a
				rra
				add		a, 0x80
				ld		h, a
				ld		a, PN_LIFE_Y
				cpl
				add		a, ROW0 + 1
				ld		l, a
				ld		a, (C_actual_player_height)
				ld		b, a
				ld		c, 6					; 2 столбца x 3 плоскости
pl_pc:			push	hl
				push	bc
				xor		a
pl_r:			ld		(hl), a
				dec		l
				dec		b
				jp		nz, pl_r
				pop		bc
				pop		hl
				inc		h
				ld		a, c
				cp		5
				jp		z, pl_n
				cp		3
				jp		z, pl_n
				cp		1
				jp		z, pl_n
				jp		pl_nn
pl_n:			ld		a, h					; после второго столбца — следующая плоскость
				add		a, 0x20 - 2
				ld		h, a
pl_nn:			dec		c
				jp		nz, pl_pc
				jp		pn_lives_upd

; карманы: pocket1..3 -> предмет (ix+1: описатель) в слоты x 50/54/58, строка 0x22; 0xFF — пусто
pn_pockets_upd:	ld		hl, C_pocket1
				ld		de, pn_pockets
				ld		b, 50
pp_l:			ld		a, (de)
				cp		(hl)
				jp		z, pp_n
				ld		a, (hl)
				ld		(de), a
				push	hl
				push	de
				push	bc
				cp		0xff
				jp		z, pp_empty
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		de, C_collectable_items + 1
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		a, b
				ld		c, PN_POCKET_Y
				call	item_at
				jp		pp_d
pp_empty:		ld		hl, (C_collectable_items + 1)	; любой предмет 4x16 — для стирания по маске
				ld		a, b
				ld		c, PN_POCKET_Y
				call	item_clear_at
pp_d:			pop		bc
				pop		de
				pop		hl
pp_n:			inc		hl
				inc		de
				ld		a, b
				add		a, 4
				ld		b, a
				cp		62
				jp		nz, pp_l
				ret

pn_ssp:			DW		0
pn_time:		DS		6
pn_score:		DS		6
pn_health:		DB		0
pn_lives:		DB		0
pn_pockets:		DS		3
