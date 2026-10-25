; util.asm: RANDOM_IN_A (macros.asm CPC) и счёт (score.asm).

; random_seed = f(random_seed) -> A; портит B (как в оригинале)
random:			ld		a, (C_random_seed)
				ld		b, a
				rrca
				rrca
				rrca
				xor		0x1f
				add		a, b
				sbc		a, 0xff
				ld		(C_random_seed), a
				ret

; BC = добавка (BCD) -> score и score_text. Портит A, B, DE, HL.
add_to_score:	ld		hl, C_score + 2
				ld		a, (hl)
				add		a, c
				daa
				ld		(hl), a
				dec		hl
				ld		a, (hl)
				adc		a, b
				daa
				ld		(hl), a
				dec		hl
				ld		a, (hl)
				adc		a, 0
				daa
				ld		(hl), a
				ld		de, C_score_text + 3
				ld		b, 3
as_l:			ld		a, (hl)
				rrca
				rrca
				rrca
				rrca
				and		0x0f
				add		a, '0'
				ld		(de), a
				inc		de
				ld		a, (hl)
				and		0x0f
				add		a, '0'
				ld		(de), a
				inc		de
				inc		hl
				dec		b
				jp		nz, as_l
				ret
