; Atic Atac для Вектора-06Ц (квазидиск): логика CPC на i8080 (src/i8080, сверена с JS-моделью),
; вывод — комнаты и спрайты (src/vec). Раскладка: страница 0 CPC по своим адресам (переменные и таблицы
; логики), код и данные — в свободных участках (tools/layout.py), банк комнат 0x4000, еда FOOD80, экран
; 0x8000..0xDFFF (8 цветов, 3 плоскости). Графика — в квазидиске (build/game/aticatac.edd).
;   tools/build_game.sh
				DEVICE	NOSLOT64K
				INCLUDE	"../../build/l80/cpcsym.inc"
				INCLUDE	"../i8080/defs.asm"
				INCLUDE	"../../build/room/room.inc"

				ORG		0x0000
				di
				jp		start
				ORG		0x0038				; RST 7 — только чтобы halt дождался начала кадра (палитра)
				ret

				ORG		0x0100
				INCBIN	"../../build/cpcnew/gamecode.bin"
				ORG		FOOD80
				INCBIN	"../../build/cpcnew/heroes.bin", C_food_items - 0x4000, C_food_items_end - C_food_items
				ORG		0x4000
				INCBIN	"../../build/cpcnew/rooms.bin"
				INCLUDE	"../../build/game/patch.inc"
				INCLUDE	"../../build/game/layout.inc"
				SAVEBIN	"../../build/game/aticatac.rom", 0, 0x10000
