; sound_game.asm: звук игры и случайность (в сверке логики — src/i8080/sound.asm).
; Звук — проигрыватель Arkos akg80 (src/vec/akg80.tpl, перенос PlayerAkg CPC на i8080, сверка с CPC —
; tools/akg80check.js) и данные CPC в квазидиске стр. 0 с 0xA000, в прерывании кадра — через окно (snd_tick).
; Есть AY (порты 0x15 — регистр, 0x14 — данные) — регистры с периодами x1,75; нет — тон двух самых громких
; каналов на счётчики 1 и 2 ВИ53 (счётчик 0 — часы кадра).

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

; E = эффект 1..12 (play_sfx CPC): защита от «шагов», запуск потока
play_sfx:		ld		a, sound_persist_time
				ld		(C_sound_guard), a
				ld		a, e
				ld		(last_sfx), a
				add		a, SND_SFX1 - 1
				jp		snd_play
play_lowpriority_sfx:
				ld		a, (C_sound_guard)
				or		a
				ret		nz
				ld		a, e
				add		a, SND_SFX1 - 1
				jp		snd_play
last_sfx:		DB		0

; номера звуков для snd_play: мелодии (подпесни atic_tunes CPC 0, 1, 2, 4) и эффекты 1..12
SND_MENU		equ		0
SND_START		equ		1
SND_OVER		equ		2
SND_DONE		equ		3
SND_SFX1		equ		4
SND_WIN			equ		0x20					; порт 0x10: окно квазидиска стр. 0 на 0xA000..0xDFFF (плеер akg80)
; A = звук SND_* — запрос; подхватывает прерывание (snd_tick): номер, потом флаг — запись байта неделима,
; состояние прерываний не трогается
snd_play:		cp		SND_SFX1				; ВИ53: порог громкости и шум — у музыки и эффектов свои
				ld		hl, VI_THR_SFX
				jp		nc, sp_sfx
				ld		hl, VI_THR_MUS | 0x100	; H = 1 — музыка (шум не играть)
sp_sfx:			ld		(vi_thr), hl
snd_req_a:		ld		(snd_req), a
				ld		a, 1
				ld		(snd_reqf), a
				ret
; тишина: пустая песня (NoMusic CPC — в игре музыки нет, только эффекты)
snd_stop:		ld		a, 0xff
				jp		snd_req_a
; заглушить: AY — громкости 0; ВИ53 — счётчики 1 и 2 в режиме 3 с делителем 2 (750 кГц не слышно, а средний
; уровень тот же, что у ноты: без скачка-щелчка; режим 3 дальше не меняется — пишется только делитель)
snd_mute:		ld		a, (snd_ay)
				or		a
				jp		z, sm_vi
				ld		b, 8
sm_l:			ld		a, b
				out		(0x15), a
				xor		a
				out		(0x14), a
				inc		b
				ld		a, b
				cp		11
				jp		nz, sm_l
				ret
sm_vi:			ld		a, 0x76
				out		(0x08), a
				ld		a, 2
				out		(0x0A), a
				xor		a
				out		(0x0A), a
				ld		a, 0xb6
				out		(0x08), a
				ld		a, 2
				out		(0x09), a
				xor		a
				out		(0x09), a
				ld		hl, 0
				ld		(snd_d1), hl
				ld		(snd_d2), hl
				ret

; есть ли AY: записать и прочитать регистр 2 (без AY порт читается 0xFF)
ay_detect:
	IFDEF NOAY
				jp		ad_no					; сборка «только ВИ53» (SJFLAGS=-DNOAY)
	ENDIF
				ld		a, 2
				out		(0x15), a
				ld		a, 0x5a
				out		(0x14), a
				in		a, (0x14)
				cp		0x5a
				jp		nz, ad_no
				ld		a, 0xa5
				out		(0x14), a
				in		a, (0x14)
				cp		0xa5
				jp		nz, ad_no
				ld		a, 1
				ld		(snd_ay), a
				ret
ad_no:			xor		a
				ld		(snd_ay), a
				ret

; ---- кадр звука (из прерывания, DI): запрос, плеер akg80 (окно квазидиска), периоды x1,75 (AY Вектора 1,75 МГц,
;      CPC — 1 МГц), изменившиеся регистры -> AY или ВИ53 ----
snd_tick:		ld		a, SND_WIN
				out		(0x10), a
				ld		a, (snd_reqf)
				or		a
				jp		z, st_play
				xor		a
				ld		(snd_reqf), a
				ld		a, (snd_req)
				cp		0xff
				jp		z, st_stop
				cp		SND_SFX1
				jp		nc, st_sfx
				ld		e, a					; мелодия: подпесня
				ld		d, 0
				ld		hl, st_subs
				add		hl, de
				ld		a, (hl)
				ld		hl, AKG_ATIC_START
				jp		st_init
st_stop:		ld		a, 1					; пустая песня — akg_quiet
				ld		(snd_quiet), a
				ld		hl, AKG_NOMUSIC_START
				xor		a
				jp		st_init0
st_init:		push	af
				xor		a
				ld		(snd_quiet), a
				pop		af
st_init0:		call	akg_init
				ld		hl, AKG_SOUNDEFFECTS
				call	akg_initsfx
				jp		st_play
st_sfx:			sub		SND_SFX1 - 1			; эффект на канале 1 (B), громкость полная — как play_sfx CPC
				ld		bc, 0x0001
				call	akg_playsfx
st_play:		ld		a, (snd_quiet)
				or		a
				jp		z, st_full
				call	akg_quiet				; A = R7
				jp		st_r7
st_full:		call	akg_play				; A = R7
st_r7:
				and		0x3f
				ld		(snd_new + 7), a
				ld		hl, akg_regs
				ld		de, snd_new
				ld		c, 7
st_cp:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, st_cp
				inc		hl
				inc		de
				ld		c, 3
st_cp2:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		c
				jp		nz, st_cp2
				xor		a
				out		(0x10), a				; окно закрыто
				ld		hl, snd_new				; периоды: (P * 7 + 2) / 4
				ld		b, 3
st_sc:			push	hl
				ld		e, (hl)
				inc		hl
				ld		a, (hl)
				and		0x0f
				ld		d, a
				ld		h, d
				ld		l, e
				add		hl, hl
				add		hl, hl
				add		hl, hl
				ld		a, l
				sub		e
				ld		l, a
				ld		a, h
				sbc		a, d
				ld		h, a					; * 7
				inc		hl
				inc		hl
				ld		a, h					; / 4
				or		a
				rra
				ld		h, a
				ld		a, l
				rra
				ld		l, a
				ld		a, h
				or		a
				rra
				ld		h, a
				ld		a, l
				rra
				ld		l, a
				ld		a, h
				cp		0x10
				jp		c, st_sc1
				ld		hl, 0x0fff
st_sc1:			ex		de, hl
				pop		hl
				ld		(hl), e
				inc		hl
				ld		(hl), d
				inc		hl
				dec		b
				jp		nz, st_sc
				ld		a, (hl)					; шум R6: (n * 7 + 2) / 4, не больше 31
				and		0x1f
				ld		b, a
				add		a, a
				add		a, a
				add		a, a
				sub		b
				add		a, 2
				rra
				and		0x7f
				rra
				and		0x3f
				cp		32
				jp		c, st_n1
				ld		a, 31
st_n1:			ld		(hl), a
				ld		hl, snd_new				; изменившиеся -> snd_st, AY
				ld		de, snd_st
				ld		c, 0
st_o:			ld		a, (de)
				cp		(hl)
				jp		z, st_o1
				ld		a, (hl)
				ld		(de), a
				ld		a, (snd_ay)
				or		a
				jp		z, st_o1
				ld		a, c
				out		(0x15), a
				ld		a, (hl)
				out		(0x14), a
st_o1:			inc		hl
				inc		de
				inc		c
				ld		a, c
				cp		11
				jp		nz, st_o
				ld		a, (snd_ay)
				or		a
				ret		nz
				jp		vi_update
st_subs:		DB		0, 1, 2, 4				; подпесни atic_tunes: меню, старт, конец игры, победа
snd_new:		DS		11

; ---- без AY: два самых громких звучащих канала -> счётчики 1 (порт 0x0A) и 2 (0x09) ВИ53, режим 3.
; Делитель ВИ53 (1,5 МГц) по периоду AY Вектора (1,75 МГц): D = P * 13,71 ~ P * 14 - P / 4; шум — случайный.
vi_update:		ld		hl, 0					; H — громкость лучшего, L — канал; D/E — второй
				ld		de, 0
				ld		c, 0
vu_l:			ld		a, c
				add		a, low (snd_st + 8)
				ld		l, a
				ld		a, high (snd_st + 8)
				adc		a, 0
				ld		h, a
				ld		a, (hl)
				and		0x1f
				cp		16
				jp		c, vu_v
				ld		a, 15					; огибающая — как громкая
vu_v:			ld		e, a					; громкости у ВИ53 нет: нота звучит, пока громкость не ниже
				ld		hl, vu_pv				; половины её пика (пик — при росте громкости: новая нота),
				ld		a, l					; затухающий хвост молчит
				add		a, c
				ld		l, a
				ld		a, h
				adc		a, 0
				ld		h, a
				ld		a, (hl)
				ld		(hl), e
				inc		hl
				inc		hl
				inc		hl						; -> vu_pk[канал]
				cp		e
				jp		nc, vu_nd
				ld		(hl), e
vu_nd:			ld		a, (hl)
				inc		a
				or		a
				rra								; (пик + 1) / 2
				dec		a
				cp		e
				jp		nc, vu_next
				ld		a, e
				ld		hl, vi_thr				; и не тише порога
				cp		(hl)
				jp		c, vu_next
				ld		b, a
				ld		a, (snd_st + 7)			; звучит: тон или шум разрешён
				push	bc
vu_s:			dec		c
				jp		m, vu_s1
				rrca
				jp		vu_s
vu_s1:			pop		bc
				and		0x09
				cp		0x09
				jp		z, vu_next				; оба запрещены
				cp		0x01
				jp		nz, vu_tn
				ld		a, (vi_mus)				; только шум: в музыке не играть
				or		a
				jp		nz, vu_next
vu_tn:
				ld		a, b
				or		a
				jp		z, vu_next
				ld		a, (vu_v1)				; лучший?
				cp		b
				jp		nc, vu_2
				ld		a, (vu_v1)				; прежний лучший — во второй
				ld		(vu_v2), a
				ld		a, (vu_c1)
				ld		(vu_c2), a
				ld		a, b
				ld		(vu_v1), a
				ld		a, c
				ld		(vu_c1), a
				jp		vu_next
vu_2:			ld		a, (vu_v2)
				cp		b
				jp		nc, vu_next
				ld		a, b
				ld		(vu_v2), a
				ld		a, c
				ld		(vu_c2), a
vu_next:		inc		c
				ld		a, c
				cp		3
				jp		nz, vu_l
				ld		a, (vu_v1)				; голос держится на своём счётчике: был на втором — туда же
				or		a
				jp		z, vu_s2
				ld		a, (vu_c1)
				ld		hl, vu_p2
				cp		(hl)
				jp		z, vu_sw
vu_s2:			ld		a, (vu_v2)
				or		a
				jp		z, vu_ns
				ld		a, (vu_c2)
				ld		hl, vu_p1
				cp		(hl)
				jp		nz, vu_ns
vu_sw:			ld		hl, (vu_v1)				; обмен (громкость, канал) первого и второго
				ex		de, hl
				ld		hl, (vu_v2)
				ld		(vu_v1), hl
				ex		de, hl
				ld		(vu_v2), hl
vu_ns:			ld		a, (vu_v1)				; запомнить каналы на счётчиках (0xFF — молчит)
				or		a
				ld		a, (vu_c1)
				jp		nz, vu_k1
				ld		a, 0xff
vu_k1:			ld		(vu_p1), a
				ld		a, (vu_v2)
				or		a
				ld		a, (vu_c2)
				jp		nz, vu_k2
				ld		a, 0xff
vu_k2:			ld		(vu_p2), a
				ld		a, (vu_v1)
				ld		b, a
				ld		a, (vu_c1)
				ld		hl, snd_d1
				ld		e, 0x76					; счётчик 1, режим 3
				ld		d, 0x0A
				call	vu_chan
				ld		a, (vu_v2)
				ld		b, a
				ld		a, (vu_c2)
				ld		hl, snd_d2
				ld		e, 0xb6					; счётчик 2, режим 3
				ld		d, 0x09
				call	vu_chan
				xor		a
				ld		(vu_v1), a
				ld		(vu_v2), a
				ret
; B = громкость (0 — тишина), A = канал AY, HL -> прежний делитель, E = управляющее слово, D = порт счётчика
vu_chan:		push	hl
				ld		c, a
				ld		a, b
				or		a
				jp		z, vu_off
				ld		a, (snd_st + 7)
				push	bc
vu_t:			dec		c
				jp		m, vu_t1
				rrca
				jp		vu_t
vu_t1:			pop		bc
				and		1
				jp		z, vu_tone
				call	ldar					; только шум: случайный делитель 256..2303
				and		7
				ld		h, a
				call	ldar
				ld		l, a
				inc		h
				jp		vu_set
vu_tone:		ld		a, c					; период тона канала C
				add		a, a
				add		a, low snd_st
				ld		l, a
				ld		a, high snd_st
				adc		a, 0
				ld		h, a
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ld		a, h
				and		0x0f
				ld		h, a
				ld		b, h					; D = P * 14 - P / 4
				ld		c, l
				add		hl, hl					; 2P
				add		hl, bc					; 3P
				add		hl, hl					; 6P
				add		hl, bc					; 7P
				add		hl, hl					; 14P
				push	hl
				ld		a, b
				or		a
				rra
				ld		b, a
				ld		a, c
				rra
				ld		c, a
				ld		a, b
				or		a
				rra
				ld		b, a
				ld		a, c
				rra
				ld		c, a					; P / 4
				pop		hl
				ld		a, l
				sub		c
				ld		l, a
				ld		a, h
				sbc		a, b
				ld		h, a
vu_set:			ex		de, hl					; DE = делитель, HL = управляющее/порт
				ex		(sp), hl				; HL -> прежний, на стеке управляющее/порт
				ld		a, (hl)
				cp		e
				jp		nz, vu_new
				inc		hl
				ld		a, (hl)
				cp		d
				jp		z, vu_same
				dec		hl
vu_new:			ld		(hl), e
				inc		hl
				ld		(hl), d
				pop		hl						; H = порт (режим 3 уже стоит — только делитель)
vu_out:			ld		a, h
				cp		0x0A
				ld		a, e
				jp		nz, vu_p9
				out		(0x0A), a
				ld		a, d
				out		(0x0A), a
				ret
vu_p9:			out		(0x09), a
				ld		a, d
				out		(0x09), a
				ret
vu_same:		pop		hl
				ret
vu_off:			pop		hl						; тишина: делитель 2 (см. snd_mute)
				ld		a, (hl)
				inc		hl
				or		(hl)
				ret		z
				ld		(hl), 0
				dec		hl
				ld		(hl), 0
				ld		e, 2
				ld		a, d
				ld		d, 0
				ld		h, a
				jp		vu_out


snd_req:		DB		0						; запрос из основного кода (snd_play / snd_stop)
snd_quiet:		DB		0						; 1 — пустая песня: только эффекты (akg_quiet)
snd_reqf:		DB		0
snd_ay:			DB		0						; 1 — есть AY
snd_d1:			DW		0						; делители ВИ53 на счётчиках 1 и 2 (0 — тишина)
snd_d2:			DW		0
VI_THR_MUS		equ		3						; наименьшая громкость на ВИ53: музыка
VI_THR_SFX		equ		2						; эффекты
vu_pv:			DS		3						; громкость каналов AY в прошлом кадре
vu_pk:			DS		3						; пик текущей ноты
vi_thr:			DB		VI_THR_SFX
vi_mus:			DB		0						; 1 — музыка: шумовые голоса молчат
vu_v1:			DB		0						; vu_v1/vu_c1 и vu_v2/vu_c2 — пары (обмен словом)
vu_c1:			DB		0
vu_v2:			DB		0
vu_c2:			DB		0
vu_p1:			DB		0xff					; канал AY на счётчике 1 / 2 в прошлом кадре
vu_p2:			DB		0xff
snd_st:			DS		14						; состояние регистров AY
