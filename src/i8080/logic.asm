; Логика Atic Atac (CPC) на i8080 — этап 2 (docs/LOGIC_PLAN.md). Сверка с JS-моделью: tools/lock80.js.
; Раскладка на время сверки: переменные и таблицы CPC — по своим адресам (C_имя, build/l80/cpcsym.inc),
; банк комнат — 0x4000, еда — FOOD80, код — CODE80. Банки CPC не нужны (данные лежат рядом).
;   python3 tools/mk80sym.py && tools/sjasmplus --i8080 src/i8080/logic.asm   (build/l80/logic.bin, .sym)
				DEVICE	NOSLOT64K
				INCLUDE	"../../build/l80/cpcsym.inc"

FOOD80			equ		0x3800				; food_items (банк героев CPC 0x5FD8) -> сюда
FOOD_DELTA		equ		FOOD80 - C_food_items

; служебное сверки: очередь ld a,r и журнал звуков
				ORG		0xDF00
r_buf:			DS		64
r_idx:			DB		0
sfx_n:			DB		0
sfx_buf:		DS		16

CODE80			equ		0xE000
				ORG		CODE80
				INCLUDE	"sound.asm"
				INCLUDE	"playermove.asm"
				INCLUDE	"util.asm"
				INCLUDE	"weapon.asm"
				INCLUDE	"sprite.asm"
				INCLUDE	"boss.asm"
				INCLUDE	"doors.asm"
				INCLUDE	"items.asm"
				INCLUDE	"room.asm"
				INCLUDE	"food.asm"
				INCLUDE	"chicken.asm"
				INCLUDE	"player.asm"
				INCLUDE	"collectables.asm"
				INCLUDE	"clock.asm"
				INCLUDE	"state.asm"
				INCLUDE	"game.asm"
				INCLUDE	"../../build/l80/item_wh.inc"
code80_end:
				SAVEBIN	"../../build/l80/logic.bin", CODE80, code80_end - CODE80
