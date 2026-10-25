; roomdraw.asm: вывод комнаты (контур, предметы — из proto/room.asm), ключи и еда, предметы по одному
; (переключение двери), стирание еды. Данные — tools/mkroom.py (items.inc: item_var, контуры) и tools/mkgame.py
; (описатели ключей/еды it_*). Описатель предмета: DB порт, DW адрес в квазидиске, DB строк, столбцов, маски.

; ---- комната room_number: очистить поле, контур, предметы, ключи, еда ----
render_room:	ld		a, (C_room_number)
				ld		(dr_room), a
				call	clear_room
				call	draw_outline
				call	draw_items_v
				call	draw_collectables
				jp		draw_room_food
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
				ld		de, C_room_bank_roominfo
				add		hl, de
				ld		b, (hl)				; цвет
				inc		hl
				ld		c, (hl)				; тип
				ld		a, (dr_room)
				cp		skeleton_room1
				jp		z, do_skel
				cp		skeleton_room2
				jp		z, do_skel
				cp		skeleton_room3
				jp		z, do_skel
				cp		skeleton_room4
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
draw_items_v:	ld		a, (dr_room)
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		de, C_room_bank_items_per_room
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl				; HL = список указателей
rd_loop:		ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		a, d
				or		e
				ret		z
				push	hl
				ex		de, hl				; HL = запись item_list (8 байт)
				call	draw_list_item
				pop		hl
				jp		rd_loop

; HL = запись item_list (пара: своя половина выбирается по номеру комнаты)
draw_list_item:	xor		a
				ld		(dt_clear), a
				inc		hl
				ld		a, (C_room_number)
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
				jp		draw_item
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
				ld		a, (dt_clear)
				or		a
				jp		nz, dt_cl
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
dt_rw:			ld		a, (dt_clear)
				or		a
				ld		bc, 0
				jp		nz, dt_rw0
				pop		bc
dt_rw0:
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
dt_clear:		DB		0
dt_n:			DB		0
dt_col:			DB		0
dt_top:			DB		0
dt_h:			DB		0
dt_k:			DB		0
dt_mp:			DW		0
dt_ssp:			DW		0


; ---- ключи комнаты: collectable_items (комната, описатель, x байт, y верх) ----
draw_collectables:
				ld		hl, C_collectable_items
dc_l:			ld		a, (hl)
				cp		0xff
				ret		z
				push	hl
				ld		b, a
				ld		a, (C_room_number)
				cp		b
				jp		nz, dc_n
				inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)					; описатель
				inc		hl
				ld		a, (hl)					; x байт CPC
				inc		hl
				ld		c, (hl)					; y верх
				ex		de, hl
				call	item_at
dc_n:			pop		hl
				ld		de, 8
				add		hl, de
				jp		dc_l

; ---- еда комнаты (this_rooms_food_list) ----
draw_room_food:	ld		a, (C_this_rooms_food_count)
				or		a
				ret		z
				ld		b, a
				ld		hl, C_this_rooms_food_list
drf_l:			push	bc
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				push	hl
				ex		de, hl
				call	draw_food_item
				pop		hl
				pop		bc
				dec		b
				jp		nz, drf_l
				ret
; HL = еда (тип, комната, таймер, x байт, y низ, ., ., высота): предмет с верхом y - высота
draw_food_item:	ld		a, 1
				jp		food_common
erase_food_item:
				xor		a
food_common:	ld		(fc_draw), a
				ld		a, (hl)
				sub		0x50
				add		a, a
				ld		e, a
				ld		d, 0
				push	hl
				ld		hl, C_food_table
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)					; описатель
				pop		hl
				inc		hl
				inc		hl
				inc		hl
				ld		a, (hl)					; x байт
				inc		hl
				ld		b, (hl)					; y низ
				inc		hl
				inc		hl
				inc		hl
				ld		c, a
				ld		a, b
				sub		(hl)					; y - высота
				ld		b, c
				ld		c, a
				ld		a, b
				ex		de, hl
				ld		b, a
				ld		a, (fc_draw)
				or		a
				ld		a, b
				jp		nz, item_at
				jp		item_clear_at
fc_draw:		DB		0

; ---- HL = описатель предмета (фаза 0), A = x байт CPC, C = y верх: вывести / стереть по маске ----
item_at:		ld		b, 0
				jp		ia_1
item_clear_at:	ld		b, 1
ia_1:			ld		e, a
				ld		a, b
				ld		(dt_clear), a
				ld		a, e
				rrca
				jp		nc, ia_ph0
				push	af
				inc		hl
				inc		hl
				inc		hl
				inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, 0
				add		hl, de					; описатель фазы 1
				pop		af
ia_ph0:			and		0x7f
				add		a, 0x80
				ld		d, a
				ld		a, c
				cpl
				add		a, ROW0 + 1
				ld		e, a					; строка памяти верха
				jp		draw_item
