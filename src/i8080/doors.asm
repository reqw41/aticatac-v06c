; doors.asm: двери — начальная раскладка, проход, автоматические двери, сетка (= src/model/doors.js).
; Записи списков (item_list, this_rooms_door_list) — через указатель ixp и ixa (не горячий путь).

ixp:			DW		0
; A = смещение -> HL = (ixp) + A. Портит A.
ixa:			ld		hl, (ixp)
				add		a, l
				ld		l, a
				ret		nc
				inc		h
				ret

init_doors:		ld		hl, C_room_bank_item_list
				ld		(ixp), hl
				ld		hl, (C_end_room_bank_item_list - C_room_bank_item_list) >> 4
				ld		(id_n), hl
				call	ldar
				ld		(C_random_seed), a
				xor		a
				ld		(id_iyl), a
id_loop:		ld		a, 7
				call	ixa
				ld		a, (hl)
				or		a
				jp		z, id_next
				ld		c, 0x80
				call	id_or
				ld		a, 0
				call	ixa
				ld		a, (hl)
				cp		active_door_trapdoor
				jp		z, id_auto
				cp		active_door_big + 1
				jp		c, id_unlocked
				ld		hl, C_magic_door
				cp		(hl)
				jp		z, id_ignore
				ld		c, 0xbf
				call	id_and
				jp		id_next
id_unlocked:	ld		c, a
				ld		a, 8
				call	ixa
				ld		a, c
				cp		(hl)
				jp		nz, id_ignore
				call	random
				cp		179
				jp		c, id_auto
id_ignore:		ld		c, 0x3f
				call	id_and
				jp		id_next
id_auto:		ld		c, 0x40
				call	id_or
				call	random
				and		7
				add		a, a
				add		a, a
				add		a, a
				ld		b, a
				ld		a, (id_iyl)
				or		b
				ld		b, a
				ld		a, 2
				call	ixa
				ld		a, (hl)
				or		b
				ld		(hl), a
				ld		b, a
				ld		a, 10
				call	ixa
				ld		(hl), b
				ld		a, (id_iyl)
				inc		a
				and		7
				ld		(id_iyl), a
id_next:		ld		hl, (ixp)
				ld		de, 16
				add		hl, de
				ld		(ixp), hl
				ld		hl, (id_n)
				dec		hl
				ld		(id_n), hl
				ld		a, h
				or		l
				jp		nz, id_loop
				ret
; (ix+2) и (ix+10): or C / and C
id_or:			ld		a, 2
				call	ixa
				ld		a, (hl)
				or		c
				ld		(hl), a
				ld		a, 10
				call	ixa
				ld		a, (hl)
				or		c
				ld		(hl), a
				ret
id_and:			ld		a, 2
				call	ixa
				ld		a, (hl)
				and		c
				ld		(hl), a
				ld		a, 10
				call	ixa
				ld		a, (hl)
				and		c
				ld		(hl), a
				ret
id_n:			DW		0
id_iyl:			DB		0

; HL += ±8 по смещению пары (ix+7): не 0 -> -8
twin:			push	hl
				ld		a, 7
				call	ixa
				ld		a, (hl)
				pop		hl
				or		a
				ld		de, 8
				jp		z, tw_1
				ld		de, -8
tw_1:			add		hl, de
				ret
; HL = (ix+3,4) — указатель на предмет в item_list
item_ptr:		ld		a, 3
				call	ixa
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ret

check_doors:	ld		a, (C_collision_info)
				or		a
				ret		z
				ld		b, a
				ld		a, (C_collision_info + 1)
				cp		b
				ret		nz
				ld		a, (C_collision_info + 2)
				cp		b
				ret		nz
				ld		a, (C_collision_info + 3)
				cp		b
				ret		nz
				ld		a, b
				dec		a
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		de, C_this_rooms_door_list
				add		hl, de
				ld		(ixp), hl
				ld		a, (hl)
				cp		active_door_trapdoor
				jp		z, trapdoor_collision
				ld		a, (C_keys_pressed)
				and		0x0f
				ret		z
				ld		c, a
				call	item_ptr
				ld		de, 5
				add		hl, de
				ld		a, (hl)
				and		0xc0
				or		c
				cp		0x42
				jp		z, do_collision
				cp		0xc1
				jp		z, do_collision
				cp		0x88
				jp		z, do_collision
				cp		0x04
				jp		z, do_collision
				ret

trapdoor_collision:
				call	item_ptr
				push	hl
				inc		hl
				inc		hl
				ld		a, (hl)
				pop		hl
				and		0x80
				ret		nz
				call	twin
				inc		hl
				ld		a, (hl)
				ld		(C_room_number), a
				ld		b, state_falling
				jp		switch_game_state

do_collision:	ld		a, c
				ld		(C_transition_keypress), a
				call	item_ptr
				inc		hl
				inc		hl
				ld		a, (hl)
				and		0x7f
				ld		(hl), a
				call	twin
				ld		a, (hl)
				and		0x7f
				ld		(hl), a
				dec		hl
				dec		hl
				call	get_new_door_dimensions
				ld		a, (C_room_number)
				ld		(C_last_room_number), a
				inc		hl
				ld		a, (hl)
				ld		(C_room_number), a
				ld		a, 1
				ld		(C_room_changed), a
				push	hl
				ld		e, sound_door
				call	play_sfx
				pop		hl
				ld		a, transition_time
				ld		(C_screen_transition_in_progress), a
				inc		hl
				inc		hl
				ld		a, (hl)
				or		a
				rra
				ld		b, a					; x новой двери / 2
				inc		hl
				ld		c, (hl)					; низ новой двери
				inc		hl
				ld		a, (hl)
				and		0xfe
				ld		d, a					; поворот
				xor		a
				ld		(C_collision_info), a
				ld		(C_collision_info + 2), a
				ld		a, d
				cp		rotation_top
				jp		z, dc_top
				cp		rotation_bottom
				jp		z, dc_bot
				cp		rotation_left
				jp		z, dc_left
				ld		a, b					; справа
				sub		player_width - 1
				add		a, 2
				ld		(C_player_x), a
				jp		dc_y_side
dc_left:		ld		a, (C_this_item_height)
				rrca
				rrca
				and		0x3f
				add		a, b
				ld		(C_player_x), a
dc_y_side:		ld		a, (C_this_item_width)
				add		a, a
				ld		b, a
				ld		a, c
				sub		b
				sub		average_player_height / 2
				ld		(C_player_y), a
				ret
dc_bot:			ld		a, (C_this_item_height)
				ld		d, a
				ld		a, c
				sub		d
				sub		average_player_height
				add		a, 12
				ld		(C_player_y), a
				jp		dc_x
dc_top:			ld		a, c
				sub		12
				ld		(C_player_y), a
dc_x:			ld		a, (C_this_item_width)
				add		a, b
				sub		player_width
				inc		a
				ld		(C_player_x), a
				ret

; HL = предмет в item_list -> this_item_width/height (HL сохраняется)
get_new_door_dimensions:
				push	hl
				ld		a, (hl)
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, item_wh
				add		hl, de
				ld		a, (hl)
				ld		(C_this_item_width), a
				inc		hl
				ld		a, (hl)
				ld		(C_this_item_height), a
				pop		hl
				ret

update_doors:	ld		a, (C_player_x)
				ld		b, a
				inc		b
				ld		a, (C_min_x)
				cp		b
				ret		nc
				dec		b
				ld		a, (C_max_x)
				cp		b
				ret		c
				ld		a, (C_player_y)
				ld		b, a
				ld		a, (C_min_y)
				cp		b
				ret		nc
				ld		a, (C_max_y)
				cp		b
				ret		c
				ld		a, (C_this_rooms_door_count)
				ld		b, a
				ld		hl, C_this_rooms_door_list
				ld		(ixp), hl
ud_loop:		push	bc
				call	item_ptr
				inc		hl
				inc		hl
				ld		(ud_p), hl
				ld		a, (hl)
				ld		c, a
				and		0x40
				jp		z, ud_next
				ld		a, c
				inc		a
				and		7
				ld		e, a
				ld		a, c
				and		0x38
				rrca
				rrca
				rrca
				cp		e
				jp		nz, ud_count
				ld		a, c
				and		0xf8
				xor		0x80
				ld		(hl), a
				ld		c, a
				ld		a, 7
				call	ixa
				ld		a, (hl)
				cp		8
				ld		de, 8
				jp		nz, ud_tw
				ld		de, -8
ud_tw:			ld		hl, (ud_p)
				add		hl, de
				ld		(hl), c
				ld		a, 0
				call	ixa
				ld		a, (hl)
				cp		active_door_trapdoor
				ld		a, c
				jp		nz, ud_g
				ld		a, (hl)
				and		0x7f
ud_g:			pop		bc
				push	bc
				call	update_collision_grid_for_door
				pop		bc
				call	item_ptr
				ld		a, (hl)
				cp		active_door_trapdoor
				ret		z						; решётка люка — только вывод
				ld		(C_door_to_toggle), hl
				ret
ud_count:		ld		a, c
				and		0xf8
				or		e
				ld		(hl), a
ud_next:		ld		hl, (ixp)
				ld		de, 8
				add		hl, de
				ld		(ixp), hl
				pop		bc
				dec		b
				jp		nz, ud_loop
				ret
ud_p:			DW		0

update_collision_grid_for_items:
				ld		a, (C_this_rooms_door_count)
				ld		b, a
				ld		hl, C_this_rooms_door_list
				ld		(ixp), hl
ui_loop:		push	bc
				ld		a, 0
				call	ixa
				ld		a, (hl)
				cp		door_acg
				jp		z, ui_acg
				ld		c, a
				call	item_ptr
				inc		hl
				inc		hl
				ld		a, (hl)
				ld		e, a
				and		0x40
				jp		nz, ui_next
				ld		a, e
				and		0x80
				jp		z, ui_next
				ld		a, c
				cp		16
				jp		nc, ui_next
				cp		7
				jp		c, ui_next
				and		0xfb
				ld		c, 3
				cp		door_blue
				jp		z, ui_found
				ld		c, 4
				cp		door_green
				jp		z, ui_found
				ld		c, 5
				cp		door_red
				jp		z, ui_found
				ld		c, 6
				cp		door_yellow
				jp		nz, ui_next
ui_found:		ld		e, 0
				ld		a, (C_pocket1)
				cp		c
				jp		z, ui_key
				ld		a, (C_pocket2)
				cp		c
				jp		z, ui_key
				ld		a, (C_pocket3)
				cp		c
				jp		z, ui_key
				ld		e, 0x80
ui_key:			pop		bc
				push	bc
				ld		a, e
				call	update_collision_grid_for_door
				jp		ui_next
ui_acg:			ld		e, 0x80
				ld		a, (C_pocket3)
				cp		2
				jp		nz, ui_na
				ld		a, (C_pocket1 + 1)
				cp		1
				jp		nz, ui_na
				ld		a, (C_pocket1)
				or		a
				jp		nz, ui_na
				ld		e, 0
ui_na:			pop		bc
				push	bc
				ld		a, e
				call	update_collision_grid_for_door
				ld		hl, C_collision_grid + 24 * 8 + 19
				ld		b, 8
				ld		de, 24
ui_c:			ld		(hl), 0
				add		hl, de
				dec		b
				jp		nz, ui_c
ui_next:		ld		hl, (ixp)
				ld		de, 8
				add		hl, de
				ld		(ixp), hl
				pop		bc
				dec		b
				jp		nz, ui_loop
				ret

; HL = клетка сетки для записи списка (ixp): collision_grid + (y >> 3) * 24 + (x >> 2)
grid_ptr:		ld		a, 2
				call	ixa
				ld		a, (hl)
				rrca
				rrca
				rrca
				and		0x1f
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, de
				push	hl
				ld		a, 1
				call	ixa
				ld		a, (hl)
				rrca
				rrca
				and		0x3f
				pop		hl
				ld		e, a
				ld		d, 0
				add		hl, de
				ld		de, C_collision_grid
				add		hl, de
				ret

; A: бит 7 — закрыта (0xFF), иначе номер двери count - B + 1; ixp — запись списка
update_collision_grid_for_door:
				and		0x80
				ld		a, 0xff
				jp		nz, ug_2
				ld		a, (C_this_rooms_door_count)
				sub		b
				inc		a
ug_2:			ld		(ug_v), a
				call	grid_ptr
				push	hl
				ld		a, 6
				call	ixa
				ld		a, (hl)
				rrca
				rrca
				rrca
				and		0x1f
				ld		c, a
				ld		a, 5
				call	ixa
				ld		a, (hl)
				or		a
				rra
				ld		(ug_w), a
				pop		hl
ug_row:			ld		a, (ug_w)
				ld		b, a
				push	hl
				ld		a, (ug_v)
ug_col:			ld		(hl), a
				inc		hl
				dec		b
				jp		nz, ug_col
				pop		hl
				ld		de, 24
				add		hl, de
				dec		c
				jp		nz, ug_row
				ret
ug_v:			DB		0
ug_w:			DB		0
