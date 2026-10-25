; player.asm: появление/исчезновение героя, жизни, столкновения с врагами и боссами (= src/model/player.js).

init_player:	ld		hl, (C_selected_player)
				ld		(C_anim_frames_table), hl
				ld		a, (C_selected_player_height)
				ld		(C_actual_player_height), a
				ld		a, 3
				ld		(C_num_lives), a
make_player_appear:
				ld		a, default_frame
				ld		(C_player_frame), a
				ld		a, 0x2c
				ld		(C_player_x), a
				ld		a, 0x53
				ld		(C_player_y), a
				ld		a, player_is_going_right
				ld		(C_player_orientation), a
				ld		a, player_appearing
				ld		(C_player_growing), a
				ld		a, 1
				ld		(C_current_player_height), a
				ld		a, (C_actual_player_height)
				dec		a
				ld		l, a
				ld		h, 0
				add		hl, hl
				add		hl, hl
				ld		c, a
				ld		b, 0
				add		hl, bc
				ld		(C_current_height_gfx_offset), hl
				ld		a, max_health
				ld		(C_health), a
				ret

make_player_disappear:
				ld		a, player_disappearing
				ld		(C_player_growing), a
				ld		a, (C_actual_player_height)
				ld		(C_current_player_height), a
				ld		hl, 0
				ld		(C_current_height_gfx_offset), hl
				ld		a, (C_sprite1 + spr_state)
				cp		state_dead
				ld		hl, C_sprite1
				call	nz, kill_sprite
				ld		a, (C_sprite2 + spr_state)
				cp		state_dead
				ld		hl, C_sprite2
				call	nz, kill_sprite
				ld		a, (C_sprite3 + spr_state)
				cp		state_dead
				ret		z
				ld		hl, C_sprite3
				jp		kill_sprite

decrease_lives:	ld		a, (C_num_lives)
				or		a
				jp		nz, dl_1
				ld		a, game_finished
				ld		(C_game_over), a
				ret
dl_1:			dec		a
				ld		(C_num_lives), a
				ret

	MACRO PVB pobj, skip_kill
				ld		a, (pobj + spr_state)
				cp		state_active
				jp		nz, .miss
				ld		a, (pobj + 0)
				ld		b, a
				ld		a, (pobj + 5)
				add		a, b
				ld		b, a
				ld		a, (C_player_x)
				cp		b
				jp		nc, .miss
				add		a, player_width
				ld		b, a
				ld		a, (pobj + 0)
				ld		c, a
				ld		a, b
				cp		c
				jp		c, .miss
				ld		a, (pobj + 1)
				ld		b, a
				ld		a, (pobj + 6)
				add		a, b
				ld		b, a
				ld		a, (C_player_y)
				cp		b
				jp		nc, .miss
				ld		b, a
				ld		a, (C_actual_player_height)
				add		a, b
				ld		b, a
				ld		a, (pobj + 1)
				ld		c, a
				ld		a, b
				cp		c
				jp		c, .miss
				ld		a, (pobj + 26)
				or		a
				ld		hl, pobj
				jp		nz, .boss
				call	kill_sprite
				call	health_down
				IF skip_kill == 0
				ret								; задет обычный враг — дальше не проверять
				ENDIF
				jp		.miss
.boss:			call	touching_boss
.miss:
	ENDM

check_player_hit_baddie:
				PVB		C_boss, 1
				PVB		C_sprite1, 0
				PVB		C_sprite2, 0
				PVB		C_sprite3, 0
				ret

; HL = босс
touching_boss:	ld		a, (C_room_number)
				cp		0x55
				jp		nz, tb_drac
				ld		a, (C_pocket1)
				cp		wrench
				jp		z, tb_kill
				ld		a, (C_pocket1 + 1)
				cp		wrench
				jp		z, tb_kill
				ld		a, (C_pocket1 + 2)
				cp		wrench
				jp		z, tb_kill
tb_drac:		ld		a, (C_dracula_room)
				ld		b, a
				ld		a, (C_room_number)
				cp		b
				jp		nz, tb_hit
				ld		a, (C_pocket1)
				cp		crucifix
				ret		z
				ld		a, (C_pocket1 + 1)
				cp		crucifix
				ret		z
				ld		a, (C_pocket1 + 2)
				cp		crucifix
				ret		z
tb_hit:			ld		e, sound_clock
				call	play_sfx
				jp		health_decay
tb_kill:		call	kill_sprite
				ld		a, 1
				ld		(C_frank_dead), a
				ld		bc, 0x845
				jp		add_to_score
