"""Общие константы раскладки цветов и строк для mkroom.py / roomcmp.py."""
ROW0 = 223
PAL8 = (0, 1, 4, 7, 8, 10, 13, 15)
PMAP = [0, 1, 1, 2, 2, 2, 2, 3, 4, 3, 5, 5, 5, 6, 4, 7]
PERM = (0, 2, 3, 5, 4, 1, 7, 6)                    # как выбрал mkovr.py
INV = [PERM.index(j) for j in range(8)]
SLOT = [INV[PMAP[p]] for p in range(16)]          # перо CPC -> индекс палитры Вектора (3 бита)
