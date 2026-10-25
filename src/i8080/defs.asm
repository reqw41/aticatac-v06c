; defs.asm: общие определения логики i8080 (сверка logic.asm и игра src/vec/game.asm).
FOOD80			equ		0x3800				; food_items (банк героев CPC 0x5FD8) -> сюда
FOOD_DELTA		equ		FOOD80 - C_food_items
