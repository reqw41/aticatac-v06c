; akg80: проигрыватель Arkos Tracker 2 (PlayerAkg, Targhan/Arkos) на i8080 — перенос версии банка звука CPC
; (конфигурация ref/cpc/include_banks.asm: дорожки скорости, эффекты, «только программный звук» с арпеджио
; и питчем, легато, арпеджио; эффекты-звуки — программный звук и шум). Развёрнутый оригинал —
; build/sound/akg/flat.asm (tools/akgflat.py), этот файл — шаблон: блоки {{CH}}..{{END}} повторяются для
; каналов 1..3 ({N} — номер, {I} — номер с 0), tools/mkakg.py -> build/sound/akg/akg80.asm.
; Отличия от Z80: нет теневых регистров (нота, питч, период — в памяти), нет IX/IY (поля канала — блок chN_d,
; эффектам — указатель fx_ch), данные читаются через HL/DE (стек не переносится); отправка в AY — своя:
; регистры 0..10 (периоды CPC, без пересчёта) в akg_regs, R7 — в A после akg_play.
; Входы: akg_init (HL = песня, A = подпесня), akg_initsfx (HL = таблица эффектов), akg_playsfx (A = эффект 1..,
; C = канал 0..2, B = обратная громкость), akg_play (кадр).

CH_ARPSPEED		equ		0						; поля канала (chN_d)
CH_ARPBASESPEED	equ		1
CH_ARPTAB		equ		2						; текущий указатель таблицы арпеджио
CH_ARPTABBASE	equ		4
CH_ISARP		equ		6						; 1 — есть таблица арпеджио
CH_ARPSTEP		equ		7
CH_TRACKNOTE	equ		8
CH_ARPNOTE		equ		9
CH_PITCH		equ		10						; слово
CH_INSTRSTEP	equ		12
CH_PTINSTR		equ		13						; слово
CH_INSTRSPEED	equ		15
CH_PTBASEINSTR	equ		16						; слово
CH_INVVOL		equ		18						; обратная громкость канала (0 — полная)
CH_SIZE			equ		19

; ---- звуковые эффекты (PlayerAkg_SoundEffects) ----
akg_initsfx:	ld		(as_tab + 1), hl
				ret
; A = эффект (1..), C = канал, B = обратная громкость
akg_playsfx:	dec		a
as_tab:			ld		hl, 0
				push	bc
				ld		e, a
				ld		d, 0
				add		hl, de
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ld		a, (de)					; скорость
				inc		de
				pop		bc
				push	af
				ld		a, c
				add		a, a
				add		a, a
				add		a, a
				ld		l, a
				ld		h, 0
				push	de
				ld		de, sfx_ch1
				add		hl, de
				pop		de
				ld		(hl), e					; данные
				inc		hl
				ld		(hl), d
				inc		hl
				ld		(hl), b					; обратная громкость
				inc		hl
				ld		(hl), 0					; текущий шаг
				inc		hl
				pop		af
				ld		(hl), a					; скорость
				ret
SFX_INVVOL		equ		2
SFX_STEP		equ		3
SFX_SPEED		equ		4
sfx_ch1:		DS		8, 0
sfx_ch2:		DS		8, 0
sfx_ch3:		DS		8, 0

; A = микшер (D после канала 3) -> A = микшер с эффектами (PLY_AKG_PlaySoundEffectsStream)
akg_sfxstream:	rla
				rla
				ld		c, a
				ld		hl, sfx_ch1
				ld		(ps_ix), hl
				ld		hl, akg_regs + 8
				ld		(ps_iy), hl
				ld		hl, akg_regs + 0
				ld		(ps_reg), hl
				call	pses_play
				ld		hl, sfx_ch2
				ld		(ps_ix), hl
				ld		hl, akg_regs + 9
				ld		(ps_iy), hl
				ld		hl, akg_regs + 2
				ld		(ps_reg), hl
				ld		a, c					; srl c
				or		a
				rra
				ld		c, a
				call	pses_play
				ld		hl, sfx_ch3
				ld		(ps_ix), hl
				ld		hl, akg_regs + 10
				ld		(ps_iy), hl
				ld		hl, akg_regs + 4
				ld		(ps_reg), hl
				ld		a, c					; rr c (перенос — от pses_play, как у Z80)
				rra
				ld		c, a
				call	pses_play
				ld		a, c
				ret
ps_ix:			DW		0
ps_iy:			DW		0
ps_reg:			DW		0

pses_play:		ld		hl, (ps_ix)
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		a, l
				or		h
				ret		z
				ld		a, (hl)
				inc		hl
				ld		b, a
				rra
				jp		c, pses_soft
				xor		a						; конец эффекта
				ld		hl, (ps_ix)
				ld		(hl), a
				inc		hl
				ld		(hl), a
				ret
pses_save:		push	hl						; HL = поток
				ld		hl, (ps_ix)
				ld		de, SFX_STEP
				add		hl, de
				ld		a, (hl)
				inc		hl
				cp		(hl)					; шаг < скорости — кадр ещё держится
				dec		hl
				jp		c, pses_nr
				ld		(hl), 0
				pop		de
				ld		hl, (ps_ix)
				ld		(hl), e
				inc		hl
				ld		(hl), d
				ret
pses_nr:		inc		(hl)
				pop		hl
				ret
pses_soft:		rra
				and		0x0f
				push	hl
				ld		hl, (ps_ix)
				inc		hl
				inc		hl
				sub		(hl)					; - обратная громкость
				jp		nc, pses_v
				xor		a
pses_v:			ld		hl, (ps_iy)
				ld		(hl), a
				pop		hl
				ld		a, b					; rl b: шум?
				rla
				ld		b, a
				call	c, pses_noise
				ld		a, c					; res 2,c — звук канала открыт
				and		0xfb
				ld		c, a
				ld		e, (hl)					; период
				inc		hl
				ld		d, (hl)
				inc		hl
				push	hl
				ld		hl, (ps_reg)
				ld		(hl), e
				inc		hl
				ld		(hl), d
				pop		hl
				jp		pses_save
pses_noise:		ld		a, (hl)
				ld		(akg_regs + 6), a
				inc		hl
				ld		a, c					; res 5,c — шум канала открыт
				and		0xdf
				ld		c, a
				ret

; ---- запуск песни: HL = песня, A = подпесня (PLY_AKG_Init) ----
akg_init:		push	af
				ld		de, 4
				add		hl, de
				ld		e, (hl)					; таблица арпеджио
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(arp_tables), hl
				ex		de, hl
				inc		hl						; таблица питчей — не используется
				inc		hl
				ld		e, (hl)					; таблица инструментов
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(instr_tab), hl
				ex		de, hl
				ld		e, (hl)					; блоки эффектов
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(fx_blocks), hl
				ex		de, hl
				pop		af
				add		a, a
				ld		e, a
				ld		d, 0
				add		hl, de
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ld		de, 5
				add		hl, de
				ld		a, (hl)
				inc		hl
				ld		(cur_speed), a
				ld		a, (hl)
				inc		hl
				ld		(base_note), a
				ld		(linker_pt), hl
				xor		a
				ld		(ch1_d + CH_INVVOL), a
				ld		(ch2_d + CH_INVVOL), a
				ld		(ch3_d + CH_INVVOL), a
				ld		(ch1_d + CH_ISARP), a
				ld		(ch2_d + CH_ISARP), a
				ld		(ch3_d + CH_ISARP), a
				inc		a
				ld		(pat_height), a
				ld		(tick_cnt), a
				ld		hl, (instr_tab)			; пустой инструмент: первый в таблице, после заголовка
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				inc		hl
				ld		(empty_instr), hl
				ld		(ch1_d + CH_PTINSTR), hl
				ld		(ch2_d + CH_PTINSTR), hl
				ld		(ch3_d + CH_PTINSTR), hl
				ld		hl, 0
				ld		(sfx_ch1), hl
				ld		(sfx_ch2), hl
				ld		(sfx_ch3), hl
				ret

; ---- кадр (PLY_AKG_Play) ----
akg_play:		ld		a, (tick_cnt)
				dec		a
				jp		nz, set_speed
				ld		a, (pat_height)
				dec		a
				jp		nz, set_line
				ld		hl, (linker_pt)			; позиция: дорожки каналов, блок (высота, скорость)
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		a, e
				or		d
				jp		nz, rl_noloop
				ld		e, (hl)					; конец песни — к позиции повтора
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
rl_noloop:		ex		de, hl
				ld		(ch1_pttrack), hl
				ex		de, hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(ch2_pttrack), hl
				ex		de, hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ex		de, hl
				ld		(ch3_pttrack), hl
				ex		de, hl
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				ld		(linker_pt), hl
				ex		de, hl
				ld		c, (hl)					; высота
				inc		hl
				inc		hl
				inc		hl
				inc		hl
				ld		e, (hl)					; дорожка скорости
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		(spd_pttrack), hl
				xor		a
				ld		(spd_wait), a
				ld		(ch1_wait), a
				ld		(ch2_wait), a
				ld		(ch3_wait), a
				ld		a, c
set_line:		ld		(pat_height), a
				ld		a, (spd_wait)			; дорожка скорости
				sub		1
				jp		nc, spd_must
				ld		hl, (spd_pttrack)
				ld		a, (hl)
				inc		hl
				or		a						; srl a: бит 0 — ждать
				rra
				jp		c, spd_store
				or		a
				jp		nz, spd_norm
				ld		a, (hl)
				inc		hl
spd_norm:		ld		(cur_speed), a
				xor		a
spd_store:		ld		(spd_pttrack), hl
spd_must:		ld		(spd_wait), a
{{CH}}
; -- дорожка канала {N}
				ld		a, (ch{N}_wait)
				sub		1
				jp		c, ch{N}_read
				ld		(ch{N}_wait), a
				jp		ch{N}_cellend
ch{N}_read:		ld		hl, (ch{N}_pttrack)
				ld		c, (hl)					; C: данные (б5..0), эффекты (б6), инструмент (б7)
				inc		hl
				ld		a, c
				and		0x3f
				cp		60
				jp		c, ch{N}_note
				sub		60
				jp		z, ch{N}_maybefx
				dec		a
				jp		z, ch{N}_waitv
				dec		a
				jp		z, ch{N}_smallw
				ld		a, (hl)					; нота полностью
				inc		hl
				jp		ch{N}_afternote
ch{N}_smallw:	ld		a, c
				rlca
				rlca
				and		3
				inc		a
				ld		(ch{N}_wait), a
				jp		ch{N}_store
ch{N}_waitv:	ld		a, (hl)
				ld		(ch{N}_wait), a
				inc		hl
				jp		ch{N}_store
ch{N}_same:		ex		de, hl					; тот же инструмент — с начала
				ld		hl, (ch{N}_d + CH_PTBASEINSTR)
				ld		(ch{N}_d + CH_PTINSTR), hl
				ex		de, hl
				jp		ch{N}_afterins
ch{N}_note:		ld		b, a
				ld		a, (base_note)
				add		a, b
ch{N}_afternote:
				ld		(ch{N}_d + CH_TRACKNOTE), a
				ld		a, c					; rl c: новый инструмент?
				rla
				ld		c, a
				jp		nc, ch{N}_same
				ld		a, (hl)
				inc		hl
				push	hl
				ld		l, a
				ld		h, 0
				add		hl, hl
				ex		de, hl
				ld		hl, (instr_tab)
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ex		de, hl
				ld		a, (hl)					; скорость инструмента
				inc		hl
				ld		(ch{N}_d + CH_INSTRSPEED), a
				ld		(ch{N}_d + CH_PTINSTR), hl
				ld		(ch{N}_d + CH_PTBASEINSTR), hl
				pop		hl
ch{N}_afterins:	xor		a
				ld		(ch{N}_d + CH_ARPSTEP), a
				ld		(ch{N}_d + CH_INSTRSTEP), a
				ld		a, (ch{N}_d + CH_ARPBASESPEED)
				ld		(ch{N}_d + CH_ARPSPEED), a
				ex		de, hl
				ld		hl, (ch{N}_d + CH_ARPTABBASE)
				ld		(ch{N}_d + CH_ARPTAB), hl
				ex		de, hl
				ld		a, c					; rl c: эффекты?
				rla
				ld		c, a
				jp		c, ch{N}_readfx
ch{N}_store:	ld		(ch{N}_pttrack), hl
ch{N}_cellend:
{{END}}
				ld		a, (cur_speed)
set_speed:		ld		(tick_cnt), a
{{CH}}
; -- поток канала {N}: обратная громкость, арпеджио
				ld		c, 0
				ld		a, (ch{N}_d + CH_ISARP)
				or		a
				jp		z, ch{N}_arpend
				ld		hl, (ch{N}_d + CH_ARPTAB)
				ld		a, (hl)
				cp		0x80					; -128: повтор
				jp		nz, ch{N}_arpv
				inc		hl
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				ld		a, (hl)
ch{N}_arpv:		ld		c, a
				ld		a, (ch{N}_d + CH_ARPSPEED)
				ld		d, a
				ld		a, (ch{N}_d + CH_ARPSTEP)
				inc		a
				cp		d
				jp		c, ch{N}_arpst
				inc		hl
				ld		(ch{N}_d + CH_ARPTAB), hl
				xor		a
ch{N}_arpst:	ld		(ch{N}_d + CH_ARPSTEP), a
ch{N}_arpend:	ld		hl, 0					; питча нет (таблиц питча в песнях нет)
				ld		(ch{N}_d + CH_PITCH), hl
				ld		a, c
				ld		(ch{N}_d + CH_ARPNOTE), a
{{END}}
				ld		d, 0xe0					; микшер: каналы закрывают тон битом 2, сдвиг после канала
{{CH}}
; -- инструмент канала {N}
				ld		hl, (ch{N}_d + CH_PITCH)
				ld		(akg_pitch), hl
				ld		(akg_per), hl			; без звука период = питч (у Z80 — HL' не тронут)
				ld		a, (ch{N}_d + CH_ARPNOTE)
				ld		b, a
				ld		a, (ch{N}_d + CH_TRACKNOTE)
				add		a, b
				ld		(akg_note), a
				ld		a, (ch{N}_d + CH_INVVOL)
				ld		e, a
				ld		hl, (ch{N}_d + CH_PTINSTR)
				call	ric
				ld		a, (ch{N}_d + CH_INSTRSPEED)
				ld		c, a
				ld		a, (ch{N}_d + CH_INSTRSTEP)
				inc		a
				cp		c
				jp		c, ch{N}_setst
				ld		(ch{N}_d + CH_PTINSTR), hl
				xor		a
ch{N}_setst:	ld		(ch{N}_d + CH_INSTRSTEP), a
				ld		a, e
				ld		(akg_regs + 8 + {I}), a
				ld		hl, (akg_per)
				ld		(akg_regs + 2 * {I}), hl
				ld		a, d					; srl d (у канала 3 — без сдвига)
	IF {N} != 3
				or		a
				rra
				ld		d, a
	ENDIF
{{END}}
				jp		akg_sfxstream			; A = микшер -> A = R7

; ---- кадр пустой песни (NoMusic, в игре): результат постоянный — периоды и громкости 0, микшер 0x3F
;      (каждый канал «ни тона, ни огибающей»), дальше только эффекты. Сверка — tools/akg80check.js
akg_quiet:		ld		hl, 0
				ld		(akg_regs + 0), hl
				ld		(akg_regs + 2), hl
				ld		(akg_regs + 4), hl
				ld		(akg_regs + 8), hl
				xor		a
				ld		(akg_regs + 10), a
				ld		a, 0x3f
				jp		akg_sfxstream

; ---- клетка инструмента (PLY_AKG_ReadInstrumentCell): HL = клетка, E = обратная громкость, D = микшер ->
;      E = громкость, D, akg_per = период (таблица[нота] + питч), HL = следующая клетка
ric:			ld		a, (hl)
				inc		hl
				ld		b, a
				rra
				jp		c, ric_sl
				rra
				jp		c, ric_sth
				rra
ric_nsnh:		and		0x0f					; ни тона, ни огибающей
				sub		e
				jp		nc, ric_n1
				xor		a
ric_n1:			ld		e, a
				ld		a, d					; set 2,d — тон закрыт
				or		4
				ld		d, a
				ret
ric_soft:		and		0x0f
				sub		e
				jp		nc, ric_s1
				xor		a
ric_s1:			ld		e, a
				ld		a, b					; rl b: простая клетка?
				rla
				ld		b, a
				jp		nc, ric_nsimp
				ld		c, 0
				jp		ric_period				; перенос = 1
ric_nsimp:		ld		b, (hl)					; перенос = 0
				ld		c, b
				inc		hl
ric_period:		jp		nc, ric_next
				call	per_calc
				ld		a, b					; rl b x3
				rla
				rla
				rla
				ld		b, a
				ret
ric_next:		ld		a, b					; rl b x2: арпеджио?
				rla
				rla
				ld		b, a
				jp		nc, ric_aarp
				ld		a, (hl)
				inc		hl
				push	hl
				ld		hl, akg_note
				add		a, (hl)
				ld		(hl), a
				pop		hl
ric_aarp:		ld		a, b					; rl b: питч?
				rla
				ld		b, a
				jp		nc, per_calc
				push	de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				inc		hl
				push	hl
				ld		hl, (akg_pitch)
				add		hl, de
				ld		(akg_pitch), hl
				pop		hl
				pop		de
; период = таблица[нота] + питч -> akg_per; перенос — от сложения (как у Z80)
per_calc:		push	hl
				push	de
				ld		a, (akg_note)
				ld		l, a
				ld		h, 0
				add		hl, hl
				ld		de, period_table
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
				ld		hl, (akg_pitch)
				add		hl, de
				ld		(akg_per), hl
				pop		de
				pop		hl
				ret
ric_sl:			rra								; б0 = 1: программный звук или конец с повтором
				jp		c, ric_loop
				rra
				jp		nc, ric_soft
ric_loop:		ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				jp		ric
ric_sth:		rra								; конец без повтора — пустой инструмент
				ld		hl, (empty_instr)
				inc		hl
				xor		a
				ld		b, a
				jp		ric_nsnh

; ---- эффекты в клетке (PLY_AKG_Channel_ReadEffects): HL = дорожка, fx_ch — поля канала, DE — возврат ----
{{CH}}
ch{N}_maybefx:	ld		(ch{N}_wait), a
				ld		a, c					; bit 6,c
				and		0x40
				jp		z, ch{N}_store
ch{N}_readfx:	ld		de, ch{N}_d
				ex		de, hl
				ld		(fx_ch), hl
				ld		hl, ch{N}_store
				ld		(fx_ret + 1), hl
				ex		de, hl
				jp		fx_read
{{END}}
fx_read:		ld		a, (hl)
				inc		hl
				add		a, a					; sla a
				jp		c, fx_rel
				ld		(fx_trk), hl
				ld		l, a
				ld		h, 0
				ex		de, hl
				ld		hl, (fx_blocks)
				add		hl, de
				ld		e, (hl)
				inc		hl
				ld		d, (hl)
fx_known:		ld		a, (de)					; DE — блок эффектов
				inc		de
				ld		(fx_next + 1), a
				and		0xfe
				ld		l, a
				ld		h, 0
				ld		bc, fx_table
				add		hl, bc
				ld		a, (hl)
				inc		hl
				ld		h, (hl)
				ld		l, a
				jp		(hl)
fx_return:
fx_next:		ld		a, 0
				rra
				jp		c, fx_known
				ld		hl, (fx_trk)
fx_ret:			jp		0
fx_rel:			or		a						; srl a: смещение блока — 15 бит (как у Z80: DE = база блоков)
				rra
				ld		a, (hl)
				inc		hl
				ld		(fx_trk), hl
				ld		hl, (fx_blocks)
				ex		de, hl
				jp		fx_known
fx_table:		DW		0, 0, 0, fx_arptab, fx_arpstop, 0, 0, 0, 0, 0, 0, 0, 0, 0, fx_legato, 0, 0
; таблица арпеджио: номер -> скорость, таблица (база и текущая), есть таблица, шаг 0
fx_arptab:		ld		a, (de)
				inc		de
				ld		l, a
				ld		h, 0
				add		hl, hl
				push	hl
				ld		hl, (arp_tables)
				ld		b, h
				ld		c, l
				pop		hl
				add		hl, bc
				ld		c, (hl)
				inc		hl
				ld		b, (hl)
				ld		a, (bc)					; скорость
				inc		bc
				ld		hl, (fx_ch)
				ld		(hl), a					; CH_ARPSPEED
				inc		hl
				ld		(hl), a					; CH_ARPBASESPEED
				inc		hl
				ld		(hl), c					; CH_ARPTAB
				inc		hl
				ld		(hl), b
				inc		hl
				ld		(hl), c					; CH_ARPTABBASE
				inc		hl
				ld		(hl), b
				inc		hl
				ld		(hl), 1					; CH_ISARP
				inc		hl
				ld		(hl), 0					; CH_ARPSTEP
				jp		fx_return
fx_arpstop:		ld		hl, (fx_ch)
				ld		bc, CH_ISARP
				add		hl, bc
				ld		(hl), 0
				jp		fx_return
fx_legato:		ld		a, (de)
				inc		de
				ld		hl, (fx_ch)
				ld		bc, CH_TRACKNOTE
				add		hl, bc
				ld		(hl), a
				jp		fx_return

; ---- переменные ----
akg_regs:		DS		11, 0					; R0..R10 (периоды CPC)
akg_note:		DB		0
akg_pitch:		DW		0
akg_per:		DW		0
tick_cnt:		DB		1
pat_height:		DB		1
cur_speed:		DB		0
base_note:		DB		0
linker_pt:		DW		0
spd_wait:		DB		0
spd_pttrack:	DW		0
instr_tab:		DW		0
arp_tables:		DW		0
fx_blocks:		DW		0
empty_instr:	DW		0
fx_ch:			DW		0
fx_trk:			DW		0
{{CH}}
ch{N}_wait:		DB		0
ch{N}_pttrack:	DW		0
ch{N}_d:		DS		CH_SIZE, 0
{{END}}
				ASSERT	CH_ARPBASESPEED == CH_ARPSPEED + 1 && CH_ARPTAB == CH_ARPSPEED + 2 && CH_ARPTABBASE == CH_ARPSPEED + 4 && CH_ISARP == CH_ARPSPEED + 6 && CH_ARPSTEP == CH_ARPSPEED + 7 && CH_ARPSPEED == 0
period_table:	DW		3822,3608,3405,3214,3034,2863,2703,2551,2408,2273,2145,2025
				DW		1911,1804,1703,1607,1517,1432,1351,1276,1204,1136,1073,1012
				DW		956,902,851,804,758,716,676,638,602,568,536,506
				DW		478,451,426,402,379,358,338,319,301,284,268,253
				DW		239,225,213,201,190,179,169,159,150,142,134,127
				DW		119,113,106,100,95,89,84,80,75,71,67,63
				DW		60,56,53,50,47,45,42,40,38,36,34,32
				DW		30,28,27,25,24,22,21,20,19,18,17,16
				DW		15,14,13,13,12,11,11,10,9,9,8,8
				DW		7,7,7,6,6,6,5,5,5,4,4,4
				DW		4,4,3,3,3,3,3,2
