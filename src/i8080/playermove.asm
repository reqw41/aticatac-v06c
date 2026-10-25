; playermove.asm: движение героя, столкновения с сеткой комнаты, кадр анимации (= src/model/playermove.js).

move_player:	ld		a, (C_keys_pressed)
				ld		c, a
				ld		a, (C_screen_transition_in_progress)
				or		a
				jp		z, mp_1
				dec		a
				ld		(C_screen_transition_in_progress), a
				ld		a, (C_transition_keypress)
				ld		(C_keys_pressed), a
				ld		c, a
mp_1:			ld		a, c
				ld		(mp_keys), a
				ld		a, (C_player_x)
				ld		(C_updated_x), a
				ld		a, (mp_keys)
				and		1 << player_up_bit
				call	nz, move_up
				ld		a, (mp_keys)
				and		1 << player_down_bit
				call	nz, move_down
				ld		a, (C_player_y)
				ld		(C_updated_y), a
				ld		a, (mp_keys)
				and		1 << player_left_bit
				call	nz, move_left
				ld		a, (mp_keys)
				and		1 << player_right_bit
				call	nz, move_right
				ld		a, (mp_keys)
				and		1 << player_fire1_bit
				call	nz, fire_weapon
				call	check_collision_squares
				ld		a, (C_screen_transition_in_progress)
				or		a
				jp		nz, mp_inc
				ld		a, (C_keys_pressed)
				and		0x0f
				jp		nz, mp_inc
				ld		a, default_frame
				ld		(C_player_frame), a
				ret
mp_inc:			ld		a, (C_player_frame)
				inc		a
				and		0x0f
				ld		(C_player_frame), a
				cp		player_step_frame1
				jp		z, mp_step
				cp		player_step_frame2
				ret		nz
mp_step:		ld		e, sound_steps
				jp		play_lowpriority_sfx
mp_keys:		DB		0

move_up:		ld		a, player_is_going_up
				ld		(C_player_orientation), a
				ld		a, (C_player_y)
				add		a, -player_vert_speed
				jp		mv_y
move_down:		ld		a, player_is_going_down
				ld		(C_player_orientation), a
				ld		a, (C_player_y)
				add		a, player_vert_speed
mv_y:			ld		(C_updated_y), a
				call	check_collision
				or		a
				ret		nz
				ld		a, (C_updated_y)
				ld		(C_player_y), a
				ret
move_left:		ld		a, player_is_going_left
				ld		(C_player_orientation), a
				ld		a, (C_player_x)
				add		a, -player_horiz_speed
				jp		mv_x
move_right:		ld		a, player_is_going_right
				ld		(C_player_orientation), a
				ld		a, (C_player_x)
				add		a, player_horiz_speed
mv_x:			ld		(C_updated_x), a
				call	check_collision
				or		a
				ret		nz
				ld		a, (C_updated_x)
				ld		(C_player_x), a
				ret

; 6 углов героя на updated_x/y -> A = 1, если хоть один в стене (0xFF)
check_collision:
				ld		a, (C_updated_y)
				ld		c, a					; C = y верха
				ld		a, (C_actual_player_height)
				add		a, c
				ld		(cc_y2), a
				ld		a, (C_updated_x)
				ld		d, a					; D = x
				ld		a, c
				call	cc_row					; HL = строка сетки для y
				call	cc_three
				ret		nz
				ld		a, (cc_y2)
				call	cc_row
				call	cc_three
				ret		nz
				xor		a
				ret
cc_y2:			DB		0
; три угла строки HL: x, x+3, x+player_width+2 -> NZ и A = 1, если стена
cc_three:		ld		a, d
				call	cc_cell
				ret		nz
				ld		a, d
				add		a, 3
				call	cc_cell
				ret		nz
				ld		a, d
				add		a, player_width + 2
cc_cell:		rrca
				rrca
				and		0x3f
				push	hl
				add		a, l
				ld		l, a
				jp		nc, cc_c1
				inc		h
cc_c1:			ld		a, (hl)
				pop		hl
				inc		a						; 0xFF -> 0 (Z)
				jp		z, cc_wall
				xor		a
				ret
cc_wall:		inc		a						; A = 1, NZ
				ret
; A = y -> HL = collision_rows[y >> 3]
cc_row:			rrca
				rrca
				rrca
				and		0x1f
				add		a, a
				add		a, low C_collision_rows
				ld		l, a
				ld		a, 0
				adc		a, high C_collision_rows
				ld		h, a
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ret

check_collision_squares:
				ld		a, (C_player_y)
				ld		c, a
				call	cc_row
				ld		a, (C_player_x)
				ld		d, a
				call	cs_cell
				ld		(C_collision_info + 0), a
				ld		a, d
				add		a, player_width + 2
				call	cs_cell
				ld		(C_collision_info + 1), a
				ld		a, (C_actual_player_height)
				add		a, c
				call	cc_row
				ld		a, d
				call	cs_cell
				ld		(C_collision_info + 2), a
				ld		a, d
				add		a, player_width + 2
				call	cs_cell
				ld		(C_collision_info + 3), a
				ret
cs_cell:		rrca
				rrca
				and		0x3f
				add		a, l
				ld		e, a
				ld		a, 0
				adc		a, h
				push	hl
				ld		h, a
				ld		l, e
				ld		a, (hl)
				pop		hl
				ret

; A = y, B = x -> A = клетка, B = 1, если 0xFF (для сверки отдельно)
check_corner_collision:
				call	cc_row
				ld		a, b
				call	cs_cell
				ld		b, 0
				cp		0xff
				ret		nz
				inc		b
				ret

