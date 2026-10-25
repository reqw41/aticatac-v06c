; food.asm: еда, могилы, подбор еды (= src/model/food.js). food_items лежит с FOOD80.

FOODI			equ		FOOD80
TOMB			equ		FOOD80 + (C_tombstones - C_food_items)
FD_N			equ		(C_food_items_end - C_food_items) / 8

init_food:		ld		hl, FOODI + 2
				ld		b, FD_N
				ld		de, 8
if_l:			ld		(hl), 0
				add		hl, de
				dec		b
				jp		nz, if_l
				ld		a, 0xff
				ld		(TOMB + 1), a
				ld		(TOMB + 9), a
				ld		(TOMB + 17), a
				ret

replen_food:	ld		hl, FOODI + 2
				ld		b, FD_N
				ld		de, 8
rf_l:			ld		a, (hl)
				or		a
				jp		z, rf_n
				dec		a
				ld		(hl), a
rf_n:			add		hl, de
				dec		b
				jp		nz, rf_l
				ret

add_tombstone:	ld		a, (C_num_lives)
				add		a, a
				add		a, a
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, TOMB
				add		hl, de
				push	hl
				inc		hl
				ld		a, (C_room_number)
				ld		(hl), a
				inc		hl
				inc		hl
				ld		a, (C_player_x)
				or		a
				rra
				ld		(hl), a
				inc		hl
				ld		a, (C_player_y)
				ld		b, a
				ld		a, (C_actual_player_height)
				add		a, b
				ld		(hl), a
				pop		hl
				ld		(C_draw_tombstone_with_index), hl
				ret

; A = число еды в комнате
check_food_collision:
				ld		b, a
				ld		hl, C_this_rooms_food_list
cf_l:			ld		e, (hl)
				inc		hl
				ld		d, (hl)
				push	hl
				push	bc
				ld		hl, 2
				add		hl, de
				ld		a, (hl)
				or		a
				jp		nz, cf_n
				call	check_food
				or		a
				jp		nz, cf_done
cf_n:			pop		bc
				pop		hl
				inc		hl
				dec		b
				jp		nz, cf_l
				ret
cf_done:		pop		bc
				pop		hl
				ret

; DE = еда -> A = 1, если подобрана
check_food:		ld		a, (C_player_x)
				or		a
				rra
				add		a, 2
				ld		c, a
				ld		hl, 3
				add		hl, de
				ld		a, (hl)
				inc		a
				sub		c
				jp		p, ck_1
				cpl
				inc		a
ck_1:			cp		4
				jp		nc, ck_no
				ld		a, (C_player_y)
				add		a, average_player_height / 2
				ld		c, a
				ld		hl, 7
				add		hl, de
				ld		a, (hl)
				or		a
				rra
				ld		b, a
				ld		hl, 4
				add		hl, de
				ld		a, (hl)
				sub		b
				sub		c
				jp		p, ck_2
				cpl
				inc		a
ck_2:			cp		12
				jp		nc, ck_no
				ld		a, (de)
				cp		type_tombstone
				jp		z, ck_no
				cp		type_mushroom
				jp		nz, ck_eat
				ld		e, sound_clock
				call	play_sfx
				call	health_decay
				xor		a
				ret
ck_eat:			ld		hl, 2
				add		hl, de
				ld		(hl), food_respawn
				ex		de, hl
				ld		(C_erase_food_with_index), hl
				ld		e, sound_c_food
				call	play_sfx
				call	health_up
				ld		a, 1
				ret
ck_no:			xor		a
				ret

reset_food_collected:
				ld		hl, 0
				ld		(C_erase_food_with_index), hl
				ld		(C_draw_tombstone_with_index), hl
				ret

; список еды комнаты (логика draw_food)
draw_food:		xor		a
				ld		(C_this_rooms_food_count), a
				ld		a, (C_room_number)
				ld		c, a
				ld		hl, FOODI
				ld		b, FD_N
cl_l:			push	bc
				push	hl
				inc		hl
				ld		a, (hl)
				cp		c
				jp		nz, cl_skip
				inc		hl
				ld		a, (hl)
				or		a
				jp		nz, cl_skip
				ld		a, (C_this_rooms_food_count)
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, C_this_rooms_food_list
				add		hl, de
				pop		de
				push	de
				ld		(hl), e
				inc		hl
				ld		(hl), d
				ld		hl, C_this_rooms_food_count
				inc		(hl)
				ld		a, (hl)
				cp		max_food
				jp		c, cl_skip
				pop		hl
				pop		bc
				ret
cl_skip:		pop		hl
				ld		de, 8
				add		hl, de
				pop		bc
				dec		b
				jp		nz, cl_l
				ret
