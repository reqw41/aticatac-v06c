; spr.asm: спрайты игры — XOR из потока квазидиска (tools/mkgame.py), 6 объектов: герой, оружие, босс,
; враги 1..3. Каждый шаг: новое положение/кадр из состояния логики; изменилось — стереть старое (тот же
; XOR) и нарисовать новое. Прерывания запрещены всегда (стековый режим квазидиска).

MAXPAIRS		equ		12					; высота кадра до 24 строк
NOBJ			equ		6
; объект: нарисован?, запись кадра (2), фаза, столбец (0x80+), строка памяти y; затем новое — так же
OB_DRAWN		equ		0
OB_REC			equ		1
OB_PH			equ		3
OB_COL			equ		4
OB_ROW			equ		5
OB_NEW			equ		6					; +6: видим?, запись, фаза, столбец, строка
OBSZ			equ		12
objs:			DS		OBSZ * NOBJ, 0

; ---- XOR-вывод кадра: HL = запись кадра, A = фаза, D = 0x80 + столбец, E = строка памяти y ----
BLIT_COST		equ		14						; старших байтов счётчика (~7 тыс. тактов) — с запасом на кадр
blit_x:			push	af
				push	hl
				push	de
				ld		a, BLIT_COST
				call	di_guard
				pop		de
				pop		hl
				pop		af
				push	de
				add		a, a
				ld		(bx_ph), a
				ld		a, (hl)					; высота (чётная) -> вход в развёрнутый цикл
				or		a
				rra
				ld		b, a
				ld		a, MAXPAIRS
				sub		b
				ld		c, a					; пропуск пар
				add		a, a
				add		a, a
				add		a, a
				add		a, c					; * 9 (BX_PAIR)
				add		a, low bx_body
				ld		(bx_jp + 1), a
				ld		a, 0
				adc		a, high bx_body
				ld		(bx_jp + 2), a
				inc		hl
				ld		a, e
				sub		(hl)					; минус сдвиг пустых строк сверху
				ld		(bx_row + 1), a
				inc		hl
				ld		a, (hl)
				ld		(bx_pg + 1), a
				inc		hl
				ld		a, (bx_ph)
				add		a, l
				ld		l, a
				jp		nc, bx_1
				inc		h
bx_1:			ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ld		(bx_sp + 1), hl
				pop		de
				ld		a, d
				ld		(bx_col + 1), a
				ld		hl, 0
				add		hl, sp
				ld		(bx_ssp), hl
bx_pg:			ld		a, 0
				out		(0x10), a
bx_sp:			ld		sp, 0
bx_next:		pop		bc
				ld		a, b
				or		a
				jp		nz, bx_end
				ld		a, c
bx_col:			add		a, 0
				ld		h, a
bx_row:			ld		l, 0
bx_jp:			jp		0
bx_body:
				DUP		MAXPAIRS
				pop		bc
				ld		a, c
				xor		(hl)
				ld		(hl), a
				dec		l
				ld		a, b
				xor		(hl)
				ld		(hl), a
				dec		l
				EDUP
				jp		bx_next
bx_end:			xor		a
				out		(0x10), a
				ld		hl, (bx_ssp)
				ld		sp, hl
				ei
				ret
BX_PAIR			equ		9
bx_ph:			DB		0
bx_ssp:			DW		0

; ---- новое состояние объектов из логики: (видим, запись, x пикселей CPC, y) -> поля OB_NEW ----
; HL = объект, A = видим, DE = запись, B = x, C = y
obj_set:		push	hl
				ld		de, OB_NEW
				add		hl, de
				pop		de
				ret
; запись нового: HL -> поле OB_NEW объекта; на входе в ob_put: A = видим, DE = запись, B = x, C = y
ob_put:			ld		(hl), a
				inc		hl
				ld		(hl), e
				inc		hl
				ld		(hl), d
				inc		hl
				ld		a, b
				and		3
				ld		(hl), a
				inc		hl
				ld		a, b
				rrca
				rrca
				and		0x3f
				add		a, 0x80
				ld		(hl), a
				inc		hl
				ld		a, c
				cpl
				add		a, ROW0 + 1				; ROW0 - y
				ld		(hl), a
				ret

; герой: hero_frames[герой*16 + ориентация/2 + шаг]; виден, когда не появляется/не исчезает
obj_player:		ld		hl, objs + 0 * OBSZ + OB_NEW
				ld		a, (C_player_growing)
				or		a
				jp		nz, ob_hide
				ld		a, (hero)
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
				push	hl
				ld		hl, hero_frames
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				pop		hl
				ld		a, (C_player_x)
				ld		b, a
				ld		a, (C_player_y)
				ld		c, a
				ld		a, 1
				jp		ob_put
ob_hide:		ld		(hl), 0
				ret

; оружие: кадр last_drawn_weapon_frame (w, h, offx, offy, запись); x = 2*((weapon_x >> 1) + offx)
obj_weapon:		ld		hl, objs + 1 * OBSZ + OB_NEW
				ld		a, (C_weapon_active)
				or		a
				jp		z, ob_hide
				push	hl
				ld		hl, (C_last_drawn_weapon_frame)
				inc		hl
				inc		hl
				ld		a, (C_weapon_x)
				or		a
				rra
				add		a, (hl)
				add		a, a
				ld		b, a
				inc		hl
				ld		a, (C_weapon_y)
				add		a, (hl)
				ld		c, a
				inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				pop		hl
				ld		a, 1
				jp		ob_put

; враг/босс: DE = структура, HL = поле OB_NEW. Список кадров — spr_gfx или spr_alt (fdom и x влево)
	MACRO OBJSPR pobj, k
				ld		hl, objs + k * OBSZ + OB_NEW
				ld		a, (pobj + spr_state)
				or		a
				jp		z, ob_hide
				push	hl
				ld		hl, (pobj + spr_gfx)
				ld		a, (pobj + spr_fdom)
				or		a
				jp		z, .g
				ld		a, (pobj + spr_xinc)
				or		a
				jp		p, .g
				ld		hl, (pobj + spr_alt)
.g:				ld		a, (pobj + spr_frame)
				rrca
				and		0x06
				ld		e, a
				ld		d, 0
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				pop		hl
				ld		a, (pobj + spr_x)
				ld		b, a
				ld		a, (pobj + spr_y)
				ld		c, a
				ld		a, 1
				jp		ob_put
	ENDM
obj_boss:		OBJSPR	C_boss, 2
obj_s1:			OBJSPR	C_sprite1, 3
obj_s2:			OBJSPR	C_sprite2, 4
obj_s3:			OBJSPR	C_sprite3, 5

; ---- шаг вывода: новые состояния, потом стереть/нарисовать изменившиеся ----
render_sprites:	call	obj_player
				call	obj_weapon
				call	obj_boss
				call	obj_s1
				call	obj_s2
				call	obj_s3
				ld		hl, objs
				ld		b, NOBJ
rs_l:			push	bc
				push	hl
				call	obj_update
				pop		hl
				ld		de, OBSZ
				add		hl, de
				pop		bc
				dec		b
				jp		nz, rs_l
				ret

; HL = объект: если новое (видим, запись, фаза, столбец, строка) отличается от нарисованного — заменить
obj_update:		push	hl
				ld		d, h
				ld		e, l
				ld		bc, OB_NEW
				add		hl, bc
				ld		a, (hl)
				or		a
				jp		nz, ou_cmp
				ld		a, (de)					; не видим: стереть, если нарисован
				or		a
				pop		hl
				ret		z
				push	hl
				call	obj_erase
				pop		hl
				ld		(hl), 0
				ret
ou_cmp:			ld		a, (de)					; сравнить 6 байт
				or		a
				jp		z, ou_draw
				ld		c, 5
ou_c:			inc		hl
				inc		de
				ld		a, (de)
				cp		(hl)
				jp		nz, ou_chg
				dec		c
				jp		nz, ou_c
				pop		hl
				ret								; не изменился
ou_chg:			pop		hl
				push	hl
				call	obj_erase
				pop		hl
				push	hl
ou_draw:		pop		hl
				push	hl
				ld		d, h
				ld		e, l
				ld		bc, OB_NEW
				add		hl, bc
				ld		c, 6
ou_cp:			ld		a, (hl)					; нарисованное = новое
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, ou_cp
				pop		hl
; HL = объект (нарисованное): XOR кадра
obj_xor:		inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		a, (hl)
				inc		hl
				ld		b, (hl)
				inc		hl
				ld		c, (hl)
				ex		de, hl
				ld		d, b
				ld		e, c
				jp		blit_x
obj_erase:		jp		obj_xor

; всё стереть (перед переключением двери, съеденной едой и т.п.)
erase_all:		ld		hl, objs
				ld		b, NOBJ
ea_l:			push	bc
				push	hl
				ld		a, (hl)
				or		a
				call	nz, obj_xor
				pop		hl
				ld		(hl), 0
				ld		de, OBSZ
				add		hl, de
				pop		bc
				dec		b
				jp		nz, ea_l
				ret
; забыть нарисованное (экран очищен)
forget_all:		ld		hl, objs
				ld		b, NOBJ
				ld		de, OBSZ
fa_l:			ld		(hl), 0
				add		hl, de
				dec		b
				jp		nz, fa_l
				ret
