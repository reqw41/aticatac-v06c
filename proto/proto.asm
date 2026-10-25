; Прототип вывода Atic Atac (CPC) на Векторе-06Ц: фон комнаты 0 (снимок CPC), 6 спрайтов XOR в 4 плоскостях,
; графика читается POP из квазидиска (стековый режим, страница 0). Логики игры нет: объекты летают
; и отражаются от стен комнаты. Замер — stand/vec/run.js по счётчику тиков vt_ticks.
;   tools/sjasmplus --i8080 proto/proto.asm   (данные — tools/mkproto.py в build/proto)
				DEVICE	NOSLOT64K
				INCLUDE	"../build/proto/spr.inc"

NOBJ			equ		6
STACK			equ		KVAZ0				; стек ниже данных спрайтов

				ORG		0x0000
				di
				jp		start

				ORG		0x0038
; ISR: палитра 16 записей (в обратном ходе луча) и счётчик кадров. Работает только при загрузке:
; во время замера прерывания запрещены (стековый режим квазидиска перехватывает и стек ISR).
isr:			push	af
				push	bc
				push	hl
				ld		hl, pal_data + 15
				ld		c, 15
isr_pal:		ld		a, c
				out		(0x02), a
				ld		a, (hl)
				dec		hl
				out		(0x0C), a
				out		(0x0C), a
				out		(0x0C), a
				out		(0x0C), a
				dec		c
				jp		p, isr_pal
				xor		a
				out		(0x02), a
				ld		hl, (vt_frames)
				inc		hl
				ld		(vt_frames), hl
				pop		hl
				pop		bc
				pop		af
				ei
				ret

				ORG		0x0080
vt_ticks:		DW		0					; тиков (все объекты стёрты и нарисованы заново) — читает стенд
vt_frames:		DW		0
vt_spin:		DB		0					; сколько раз планировщик ждал луч (mod 256)
				INCLUDE	"../build/proto/pal.inc"

; ---- объекты: x (пиксель CPC 0..127), y (строка CPC 0..191), dx, dy, границы, счётчик анимации,
;      таблицы вида вправо/влево, что нарисовано (дескриптор, D, E), флаг ----
O_X				equ		0
O_Y				equ		1
O_DX			equ		2
O_DY			equ		3
O_XMIN			equ		4
O_XMAX			equ		5
O_YMIN			equ		6
O_YMAX			equ		7
O_ANIM			equ		8
O_TR			equ		9
O_TL			equ		11
O_OD			equ		13
O_ODD			equ		15
O_OE			equ		16
O_DRAWN			equ		17
O_PEND			equ		18					; 1 = объект ещё не обработан в этом тике (планировщик BEAM)
OSZ				equ		19

	MACRO OBJ x, y, dx, dy, anim, tr, tl
				DB		x, y, dx, dy, 16, 68, 32, 124, anim
				DW		tr, tl, 0
				DB		0, 0, 0, 0
	ENDM
objs:			OBJ		40, 100, 1, 2, 0, t_knight_r, t_knight_l
				OBJ		20, 40, 2, 4, 3, t_axe, t_axe
				OBJ		60, 50, -1, 2, 5, t_ghost, t_ghost
				OBJ		30, 110, 1, -2, 9, t_bat, t_bat
				OBJ		50, 80, -1, -2, 13, t_witch, t_witch
				OBJ		64, 120, 1, 2, 17, t_pumpkin, t_pumpkin

; рабочая копия текущего объекта
o_cur:			DS		OSZ
o_ptr:			DW		0
o_cnt:			DB		0

start:			ld		sp, STACK
				ld		a, 0x88
				out		(0x00), a
				xor		a
				out		(0x02), a
				ld		a, 0xFF
				out		(0x03), a
				; спрайты из ОЗУ [KVAZ0, KVAZ_END) -> квазидиск, страница 0, те же адреса (PUSH сверху вниз)
				ld		hl, KVAZ_END - 1
				ld		a, 0x10
				out		(0x10), a
				ld		sp, KVAZ_END
cp_kv:			ld		d, (hl)
				dec		hl
				ld		e, (hl)
				dec		hl
				push	de
				ld		a, l
				cp		low (KVAZ0 - 1)
				jp		nz, cp_kv
				ld		a, h
				cp		high (KVAZ0 - 1)
				jp		nz, cp_kv
				xor		a
				out		(0x10), a
				ld		sp, STACK
				; ОЗУ-копию обнулить: выводу остаётся только квазидиск
				ld		hl, KVAZ0
clr:			ld		(hl), 0
				inc		hl
				ld		a, h
				cp		(high KVAZ_END) + 1
				jp		nz, clr
				; палитру грузит ISR в обратном ходе
				ei
				halt
				halt
				halt
				di
	IFDEF BEAM
				; ВИ53 счётчик 0: режим 2, делитель 29952 = ровно кадр (1.5 МГц). Запуск сразу после ISR,
				; дальше прерывания не нужны: положение луча = фаза счётчика (см. beam)
				ld		a, 0x34
				out		(0x08), a
				xor		a
				out		(0x0B), a
				ld		a, high 29952
				out		(0x0B), a
	ENDIF

	IFDEF BEAM
; ---- тик с планировщиком по лучу: объект берётся, только если луч не зайдёт в его строки,
;      пока он стирается и рисуется (WIN_U), и не находится в них сейчас (HU) ----
tick:			ld		hl, objs + O_PEND
				ld		de, OSZ
				ld		c, NOBJ
tk_pend:		ld		(hl), 1
				add		hl, de
				dec		c
				jp		nz, tk_pend
				ld		a, NOBJ
				ld		(sc_left), a
sched:			call	beam
				ld		(sc_u), a
				ld		hl, objs
				ld		(sc_p), hl
				ld		a, NOBJ
				ld		(sc_cnt), a
sc_l:			ld		hl, (sc_p)
				ld		de, O_PEND
				add		hl, de
				ld		a, (hl)
				or		a
				jp		z, sc_next
				ld		hl, (sc_p)
				inc		hl					; O_Y
				ld		e, (hl)
				ld		d, 0
				ld		hl, yu_tab
				add		hl, de
				ld		a, (sc_u)
				sub		(hl)				; k = (луч - верх) mod кадр
				jp		nc, sc_k
				add		a, FRAME_U
sc_k:			cp		HU + 1
				jp		c, sc_next			; луч внутри строк объекта
				cp		FRAME_U - WIN_U
				jp		nc, sc_next			; луч дойдёт до объекта раньше, чем он будет готов
				ld		hl, (sc_p)
				ld		(o_ptr), hl
				ld		de, O_PEND
				add		hl, de
				ld		(hl), 0
				call	do_obj
				ld		hl, sc_left
				dec		(hl)
				jp		nz, sched
				jp		tick_done
sc_next:		ld		hl, (sc_p)
				ld		de, OSZ
				add		hl, de
				ld		(sc_p), hl
				ld		hl, sc_cnt
				dec		(hl)
				jp		nz, sc_l
				ld		hl, vt_spin			; ни один объект сейчас нельзя — ждём луч
				inc		(hl)
				jp		sched

; положение луча в единицах U = 128 тиков ВИ53 = 4/3 строки, 0..FRAME_U-1, 0 = прерывание кадра
beam:			xor		a
				out		(0x08), a			; защёлкнуть счётчик 0
				in		a, (0x0B)
				ld		l, a
				in		a, (0x0B)
				ld		h, a
				xor		a
				sub		l
				ld		e, a
				ld		a, high 29952
				sbc		a, h				; DE = 29952 - счётчик = тиков с начала периода
				ld		d, a
				ld		a, e
				rla
				ld		a, d
				rla							; A = DE >> 7
				add		a, OFS_U
				cp		FRAME_U
				ret		c
				sub		FRAME_U
				ret
FRAME_U			equ		234					; 29952 / 128
	IFNDEF OFS_U
OFS_U			equ		0					; луч в момент запуска счётчика (после ISR палитры); перебор 0/4/8 — разница в пределах шума
	ENDIF
	IFNDEF HU
HU				equ		24					; высота окна объекта: 32 строки (24 спрайт + 2x4 движение) * 3/4
	ENDIF
	IFNDEF WIN_U
WIN_U			equ		90					; длительность обработки объекта с запасом (~23 тыс. тактов)
	ENDIF
; строка луча (U) верхнего края окна объекта по y CPC: экранная строка 32+y-4, строка луча +40
yu_tab:
				DUP		256, yy
				DB		((68 + yy) * 3 / 4) % FRAME_U
				EDUP
sc_p:			DW		0
sc_cnt:			DB		0
sc_left:		DB		0
sc_u:			DB		0
	ELSE
tick:			ld		hl, objs
				ld		(o_ptr), hl
				ld		a, NOBJ
				ld		(o_cnt), a
tk_l:			call	do_obj
				ld		hl, (o_ptr)
				ld		de, OSZ
				add		hl, de
				ld		(o_ptr), hl
				ld		hl, o_cnt
				dec		(hl)
				jp		nz, tk_l
				jp		tick_done
	ENDIF

; ---- один объект: стереть, сдвинуть, нарисовать (объект по адресу o_ptr) ----
do_obj:			ld		hl, (o_ptr)
				ld		de, o_cur
				call	copy_obj
				; стереть прежнее положение
				ld		a, (o_cur + O_DRAWN)
				or		a
				jp		z, no_erase
				ld		a, (o_cur + O_ODD)
				ld		d, a
				ld		a, (o_cur + O_OE)
				ld		e, a
				ld		hl, (o_cur + O_OD)
				call	blit
no_erase:		; движение по x с отражением
				ld		a, (o_cur + O_DX)
				ld		hl, o_cur + O_X
				add		a, (hl)
				ld		(hl), a
				ld		hl, o_cur + O_XMIN
				cp		(hl)
				jp		c, bounce_x
				ld		hl, o_cur + O_XMAX
				cp		(hl)
				jp		c, move_y
bounce_x:		ld		a, (o_cur + O_DX)
				cpl
				inc		a
				ld		(o_cur + O_DX), a
				ld		hl, o_cur + O_X
				add		a, (hl)				; шаг назад: x = x - dx_старый
				ld		(hl), a
move_y:			ld		a, (o_cur + O_DY)
				ld		hl, o_cur + O_Y
				add		a, (hl)
				ld		(hl), a
				ld		hl, o_cur + O_YMIN
				cp		(hl)
				jp		c, bounce_y
				ld		hl, o_cur + O_YMAX
				cp		(hl)
				jp		c, anim
bounce_y:		ld		a, (o_cur + O_DY)
				cpl
				inc		a
				ld		(o_cur + O_DY), a
				ld		hl, o_cur + O_Y
				add		a, (hl)
				ld		(hl), a
anim:			; шаг анимации = (счётчик / 4) mod 8, таблица по знаку dx
				ld		hl, o_cur + O_ANIM
				inc		(hl)
				ld		a, (hl)
	IFDEF PIX1
				add		a, a
				add		a, a
				and		0x70				; шаг*16 (запись таблицы — 8 фаз по 2 байта)
				ld		c, a
				ld		a, (o_cur + O_X)
				and		7
	ELSE
				add		a, a
				and		0x38				; шаг*8 (запись таблицы — 4 фазы по 2 байта)
				ld		c, a
				ld		a, (o_cur + O_X)
				and		3
	ENDIF
				add		a, a
				add		a, c
				ld		c, a
				ld		b, 0
				ld		a, (o_cur + O_DX)
				or		a
				ld		hl, (o_cur + O_TR)
				jp		p, anim_r
				ld		hl, (o_cur + O_TL)
anim_r:			add		hl, bc
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ld		(o_cur + O_OD), hl
				ld		a, (o_cur + O_X)
				rrca
				rrca
	IFDEF PIX1
				rrca
				and		0x1F
				add		a, 0x88				; пиксель CPC = точка: картинка 128 точек со столбца 8
	ELSE
				and		0x3F
				add		a, 0x80
	ENDIF
				ld		(o_cur + O_ODD), a
				ld		d, a
				ld		a, (o_cur + O_Y)
				cpl
				add		a, ROW0 + 1			; ROW0 - y
				ld		(o_cur + O_OE), a
				ld		e, a
				call	blit
				ld		a, 1
				ld		(o_cur + O_DRAWN), a
				; вернуть объект
				ld		hl, (o_ptr)
				ex		de, hl
				ld		hl, o_cur
				jp		copy_obj

tick_done:		ld		hl, (vt_ticks)
				inc		hl
				ld		(vt_ticks), hl
	IFDEF ERASECHK
				ld		a, h				; проверка XOR: после 200 тиков стереть всё и встать — экран = фон
				or		a
				jp		nz, tick
				ld		a, l
				cp		200
				jp		nz, tick
				ld		hl, objs
				ld		(o_ptr), hl
				ld		a, NOBJ
				ld		(o_cnt), a
ec_loop:		ld		hl, (o_ptr)
				ld		de, OSZ
				add		hl, de
				ld		(o_ptr), hl
				ld		de, O_DRAWN - OSZ
				add		hl, de
				ld		a, (hl)
				or		a
				jp		z, ec_next
				ld		de, O_OD - O_DRAWN
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				push	de
				ld		d, (hl)				; O_ODD
				inc		hl
				ld		e, (hl)				; O_OE
				pop		hl
				call	blit
ec_next:		ld		hl, o_cnt
				dec		(hl)
				jp		nz, ec_loop
				ld		a, 0xEC
				ld		(vt_frames + 1), a	; признак «стёрто»
				jp		$
	ENDIF
				jp		tick

copy_obj:		ld		c, OSZ				; HL -> DE, OSZ байт
co_l:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, co_l
				ret

; ---- blit: XOR спрайта из квазидиска. HL = дескриптор, D = 0x80 + столбец, E = строка памяти верха ----
; Портит всё. Прерывания должны быть запрещены (стековый режим).
blit:			ld		c, (hl)
				inc		hl
				ld		b, (hl)
				inc		hl
				ld		a, c
				ld		(bl_sp + 1), a
				ld		a, b
				ld		(bl_sp + 2), a
				ld		a, (hl)
				inc		hl
				ld		(bl_jp + 1), a
				ld		a, (hl)
				inc		hl
				ld		(bl_jp + 2), a
				ld		a, e
				sub		(hl)				; строка - сдвиг пустых строк сверху
				inc		hl
				ld		(bl_row + 1), a
				ld		a, (hl)
				inc		hl
				or		a
				ret		z
				ld		(bl_cnt), a
				ld		(bl_desc), hl
				ld		a, d
				ld		(bl_base + 1), a
				ld		hl, 0
				add		hl, sp
				ld		(bl_ssp), hl
				ld		a, 0x10
				out		(0x10), a
bl_sp:			ld		sp, 0
bl_next:		ld		hl, (bl_desc)
				ld		a, (hl)
				inc		hl
				ld		(bl_desc), hl
bl_base:		add		a, 0
				ld		h, a
bl_row:			ld		l, 0
bl_jp:			jp		0
bl_body:
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
				ld		hl, bl_cnt
				dec		(hl)
				jp		nz, bl_next
				xor		a
				out		(0x10), a
				ld		hl, (bl_ssp)
				ld		sp, hl
				ret
BL_PAIR			equ		9
bl_cnt:			DB		0
bl_desc:		DW		0
bl_ssp:			DW		0

				INCLUDE	"../build/proto/spr_desc.inc"
code_end:
				ASSERT	code_end <= STACK - 0x100

				ORG		KVAZ0
				INCBIN	"../build/proto/spr.bin"
				ORG		0x8000
				INCBIN	"../build/proto/bg.bin"
				SAVEBIN	"../build/proto/proto.r0m", 0, 0x10000
