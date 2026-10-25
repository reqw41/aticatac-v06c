; boss.asm: боссы — выбор по комнате и движение (= src/model/boss.js). Босс — всегда структура boss.

BS				equ		C_boss

init_boss:		ld		a, (C_room_number)
				cp		room_frankenstein
				jp		z, ib_frank
				ld		hl, C_mummy_room
				cp		(hl)
				jp		z, ib_mummy
				cp		room_hunchback
				jp		z, ib_hunch
				cp		room_devil
				jp		z, ib_devil
				ld		hl, C_dracula_room
				cp		(hl)
				jp		z, ib_drac
				ld		a, state_dead
				ld		(BS + spr_state), a
				ret
ib_common:		ld		a, state_active			; DE = описание босса
				ld		(BS + spr_state), a
				ld		hl, 14
				add		hl, de
				ld		a, (hl)
				ld		(BS + spr_x), a
				inc		hl
				ld		a, (hl)
				ld		(BS + spr_y), a
				ld		hl, BS
				jp		init_sprite
ib_frank:		ld		a, (C_frank_dead)
				or		a
				ret		nz
				ld		hl, C_move_devil_and_frank
				ld		(C_boss_mover), hl
				ld		de, C_boss_frankie
				jp		ib_common
ib_drac:		ld		hl, C_move_dracula
				ld		(C_boss_mover), hl
				ld		de, C_boss_dracula
				jp		ib_common
ib_mummy:		ld		hl, C_move_mummy
				ld		(C_boss_mover), hl
				ld		de, C_boss_mummy
				call	ib_common
				ld		a, (C_mummy_angry)
				or		a
				ret		nz
				ld		a, 1
				ld		(C_mummy_inc), a
				ld		a, mummy_count_max / 2
				ld		(C_mummy_count), a
				ret
ib_hunch:		ld		hl, C_move_hunchback
				ld		(C_boss_mover), hl
				ld		de, C_boss_hunchback
				jp		ib_common
ib_devil:		ld		hl, C_move_devil_and_frank
				ld		(C_boss_mover), hl
				xor		a
				ld		(C_boss_timer), a
				ld		de, C_boss_devil
				jp		ib_common

	MACRO JPIF16 val, target
				ld		a, l
				cp		low val
				jp		nz, .no
				ld		a, h
				cp		high val
				jp		z, target
.no:
	ENDM

; boss_mover хранит адрес процедуры CPC — здесь он служит номером
update_boss:	ld		hl, (C_boss_mover)
				JPIF16	C_move_dracula, move_dracula
				JPIF16	C_move_mummy, move_mummy
				JPIF16	C_move_hunchback, move_hunchback
				JPIF16	C_move_devil_and_frank, move_devil_and_frank
				JPIF16	C_move_frankie, boss_anim
				ret

boss_anim:		ld		a, (BS + spr_frame)
				inc		a
				and		0x0f
				ld		(BS + spr_frame), a
				ret

; A = цель, B = позиция -> A = 0 / -1 / 1
toward:			cp		b
				ld		a, 0
				ret		z
				ld		a, 0xff
				ret		c
				ld		a, 1
				ret

move_dracula:	ld		a, (C_dracula_timer)
				inc		a
				ld		(C_dracula_timer), a
				cp		2
				ret		nz
				xor		a
				ld		(C_dracula_timer), a
				ld		de, 0xff01
				ld		a, (C_player_growing)
				or		a
				jp		nz, within_bounds
				ld		a, (C_pocket1 + 1)
				cp		crucifix
				jp		z, md_avoid
				ld		a, (C_pocket1)
				cp		crucifix
				jp		z, md_avoid
				ld		a, (C_pocket3)
				cp		crucifix
				jp		nz, normal_move_towards
md_avoid:		ld		a, (BS + spr_x)
				ld		b, a
				ld		a, (C_player_x)
				cp		b
				ld		d, 1
				jp		c, md_y
				ld		d, 0xff
md_y:			ld		a, (BS + spr_y)
				ld		b, a
				ld		a, (C_player_y)
				cp		b
				ld		e, 1
				jp		c, within_bounds
				ld		e, 0xff
				jp		within_bounds

move_mummy:		ld		a, (C_heartbeat)
				and		1
				ret		z
				ld		a, (C_mummy_angry)
				or		a
				jp		nz, mm_mad
				ld		a, (C_room_number)
				ld		b, a
				ld		a, (C_col_leaf)
				cp		b
				jp		nz, mm_bounce
				ld		a, 1
				ld		(C_mummy_angry), a
				ret
mm_bounce:		ld		a, (C_mummy_inc)
				ld		b, a
				ld		a, (BS + spr_x)
				add		a, b
				ld		(BS + spr_x), a
				ld		a, (BS + spr_y)
				add		a, b
				ld		(BS + spr_y), a
				ld		a, (C_mummy_count)
				inc		a
				ld		(C_mummy_count), a
				cp		mummy_count_max
				jp		nz, boss_anim
				ld		a, b
				cpl
				inc		a
				ld		(C_mummy_inc), a
				xor		a
				ld		(C_mummy_count), a
				jp		boss_anim
mm_mad:			ld		a, (C_room_number)
				ld		b, a
				ld		a, (C_col_leaf)
				cp		b
				jp		nz, devil_frank_mummy
				ld		a, (BS + spr_x)
				ld		b, a
				ld		a, (C_col_leaf + 3)
				add		a, a
				call	toward
				ld		d, a
				ld		a, (BS + spr_y)
				ld		b, a
				ld		a, (C_col_leaf + 4)
				call	toward
				ld		e, a
				ld		a, (BS + spr_x)
				add		a, d
				ld		(BS + spr_x), a
				ld		a, (BS + spr_y)
				add		a, e
				ld		(BS + spr_y), a
				call	boss_anim
				ld		a, d
				or		e
				ret		nz
				ld		a, 0x6b					; лист съеден — в другую комнату
				ld		(C_col_leaf), a
				ret

move_hunchback:	ld		a, (C_boss_timer)
				inc		a
				and		3
				ld		(C_boss_timer), a
				ret		nz
				ld		hl, 0
				ld		(mh_iy), hl
				ld		bc, 0x2c20
				ld		a, (C_player_growing)
				or		a
				jp		nz, mh_aim
				ld		a, (C_room_number)
				ld		c, a
				ld		hl, C_col_money
				ld		b, 10
mh_l:			ld		a, b
				cp		5
				jp		z, mh_skip
				cp		8
				jp		z, mh_skip
				ld		a, (hl)
				cp		c
				jp		z, mh_found
mh_skip:		ld		de, 8
				add		hl, de
				dec		b
				jp		nz, mh_l
				ret
mh_found:		ld		(mh_iy), hl
				inc		hl
				inc		hl
				inc		hl
				ld		a, (hl)
				add		a, a
				ld		b, a
				inc		hl
				ld		c, (hl)
mh_aim:			push	bc
				ld		a, (BS + spr_x)
				ld		c, a
				ld		a, b
				ld		b, c
				call	toward
				ld		d, a
				pop		bc
				ld		a, (BS + spr_y)
				ld		b, a
				ld		a, c
				call	toward
				ld		e, a
				ld		a, (BS + spr_x)
				add		a, d
				ld		(BS + spr_x), a
				ld		(C_boss_hunchback + 14), a
				ld		a, (BS + spr_y)
				add		a, e
				ld		(BS + spr_y), a
				ld		(C_boss_hunchback + 15), a
				ld		a, d
				or		e
				jp		nz, boss_anim
				ld		hl, (mh_iy)
				ld		a, h
				or		l
				ret		z
				ld		(hl), 0xfe				; предмет унесён
				ret
mh_iy:			DW		0

move_devil_and_frank:
				ld		a, (C_boss_timer)
				inc		a
				and		3
				ld		(C_boss_timer), a
				ret		nz
devil_frank_mummy:
				ld		de, 0xff01
				ld		a, (C_player_growing)
				or		a
				jp		nz, within_bounds
normal_move_towards:
				ld		a, (BS + spr_x)
				ld		b, a
				ld		a, (C_player_x)
				call	toward
				ld		d, a
				ld		a, (BS + spr_y)
				ld		b, a
				ld		a, (C_player_y)
				call	toward
				ld		e, a
; D, E = шаг; в пределах [min, min+1) по каждой оси
within_bounds:	ld		a, (C_min_x)
				ld		c, a
				ld		a, (C_min_x + 1)
				ld		b, a
				ld		a, (BS + spr_x)
				add		a, d
				cp		c
				jp		c, wb_y
				cp		b
				jp		nc, wb_y
				ld		(BS + spr_x), a
wb_y:			ld		a, (C_min_y)
				ld		c, a
				ld		a, (C_min_y + 1)
				ld		b, a
				ld		a, (BS + spr_y)
				add		a, e
				cp		c
				jp		c, boss_anim
				cp		b
				jp		nc, boss_anim
				ld		(BS + spr_y), a
				jp		boss_anim

try_teleport_dracula:
				call	random
				and		0x7f
				ret		z
				ld		c, a
				ld		l, a
				ld		h, 0
				ld		de, C_room_bank_roominfo + 1
				add		hl, de
				ld		a, (hl)
				cp		3
				ret		z
				ld		a, c
				ld		(C_dracula_room), a
				ret
