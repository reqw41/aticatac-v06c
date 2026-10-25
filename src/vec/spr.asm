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
OB_LATE			equ		16					; отложен бюджетом кадра — в следующем кадре обязателен
OBSZ			equ		32
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
				ld		de, 15					; стоимость этого изображения (запись + 15 + фаза, по 64 такта)
				add		hl, de
				ld		e, c
				ld		d, 0
				add		hl, de
				ld		a, (hl)
				rrca
				rrca
				rrca
				and		0x1f
				add		a, 3					; + запас (в замещении — нули)
	IFDEF OLDBC
				ld		a, BLIT_COST
	ENDIF
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
				ld		a, (bx_mode)
				or		a
				jp		nz, bl_ov
				ld		a, c
				add		a, a
				add		a, a
				add		a, a
				add		a, c					; * 9 (BX_PAIR)
				add		a, low bx_body
				ld		(bx_jp + 1), a
				ld		a, 0
				adc		a, high bx_body
				jp		bl_e
bl_ov:			ld		a, c
				add		a, a
				add		a, a
				add		a, c					; * 5 (BO_PAIR)
				add		a, low bo_body
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
				dec		l
				ld		(hl), b
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
				ld		a, (bx_h)
				call	zf_entry
				ld		(bx_zc + 1), hl
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
				xor		a
bx_zc:			call	0
				jp		bx_z
bx_ret:			ei
				ret
; нули вниз от HL (A = 0): вход zf_entry(A = строк, до 24) -> HL; портит A, C
zf_entry:		add		a, a
				ld		c, a
				ld		hl, zf_end
				ld		a, l
				sub		c
				ld		l, a
				ld		a, h
				sbc		a, 0
				ld		h, a
				ret
zf_body:
				DUP		24
				ld		(hl), a
				dec		l
				EDUP
zf_end:			ret
BX_PAIR			equ		9
BO_PAIR			equ		5
				ASSERT	bo_body - bx_body == MAXPAIRS * BX_PAIR + 3
				ASSERT	bx_nd - bo_body == MAXPAIRS * BO_PAIR + 3
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
	IFNDEF BEAM_PAD
BEAM_PAD		equ		12						; запас к оценке стоимости объекта, старшие байты счётчика (перебор: 4 — 17,9 % переполнений кадра, 8 — 8,1 %, 12 — 1,9 %)
	ENDIF
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
				call	obj_window				; A = 0 — не менялся, иначе B = верх, C = низ, ow_cost, nb_*
				pop		de
				or		a
				jp		z, rw_st
				pop		hl						; отложен в прошлом кадре — флаг 2 (первым в очереди)
				push	hl
				push	de
				ld		de, OB_LATE
				add		hl, de
				ld		a, (hl)
				pop		de
				inc		a
rw_st:			ld		(de), a
				inc		de
				ld		a, b
				ld		(de), a
				inc		de
				ld		a, c
				ld		(de), a
				inc		de
				ld		a, (ow_cost)
				ld		(de), a
				inc		de
				ld		hl, nb_c0
				ld		c, 4
rw_nb:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, rw_nb
				pop		hl
				ld		bc, OBSZ
				add		hl, bc
				pop		bc
				dec		b
				jp		nz, rw_l
				ld		a, (frames)				; кадр начала вывода
				ld		(rs_frm), a
; выбор следующего: из ждущих — обгоняющий луч (луч + стоимость < верха окна) с самым ранним сроком начала,
; иначе уже пройденный лучом; никого — шаг логики или ждать луч
rs_pass:		call	beam_hi
				ld		(rs_beam), a
				ld		b, a					; B = луч
				ld		a, 0xff
				ld		(rs_bt), a				; ключ лучшего: верх окна, пройденный — 0xFE, нет — 0xFF
				xor		a
				ld		(rs_left), a
				ld		hl, rs_win
				ld		c, NOBJ
rq_l:			ld		a, (hl)
				or		a
				jp		z, rq_next
				ld		(rs_left), a
				ld		(rs_fl), a
				push	hl
				inc		hl
				ld		e, (hl)					; верх
				inc		hl
				ld		a, (hl)					; низ
				ld		(rs_bot), a
				cp		b
				jp		c, rq_pass				; луч уже прошёл
				inc		hl
				ld		a, (hl)					; стоимость
				ld		d, a
				add		a, b
				jp		c, rq_pop
				cp		e
				jp		nc, rq_pop				; не обгонит
	IFDEF RS_LOW
				ld		a, (rs_bot)				; ниже на экране — раньше (его ждать дольше)
				cpl
	ELSE
				ld		a, e
				sub		d
	ENDIF
				ld		e, a					; срок начала: верх - стоимость (меньше — срочнее)
				ld		a, (rs_fl)
				cp		2
				jp		nz, rq_cmp
				ld		a, e					; отложенный — раньше
				sub		64
				jp		nc, rq_d
				ld		a, 1
rq_d:			ld		e, a
rq_cmp:			ld		a, (rs_bt)
				cp		e
				jp		c, rq_pop
				jp		z, rq_pop
				ld		a, e
rq_take:		ld		(rs_bt), a
				pop		hl
				ld		(rs_best), hl
				jp		rq_next
rq_pass:		ld		a, (rs_fl)				; пройденный лучом: 0xFE, отложенный — 0xFD
				cp		2
				ld		a, 0xfd
				jp		z, rq_pk
				ld		a, 0xfe
rq_pk:			ld		e, a
				ld		a, (rs_bt)
				cp		e
				jp		c, rq_pop
				jp		z, rq_pop
				ld		a, e
				jp		rq_take
rq_pop:			pop		hl
rq_next:		ld		de, RSW
				add		hl, de
				dec		c
				jp		nz, rq_l
				ld		a, (rs_bt)
				cp		0xff
				jp		z, rs_none
rq_sel:			ld		hl, (rs_best)			; объект = objs + (окно - rs_win) * OBSZ / RSW
				ld		de, 0 - rs_win
				add		hl, de
				add		hl, hl
				add		hl, hl
				ld		de, objs
				add		hl, de
				ex		de, hl
				ld		hl, (rs_best)
				ex		de, hl					; HL = объект, DE = окно
				push	hl
				push	de
				call	rs_budget
				pop		de
				pop		hl
				ld		a, 0
				ld		(de), a					; окно обработано
				ld		bc, OB_LATE
				jp		c, rs_go
rs_defer:		push	hl						; не укладывается в кадр — в следующем кадре
				add		hl, bc
				ld		(hl), 1
				pop		hl
				jp		rs_pass
rs_go:			push	hl
				add		hl, bc
				ld		(hl), a
				pop		hl
				ld		(ou_obj), hl
				ex		de, hl
				ld		(ou_win), hl
				ex		de, hl
				call	obj_update
				jp		rs_pass
rs_none:		ld		a, (rs_left)
				or		a
				ret		z
				call	logic_pend				; ждём луч — пока шаг логики (состояние объектов уже снято)
				jp		nz, rs_pass
	IFNDEF NOFORCE
				ld		hl, rs_win				; герой или оружие: ожидание луча переполнит кадр —
				call	rs_force				; рисовать сейчас (шов в одном кадре лучше потерянного кадра)
				jp		c, rq_sel
				ld		hl, rs_win + RSW
				call	rs_force
				jp		c, rq_sel
	ENDIF
	IFNDEF NORN
				ld		hl, rs_win + 2 * RSW	; остальные: ожидание луча переполнит кадр — в следующий кадр
				ld		b, NOBJ - 2
rn_l:			push	bc
				push	hl
				call	rs_force
				pop		hl
				jp		nc, rn_n
				ld		(hl), 0
				push	hl
				ld		de, 0 - rs_win			; объект = objs + (окно - rs_win) * 4
				add		hl, de
				add		hl, hl
				add		hl, hl
				ld		de, objs + OB_LATE
				add		hl, de
				ld		(hl), 1
				pop		hl
rn_n:			ld		de, RSW
				add		hl, de
				pop		bc
				dec		b
				jp		nz, rn_l
	ENDIF
				ld		a, (frames)				; ждём луч; кадр уже сменился — выводим как есть
				ld		hl, rs_frm
				cp		(hl)
				jp		z, rs_pass
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
				add		hl, hl
				add		hl, hl					; * OBSZ (32)
				ld		de, objs
				add		hl, de
				ld		(ou_obj), hl
				pop		bc
				pop		hl
				push	hl
				push	bc
				ld		(ou_win), hl
				ld		hl, (ou_obj)			; obj_update: HL = объект
				call	obj_update
				pop		bc
				pop		hl
rs_f1:			ld		de, RSW
				add		hl, de
				dec		b
				jp		nz, rs_f
				ret
RSW				equ		8
rs_win:			DS		NOBJ * RSW				; менялся?, верх, низ (старшие байты счётчика), стоимость, nb_c0..nb_y1
ou_win:			DW		0
rs_left:		DB		0
rs_beam:		DB		0
rs_bt:			DB		0
rs_fl:			DB		0
rs_bot:			DB		0
rs_best:		DW		0
				ASSERT	OBSZ == RSW * 4
; бюджет кадра: HL = объект, DE = окно -> C — обновлять сейчас: герой всегда, остальные — если укладываются
; (луч + стоимость + герой, если ещё ждёт, + шаг логики, если ещё не сделан, + панель < конца кадра)
	IFNDEF LOGIC_HI
LOGIC_HI		equ		19						; шаг логики, 99 % — 9,4 тыс. тактов
	ENDIF
	IFNDEF PANEL_HI
PANEL_HI		equ		10						; панель и возврат в цикл
	ENDIF
rs_budget:		ld		a, l					; герой и оружие (HL < objs + 2 * OBSZ) — всегда
				sub		low (objs + 2 * OBSZ)
				ld		a, h
				sbc		a, high (objs + 2 * OBSZ)
	IFDEF OLDWP
				ld		a, l
				cp		low objs
				jp		nz, rb_1
				ld		a, h
				cp		high objs
				jp		z, rb_ok
	ELSE
				jp		c, rb_ok
	ENDIF
rb_1:			inc		de
				inc		de
				inc		de
				ld		a, (rs_beam)
				ld		b, a
				ld		a, (de)
				add		a, b
				jp		c, rb_no
				ld		b, a
				ld		a, (rs_win)				; герой ещё ждёт — его стоимость в запас
				or		a
				jp		z, rb_h
				ld		a, (rs_win + 3)
				add		a, b
				jp		c, rb_no
				ld		b, a
rb_h:			ld		a, (rs_win + RSW)		; оружие — тоже
				or		a
				jp		z, rb_w
				ld		a, (rs_win + RSW + 3)
				add		a, b
				jp		c, rb_no
				ld		b, a
rb_w:			ld		a, (ml_pend)
				or		a
				ld		a, b
				jp		z, rb_2
				add		a, LOGIC_HI
				jp		c, rb_no
rb_2:			add		a, PANEL_HI
				jp		c, rb_no
				cp		FRAME_HI
				ret
rb_ok:			scf
				ret
rb_no:			or		a
				ret
; HL = окно обязательного объекта -> C и rs_best = HL, если ждёт и низ окна + стоимость + панель >= кадра
rs_force:		ld		a, (hl)
				or		a
				ret		z
				ld		(rs_best), hl
				inc		hl
				inc		hl
				ld		a, (hl)					; низ
				inc		hl
				add		a, (hl)					; + стоимость
				ret		c						; перенос — точно не успеть
				add		a, PANEL_HI + FORCE_M
				ret		c
				cp		FRAME_HI
				ccf
				ret
	IFNDEF FORCE_M
FORCE_M			equ		0						; запас: ждать луч только если после него кадр не переполнится с запасом
	ENDIF
rs_frm:			DB		0
ou_obj:			DW		0
				ASSERT	OBSZ == 32

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
ow_done:		call	ow_estimate
				ld		a, (ow_y0)				; строка луча = 72 + y; старшие байты = (72 + y) * 3 / 8
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
; стоимость обновления в старших байтах счётчика: XOR старого (если нарисовано) и нового (если видимо) —
; из записей кадров (байт фазы, единицы по 64 такта, tools/mkgame.py) + обвязка OBJ_FIX, + BEAM_PAD
	IFNDEF OBJ_FIX
OBJ_FIX			equ		28						; обвязка обновления объекта, единицы по 64 такта (~1,8 тыс.)
	ENDIF
ow_estimate:	ld		hl, OBJ_FIX
				ld		(ow_area), hl
				ld		hl, (ow_obj)
				ld		a, (hl)
				or		a
				jp		z, oe_new
				call	oe_add
oe_new:			ld		hl, (ow_obj)
				ld		de, OB_NEW
				add		hl, de
				ld		a, (hl)
				or		a
				call	nz, oe_add
				ld		hl, (ow_area)			; / 8 -> старшие байты
				add		hl, hl
				add		hl, hl
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		a, h
				add		a, BEAM_PAD
				ld		(ow_cost), a
				ret
; HL -> (видим/нарисован, запись, фаза): ow_area += запись[15 + фаза]
oe_add:			inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		a, (hl)
				ex		de, hl
				ld		de, 15
				add		hl, de
				ld		e, a
				ld		d, 0
				add		hl, de
				ld		e, (hl)
				ld		hl, (ow_area)
				add		hl, de
				ld		(ow_area), hl
				ret
ow_area:		DW		0
ow_cost:		DB		0
ow_obj:			DW		0
ow_y0:			DB		0
ow_y1:			DB		0
; положение луча: старший байт прошедших отсчётов счётчика 0 с прерывания кадра
; прошло FRAME_HI и больше — прерывание потеряно: перезарядить счётчик, засчитать кадр (как di_guard)
beam_hi:		di
				xor		a
				out		(0x08), a
				in		a, (0x0B)
				in		a, (0x0B)
				cpl
	IFNDEF OLDBH
				cp		FRAME_HI + 2			; с запасом: прерывание в этот момент ещё может прийти
				jp		nc, bh_lost
	ENDIF
				ei
				ret
bh_lost:		push	hl
				call	dg_lost
				pop		hl
				xor		a
				ei
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
ou_vis:			call	nb_load					; рамка нового -> nb_* (посчитана в obj_window)
				ld		a, (de)
				or		a
				jp		z, ou_newonly			; изменился (иначе obj_update не вызывается)
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
ou_newonly:		ld		hl, (ou_obj)
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

; рамка нового из окна объекта (ou_win + 4) -> nb_*; DE сохраняется
nb_load:		ld		hl, (ou_win)
				ld		bc, 4
				add		hl, bc
				ld		a, (hl)
				ld		(nb_c0), a
				inc		hl
				ld		a, (hl)
				ld		(nb_c1), a
				inc		hl
				ld		a, (hl)
				ld		(nb_y0), a
				inc		hl
				ld		a, (hl)
				ld		(nb_y1), a
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
				ld		a, (uc0)				; bgraw[c * 24 + g]
				ld		c, a
				ld		l, a
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
				ld		(rp_n), a
				ld		a, (uc1)
				sub		c
				inc		a
				ld		c, a					; столбцов
				ld		de, 24
rp_col:			push	hl
				ld		a, (rp_n)
				ld		b, a
				xor		a
rp_g:			or		(hl)
				inc		hl
				dec		b
				jp		nz, rp_g
				pop		hl
				or		a
				jp		nz, rp_no
				add		hl, de
				dec		c
				jp		nz, rp_col
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
rp_n:			DB		0
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
				inc		a						; строк
				push	de
				call	zf_entry
				ld		(zr_c + 1), hl
				pop		de
				ld		a, d
				cpl
				add		a, ROW0 + 1
				ld		l, a					; строка памяти верха
				ld		a, (zl_c)
				add		a, 0x80
				ld		h, a
				ld		c, 3
zr_pl:			push	hl
				xor		a
zr_c:			call	0
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
