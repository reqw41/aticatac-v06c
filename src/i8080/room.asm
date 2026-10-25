; room.asm: смена комнаты — логика draw_room (= src/model/room.js; вывод — proto/room.asm).

SPR_LEN			equ		C_sprite_end - C_sprite1

draw_room:		call	outline_logic
				call	draw_items
				call	draw_food
				call	calc_room_dimensions
				call	calculate_collision_grid
				call	update_collision_grid_for_items
				call	try_teleport_dracula
				call	replen_food
				xor		a
				ld		(C_room_changed), a
				ld		hl, C_sprite1
				ld		de, C_temp_sprite_data
				call	copy_spr
				ld		a, (C_saved_room_number)
				ld		b, a
				ld		a, (C_room_number)
				cp		b
				jp		z, dr_back
				call	reset_sprites
				jp		dr_1
dr_back:		ld		hl, C_old_room_sprites
				ld		de, C_sprite1
				call	copy_spr
dr_1:			ld		hl, C_temp_sprite_data
				ld		de, C_old_room_sprites
				call	copy_spr
				ld		a, (C_last_room_number)
				ld		(C_saved_room_number), a
				call	ldar
				ld		(C_random_seed), a
				ld		hl, 0
				ld		(C_door_to_toggle), hl
				call	init_boss
				call	reset_weapon
				call	reset_food_collected
				ld		a, (C_room_number)
				cp		end_room
				ret		nz
				ld		a, game_completed
				ld		(C_game_over), a
				ret
copy_spr:		ld		c, SPR_LEN
cs_l:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, cs_l
				ret

; логика draw_outline: «посещена», тип, размер, указатель вершин
outline_logic:	ld		a, (C_room_number)
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		de, C_room_bank_roominfo
				add		hl, de
				ld		a, (hl)
				or		0x80
				ld		(hl), a
				inc		hl
				ld		a, (hl)
				ld		(C_room_type), a
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		d, h
				ld		e, l
				add		hl, hl
				add		hl, de
				ld		de, C_room_bank_roomtypes
				add		hl, de
				ld		a, (hl)
				ld		(C_room_size + 1), a
				inc		hl
				ld		a, (hl)
				ld		(C_room_size), a
				inc		hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		(C_point_address), hl
				ret

calc_room_dimensions:
				ld		a, (C_room_size + 1)
				or		a
				rra
				ld		b, a
				ld		a, 0x30
				sub		b
				sub		4
				ld		(C_min_x), a
				ld		a, 0x30
				add		a, b
				sub		4
				ld		(C_max_x), a
				ld		a, (C_room_size)
				ld		c, a
				ld		a, 0x60
				sub		c
				sub		9
				ld		(C_min_y), a
				ld		a, 0x60
				add		a, c
				sub		12
				ld		(C_max_y), a
				ret

calculate_collision_grid:
				ld		hl, C_collision_grid
				ld		bc, collision_grid_size * collision_grid_size
ccg_f:			ld		(hl), 0xff
				inc		hl
				dec		bc
				ld		a, b
				or		c
				jp		nz, ccg_f
				call	block_items
				jp		block_room

block_items:	ld		a, (C_this_rooms_door_count)
				ld		b, a
				ld		hl, C_this_rooms_door_list
				ld		(ixp), hl
bi_loop:		push	bc
				call	grid_ptr
				pop		bc
				push	bc
				ld		a, (C_this_rooms_door_count)
				sub		b
				inc		a
				ld		(C_this_doors_index), a
				call	block_out_item
				ld		hl, (ixp)
				ld		de, 8
				add		hl, de
				ld		(ixp), hl
				pop		bc
				dec		b
				jp		nz, bi_loop
				ret

block_out_item:	push	hl
				call	item_ptr
				ld		a, (hl)
				cp		item_table
				jp		z, bo_1
				inc		hl
				inc		hl
				ld		a, (hl)
				and		0x80
				jp		z, bo_1
				ld		a, 0xff
				ld		(C_this_doors_index), a
bo_1:			ld		a, 6
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
				ld		b, a
				ld		a, 0
				call	ixa
				ld		a, (hl)
				cp		item_clock
				jp		nz, bo_2
				dec		b
bo_2:			ld		a, b
				ld		(bo_w), a
				pop		hl
bo_row:			ld		a, (bo_w)
				ld		b, a
				push	hl
				ld		a, (C_this_doors_index)
bo_col:			ld		(hl), a
				inc		hl
				dec		b
				jp		nz, bo_col
				pop		hl
				ld		de, 24
				add		hl, de
				dec		c
				jp		nz, bo_row
				ret
bo_w:			DB		0

block_room:		ld		a, (C_min_y)
				rrca
				rrca
				rrca
				and		0x1f
				ld		(br_ymin), a
				ld		a, (C_max_y)
				rrca
				rrca
				rrca
				and		0x1f
				add		a, 2
				ld		(br_ymax), a
				ld		a, (C_min_x)
				rrca
				rrca
				and		0x3f
				dec		a
				ld		(br_xmin), a
				ld		a, (C_max_x)
				rrca
				rrca
				and		0x3f
				inc		a
				ld		(br_xmax), a
				ld		hl, C_collision_grid
				ld		b, 0
br_row:			ld		c, 0
br_col:			ld		a, (br_ymin)
				cp		b
				jp		nc, br_skip
				ld		a, (br_ymax)
				cp		b
				jp		c, br_skip
				ld		a, (br_xmin)
				cp		c
				jp		nc, br_skip
				ld		a, (br_xmax)
				cp		c
				jp		c, br_skip
				ld		a, (hl)
				push	hl
				dec		a
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		de, C_this_rooms_door_list
				add		hl, de
				ld		a, (hl)
				pop		hl
				cp		active_door_trapdoor
				jp		z, br_skip
				cp		item_table
				jp		nz, br_clr
				ld		(hl), 0xff
				jp		br_skip
br_clr:			ld		(hl), 0
br_skip:		inc		hl
				inc		c
				ld		a, c
				cp		collision_grid_size
				jp		nz, br_col
				inc		b
				ld		a, b
				cp		collision_grid_size
				jp		nz, br_row
				ret
br_ymin:		DB		0
br_ymax:		DB		0
br_xmin:		DB		0
br_xmax:		DB		0
