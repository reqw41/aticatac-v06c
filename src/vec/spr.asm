; spr.asm: спрайты игры — 6 объектов: герой, оружие, босс, враги 1..3 (кадры — tools/mkgame.py, поток в
; квазидиске). Каждый шаг: новое положение/кадр из состояния логики; изменилось —
;   на чёрном полу и без соседей: ЗАМЕЩЕНИЕ НА МЕСТЕ — новая рамка целиком (данные или нули), потом нули на
;     уходящих краях старой рамки: момента «стёрто — ещё не нарисовано» нет;
;   иначе (фон под рамкой, касание другого объекта) — XOR: стереть старое, нарисовать новое, как на CPC.
; Стирание XOR верно для обоих способов: замещение пишет только на чёрном полу.
; Карта фона комнаты bgraw (24 столбца x 24 группы по 8 строк) — roomdraw.asm (load_bgf, bg_mark).

MAXPAIRS		equ		12					; высота кадра до 24 строк
NOBJ			equ		6
; объект: нарисован?, запись (2), фаза, столбец (0x80+), строка памяти y, рамка c0, c1, y0, y1 (y CPC);
; затем новое: видим?, запись (2), фаза, столбец, строка; рамка нового — nb_*
OB_DRAWN		equ		0
OB_REC			equ		1
OB_PH			equ		3
OB_COL			equ		4
OB_ROW			equ		5
OB_C0			equ		6
OB_C1			equ		7
OB_Y0			equ		8
OB_Y1			equ		9
OB_NEW			equ		10					; +10: видим?, запись, фаза, столбец, строка
OBSZ			equ		16
objs:			DS		OBSZ * NOBJ, 0

; ---- рамка кадра: HL = запись, A = фаза, B = 0x80+столбец, C = строка памяти y -> nb_c0, nb_c1, nb_y0, nb_y1
frame_box:		push	hl
				ld		e, a
				ld		a, b
				sub		0x80
				ld		(nb_c0), a
				ld		d, a
				push	de
				ld		de, 11					; столбцов фазы: запись + 11 + фаза
				add		hl, de
				pop		de
				ld		a, l
				add		a, e
				ld		l, a
				jp		nc, fb_1
				inc		h
fb_1:			ld		a, (hl)
				add		a, d
				dec		a
				ld		(nb_c1), a
				pop		hl
				ld		a, c
				cpl
				add		a, ROW0 + 1				; y = ROW0 - строка
				inc		hl
				add		a, (hl)					; + сдвиг сверху
				ld		(nb_y0), a
				dec		hl
				add		a, (hl)					; + высота
				dec		a
				ld		(nb_y1), a
				ret
nb_c0:			DB		0
nb_c1:			DB		0
nb_y0:			DB		0
nb_y1:			DB		0

; ---- вывод кадра: HL = запись, A = фаза, D = 0x80 + столбец, E = строка памяти y; режим bx_mode:
;      0 — XOR (блоки без данных пропускаются), 1 — замещение (данные пишутся, в блоки без данных — нули) ----
BLIT_COST		equ		14						; старших байтов счётчика (~7 тыс. тактов) — запас на кадр
blit_x:			ld		c, a
				xor		a
				jp		bl_go
blit_o:			ld		c, a
				ld		a, 1
bl_go:			ld		(bx_mode), a
				push	hl
				push	de
				push	bc
				ld		a, BLIT_COST
				call	di_guard
				pop		bc
				pop		de
				pop		hl
				ld		a, c
				push	de
				add		a, a
				ld		(bx_ph), a
				ld		a, (hl)					; высота (чётная) -> вход в развёрнутый цикл
				ld		(bx_h), a
				or		a
				rra
				ld		b, a
				ld		a, MAXPAIRS
				sub		b
				ld		c, a					; пропуск пар
				add		a, a
				add		a, a
				add		a, a
				add		a, c					; * 9 (BX_PAIR) — оба тела одной длины
				ld		c, a
				ld		a, (bx_mode)
				or		a
				ld		a, c
				jp		nz, bl_ov
				add		a, low bx_body
				ld		(bx_jp + 1), a
				ld		a, 0
				adc		a, high bx_body
				jp		bl_e
bl_ov:			add		a, low bo_body
				ld		(bx_jp + 1), a
				ld		a, 0
				adc		a, high bo_body
bl_e:			ld		(bx_jp + 2), a
				inc		hl
				ld		a, e
				sub		(hl)					; минус сдвиг пустых строк сверху
				ld		(bx_row + 1), a
				ld		(bx_top), a
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
				ld		(bx_c), a
				ld		hl, 0
				add		hl, sp
				ld		(bx_ssp), hl
				ld		de, bx_zq				; очередь блоков без данных (для замещения)
bx_pg:			ld		a, 0
				out		(0x10), a
bx_sp:			ld		sp, 0
bx_next:		pop		bc
				ld		a, b
				or		a
				jp		nz, bx_nd
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
bo_body:
				DUP		MAXPAIRS
				pop		bc
				ld		(hl), c
				nop
				nop
				dec		l
				ld		(hl), b
				nop
				nop
				dec		l
				EDUP
				jp		bx_next
bx_nd:			dec		a						; 1 — блок без данных, 2 — конец
				jp		nz, bx_end
				ld		a, c
				ld		(de), a
				inc		de
				jp		bx_next
bx_end:			xor		a
				out		(0x10), a
				ld		hl, (bx_ssp)
				ld		sp, hl
				ld		a, (bx_mode)
				or		a
				jp		z, bx_ret
				; замещение: нули в блоки без данных (высота строк от верха)
				ld		a, 0xff
				ld		(de), a
				ld		de, bx_zq
bx_z:			ld		a, (de)
				cp		0xff
				jp		z, bx_ret
				inc		de
				ld		hl, bx_c
				add		a, (hl)
				ld		h, a
				ld		a, (bx_top)
				ld		l, a
				ld		a, (bx_h)
				ld		b, a
				xor		a
bx_zl:			ld		(hl), a
				dec		l
				dec		b
				jp		nz, bx_zl
				jp		bx_z
bx_ret:			ei
				ret
BX_PAIR			equ		9
bx_ph:			DB		0
bx_mode:		DB		0
bx_h:			DB		0
bx_top:			DB		0
bx_c:			DB		0
bx_ssp:			DW		0
bx_zq:			DS		16

; ---- новое состояние объектов из логики ----
; запись нового: HL -> поле OB_NEW объекта; A = видим, DE = запись, B = x, C = y
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
ob_hide:		ld		(hl), 0
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

; враг/босс: список кадров — spr_gfx или spr_alt (fdom и x влево)
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

; ---- шаг вывода: новые состояния; изменившиеся объекты — по лучу: объект обновляется, когда луч уже
;      прошёл его строки или не дойдёт до них за время вывода (BEAM_W), иначе откладывается ----
	IFNDEF BEAM_W
BEAM_W			equ		42						; запас на вывод объекта, старшие байты счётчика (перебор: 20 — 10,6 % разрывов, 30 — 2,6 %, 42 — 0,3 %, 50 — 0,5 %)
	ENDIF
	IFNDEF BEAM_Y
BEAM_Y			equ		72						; строка луча для y = 0 (40 строк до картинки + 32 сверху)
	ENDIF
render_sprites:	call	obj_player
				call	obj_weapon
				call	obj_boss
				call	obj_s1
				call	obj_s2
				call	obj_s3
				; окна строк изменившихся объектов (y CPC -> старшие байты счётчика от прерывания)
				ld		hl, objs
				ld		de, rs_win
				ld		b, NOBJ
rw_l:			push	bc
				push	hl
				push	de
				call	obj_window				; A = 0 — не менялся, иначе B = верх, C = низ
				pop		de
				ld		(de), a
				inc		de
				ld		a, b
				ld		(de), a
				inc		de
				ld		a, c
				ld		(de), a
				inc		de
				pop		hl
				ld		bc, OBSZ
				add		hl, bc
				pop		bc
				dec		b
				jp		nz, rw_l
				ld		a, 0
				ld		(rs_spin), a
rs_pass:		ld		hl, objs
				ld		de, rs_win
				ld		b, NOBJ
				ld		c, 0					; сделано за проход
				ld		a, 0
				ld		(rs_left), a
rs_l:			push	bc
				ld		a, (de)
				or		a
				jp		z, rs_skip
				push	hl
				push	de
				call	beam_hi					; A = луч
	IFDEF NOBEAM
				ld		a, 0xf0					; без привязки: «луч уже прошёл»
	ENDIF
				pop		de
				push	de
				inc		de
				ld		b, a
				ld		a, (de)					; верх окна
				ld		c, a
				inc		de
				ld		a, (de)					; низ окна
				cp		b
				jp		c, rs_go				; луч ниже окна — уже прошёл
				ld		a, b
				add		a, BEAM_W
				cp		c
				jp		c, rs_go				; луч не успеет дойти до верха
				pop		de
				pop		hl
				ld		a, 1
				ld		(rs_left), a
				jp		rs_skip
rs_go:
	IFDEF NOBEAM
	ENDIF
				pop		de
				pop		hl
				xor		a
				ld		(de), a
				push	hl
				push	de
				ld		(ou_obj), hl
				call	obj_update
				pop		de
				pop		hl
				pop		bc
				inc		c
				push	bc
rs_skip:		pop		bc
				inc		de
				inc		de
				inc		de
				push	de
				ld		de, OBSZ
				add		hl, de
				pop		de
				dec		b
				jp		nz, rs_l
				ld		a, (rs_left)
				or		a
				ret		z
				ld		a, (rs_spin)			; ждём луч; слишком долго (кадр сменился) — выводим как есть
				inc		a
				ld		(rs_spin), a
				cp		200
				jp		c, rs_pass
				ld		hl, rs_win
				ld		b, NOBJ
rs_f:			ld		a, (hl)
				or		a
				jp		z, rs_f1
				ld		(hl), 0
				push	hl
				push	bc
				ld		a, NOBJ
				sub		b
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				add		hl, hl					; * OBSZ (16)
				ld		de, objs
				add		hl, de
				ld		(ou_obj), hl
				call	obj_update
				pop		bc
				pop		hl
rs_f1:			inc		hl
				inc		hl
				inc		hl
				dec		b
				jp		nz, rs_f
				ret
rs_win:			DS		NOBJ * 3				; менялся?, верх, низ (старшие байты счётчика)
rs_left:		DB		0
rs_spin:		DB		0
ou_obj:			DW		0
				ASSERT	OBSZ == 16

; HL = объект -> A = 1 и B/C = верх/низ окна строк (старое + новое), если изменился; иначе A = 0
obj_window:		ld		(ow_obj), hl
				ld		d, h
				ld		e, l
				ld		bc, OB_NEW
				add		hl, bc
				ld		a, (de)					; нарисован?
				or		(hl)					; видим?
				ret		z
				ld		a, (de)
				or		a
				jp		z, ow_chg
				ld		a, (hl)
				or		a
				jp		z, ow_chg
				ld		c, 5
ow_c:			inc		hl
				inc		de
				ld		a, (de)
				cp		(hl)
				jp		nz, ow_chg
				dec		c
				jp		nz, ow_c
				xor		a
				ret
ow_chg:			ld		a, 0xff
				ld		(ow_y0), a
				xor		a
				ld		(ow_y1), a
				ld		hl, (ow_obj)
				ld		a, (hl)
				or		a
				jp		z, ow_new
				ld		de, OB_Y0
				add		hl, de
				ld		a, (hl)
				ld		(ow_y0), a
				inc		hl
				ld		a, (hl)
				ld		(ow_y1), a
ow_new:			ld		hl, (ow_obj)
				ld		de, OB_NEW
				add		hl, de
				ld		a, (hl)
				or		a
				jp		z, ow_done
				ld		hl, (ow_obj)
				ld		(ou_obj), hl
				call	new_box
				ld		a, (nb_y0)
				ld		hl, ow_y0
				cp		(hl)
				jp		nc, ow_1
				ld		(hl), a
ow_1:			ld		a, (nb_y1)
				ld		hl, ow_y1
				cp		(hl)
				jp		c, ow_done
				ld		(hl), a
ow_done:		ld		a, (ow_y0)				; строка луча = 72 + y; старшие байты = (72 + y) * 3 / 8
				call	y_hi
				ld		b, a
				ld		a, (ow_y1)
				call	y_hi
				inc		a
				ld		c, a
				ld		a, 1
				ret
y_hi:			ld		l, a
				ld		h, 0
				ld		de, BEAM_Y
				add		hl, de
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, de					; * 3
				ld		a, l
				rrca
				rrca
				rrca
				and		0x1f
				ld		e, a
				ld		a, h
				rrca
				rrca
				rrca
				and		0xe0
				or		e						; / 8
				ret
ow_obj:			DW		0
ow_y0:			DB		0
ow_y1:			DB		0
; положение луча: старший байт прошедших отсчётов счётчика 0 с прерывания кадра
beam_hi:		di
				xor		a
				out		(0x08), a
				in		a, (0x0B)
				in		a, (0x0B)
				ei
				cpl
				ret

; HL = объект
obj_update:		ld		d, h
				ld		e, l
				ld		bc, OB_NEW
				add		hl, bc
				ld		a, (hl)
				or		a
				jp		nz, ou_vis
				ld		a, (de)					; не видим: стереть, если нарисован
				or		a
				ret		z
				ex		de, hl
				push	hl
				call	obj_xor
				pop		hl
				ld		(hl), 0
				ret
ou_vis:			ld		a, (de)
				or		a
				jp		z, ou_newonly
				ld		c, 5					; сравнить запись, фазу, столбец, строку
ou_c:			inc		hl
				inc		de
				ld		a, (de)
				cp		(hl)
				jp		nz, ou_chg
				dec		c
				jp		nz, ou_c
				ret								; не изменился
ou_chg:			call	new_box					; рамка нового -> nb_*
				call	can_replace
				jp		nz, ou_xor
				; замещение на месте: новая рамка целиком, потом уходящие края старой
				ld		hl, (ou_obj)
				call	new_args
				call	blit_o
				call	zero_leftover
				jp		ou_store
ou_xor:			ld		hl, (ou_obj)
				call	obj_xor					; стереть старое
ou_newonly:		call	new_box
				ld		hl, (ou_obj)
				call	new_args
				call	blit_x					; нарисовать новое
; нарисованное = новое, рамка — nb_*
ou_store:		ld		hl, (ou_obj)
				ld		(hl), 1
				ld		d, h
				ld		e, l
				inc		de
				ld		bc, OB_NEW + 1
				add		hl, bc
				ld		c, 5
ou_cp:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, ou_cp
				ld		hl, nb_c0
				ld		c, 4
ou_cb:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, ou_cb
				ret

; рамка нового кадра объекта (ou_obj) -> nb_*
new_box:		ld		hl, (ou_obj)
				call	new_args
				ld		b, d
				ld		c, e
				jp		frame_box
; HL = объект -> HL = запись нового, A = фаза, D = столбец, E = строка
new_args:		ld		de, OB_NEW + 1
				add		hl, de
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
				ret
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

; ---- можно ли заместить на месте? Объединение старой и новой рамки: в поле, на чёрном полу (bgraw),
;      не касается рамок других нарисованных объектов. -> Z = можно
can_replace:	ld		hl, (ou_obj)
				ld		de, OB_C0
				add		hl, de
				ld		a, (nb_c0)				; объединение: uc0..uc1, uy0..uy1
				cp		(hl)
				jp		c, rp_1
				ld		a, (hl)
rp_1:			ld		(uc0), a
				inc		hl
				ld		a, (nb_c1)
				cp		(hl)
				jp		nc, rp_2
				ld		a, (hl)
rp_2:			ld		(uc1), a
				inc		hl
				ld		a, (nb_y0)
				cp		(hl)
				jp		c, rp_3
				ld		a, (hl)
rp_3:			ld		(uy0), a
				inc		hl
				ld		a, (nb_y1)
				cp		(hl)
				jp		nc, rp_4
				ld		a, (hl)
rp_4:			ld		(uy1), a
				; в поле: столбцы 0..23, строки 0..191, высота объединения не больше 40 строк
				ld		a, (uc1)
				cp		24
				jp		nc, rp_no
				ld		a, (uy1)
				cp		192
				jp		nc, rp_no
				ld		b, a
				ld		a, (uy0)
				ld		c, a
				ld		a, b
				sub		c
				cp		40
				jp		nc, rp_no
				; фон: группы uy0>>3 .. uy1>>3 по столбцам uc0..uc1
				ld		a, (uc0)
				ld		c, a
rp_col:			ld		l, c					; bgraw[c * 24 + g]
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, de
				ld		de, bgraw
				add		hl, de
				ld		a, (uy0)
				rrca
				rrca
				rrca
				and		0x1f
				ld		e, a
				ld		d, 0
				add		hl, de
				ld		a, (uy1)
				rrca
				rrca
				rrca
				and		0x1f
				sub		e
				inc		a
				ld		b, a
rp_g:			ld		a, (hl)
				or		a
				jp		nz, rp_no
				inc		hl
				dec		b
				jp		nz, rp_g
				ld		a, (uc1)
				cp		c
				jp		z, rp_obj
				inc		c
				jp		rp_col
				; другие нарисованные объекты
rp_obj:			ld		hl, objs
				ld		b, NOBJ
rp_o:			push	bc
				push	hl
				ld		a, (ou_obj)
				cp		l
				jp		nz, rp_o1
				ld		a, (ou_obj + 1)
				cp		h
				jp		z, rp_onext				; сам объект
rp_o1:			ld		a, (hl)
				or		a
				jp		z, rp_onext
				ld		de, OB_C0
				add		hl, de
				ld		a, (uc1)				; пересечение по столбцам: c0 <= uc1 и c1 >= uc0
				cp		(hl)
				jp		c, rp_onext
				inc		hl
				ld		a, (uc0)
				ld		b, a
				ld		a, (hl)
				cp		b
				jp		c, rp_onext
				inc		hl
				ld		a, (uy1)				; по строкам: y0 <= uy1 и y1 >= uy0
				cp		(hl)
				jp		c, rp_onext
				inc		hl
				ld		a, (uy0)
				ld		b, a
				ld		a, (hl)
				cp		b
				jp		c, rp_onext
				pop		hl
				pop		bc
				jp		rp_no
rp_onext:		pop		hl
				ld		de, OBSZ
				add		hl, de
				pop		bc
				dec		b
				jp		nz, rp_o
				xor		a						; Z — можно
				ret
rp_no:			or		1						; NZ
				ret
uc0:			DB		0
uc1:			DB		0
uy0:			DB		0
uy1:			DB		0

; ---- после замещения: нули там, где была старая рамка и нет новой (3 плоскости) ----
zero_leftover:	ld		hl, (ou_obj)
				ld		de, OB_C0
				add		hl, de
				ld		a, (hl)
				ld		(zl_c), a
				inc		hl
				ld		a, (hl)
				ld		(zl_c1), a
				inc		hl
				ld		a, (hl)
				ld		(zl_y0), a
				inc		hl
				ld		a, (hl)
				ld		(zl_y1), a
zl_col:			ld		a, (zl_c)
				ld		c, a
				ld		a, (nb_c0)				; столбец вне новой рамки — весь старый
				dec		a
				cp		c
				jp		nc, zl_all
				ld		a, (nb_c1)
				cp		c
				jp		c, zl_all
				; в новой рамке: старые строки выше nb_y0 и ниже nb_y1
				ld		a, (zl_y0)
				ld		d, a
				ld		a, (nb_y0)
				dec		a
				ld		e, a
				call	zero_rows				; zl_y0 .. nb_y0-1
				ld		a, (nb_y1)
				inc		a
				ld		d, a
				ld		a, (zl_y1)
				ld		e, a
				call	zero_rows				; nb_y1+1 .. zl_y1
				jp		zl_next
zl_all:			ld		a, (zl_y0)
				ld		d, a
				ld		a, (zl_y1)
				ld		e, a
				call	zero_rows
zl_next:		ld		a, (zl_c1)
				ld		b, a
				ld		a, (zl_c)
				cp		b
				jp		z, zl_done
				inc		a
				ld		(zl_c), a
				jp		zl_col
zl_done:		ret
; столбец zl_c, строки y = D .. E (если D <= E), 3 плоскости
zero_rows:		ld		a, e
				cp		d
				ret		c
				sub		d
				inc		a
				ld		b, a					; строк
				ld		a, d
				cpl
				add		a, ROW0 + 1
				ld		l, a					; строка памяти верха
				ld		a, (zl_c)
				add		a, 0x80
				ld		h, a
				ld		c, 3
zr_pl:			push	hl
				push	bc
				xor		a
zr_l:			ld		(hl), a
				dec		l
				dec		b
				jp		nz, zr_l
				pop		bc
				pop		hl
				ld		a, h
				add		a, 0x20
				ld		h, a
				dec		c
				jp		nz, zr_pl
				ret
zl_c:			DB		0
zl_c1:			DB		0
zl_y0:			DB		0
zl_y1:			DB		0

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
