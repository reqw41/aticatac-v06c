; state.asm: смена состояния игры (= src/model/state.js). Задача шага — в current_game_state+1 (адрес CPC
; как номер задачи), прерывания — current_interrupts.

; B = состояние
switch_game_state:
				ld		a, b
				cp		state_falling
				jp		z, select_falling
				cp		state_end
				jp		z, select_end
				cp		state_game
				jp		z, select_game
				ret								; меню — своё у Вектора

; новая игра
select_game:	ld		hl, C_game_tasks
				ld		(C_current_game_state + 1), hl
				ld		hl, C_game_interrupts
				ld		(C_current_interrupts), hl
				xor		a
				ld		(C_room_number), a
				ld		(C_player_orientation), a
				ld		(C_game_over), a
				ld		(C_heartbeat), a
				ld		(C_frank_dead), a
				ld		(C_mummy_angry), a
				ld		(C_game_paused), a
				inc		a
				ld		(C_room_changed), a
				ld		(C_saved_room_number), a
				call	init_player
				call	init_health
				call	init_food
				call	init_doors
				call	init_collectables
				xor		a
				ld		(C_score), a
				ld		(C_score + 1), a
				ld		(C_score + 2), a
				ld		hl, C_font_0 - 256
				ld		(C_font_type), hl
				call	reset_clock
				ld		hl, C_room_bank_roominfo
				ld		b, (C_end_room_bank - C_room_bank_roominfo) / 2
sg_l:			ld		a, (hl)
				and		0x7f
				ld		(hl), a
				inc		hl
				inc		hl
				dec		b
				jp		nz, sg_l
				ld		bc, 0
				call	add_to_score
				ld		a, 44
				ld		(C_boss_hunchback + 14), a
				ld		a, 32
				ld		(C_boss_hunchback + 15), a
				ret

select_falling:	ld		hl, C_falling_tasks
				ld		(C_current_game_state + 1), hl
				ld		hl, C_falling_interrupts
				ld		(C_current_interrupts), hl
				call	reset_sprites
				call	reset_weapon
				xor		a
				ld		(C_save_fall_data), a
				ld		(C_save_fall_data + 1), a
				ld		a, 1
				ld		(C_still_falling), a
				ld		a, 0xff
				ld		(C_fall_index), a
				ld		e, sound_p_fall
				jp		play_sfx

select_end:		ld		hl, C_end_tasks
				ld		(C_current_game_state + 1), hl
				ld		hl, C_end_game_interrupts
				ld		(C_current_interrupts), hl
				ld		a, 100
				ld		(C_end_key_delay), a
				ld		hl, C_font_data_mode0
				ld		(C_font_type), hl
				ld		hl, C_room_bank_roominfo
				ld		b, (C_end_room_bank - C_room_bank_roominfo) / 2
				ld		c, 0
se_l:			ld		a, (hl)
				and		0x80
				jp		z, se_n
				inc		c
se_n:			inc		hl
				inc		hl
				dec		b
				jp		nz, se_l
				ld		hl, C_game_over_percentage_text
				ld		a, c
				cp		end_room
				jp		c, se_pct
				ld		a, '1'
				ld		(C_game_over_percentage_text + 11), a
				ld		a, '0'
				ld		(C_game_over_percentage_text + 12), a
				ld		(C_game_over_percentage_text + 13), a
				jp		se_rest
se_pct:			ld		a, ' '
				ld		(C_game_over_percentage_text + 13), a
				ld		l, c
				ld		h, 0
				ld		de, C_percentage_lookup - 1
				add		hl, de
				ld		a, (hl)
				ld		b, a
				rrca
				rrca
				rrca
				rrca
				and		0x0f
				add		a, '0'
				ld		(C_game_over_percentage_text + 11), a
				ld		a, b
				and		0x0f
				add		a, '0'
				ld		(C_game_over_percentage_text + 12), a
se_rest:		ld		hl, C_game_time
				ld		de, C_game_over_time_text + 11
				ld		c, 6
				call	se_copy
				ld		hl, C_score_text + 3
				ld		de, C_game_over_score_text + 11
				ld		c, 6
se_copy:		ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, se_copy
				ret

end_tasks:		ld		a, (C_end_key_delay)
				or		a
				jp		z, et_1
				dec		a
				ld		(C_end_key_delay), a
				ret
et_1:			ld		a, (C_keys_pressed)
				or		a
				ret		z
				ld		b, state_menu
				jp		switch_game_state
