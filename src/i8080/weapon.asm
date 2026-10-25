; weapon.asm: выстрел, полёт и отскоки оружия, попадание по врагам (= src/model/weapon.js).

FHS				equ		fire_horizontal_speed
FVS				equ		fire_vertical_speed

fire_weapon:	ld		a, (C_weapon_active)
				or		a
				ret		nz
				ld		a, (C_fire_delay)
				or		a
				jp		z, fw_go
				dec		a
				ld		(C_fire_delay), a
				ret
fw_go:			ld		e, sound_spell
				call	play_sfx
				ld		a, fire_decay
				ld		(C_weapon_active), a
				ld		a, (C_player_x)
				ld		(C_weapon_x), a
				ld		a, (C_player_y)
				ld		(C_weapon_y), a
				ld		a, (C_fire_direction)
				ld		b, a
				ld		de, 0
				and		1 << player_left_bit
				jp		z, fw_1
				ld		d, -FHS
fw_1:			ld		a, b
				and		1 << player_right_bit
				jp		z, fw_2
				ld		d, FHS
fw_2:			ld		a, b
				and		1 << player_down_bit
				jp		z, fw_3
				ld		e, FVS
fw_3:			ld		a, b
				and		1 << player_up_bit
				jp		z, fw_4
				ld		e, -FVS
fw_4:			ld		a, d
				or		e
				jp		nz, fw_5
				ld		d, FHS
fw_5:			ld		a, d
				ld		(C_weapon_x_inc), a
				ld		a, e
				ld		(C_weapon_y_inc), a
				ret

reset_weapon:	xor		a
				ld		(C_weapon_active), a
				ret

move_weapon:	ld		a, (C_weapon_active)
				or		a
				ret		z
				dec		a
				ld		(C_weapon_active), a
				jp		nz, mw_2
				ld		a, 2
				ld		(C_fire_delay), a
mw_2:			ld		a, (C_weapon_rotates)
				or		a
				jp		z, mw_rot
				ld		a, (C_weapon_x_inc)
				or		a
				jp		z, mw_vert
				cp		FHS
				jp		z, mw_right
				ld		a, (C_weapon_y_inc)		; влево
				or		a
				ld		b, 1 * 4
				jp		z, mw_set
				cp		FVS
				ld		b, 2 * 4
				jp		z, mw_set
				ld		b, 0
				jp		mw_set
mw_vert:		ld		a, (C_weapon_y_inc)
				cp		FVS
				ld		b, 3 * 4
				jp		z, mw_set
				ld		b, 7 * 4
				jp		mw_set
mw_right:		ld		a, (C_weapon_y_inc)
				or		a
				ld		b, 5 * 4
				jp		z, mw_set
				cp		FVS
				ld		b, 4 * 4
				jp		z, mw_set
				ld		b, 6 * 4
				jp		mw_set
mw_rot:			ld		a, (C_weapon_frame)
				inc		a
				and		0x1f
				ld		b, a
mw_set:			ld		a, b
				ld		(C_weapon_frame), a
				ld		a, (C_weapon_x_inc)
				ld		b, a
				ld		a, (C_weapon_x)
				add		a, b
				ld		(C_weapon_x), a
				ld		b, a
				ld		a, (C_weapon_y_inc)
				ld		c, a
				ld		a, (C_weapon_y)
				add		a, c
				ld		(C_weapon_y), a
				ld		c, a
				ld		a, (C_min_x)
				cp		b
				jp		nc, mw_bx				; min_x >= x
				ld		a, (C_max_x)
				cp		b
				jp		nc, mw_cy				; max_x >= x
mw_bx:			ld		d, a
				ld		a, (C_weapon_x_inc)
				cpl
				inc		a
				ld		(C_weapon_x_inc), a
				ld		e, a
				ld		a, d
				ld		(C_weapon_x), a
				ld		a, e
				or		a
				jp		z, mw_cy
				push	bc
				ld		e, sound_spell_bounce
				call	play_sfx
				pop		bc
mw_cy:			ld		a, (C_min_y)
				cp		c
				jp		nc, mw_by
				ld		a, (C_max_y)
				cp		c
				ret		nc
mw_by:			ld		d, a
				ld		a, (C_weapon_y_inc)
				cpl
				inc		a
				ld		(C_weapon_y_inc), a
				ld		a, d
				ld		(C_weapon_y), a
				ld		e, sound_spell_bounce
				jp		play_sfx

; логика draw_weapon: last_drawn_weapon_frame = weapon_type[weapon_frame >> 2]
draw_weapon:	ld		a, (C_weapon_active)
				or		a
				ret		z
				ld		a, (C_weapon_frame)
				rrca
				and		0x7e
				ld		e, a
				ld		d, 0
				ld		hl, (C_weapon_type)
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		(C_last_drawn_weapon_frame), hl
				ret

	MACRO WHIT pobj
				ld		a, (C_weapon_active)
				or		a
				ret		z
				ld		a, (pobj + spr_state)
				cp		state_active
				jp		nz, .next
				ld		a, (pobj + 5)			; ширина
				or		a
				rra
				ld		b, a
				ld		a, (pobj + 0)
				add		a, b
				ld		c, a
				ld		a, (wh_cx)
				ld		d, a
				ld		a, c
				sub		d
				jp		p, .px
				cpl
				inc		a
.px:			ld		c, a
				ld		a, b
				add		a, a
				dec		a
				ld		b, a
				ld		a, c
				cp		b
				jp		nc, .next
				ld		a, (pobj + 6)			; высота
				or		a
				rra
				ld		b, a
				ld		a, (pobj + 1)
				add		a, b
				ld		c, a
				ld		a, (wh_cy)
				ld		d, a
				ld		a, c
				sub		d
				jp		p, .py
				cpl
				inc		a
.py:			ld		c, a
				ld		a, b
				add		a, a
				dec		a
				ld		b, a
				ld		a, c
				cp		b
				jp		nc, .next
				ld		hl, pobj
				call	kill_sprite
				ld		a, 1
				ld		(C_weapon_active), a
.next:
	ENDM

; попадание по sprite1..3: рамка оружия (кадр last_drawn_weapon_frame) против середин врагов
check_weapon_hit:
				ld		hl, (C_last_drawn_weapon_frame)
				ld		a, (hl)
				or		a
				rra
				ld		(wh_w2), a				; ширина / 2
				inc		hl
				ld		a, (hl)
				or		a
				rra
				ld		(wh_h2), a
				inc		hl
				ld		a, (C_weapon_x)
				add		a, (hl)
				ld		b, a
				ld		a, (wh_w2)
				add		a, b
				ld		(wh_cx), a				; c для x
				inc		hl
				ld		a, (C_weapon_y)
				add		a, (hl)
				ld		b, a
				ld		a, (wh_h2)
				add		a, b
				ld		(wh_cy), a
				WHIT	C_sprite1
				WHIT	C_sprite2
				WHIT	C_sprite3
				ret
wh_w2:			DB		0
wh_h2:			DB		0
wh_cx:			DB		0
wh_cy:			DB		0

