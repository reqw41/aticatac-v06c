; splash.asm: заставка — экран загрузки CPC (tools/mksplash.py: картинка 256 x 200 сверху, квазидиск стр. 0:
; плоскости 0-1 с SPLASH_P01, 2 и надпись — с SPLASH_P2), ниже — полоска загрузки (строки 216..223) и после неё
; «НАЖМИТЕ ПРОБЕЛ». Только при включении, до меню. Полоска — сразу полная: загрузку с дискеты показывает
; загрузчик (src/vec/fddload.asm) той же полоской.
	IFNDEF ECHK
SPL_BAR			equ		2						; кадров на столбец полоски
BAR_C0			equ		4						; полоска: столбцы 4..27
BAR_C1			equ		28
BAR_TOP			equ		255 - 216				; строки памяти рамки (сверху/снизу)
BAR_BOT			equ		255 - 223

splash:			call	clear_screen
				ld		hl, SPLASH_P01
				ld		de, 0x80ff				; плоскость 0, столбец 0, строка 255
				ld		bc, 64 * 256 + 128		; 2 плоскости x 32 столбца по 256 строк
				call	spl_copy
				ld		hl, SPLASH_P2
				ld		de, 0xc0ff
				ld		bc, 32 * 256 + 128
				call	spl_copy
				ld		hl, pal_splash + 15
				call	set_palette_hl
				ld		h, 0x80 + BAR_C0		; рамка: белый (плоскости 0 и 2), строки 216 и 223
spl_fr:			ld		a, 0xff
				ld		l, BAR_TOP
				ld		(hl), a
				ld		l, BAR_BOT
				ld		(hl), a
				ld		a, h
				add		a, 0x40
				ld		d, a
				ld		e, BAR_TOP
				ld		a, 0xff
				ld		(de), a
				ld		e, BAR_BOT
				ld		(de), a
				inc		h
				ld		a, h
				cp		0x80 + BAR_C1
				jp		nz, spl_fr
				ld		a, 0x80 + BAR_C0		; заполнение — жёлтый (плоскость 0), строки 218..221
				ld		(spl_col), a
spl_bar:		call	spl_step				; загрузка уже прошла (дискета — полоска загрузчика fddload)
				ld		a, (spl_col)
				cp		0x80 + BAR_C1
				jp		nz, spl_bar
				ld		c, 3					; надпись: 3 плоскости
				ld		hl, SPLASH_TEXT
				ld		de, SPL_TEXT_DST
spl_tx:			push	bc
				push	de
				ld		b, SPL_TEXT_N
				ld		c, 4					; 8 строк
				call	spl_copy
				pop		de
				ld		a, d
				add		a, 0x20
				ld		d, a
				pop		bc
				dec		c
				jp		nz, spl_tx
spl_w:			call	wait_frame				; пробел
				ld		a, (kb_row7)
				and		0x80
				jp		z, spl_w
				ret
; один шаг полоски загрузки
spl_step:		ld		a, (spl_col)
				ld		h, a
				inc		a
				ld		(spl_col), a
				ld		a, 0xff
				ld		l, 255 - 218
				ld		(hl), a
				dec		l
				ld		(hl), a
				dec		l
				ld		(hl), a
				dec		l
				ld		(hl), a
				ret
spl_col:		DB		0
; HL = квазидиск стр. 0, DE = верх первого столбца на экране, B = столбцов, C = пар строк; -> HL за данными
spl_copy:		di
				ld		a, c
				ld		(spc_n), a
				ex		de, hl
				ld		(spc_dst), hl
				ld		hl, 0
				add		hl, sp
				ld		(pn_ssp), hl
				ld		a, 0x10					; стр. 0, стековый режим
				out		(0x10), a
				ex		de, hl
				ld		sp, hl					; SP — данные
				ld		hl, (spc_dst)
				ld		d, b					; D — столбцов, E — верх столбца, A — пар строк
				ld		e, l
spc_col:		ld		a, (spc_n)
spc_l:			pop		bc
				ld		(hl), c
				dec		l
				ld		(hl), b
				dec		l
				dec		a
				jp		nz, spc_l
				ld		l, e
				inc		h
				dec		d
				jp		nz, spc_col
				ld		hl, 0
				add		hl, sp
				ex		de, hl					; DE — за данными
				xor		a
				out		(0x10), a
				ld		hl, (pn_ssp)
				ld		sp, hl
				ex		de, hl
				ei
				ret
spc_dst:		DW		0
spc_n:			DB		0

	ENDIF
