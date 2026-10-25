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
O_FN			equ		19					; код объекта (do_N)
OSZ				equ		21

	MACRO OBJ x, y, dx, dy, anim, tr, tl, fn
				DB		x, y, dx, dy, 16, 68, 32, 124, anim
				DW		tr, tl, 0
				DB		0, 0, 0, 0
				DW		fn
	ENDM
objs:			OBJ		40, 100, 1, 2, 0, t_knight_r, t_knight_l, do_0
				OBJ		20, 40, 2, 4, 3, t_axe, t_axe, do_1
				OBJ		60, 50, -1, 2, 5, t_ghost, t_ghost, do_2
				OBJ		30, 110, 1, -2, 9, t_bat, t_bat, do_3
				OBJ		50, 80, -1, -2, 13, t_witch, t_witch, do_4
				OBJ		64, 120, 1, 2, 17, t_pumpkin, t_pumpkin, do_5

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
	IFDEF OVR
				; фон 0x8000..0xDFFF -> квазидиск по тем же адресам (восстановление при стирании)
				ld		hl, 0xE000 - 1
				ld		sp, 0xE000
cp_bg:			ld		d, (hl)
				dec		hl
				ld		e, (hl)
				dec		hl
				push	de
				ld		a, h
				cp		0x7F
				jp		nz, cp_bg
	ENDIF
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

; ---- один объект: стереть, сдвинуть, нарисовать. Код на каждый объект (адреса полей — константы,
;      без копии в рабочую область); вызов — do_obj по o_ptr через поле O_FN ----
	MACRO DOOBJ ob
				; стереть прежнее положение
				ld		a, (ob + O_DRAWN)
				or		a
				jp		z, .no_erase
				ld		a, (ob + O_ODD)
				ld		d, a
				ld		a, (ob + O_OE)
				ld		e, a
				ld		hl, (ob + O_OD)
	IFDEF OVR
				call	ovr_erase
	ELSE
				call	blit
	ENDIF
.no_erase:		; движение по x с отражением
				ld		a, (ob + O_DX)
				ld		hl, ob + O_X
				add		a, (hl)
				ld		(hl), a
				ld		hl, ob + O_XMIN
				cp		(hl)
				jp		c, .bounce_x
				ld		hl, ob + O_XMAX
				cp		(hl)
				jp		c, .move_y
.bounce_x:		ld		a, (ob + O_DX)
				cpl
				inc		a
				ld		(ob + O_DX), a
				ld		hl, ob + O_X
				add		a, (hl)				; шаг назад: x = x - dx_старый
				ld		(hl), a
.move_y:			ld		a, (ob + O_DY)
				ld		hl, ob + O_Y
				add		a, (hl)
				ld		(hl), a
				ld		hl, ob + O_YMIN
				cp		(hl)
				jp		c, .bounce_y
				ld		hl, ob + O_YMAX
				cp		(hl)
				jp		c, .anim
.bounce_y:		ld		a, (ob + O_DY)
				cpl
				inc		a
				ld		(ob + O_DY), a
				ld		hl, ob + O_Y
				add		a, (hl)
				ld		(hl), a
.anim:			; шаг анимации = (счётчик / 4) mod 8, таблица по знаку dx
				ld		hl, ob + O_ANIM
				inc		(hl)
				ld		a, (hl)
	IFDEF PIX1
				add		a, a
				add		a, a
				and		0x70				; шаг*16 (запись таблицы — 8 фаз по 2 байта)
				ld		c, a
				ld		a, (ob + O_X)
				and		7
	ELSE
				add		a, a
				and		0x38				; шаг*8 (запись таблицы — 4 фазы по 2 байта)
				ld		c, a
				ld		a, (ob + O_X)
				and		3
	ENDIF
				add		a, a
				add		a, c
				ld		c, a
				ld		b, 0
				ld		a, (ob + O_DX)
				or		a
				ld		hl, (ob + O_TR)
				jp		p, .anim_r
				ld		hl, (ob + O_TL)
.anim_r:			add		hl, bc
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ld		(ob + O_OD), hl
				ld		a, (ob + O_X)
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
				ld		(ob + O_ODD), a
				ld		d, a
				ld		a, (ob + O_Y)
				cpl
				add		a, ROW0 + 1			; ROW0 - y
				ld		(ob + O_OE), a
				ld		e, a
	IFDEF OVR
				call	ovr_draw
	ELSE
				call	blit
	ENDIF
				ld		a, 1
				ld		(ob + O_DRAWN), a
				ret
	ENDM
do_obj:			ld		hl, (o_ptr)
				ld		de, O_FN
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				jp		(hl)
do_0:			DOOBJ objs + 0*OSZ
do_1:			DOOBJ objs + 1*OSZ
do_2:			DOOBJ objs + 2*OSZ
do_3:			DOOBJ objs + 3*OSZ
do_4:			DOOBJ objs + 4*OSZ
do_5:			DOOBJ objs + 5*OSZ

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
	IFDEF OVR
				call	ovr_erase
	ELSE
				call	blit
	ENDIF
ec_next:		ld		hl, o_cnt
				dec		(hl)
				jp		nz, ec_loop
				ld		a, 0xEC
				ld		(vt_frames + 1), a	; признак «стёрто»
				jp		$
	ENDIF
				jp		tick


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

	IFDEF OVR
; ---- запись без XOR (tools/mkovr.py). Дескриптор: DW квазидиск, вход рисования, вход нулей, вход
;      восстановления; DB сдвиг строки, высота, столбцов, данных N, смещения.., нулей M, смещения..
;      Смещение = столбец + 0x20*плоскость. HL = дескриптор, D = 0x80 + столбец, E = строка памяти ----
; разбор заголовка: HL = дескриптор, D = 0x80 + столбец, E = строка памяти. Вписывает в код столбец,
; верх, указатель карты фона; возвращает DE = список блоков данных, HL = входы (с вход нулей)
ovr_hdr:		ld		a, d
				ld		(dr_col + 1), a
				ld		(zd_col + 1), a
				ld		(ze_col + 1), a
				ld		(er_c), a
				sub		0x80
				ld		(hd_c0 + 1), a
				push	hl
				ld		bc, 8
				add		hl, bc
				ld		a, e
				sub		(hl)				; верх рамки
				inc		hl
				ld		(dr_top + 1), a
				inc		a
				ld		(zd_top + 1), a
				ld		(ze_top + 1), a
				sub		(hl)				; верх + 1 - высота = низ
				inc		hl
				ld		(er_bot + 1), a
				ld		c, (hl)				; столбцов
				inc		hl
				ld		a, c
				ld		(er_n), a
				ex		de, hl				; DE = список данных
				ld		a, (er_bot + 1)
				and		0xF8
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl				; группа*32
hd_c0:			ld		a, 0
				add		a, l
				ld		l, a				; + столбец (в пределах 32-байтного блока)
				ld		bc, bgf
				add		hl, bc
				ld		(er_f), hl
				ld		a, l
				ld		(zd_fl + 1), a
				ld		(ze_fl + 1), a
				ld		a, h
				ld		(zd_fh + 1), a
				ld		(ze_fh + 1), a
				pop		hl
				ret

ovr_draw:		call	ovr_hdr
				ld		c, (hl)
				inc		hl
				ld		b, (hl)				; BC = данные в квазидиске
				inc		hl
				ld		a, (hl)
				inc		hl
				ld		(dr_jp + 1), a
				ld		a, (hl)
				inc		hl
				ld		(dr_jp + 2), a
				ld		a, (hl)
				inc		hl
				ld		(zd_jp + 1), a
				ld		a, (hl)
				ld		(zd_jp + 2), a
				ld		hl, zd_next
				ld		(zr_ret + 1), hl
				ld		hl, 0
				add		hl, sp
				ld		(od_ssp), hl
				ld		h, b
				ld		l, c
				ld		a, 0x10
				out		(0x10), a
				ld		sp, hl
				; проход 1: блоки данных
dr_next:		ld		a, (de)
				inc		de
				or		a
				jp		m, dr_end
dr_col:			add		a, 0
				ld		h, a
dr_top:			ld		l, 0
dr_jp:			jp		0
dr_body:
				DUP		MAXPAIRS
				pop		bc
				ld		(hl), c
				dec		l
				ld		(hl), b
				dec		l
				EDUP
				jp		dr_next
dr_end:			xor		a
				out		(0x10), a
				; проход 2: нули в блоках без данных — только где под рамкой фон
				ld		bc, 0
zd_next:		ld		a, (de)
				inc		de
				or		a
				jp		m, od_done
				and		0x1F
zd_fl:			add		a, 0
				ld		l, a
zd_fh:			ld		h, 0
				ld		a, (hl)
				or		a
				jp		z, zd_next
				dec		de
				ld		a, (de)
				inc		de
zd_col:			add		a, 0
				ld		h, a
zd_top:			ld		l, 0
				ld		sp, hl
zd_jp:			jp		0
zr_body:
				DUP		MAXPAIRS
				push	bc
				EDUP
zr_ret:			jp		0
od_done:		ld		hl, (od_ssp)
				ld		sp, hl
				ret

; стирание: проход 1 — нули в блоках данных столбцов на чёрном полу; проход 2 — столбцы над фоном:
; копия фона из квазидиска во все 3 плоскости
ovr_erase:		call	ovr_hdr
				inc		hl
				inc		hl
				inc		hl
				inc		hl
				ld		a, (hl)
				inc		hl
				ld		(ze_jp + 1), a
				ld		a, (hl)
				inc		hl
				ld		(ze_jp + 2), a
				ld		a, (hl)
				inc		hl
				ld		(rs_jp + 1), a
				ld		a, (hl)
				ld		(rs_jp + 2), a
				ld		hl, ze_next
				ld		(zr_ret + 1), hl
				ld		hl, 0
				add		hl, sp
				ld		(od_ssp), hl
				ld		bc, 0
ze_next:		ld		a, (de)
				inc		de
				or		a
				jp		m, er_go
				and		0x1F
ze_fl:			add		a, 0
				ld		l, a
ze_fh:			ld		h, 0
				ld		a, (hl)
				or		a
				jp		nz, ze_next
				dec		de
				ld		a, (de)
				inc		de
ze_col:			add		a, 0
				ld		h, a
ze_top:			ld		l, 0
				ld		sp, hl
ze_jp:			jp		0
er_go:			ld		hl, (er_f)
er_loop:		ld		a, (hl)
				inc		hl
				or		a
				jp		z, er_skip
				ld		(er_f), hl
				ld		a, 3
				ld		(er_k), a
				ld		a, 0x10
				out		(0x10), a
				ld		a, (er_c)
				ld		h, a
er_bot:			ld		l, 0
er_pl:			ld		(er_hl), hl
				ld		sp, hl
rs_jp:			jp		0
rs_body:
				DUP		MAXPAIRS
				pop		bc
				ld		(hl), c
				inc		l
				ld		(hl), b
				inc		l
				EDUP
				ld		hl, (er_hl)
				ld		a, h
				add		a, 0x20
				ld		h, a
				ld		a, (er_k)
				dec		a
				ld		(er_k), a
				jp		nz, er_pl
				xor		a
				out		(0x10), a
				ld		hl, (er_f)
er_skip:		ld		a, (er_c)
				inc		a
				ld		(er_c), a
				ld		a, (er_n)
				dec		a
				ld		(er_n), a
				jp		nz, er_loop
				jp		od_done
DR_PAIR			equ		5
RS_PAIR			equ		5
od_ssp:			DW		0
er_f:			DW		0
er_hl:			DW		0
er_c:			DB		0
er_n:			DB		0
er_k:			DB		0
				ALIGN	256
bgf:			INCBIN	"../build/proto/bgf.bin"
	ENDIF
				INCLUDE	"../build/proto/spr_desc.inc"
code_end:
				ASSERT	code_end <= STACK - 0x100

				ORG		KVAZ0
				INCBIN	"../build/proto/spr.bin"
				ORG		0x8000
				INCBIN	"../build/proto/bg.bin"
				SAVEBIN	"../build/proto/proto.r0m", 0, 0x10000
