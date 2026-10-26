; sound_game.asm: звук игры и случайность (в сверке логики — src/i8080/sound.asm).
; Звук — записи регистров AY с модели CPC (tools/cpcsound.js, tools/mksound.py: потоки в квазидиске стр. 0,
; snd_tab). Проигрыватель — в прерывании кадра (snd_tick): есть AY (порты 0x15 — регистр, 0x14 — данные) —
; регистры как есть; нет — тон двух самых громких каналов на счётчики 1 и 2 ВИ53 (счётчик 0 — часы кадра).

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

SND_KV			equ		0x10					; квазидиск стр. 0, стековый режим
; A = поток SND_* — играть с начала. Запрос подхватывает прерывание (snd_tick): адрес, потом флаг —
; запись байта неделима, состояние прерываний не трогается
snd_play:		cp		SND_SFX1				; ВИ53: порог громкости и шум — у музыки и эффектов свои
				ld		hl, VI_THR_SFX
				jp		nc, sp_sfx
				ld		hl, VI_THR_MUS | 0x100	; H = 1 — музыка (шум не играть)
sp_sfx:			ld		(vi_thr), hl
				add		a, a
				ld		l, a
				ld		h, 0
				ld		de, snd_tab
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
snd_req_hl:		ld		(snd_req), hl
				ld		a, 1
				ld		(snd_reqf), a
				ret
; тишина (поток остановлен)
snd_stop:		ld		hl, 0
				jp		snd_req_hl
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

; ---- кадр звука (из прерывания, DI): 18 байт потока из квазидиска -> регистры ----
snd_tick:		ld		a, (snd_reqf)			; запрос: новый поток или тишина
				or		a
				jp		z, st_go
				xor		a
				ld		(snd_reqf), a
				ld		hl, (snd_req)
				ld		(snd_ptr), hl
				call	snd_mute
st_go:			ld		hl, (snd_ptr)
				ld		a, h
				or		l
				ret		z
				ld		(st_base), hl
				ld		a, l					; читать словами с чётного адреса
				and		0xfe
				ld		l, a
				ex		de, hl
				ld		hl, 0
				add		hl, sp
				ld		(st_ssp), hl
				ld		a, SND_KV
				out		(0x10), a
				ex		de, hl
				ld		sp, hl
				ld		hl, snd_buf
				REPT	9
				pop		bc
				ld		(hl), c
				inc		hl
				ld		(hl), b
				inc		hl
				ENDR
				xor		a
				out		(0x10), a
				ld		hl, (st_ssp)
				ld		sp, hl
				ld		hl, snd_buf
				ld		a, (st_base)
				and		1
				jp		z, st_0
				inc		hl
st_0:			ld		(st_start), hl
				ld		a, (hl)					; m0
				inc		hl
				ld		c, a
				ld		b, 0
				cp		0x80
				jp		nz, st_m
				ld		a, (hl)
				cp		0x80
				jp		z, st_end
st_m:			ld		a, c
				or		a
				jp		p, st_1
				ld		b, (hl)					; m1
				inc		hl
st_1:			ld		a, b					; маска 14 бит: BC = m0 | m1 << 7
				rrca
				and		0x80
				ld		d, a
				ld		a, c
				and		0x7f
				or		d
				ld		c, a
				ld		a, b
				or		a
				rra
				ld		b, a
				ld		de, snd_st
				xor		a
				ld		(st_rn), a
st_r:			ld		a, b					; сдвиг маски, в переносе — есть ли регистр
				or		c
				jp		z, st_done				; больше изменений нет
				ld		a, b
				or		a
				rra
				ld		b, a
				ld		a, c
				rra
				ld		c, a
				jp		nc, st_n
				ld		a, (hl)
				inc		hl
				ld		(de), a
				ld		a, (snd_ay)
				or		a
				jp		z, st_n
				ld		a, (st_rn)
				out		(0x15), a
				ld		a, (de)
				out		(0x14), a
st_n:			inc		de
				ld		a, (st_rn)
				inc		a
				ld		(st_rn), a
				cp		14
				jp		nz, st_r
st_done:		ex		de, hl					; новый указатель = старый + прочитано
				ld		hl, (st_start)
				ld		a, e
				sub		l
				ld		e, a
				ld		d, 0
				ld		hl, (st_base)
				add		hl, de
				ld		(snd_ptr), hl
				ld		a, (snd_ay)
				or		a
				ret		nz
				jp		vi_update
st_end:			inc		hl						; конец: адрес повтора (0 — тишина)
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		(snd_ptr), hl
				ld		a, h
				or		l
				ret		nz
				jp		snd_mute
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


snd_ptr:		DW		0						; следующий кадр потока в квазидиске (0 — тишина)
snd_req:		DW		0						; запрос из основного кода (snd_play / snd_stop)
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
st_base:		DW		0
st_start:		DW		0
st_ssp:			DW		0
st_rn:			DB		0
snd_st:			DS		14						; состояние регистров AY
snd_buf:		DS		18
