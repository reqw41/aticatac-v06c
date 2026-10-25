; items.asm: список дверей комнаты this_rooms_door_list (= src/model/items.js; вывод — отдельно).

draw_items:		xor		a
				ld		(C_this_rooms_door_count), a
				ld		a, (C_room_number)
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		de, C_room_bank_items_per_room
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
di_loop:		ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		a, d
				or		e
				ret		z
				push	hl
				ex		de, hl
				ld		c, 0
				inc		hl
				ld		a, (C_room_number)
				cp		(hl)
				dec		hl
				jp		z, di_t
				ld		de, 8
				add		hl, de
				ld		c, 8
di_t:			call	explode_item
				pop		hl
				jp		di_loop

; HL = запись item_list, C = смещение в паре
explode_item:	ld		(ixp), hl
				ld		a, c
				ld		(C_item_offset), a
				ld		a, (C_this_rooms_door_count)
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		de, C_this_rooms_door_list
				add		hl, de
				ld		(ex_dst), hl
				ld		a, 7
				call	ixa
				ld		a, (hl)
				ld		(C_item_is_door), a
				ld		a, 0
				call	ixa
				ld		a, (hl)
				ld		(ex_t), a
				ld		hl, (ex_dst)
				ld		(hl), a
				inc		hl
				push	hl
				ld		a, 3
				call	ixa
				ld		a, (hl)
				or		a
				rra
				pop		hl
				ld		(hl), a
				inc		hl
				push	hl
				ld		a, 4
				call	ixa
				ld		a, (hl)
				pop		hl
				ld		(hl), a
				inc		hl
				ex		de, hl
				ld		hl, (ixp)
				ex		de, hl
				ld		(hl), e
				inc		hl
				ld		(hl), d
				inc		hl
				push	hl
				ld		a, 5
				call	ixa
				ld		a, (hl)
				ld		(ex_rot), a
				ld		a, (ex_t)
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, item_wh
				add		hl, de
				ld		b, (hl)					; ширина
				inc		hl
				ld		c, (hl)					; высота
				pop		hl
				ld		a, (ex_rot)
				and		0x40
				jp		z, ex_port
				ld		a, c					; лёжа: ширина = высота / 4, высота = ширина * 4
				rrca
				rrca
				and		0x3f
				ld		(hl), a
				inc		hl
				ld		a, b
				add		a, a
				add		a, a
				ld		(hl), a
				ld		e, a
				jp		ex_inc
ex_port:		ld		(hl), b
				inc		hl
				ld		(hl), c
				ld		e, c
ex_inc:			inc		hl
				ld		a, (C_item_offset)
				ld		(hl), a
				ld		hl, (ex_dst)
				inc		hl
				inc		hl
				ld		a, (hl)
				sub		e
				inc		a
				ld		(hl), a
				ld		a, (C_magic_door)
				ld		b, a
				ld		a, (ex_t)
				cp		b
				jp		z, ex_save
				cp		item_barrel
				ret		z
				cp		item_bookcase
				ret		z
				cp		item_clock
				ret		z
				ld		a, (C_item_is_door)
				or		a
				ret		z
ex_save:		ld		hl, C_this_rooms_door_count
				inc		(hl)
				ret
ex_dst:			DW		0
ex_t:			DB		0
ex_rot:			DB		0
