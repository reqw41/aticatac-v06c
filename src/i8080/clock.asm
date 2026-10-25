; clock.asm: часы (= src/model/clock.js; часы обновляет прерывание).
show_clock:		xor		a
				ld		(C_tell_time), a
				ld		a, (C_second_only)
				or		a
				ret		z
				ld		a, (C_game_time + 5)
				ld		(C_seconds_time), a
				ret
reset_clock:	ld		a, '0'
				ld		(C_game_time), a
				ld		(C_game_time + 1), a
				ld		(C_game_time + 2), a
				ld		(C_game_time + 4), a
				ld		(C_game_time + 5), a
				ld		a, 1
				ld		(C_tell_time), a
				ret
