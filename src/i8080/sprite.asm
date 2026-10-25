; sprite.asm: враги и босс — состояния, движение, рождение и смерть (= src/model/sprite.js).
; Обновление — код на каждый экземпляр (адреса полей — константы): у 8080 нет индексной адресации.

ST_X			equ		spr_x
ST_Y			equ		spr_y

	MACRO USPR pobj
				ld		a, (pobj + spr_state)
				cp		state_dead
				jp		z, .dead
				cp		state_arriving
				jp		z, .arriving
				cp		state_dying
				jp		z, .dying
				ld		a, (pobj + spr_boss)
				or		a
				ld		hl, pobj
				jp		nz, update_boss
				ld		hl, pobj + spr_counter
				dec		(hl)
				ld		hl, pobj
				jp		z, random_sprite_action
				ld		a, (C_heartbeat)
				and		1
				ret		z
				ld		a, (pobj + spr_xinc)
				ld		b, a
				ld		a, (pobj + spr_x)
				add		a, b
				ld		(pobj + spr_x), a
				ld		b, a
				ld		a, (C_min_x)
				cp		b
				jp		nc, .bx
				ld		a, (C_max_x)
				cp		b
				jp		nc, .cy
.bx:			ld		d, a
				ld		a, (pobj + spr_xinc)
				cpl
				inc		a
				ld		(pobj + spr_xinc), a
				ld		a, d
				ld		(pobj + spr_x), a
.cy:			ld		a, (pobj + spr_yinc)
				ld		b, a
				ld		a, (pobj + spr_y)
				add		a, b
				ld		(pobj + spr_y), a
				ld		b, a
				ld		a, (C_min_y)
				cp		b
				jp		nc, .by
				ld		a, (C_max_y)
				cp		b
				jp		nc, .anim
.by:			ld		d, a
				ld		a, (pobj + spr_yinc)
				cpl
				inc		a
				ld		(pobj + spr_yinc), a
				ld		a, d
				ld		(pobj + spr_y), a
.anim:			ld		a, (pobj + spr_frame)
				inc		a
				and		0x0f
				ld		(pobj + spr_frame), a
				ret
.dead:			ld		a, (pobj + spr_boss)
				or		a
				ret		nz
				ld		a, (C_player_growing)
				or		a
				ret		nz
				ld		hl, pobj + spr_counter
				dec		(hl)
				ret		nz
				ld		a, state_arriving
				ld		(pobj + spr_state), a
				ld		a, arrival_time
				ld		(pobj + spr_counter), a
				ld		a, (C_min_x)
				ld		e, a
				ld		a, (C_max_x)
				sub		6
				sub		e
				ld		c, a
				call	random
				REPT	4
				cp		c
				jp		c, .rx
				or		a
				rra
				ENDR
.rx:			add		a, e
				ld		(pobj + spr_x), a
				ld		a, (C_min_y)
				ld		e, a
				ld		a, (C_max_y)
				sub		24
				sub		e
				ld		c, a
				call	random
				REPT	3
				cp		c
				jp		c, .ry
				or		a
				rra
				ENDR
.ry:			add		a, e
				ld		(pobj + spr_y), a
				ld		hl, pobj
				ld		de, C_sprite_birth
				jp		init_sprite
.arriving:		ld		hl, pobj + spr_counter
				dec		(hl)
				jp		nz, .anim
				ld		a, state_active
				ld		(pobj + spr_state), a
				call	random
				and		0x0f
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, C_sprite_info
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				push	de
				ld		hl, pobj
				call	random_sprite_action
				pop		de
				ld		hl, pobj
				jp		init_sprite
.dying:			ld		hl, pobj + spr_counter
				dec		(hl)
				jp		nz, .anim
				ld		a, state_dead
				ld		(pobj + spr_state), a
				call	random
				and		0x0f
				add		a, 10
				ld		(pobj + spr_counter), a
				ret
	ENDM

; HL = структура (boss, sprite1..3) -> код экземпляра
update_sprite:	ld		a, l
				cp		low C_boss
				jp		z, us_boss
				cp		low C_sprite1
				jp		z, us_spr1
				cp		low C_sprite2
				jp		z, us_spr2
				jp		us_spr3
				ASSERT	high C_boss == high C_sprite3
us_boss:		USPR	C_boss
us_spr1:		USPR	C_sprite1
us_spr2:		USPR	C_sprite2
us_spr3:		USPR	C_sprite3

; HL = структура: счётчик (ld a,r & 0x3f) + 20, направление — случайное из sprite_direction_table
random_sprite_action:
				push	hl
				call	ldar
				and		0x3f
				add		a, 20
				ld		de, spr_counter
				add		hl, de
				ld		(hl), a
				call	random
				and		7
				add		a, a
				ld		e, a
				ld		d, 0
				ld		hl, C_sprite_direction_table
				add		hl, de
				ld		a, (hl)
				inc		hl
				ld		e, (hl)
				pop		hl
				inc		hl
				inc		hl
				ld		(hl), a					; xinc
				inc		hl
				ld		(hl), e					; yinc
				ret

; HL = структура, DE = описание вида (ширина, высота, alt, fdom, кадры)
init_sprite:	push	hl
				push	de
				ld		bc, spr_frame
				add		hl, bc
				ld		(hl), 0
				pop		de
				pop		hl
				push	hl
				inc		hl
				inc		hl
				inc		hl
				inc		hl
				inc		hl						; +5 ширина
				ld		a, (de)
				ld		(hl), a
				inc		hl
				inc		de
				ld		a, (de)					; +6 высота
				ld		(hl), a
				inc		de
				pop		hl
				push	hl
				ld		bc, spr_alt
				add		hl, bc
				ld		a, (de)
				ld		(hl), a
				inc		hl
				inc		de
				ld		a, (de)
				ld		(hl), a
				inc		de
				ld		a, (de)					; fdom
				inc		de						; DE = iy + 5
				inc		hl
				ld		(hl), a					; +21
				pop		hl
				ld		bc, spr_gfx
				add		hl, bc
				ld		(hl), e
				inc		hl
				ld		(hl), d
				ret

; HL = структура: умирает (кадры смерти), звук, +155 очков
kill_sprite:	push	hl
				ld		de, spr_state
				add		hl, de
				ld		(hl), state_dying
				pop		hl
				push	hl
				ld		de, spr_counter
				add		hl, de
				ld		(hl), dying_time
				pop		hl
				ld		de, C_sprite_death
				call	init_sprite
				ld		a, (C_enemy_kill_sfx)
				inc		a
				cp		sound_clock
				jp		nz, ks_2
				ld		a, sound_thunder_1
ks_2:			ld		(C_enemy_kill_sfx), a
				ld		e, a
				call	play_sfx
				ld		bc, 0x155
				jp		add_to_score

reset_sprites:	ld		a, state_dead
				ld		(C_boss + spr_state), a
				ld		(C_sprite1 + spr_state), a
				ld		(C_sprite2 + spr_state), a
				ld		(C_sprite3 + spr_state), a
				call	random
				and		0x3f
				add		a, 5
				ld		(C_sprite1 + spr_counter), a
				call	random
				and		0x3f
				add		a, 5
				ld		(C_sprite2 + spr_counter), a
				call	random
				and		0x3f
				add		a, 5
				ld		(C_sprite3 + spr_counter), a
				ret

