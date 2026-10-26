#!/usr/bin/env python3
"""Растяжение графики CPC (точка режима 0 = 2 точки Вектора) со сглаживанием силуэта: на краю фигуры половина
точки становится фоном («стёсывание» угла) или цветом соседа («дорисовка» в пустоту) там, где край идёт по
диагонали; внутренний рисунок не меняется, новых цветов нет. Выбор 26.10 (сравнение: удвоение / все цвета /
силуэт). SMOOTH=0 — простое удвоение. Используют tools/mkgame.py (спрайты, ключи, еда) и tools/mkroom.py (предметы)."""
import os
ON = os.environ.get('SMOOTH', '1') != '0'

def smooth2x(rows):
    """перья CPC (строки по w) -> строки по 2w в точках Вектора"""
    h, w = len(rows), len(rows[0])
    px = lambda x, y: rows[y][x] if 0 <= y < h and 0 <= x < w else 0
    out = []
    for y in range(h):
        o = []
        for x in range(w):
            E = rows[y][x]
            if not ON:
                o += [E, E]; continue
            B, D, F, H = px(x, y - 1), px(x - 1, y), px(x + 1, y), px(x, y + 1)
            if E == 0:                                  # дорисовка: сосед продолжается по диагонали
                l = D if D and ((B == D) != (H == D)) else 0
                r = F if F and ((B == F) != (H == F)) else 0
            else:                                       # стёсывание угла: снаружи пусто, по вертикали — край
                l = 0 if D == 0 and ((B == 0) != (H == 0)) else E
                r = 0 if F == 0 and ((B == 0) != (H == 0)) else E
            o += [l, r]
        out.append(o)
    return out
