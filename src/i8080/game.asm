; game.asm: шаг игры (game_tasks), переход героя, падение (= src/model/game.js). Вывод — отдельно.

game_tasks:		ld		a, (C_game_paused)
				or		a
				jp		nz, game_is_paused
				ld		a, (C_room_changed)
				or		a
				jp		nz, draw_room
				ld		a, (C_tell_time)
				or		a
				call	nz, show_clock
				call	update_chicken
				ld		a, (C_do_pockets)
				or		a
				jp		z, gt_1
				dec		a
				ld		(C_do_pockets), a
gt_1:			ld		a, (C_erase_food_with_index + 1)
				or		a
				jp		z, gt_2
				ld		hl, 0
				ld		(C_erase_food_with_index), hl
gt_2:			ld		a, (C_draw_tombstone_with_index + 1)
				or		a
				jp		z, gt_3
				ld		hl, 0
				ld		(C_draw_tombstone_with_index), hl
gt_3:			ld		a, (C_player_growing)
				or		a
				jp		nz, continue_player_transition
				ld		a, (C_heartbeat)
				cp		31
				call	z, health_decay
				call	move_player
				call	check_doors
skip_some_others:
				call	move_weapon
				call	draw_weapon
				ld		hl, C_boss
				call	update_sprite
				ld		hl, C_sprite1
				call	update_sprite
				ld		hl, C_sprite2
				call	update_sprite
				ld		hl, C_sprite3
				call	update_sprite
				call	check_weapon_hit
				call	check_player_hit_baddie
				ld		a, (C_this_rooms_food_count)
				or		a
				call	nz, check_food_collision
				ld		hl, (C_door_to_toggle)
				ld		a, h
				or		l
				jp		z, gt_4
				ld		hl, 0
				ld		(C_door_to_toggle), hl
gt_4:			ld		a, (C_heartbeat)
				cp		25
				call	z, update_doors
				ld		a, (C_keys_pressed)
				and		1 << player_fire2_bit
				call	nz, pickup_tapped
				ld		a, (C_game_over)
				or		a
				jp		nz, gt_end
				ld		a, (C_keyboard_state + 5)
				and		0x10
				jp		nz, gt_5
				ld		a, 1
				ld		(C_game_paused), a
gt_5:			ld		a, (C_keyboard_state + 4)
				and		0x40
				ret		nz
gt_end:			ld		b, state_end
				jp		switch_game_state

game_is_paused:	ld		a, (C_keys_pressed)
				or		a
				ret		z
				xor		a
				ld		(C_game_paused), a
				ret

continue_player_transition:
				ld		a, (C_player_growing)
				cp		player_disappearing
				jp		z, cp_shrink
				ld		a, (C_heartbeat)
				and		3
				cp		3
				jp		nz, skip_some_others
				ld		a, (C_current_player_height)
				ld		b, a
				ld		a, (C_actual_player_height)
				cp		b
				jp		z, cp_done
				ld		a, b
				inc		a
				ld		(C_current_player_height), a
				cp		4
				jp		nz, cp_1
				ld		e, sound_p_appear
				call	play_sfx
cp_1:			ld		hl, (C_current_height_gfx_offset)
				ld		de, -5
				add		hl, de
				ld		(C_current_height_gfx_offset), hl
				jp		skip_some_others
cp_shrink:		ld		a, (C_current_player_height)
				dec		a
				jp		nz, cp_still
				call	add_tombstone
				call	make_player_appear
				jp		skip_some_others
cp_still:		ld		a, (C_heartbeat)
				and		3
				cp		3
				jp		nz, skip_some_others
				ld		a, (C_current_player_height)
				dec		a
				ld		(C_current_player_height), a
				cp		16
				jp		nz, cp_2
				ld		e, sound_p_death
				call	play_sfx
cp_2:			ld		hl, (C_current_height_gfx_offset)
				ld		de, 5
				add		hl, de
				ld		(C_current_height_gfx_offset), hl
				jp		skip_some_others
cp_done:		xor		a
				ld		(C_player_growing), a
				jp		skip_some_others

falling_tasks:	xor		a
				ld		(C_tunnel_pen), a
				ld		hl, C_save_fall_data
				ld		a, (C_hidden_screen_base_address)
				cp		0xc0
				jp		nz, ft_1
				inc		hl
ft_1:			ld		(C_this_index), hl
				ld		a, 0xf3
				ld		(C_tunnel_pen), a
				ld		a, (C_fall_index)
				inc		a
				cp		(C_end_falling_sequence - C_falling_sequence) * 2
				jp		z, ft_done
				ld		(C_fall_index), a
				or		a
				rra
				ld		e, a
				ld		d, 0
				ld		hl, C_falling_sequence
				add		hl, de
				ld		a, (hl)
				ld		hl, (C_this_index)
				ld		(hl), a
				jp		ft_2
ft_done:		xor		a
				ld		(C_still_falling), a
ft_2:			ld		a, (C_tell_time)
				or		a
				call	nz, show_clock
				ld		a, (C_still_falling)
				or		a
				ret		nz
				call	draw_room
				ld		hl, C_game_tasks
				ld		(C_current_game_state + 1), hl
				ld		hl, C_game_interrupts
				ld		(C_current_interrupts), hl
				ret
