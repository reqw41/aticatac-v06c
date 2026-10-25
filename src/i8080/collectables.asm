; collectables.asm: ключи и предметы, карманы, огонь 2 (= src/model/collectables.js).

init_collectables:
				ld		a, 0xff
				ld		(C_pocket1), a
				ld		(C_pocket2), a
				ld		(C_pocket3), a
				ld		hl, C_col_key_yellow
ic_l:			ld		a, (hl)
				cp		0xff
				jp		z, ic_rnd
				push	hl
				ld		de, 5
				add		hl, de
				ld		a, (hl)
				inc		hl
				ld		b, (hl)
				inc		hl
				ld		c, (hl)
				pop		hl
				ld		(hl), a
				push	hl
				inc		hl
				inc		hl
				inc		hl
				ld		(hl), b
				inc		hl
				ld		(hl), c
				pop		hl
				ld		de, 8
				add		hl, de
				jp		ic_l
ic_rnd:			call	ldar
				ld		(C_random_seed), a
				call	random
				and		7
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, C_random_place_table
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ld		hl, C_collectable_items
				ld		b, 6
ic_p:			ld		a, (de)
				ld		(hl), a
				inc		de
				inc		hl
				inc		hl
				inc		hl
				ld		a, (de)
				ld		(hl), a
				inc		de
				inc		hl
				ld		a, (de)
				ld		(hl), a
				inc		de
				inc		hl
				inc		hl
				inc		hl
				inc		hl
				dec		b
				jp		nz, ic_p
				ld		a, (C_col_key_red)
				ld		(C_mummy_room), a
				ld		a, room_dracula
				ld		(C_dracula_room), a
				ret

; HL = предмет -> NZ, если герой рядом
collect_this:	push	hl
				inc		hl
				inc		hl
				inc		hl
				ld		a, (C_player_x)
				or		a
				rra
				add		a, 2
				ld		e, a
				ld		a, (hl)
				add		a, 2
				sub		e
				jp		p, ct_1
				cpl
				inc		a
ct_1:			cp		4
				jp		nc, ct_no
				inc		hl
				ld		a, (C_player_y)
				add		a, average_player_height / 2
				ld		e, a
				ld		a, (hl)
				add		a, 8
				sub		e
				jp		p, ct_2
				cpl
				inc		a
ct_2:			cp		8
				jp		nc, ct_no
				pop		hl
				or		1
				ret
ct_no:			pop		hl
				xor		a
				ret

pickup_tapped:	ld		e, sound_c_food
				call	play_sfx
				ld		a, (C_room_number)
				ld		c, a
				ld		hl, C_collectable_items
				ld		b, 0
pt_l:			ld		a, (hl)
				cp		0xff
				jp		z, pt_none
				cp		c
				jp		nz, pt_n
				call	collect_this
				jp		nz, pt_got
pt_n:			inc		b
				ld		de, 8
				add		hl, de
				jp		pt_l
pt_none:		call	pt_shift
				jp		pt_drop
pt_got:			call	pt_shift
				ld		a, b
				ld		(C_pocket1), a
				ld		(hl), 0xfe
				cp		the_red_key
				jp		nz, pt_drop
				ld		a, (C_mummy_room)
				ld		c, a
				ld		a, (C_room_number)
				cp		c
				jp		nz, pt_drop
				ld		a, 1
				ld		(C_mummy_angry), a
pt_drop:		ld		a, (pt_e)
				cp		0xff
				jp		z, pt_done
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		de, C_collectable_items
				add		hl, de
				ld		a, (C_room_number)
				ld		(hl), a
				inc		hl
				inc		hl
				inc		hl
				ld		a, (C_player_x)
				or		a
				rra
				ld		(hl), a
				inc		hl
				ld		a, (C_player_y)
				add		a, 4
				ld		(hl), a
pt_done:		ld		a, 2
				ld		(C_do_pockets), a
				jp		update_collision_grid_for_items
; карманы сдвигаются: pocket3 уходит (pt_e), pocket1 = 0xFF
pt_shift:		ld		a, (C_pocket3)
				ld		(pt_e), a
				ld		a, (C_pocket2)
				ld		(C_pocket3), a
				ld		a, (C_pocket1)
				ld		(C_pocket2), a
				ld		a, 0xff
				ld		(C_pocket1), a
				ret
pt_e:			DB		0
