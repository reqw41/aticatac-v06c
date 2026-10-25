; Отрисовка комнат Atic Atac (CPC) на Векторе-06Ц: контур линиями и предметы, как draw_room CPC до
; draw_collectables (эталон — tools/roomref.py, сверенный с MAME на всех 143 комнатах).
; Банк комнат CPC лежит как есть с 0x4000 (указатели внутри верны); графика предметов — в квазидиске
; (стр. 1, tools/mkroom.py; на стенде кладётся прямо в память эмулятора). 8 цветов, 3 плоскости.
; Прогон: все комнаты по очереди; после каждой — метка rv_done (стенд снимает экран и такты).
;   tools/sjasmplus --i8080 proto/room.asm   (данные — python3 tools/mkroom.py build/room)
				DEVICE	NOSLOT64K
				INCLUDE	"../build/room/room.inc"

NROOMS			equ		143
STACK			equ		0x4000

				ORG		0x0000
				di
				jp		start

				ORG		0x0038
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
				pop		hl
				pop		bc
				pop		af
				ei
				ret

				ORG		0x0080
rv_room:		DB		0					; номер рисуемой комнаты — читает стенд
				INCLUDE	"../build/room/pal.inc"

start:			ld		sp, STACK
				ld		a, 0x88
				out		(0x00), a
				xor		a
				out		(0x02), a
				ld		a, 0xFF
				out		(0x03), a
				ei
				halt
				halt
				di
				xor		a
rv_loop:		ld		(rv_room), a
				call	draw_room
rv_done:		nop							; стенд: комната готова
				ld		a, (rv_room)
				inc		a
				cp		NROOMS
				jp		nz, rv_loop
rv_end:			jp		rv_end

; ---- комната A: очистить поле, контур, предметы ----
draw_room:		ld		(dr_room), a
				call	clear_room
				call	draw_outline
				jp		draw_items
dr_room:		DB		0

; поле CPC 96x192 пикселей = столбцы 0..23, строки памяти ROW0-191..ROW0, 3 плоскости: PUSH нулей
clear_room:		ld		hl, 0
				add		hl, sp
				ld		(cr_ssp), hl
				ld		bc, 0
				ld		de, 0x0100			; следующий столбец
				ld		hl, 0x8000 + ROW0 + 1
cr_col:			ld		sp, hl
				DUP		96
				push	bc
				EDUP
				add		hl, de
				ld		a, h
				and		0x1F
				cp		24
				jp		nz, cr_col
				ld		a, h
				add		a, 0x20 - 24		; следующая плоскость, столбец 0
				ld		h, a
				cp		0xE0
				jp		nz, cr_col
				ld		hl, (cr_ssp)
				ld		sp, hl
				ret
cr_ssp:			DW		0

; ---- контур (room.asm draw_outline): точки отрезков посчитаны заранее по типам комнат (mkroom.py,
;      тем же Брезенхемом) — список байт одной плоскости; пишется в плоскости, где у цвета комнаты бит 1 ----
draw_outline:	ld		a, (dr_room)
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		de, ROOM_BANK_ROOMINFO
				add		hl, de
				ld		b, (hl)				; цвет
				inc		hl
				ld		c, (hl)				; тип
				ld		a, (dr_room)
				cp		SKEL1
				jp		z, do_skel
				cp		SKEL2
				jp		z, do_skel
				cp		SKEL3
				jp		z, do_skel
				cp		SKEL4
				jp		nz, do_col
do_skel:		ld		b, 0
do_col:			ld		a, b
				and		3
				ld		e, a
				ld		d, 0
				ld		hl, line_slot
				add		hl, de
				ld		a, (hl)
				ld		(do_slot), a		; индекс палитры линии
				; outline_tab + тип*5
				ld		l, c
				ld		h, 0
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, hl
				add		hl, de
				ld		de, outline_tab
				add		hl, de
				ld		a, (hl)
				ld		(ol_page + 1), a
				inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(ol_sp + 1), hl
				ex		de, hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		(ol_cnt), hl
				ld		a, (do_slot)
				and		4
				ld		c, 0x00
				call	nz, ol_pass			; плоскость 0 = бит 2
				ld		a, (do_slot)
				and		2
				ld		c, 0x20
				call	nz, ol_pass
				ld		a, (do_slot)
				and		1
				ld		c, 0x40
				ret		z
; проход по списку контура в плоскость со смещением C (старший байт адреса)
ol_pass:		ld		a, c
				ld		(ol_off + 1), a
				ld		hl, 0
				add		hl, sp
				ld		(ol_ssp), hl
				ld		hl, (ol_cnt)
				ex		de, hl				; DE = счётчик
ol_page:		ld		a, 0
				out		(0x10), a
ol_sp:			ld		sp, 0
ol_l:			pop		hl
				ld		a, h
ol_off:			add		a, 0
				ld		h, a
				pop		bc
				ld		(hl), c
				dec		de
				ld		a, d
				or		e
				jp		nz, ol_l
				xor		a
				out		(0x10), a
				ld		hl, (ol_ssp)
				ld		sp, hl
				ret
do_slot:		DB		0
ol_cnt:			DW		0
ol_ssp:			DW		0

; ---- предметы (items.asm draw_items + convert_door_type) ----
draw_items:		ld		a, (dr_room)
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		de, ROOM_BANK_ITEMS_PER_ROOM
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl				; HL = список указателей
di_loop:		ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		a, d
				or		e
				ret		z
				push	hl
				ex		de, hl				; HL = запись item_list (8 байт)
				inc		hl
				ld		a, (dr_room)
				cp		(hl)
				dec		hl
				jp		z, di_this
				ld		de, 8
				add		hl, de				; вторая из пары
di_this:		ld		c, (hl)				; тип
				inc		hl
				inc		hl
				ld		b, (hl)				; состояние (бит 7 = закрыто)
				inc		hl
				ld		a, (hl)				; x
				ld		(di_x), a
				inc		hl
				ld		a, (hl)				; y
				ld		(di_y), a
				inc		hl
				ld		a, (hl)				; поворот
				and		0xC0
				rlca
				rlca
				ld		(di_v), a
				call	convert_door
				; описатель: item_var[t*4 + v]
				ld		l, c
				ld		h, 0
				add		hl, hl
				add		hl, hl
				ld		a, (di_v)
				ld		e, a
				ld		d, 0
				add		hl, de
				add		hl, hl
				ld		de, item_var
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl				; HL = описатель фазы 0
				ld		a, (di_x)
				rrca
				rrca
				and		0x3F				; байт CPC
				ld		b, a
				rrca
				jp		nc, di_ph0
				inc		hl
				inc		hl
				inc		hl
				inc		hl
				ld		e, (hl)				; столбцов фазы 0
				inc		hl
				ld		d, 0
				add		hl, de				; -> описатель фазы 1
di_ph0:			ld		a, b
				or		a
				rra
				add		a, 0x80
				ld		d, a				; D = 0x80 + столбец
				; верхняя строка памяти = ROW0 - y + строк - 1
				inc		hl
				inc		hl
				inc		hl
				ld		a, (di_y)
				ld		e, a
				ld		a, ROW0 - 1
				sub		e
				add		a, (hl)
				ld		e, a
				dec		hl
				dec		hl
				dec		hl
				call	draw_item
				pop		hl
				jp		di_loop
di_x:			DB		0
di_y:			DB		0
di_v:			DB		0

; C = тип, B = состояние -> C = тип для рисования
convert_door:	ld		a, c
				cp		1
				jp		z, cv_cave
				cp		2
				jp		z, cv_norm
				cp		25
				jp		z, cv_trap
				cp		8
				ret		c
				cp		12
				jp		c, cv_keyed
				cp		16
				ret		nc
				ld		a, b				; 12..15: открыта -> 1
				or		a
				ret		m
				ld		c, 1
				ret
cv_keyed:		ld		a, b				; 8..11: открыта -> 2
				or		a
				ret		m
				ld		c, 2
				ret
cv_norm:		ld		a, b
				or		a
				ret		p
				ld		c, 32
				ret
cv_cave:		ld		a, b
				or		a
				ret		p
				ld		c, 34
				ret
cv_trap:		ld		a, b
				or		a
				ret		m
				ld		c, 24
				ret

; ---- предмет: HL = описатель, D = 0x80 + столбец, E = верхняя строка памяти.
;      (экран & ~маска) | данные, данные POP из квазидиска ----
draw_item:		ld		a, (hl)
				ld		(dt_page + 1), a
				inc		hl
				ld		c, (hl)
				inc		hl
				ld		b, (hl)
				inc		hl
				ld		a, (hl)
				ld		(dt_rows), a
				inc		hl
				ld		a, (hl)
				ld		(dt_n), a
				inc		hl
				ld		(dt_mp), hl
				ld		a, d
				ld		(dt_col), a
				ld		a, e
				ld		(dt_top), a
				ld		hl, 0
				add		hl, sp
				ld		(dt_ssp), hl
				ld		h, b
				ld		l, c
dt_page:		ld		a, 0
				out		(0x10), a
				ld		sp, hl
dt_cl:			ld		hl, (dt_mp)
				ld		a, (hl)
				inc		hl
				ld		(dt_mp), hl
				cpl
				ld		d, a				; D = ~маска
				ld		a, (dt_col)
				ld		(dt_h), a
				ld		a, 3
				ld		(dt_k), a
dt_pl:			ld		a, (dt_h)
				ld		h, a
				ld		a, (dt_top)
				ld		l, a
				ld		a, (dt_rows)
				ld		e, a
dt_rw:			pop		bc
				ld		a, (hl)
				and		d
				or		c
				ld		(hl), a
				dec		l
				dec		e
				jp		z, dt_pe
				ld		a, (hl)
				and		d
				or		b
				ld		(hl), a
				dec		l
				dec		e
				jp		nz, dt_rw
dt_pe:			ld		a, (dt_h)
				add		a, 0x20
				ld		(dt_h), a
				ld		a, (dt_k)
				dec		a
				ld		(dt_k), a
				jp		nz, dt_pl
				ld		a, (dt_col)
				inc		a
				ld		(dt_col), a
				ld		a, (dt_n)
				dec		a
				ld		(dt_n), a
				jp		nz, dt_cl
				xor		a
				out		(0x10), a
				ld		hl, (dt_ssp)
				ld		sp, hl
				ret
dt_rows:		DB		0
dt_n:			DB		0
dt_col:			DB		0
dt_top:			DB		0
dt_h:			DB		0
dt_k:			DB		0
dt_mp:			DW		0
dt_ssp:			DW		0

				INCLUDE	"../build/room/items.inc"
code_end:
				ASSERT	code_end <= STACK - 0x100

				ORG		0x4000
				INCBIN	"../build/room/rooms.bin"
				SAVEBIN	"../build/room/room.r0m", 0, 0x8000
