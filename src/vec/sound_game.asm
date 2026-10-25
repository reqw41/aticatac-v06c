; sound_game.asm: запросы звуков и случайность для игры (в сверке — src/i8080/sound.asm).

; вместо ld a,r CPC: таймер ВИ53 (счётчик 0) + своё накопление. Портит только A.
ldar:			push	hl
				xor		a
				out		(0x08), a				; защёлкнуть счётчик 0
				in		a, (0x0B)
				ld		l, a
				in		a, (0x0B)
				xor		l
				ld		hl, rnd_mix
				add		a, (hl)
				ld		(hl), a
				pop		hl
				ret
rnd_mix:		DB		0x5a

; E = эффект (звука пока нет — только защита от «шагов»)
play_sfx:		ld		a, sound_persist_time
				ld		(C_sound_guard), a
				ld		a, e
				ld		(last_sfx), a
				ret
play_lowpriority_sfx:
				ret
last_sfx:		DB		0
