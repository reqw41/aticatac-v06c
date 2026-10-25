; sound.asm: запросы звуков (на время сверки — журнал sfx_buf; в игре — свой плеер).

; ld a,r CPC: случайное число (на сверке — из очереди r_buf). Портит только A.
ldar:			push	hl
				ld		hl, r_idx
				ld		a, (hl)
				inc		(hl)
				ld		l, a
				ld		h, high r_buf
				ld		a, (hl)
				pop		hl
				ret

; E = эффект. Портит A, HL.
play_sfx:		ld		a, S_PERSIST
				ld		(C_sound_guard), a
				jp		sfx_put
S_PERSIST		equ		sound_persist_time
play_lowpriority_sfx:
				ld		a, (C_sound_guard)
				or		a
				ret		nz
sfx_put:		ld		hl, sfx_n
				ld		a, (hl)
				inc		(hl)
				add		a, low sfx_buf
				ld		l, a
				ld		h, high sfx_buf
				ld		(hl), e
				ret
