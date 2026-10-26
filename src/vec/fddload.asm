; fddload.asm: загрузчик игры с дискеты МикроДОС (tools/build_fdd.py). Штатное ПЗУ Вектора грузит его с дорожки 0
; по 0x0080.. и входит в 0x0100 (так же он запускается из CP/M как ATICATAC.COM). Он переносит себя в невидимую
; плоскость (0xF000) и читает ATICATAC.DAT подряд: страницу 0 квазидиска (там заставка — она сразу на экран,
; с полоской загрузки), страницы 1..3, блок кода 0xE000..0xFFFF (во временное место квазидиска стр. 3), основную
; память 0x0000..0x7FFF; хвост (на месте стека игры 0x3F00) переносит блок 0xE000 и запускает игру с 0x0000.
; Чтение ВГ93 — как в порте Ianna (vec_fdd.asm): порты 0x18 данные, 0x19 сектор, 0x1A дорожка, 0x1B команда/статус,
; 0x1C управление (0x34 — сторона 0, 0x30 — сторона 1); дорожка — 2 стороны по 5 секторов 1024 Б.
; Константы раскладки (FL_*) — build/game/fddload.inc (tools/build_fdd.py), заставка — build/game/splash.inc.

				INCLUDE	"../../build/game/fddload.inc"
LD_ORG			equ		0xF000
LD_BUF			equ		0xF800					; буфер сектора (1 КБ)
STUB			equ		0x3F00					; хвост: место стека игры

				ORG		0x0100
				di
				ld		sp, LD_ORG
				ld		hl, ld_payload
				ld		de, LD_ORG
				ld		bc, file_end - ld_payload
rl_copy:		ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		bc
				ld		a, b
				or		c
				jp		nz, rl_copy
				jp		ld_start
ld_payload:
				DISP	LD_ORG
ld_start:		ld		sp, LD_ORG
				ld		a, 0xfb					; прерывание на время загрузки: ei; ret
				ld		(0x38), a
				ld		a, 0xc9
				ld		(0x39), a
				ld		a, 0x88					; порты ППА: B — выход
				out		(0x00), a
				ld		a, 0xff
				out		(0x03), a				; прокрутка
				ld		hl, ld_black + 15
				call	ld_pal
				ld		hl, 0x8000				; плоскости 0..2 — нули
lc_l:			ld		(hl), 0
				inc		hl
				ld		a, h
				cp		0xe0
				jp		nz, lc_l
				ld		a, 0x34					; дискета: сторона 0, к дорожке начала данных
				ld		(fd_ctl), a
				call	fd_restore
				ld		a, FL_SIDE
				or		a
				jp		z, ls_s0
				ld		a, 0x30
				ld		(fd_ctl), a
ls_s0:			ld		a, FL_SEC
				ld		(fd_sec), a
				ld		b, FL_TRACK
				inc		b
ls_l:			dec		b
				jp		z, ls_done
				ld		a, 0x58					; STEP-IN с обновлением дорожки
				out		(0x1b), a
				call	fd_wait
				jp		ls_l
ls_done:
				; страница 0 квазидиска: заставка, меню, звук
				ld		a, 0
				ld		hl, 0
				ld		bc, FL_P0
				call	ld_kvaz
				call	ld_splash
				ld		a, 1
				ld		hl, 0
				ld		bc, FL_P1
				call	ld_kvaz
				ld		a, 2
				ld		hl, 0
				ld		bc, FL_P2
				call	ld_kvaz
				ld		a, 3
				ld		hl, 0
				ld		bc, FL_P3
				call	ld_kvaz
				ld		a, 3					; блок кода 0xE000..0xFFFF — временно в стр. 3
				ld		hl, FL_STAGE
				ld		bc, 8
				call	ld_kvaz
				ld		hl, 0x0400				; основная память: прямо на место; первый килобайт (с вектором
				ld		c, 32					; прерывания 0x38) — последним на дискете, после чтения — DI
lr_l:			push	bc
				push	hl
				call	fd_next
				di
				pop		de
				ld		hl, LD_BUF				; буфер -> память
				ld		bc, 1024
lr_cp:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		bc
				ld		a, b
				or		c
				jp		nz, lr_cp
				ex		de, hl
				ld		a, h
				cp		0x80
				jp		nz, lr_n
				ld		hl, 0					; 0x0400..0x7FFF прочитаны — теперь 0x0000..0x03FF
lr_n:			pop		bc
				call	ld_step
				dec		c
				jp		nz, lr_l
				ld		hl, stub_rt				; хвост — на место стека игры, туда
				ld		de, STUB
				ld		bc, stub_end - STUB
st_cp:			ld		a, (hl)
				ld		(de), a
				inc		hl
				inc		de
				dec		bc
				ld		a, b
				or		c
				jp		nz, st_cp
				jp		STUB

; A = страница квазидиска, HL = адрес в ней, BC = секторов (по 1 КБ)
ld_kvaz:		rlca
				rlca
				or		0x10					; стековый режим, страница
				ld		(lk_port), a
lk_l:			push	bc
				push	hl
				call	fd_next
				pop		hl
				push	hl
				ld		de, 1024				; push пишет вниз: SP = конец куска
				add		hl, de
				di
				ld		(lk_dst), hl
				ld		hl, 0
				add		hl, sp
				ld		(lk_sp), hl
				ld		hl, (lk_dst)
				ld		sp, hl
				ld		a, (lk_port)
				out		(0x10), a
				ld		hl, LD_BUF + 1023
				ld		c, 0					; 512 слов: C = 0 -> 256 x 2
				ld		b, 2
lk_p:			ld		d, (hl)
				dec		hl
				ld		e, (hl)
				dec		hl
				push	de
				dec		c
				jp		nz, lk_p
				dec		b
				jp		nz, lk_p
				xor		a
				out		(0x10), a
				ld		hl, (lk_sp)
				ld		sp, hl
				ei
				pop		hl
				ld		de, 1024
				add		hl, de
				pop		bc
				call	ld_step
				dec		bc
				ld		a, b
				or		c
				jp		nz, lk_l
				ret
lk_port:		DB		0
lk_dst:			DW		0
lk_sp:			DW		0

; заставка из стр. 0 (как splash.asm), палитра, рамка полоски
ld_splash:		ld		hl, SPLASH_P01
				ld		de, 0x80ff
				ld		b, 64
				call	ls_copy
				ld		hl, SPLASH_P2
				ld		de, 0xc0ff
				ld		b, 32
				call	ls_copy
				ld		h, 0x80 + 4				; рамка: белый (плоскости 0 и 2), строки 216 и 223
lf_l:			ld		a, 0xff
				ld		l, 255 - 216
				ld		(hl), a
				ld		l, 255 - 223
				ld		(hl), a
				ld		a, h
				add		a, 0x40
				ld		d, a
				ld		a, 0xff
				ld		e, 255 - 216
				ld		(de), a
				ld		e, 255 - 223
				ld		(de), a
				inc		h
				ld		a, h
				cp		0x80 + 28
				jp		nz, lf_l
				ld		a, 1
				ld		(lb_on), a
				ld		hl, pal_splash + 15
				jp		ld_pal
; HL = стр. 0, DE = верх столбца (строка 255), B = столбцов по 256 строк
ls_copy:		di
				ex		de, hl
				ld		(lk_dst), hl
				ld		hl, 0
				add		hl, sp
				ld		(lk_sp), hl
				ex		de, hl
				ld		a, 0x10
				out		(0x10), a
				ld		sp, hl
				ld		hl, (lk_dst)
				ld		d, b
lsc_col:		ld		a, 128
lsc_l:			pop		bc
				ld		(hl), c
				dec		l
				ld		(hl), b
				dec		l
				dec		a
				jp		nz, lsc_l
				inc		h
				dec		d
				jp		nz, lsc_col
				xor		a
				out		(0x10), a
				ld		hl, (lk_sp)
				ld		sp, hl
				ei
				ret

; полоска: на каждые FL_PER секторов — столбец (жёлтый, плоскость 0, строки 218..221)
ld_step:		ld		a, (lb_on)				; до заставки полоски нет
				or		a
				ret		z
				ld		a, (lb_cnt)
				dec		a
				ld		(lb_cnt), a
				ret		nz
				ld		a, FL_PER
				ld		(lb_cnt), a
				ld		a, (lb_col)
				cp		0x80 + 28
				ret		nc
				push	hl
				ld		h, a
				inc		a
				ld		(lb_col), a
				ld		a, 0xff
				ld		l, 255 - 218
				ld		(hl), a
				dec		l
				ld		(hl), a
				dec		l
				ld		(hl), a
				dec		l
				ld		(hl), a
				pop		hl
				ret
lb_on:			DB		0
lb_cnt:			DB		FL_PER
lb_col:			DB		0x80 + 4

; палитра: HL = последний байт (16 байт), запись после прерывания кадра (в гашении)
ld_pal:			ei
				halt
				di
				ld		c, 15
lp_l:			ld		a, c
				out		(0x02), a
				ld		a, (hl)
				dec		hl
				out		(0x0c), a
				out		(0x0c), a
				out		(0x0c), a
				out		(0x0c), a
				dec		c
				jp		p, lp_l
				xor		a
				out		(0x02), a
				ld		a, 0xff
				out		(0x03), a
				ei
				ret
ld_black:		DS		16, 0
				INCLUDE	"../../build/game/splash.inc"	; pal_splash, SPLASH_P01, SPLASH_P2

; ---- ВГ93 (как vec_fdd.asm Ianna) ----
; следующий сектор данных -> LD_BUF; сторона 0 (1..5), сторона 1 (1..5), шаг на следующую дорожку
fd_next:		ld		a, (fd_sec)
				ld		c, a
				ld		hl, LD_BUF
				call	fd_read
				ld		a, (fd_sec)
				inc		a
				ld		(fd_sec), a
				cp		6
				ret		nz
				ld		a, 1
				ld		(fd_sec), a
				ld		a, (fd_ctl)
				xor		4
				ld		(fd_ctl), a
				call	fd_ctlw
				and		4
				ret		z						; перешли на сторону 1 — дорожка та же
				ld		a, 0x58
				out		(0x1b), a
				jp		fd_wait
fd_read:		di								; сектор C -> (HL), 1024 Б
				call	fd_ctlw
				ld		a, c
				out		(0x19), a
				ld		a, 0x80
				out		(0x1b), a
				ld		bc, 4
fr_busy:		in		a, (0x1b)
				rrca
				jp		nc, fr_busy
fr_drq:			in		a, (0x1b)
				rrca
				jp		nc, fr_end
				rrca
				jp		nc, fr_drq
				in		a, (0x18)
				ld		(hl), a
				inc		hl
				dec		b
				jp		nz, fr_drq
				dec		c
				jp		nz, fr_drq
fr_end:			in		a, (0x1b)
				rrca
				jp		c, fr_end
				ei
				ret
fd_restore:		call	fd_ctlw
				xor		a
				out		(0x1b), a
				jp		fd_wait
fd_ctlw:		ld		a, (fd_ctl)				; управление и ожидание снятия BUSY
				out		(0x1c), a
				in		a, (0x1b)
				rrca
				jp		c, fd_ctlw
				ld		a, (fd_ctl)
				ret
fd_wait:		push	bc						; конец команды типа I со счётчиком (без дискеты не виснуть)
				push	de
				ld		a, 40
fw_p:			dec		a
				jp		nz, fw_p
				ld		d, 4
				ld		bc, 0
fw_l:			in		a, (0x1b)
				and		1
				jp		z, fw_ok
				dec		bc
				ld		a, b
				or		c
				jp		nz, fw_l
				dec		d
				jp		nz, fw_l
fw_ok:			pop		de
				pop		bc
				ret
fd_ctl:			DB		0x34
fd_sec:			DB		1

ld_mainend:
				ENT
; хвост (в файле за основной частью, копируется вместе с ней): блок 0xE000..0xFFFF из стр. 3 на место, игра
stub_file:
				DISP	STUB
				ld		a, 0x1c					; стр. 3, стековый режим
				out		(0x10), a
				ld		sp, FL_STAGE
				ld		hl, 0xe000
				ld		bc, 0x1000				; 4096 слов
sb_l:			pop		de
				ld		(hl), e
				inc		hl
				ld		(hl), d
				inc		hl
				dec		bc
				ld		a, b
				or		c
				jp		nz, sb_l
				xor		a
				out		(0x10), a
				ld		sp, 0x4000
				jp		0x0000
stub_end:
				ENT
file_end:
ld_start_f		equ		ld_payload
stub_rt			equ		LD_ORG + (stub_file - ld_payload)
				ASSERT	LD_ORG + (file_end - ld_payload) <= LD_BUF
