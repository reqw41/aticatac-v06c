; chicken.asm: здоровье, курица на панели, смерть (= src/model/chicken.js).

init_health:	ld		a, max_health
				ld		(C_health), a
				ld		a, max_health / 4
				ld		(C_drawn_health), a
				ret
health_decay:	ld		a, (C_health)
				or		a
				ret		z
				dec		a
				ld		(C_health), a
				ret
health_down:	ld		a, (C_health)
				or		a
				ret		z
				sub		8
				jp		nc, hd_1
				xor		a
hd_1:			ld		(C_health), a
				ret
health_up:		ld		a, (C_health)
				add		a, 16
				cp		max_health
				jp		c, hu_1
				ld		a, max_health
hu_1:			ld		(C_health), a
				ret

update_chicken:	ld		a, (C_health)
				rrca
				rrca
				and		0x3f
				ld		b, a
				ld		a, (C_drawn_health)
				cp		b
				ret		z
				jp		nc, uc_down
				inc		a
				ld		(C_drawn_health), a
				ret
uc_down:		dec		a
				ld		(C_drawn_health), a
				or		a
				ret		nz
				call	decrease_lives
				ld		a, (C_game_over)
				or		a
				ret		nz
				jp		make_player_disappear
