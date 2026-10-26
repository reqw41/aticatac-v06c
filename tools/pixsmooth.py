#!/usr/bin/env python3
"""Растяжение графики CPC (точка режима 0 = 2 точки Вектора) со сглаживанием силуэта: на краю фигуры половина
точки становится фоном («стёсывание» угла) или цветом соседа («дорисовка» в пустоту) там, где край идёт по
диагонали; внутренний рисунок не меняется, новых цветов нет. Выбор 26.10 (сравнение: удвоение / все цвета /
силуэт). По умолчанию — простое удвоение; SMOOTH=1 — сглаживание (края выходят «мохнатыми», отклонено 26.10). Используют tools/mkgame.py (спрайты, ключи, еда, панель, курица, жизни, цифры) и tools/mkroom.py (предметы)."""
import os
ON = os.environ.get('SMOOTH', '1') != '0'

def smooth2x_pixel(rows):
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


def smooth2x(rows, holes=False):
    """сглаживание по контуру силуэта (фон — чёрное, связанное с рамкой; внутренние дыры не трогаются): край прослеживается по строкам; там, где он стоит на
    месте n строк и сдвигается на 1 точку CPC, последние n // 2 строк отрезка сдвигаются на полточки к следующему
    (лесенка 2+2 -> шаг в 1 точку Вектора). Диагонали 45 градусов (n = 1) и одиночные точки не меняются."""
    h, w = len(rows), len(rows[0])
    out = [[p for p in r for _ in (0, 1)] for r in rows]
    if not ON: return out
    px = lambda x, y: rows[y][x] if 0 <= y < h and 0 <= x < w else 0
    # фон — только чёрное, связанное с рамкой кадра: глаза, рот, прорези внутри фигуры — рисунок, не край
    outside = set(); st = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while st:
        x, y = st.pop()
        if not (0 <= x < w and 0 <= y < h) or (x, y) in outside or rows[y][x]: continue
        outside.add((x, y)); st += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    # holes=True — край и у чёрного внутри (панель: контурный рисунок свитка, чёрное внутри — тоже фон)
    bg = (lambda x, y: not (0 <= x < w and 0 <= y < h) or not rows[y][x]) if holes else \
         (lambda x, y: not (0 <= x < w and 0 <= y < h) or (x, y) in outside)
    for side in (-1, 1):                              # -1 — левые края, 1 — правые
        edges = [[x for x in range(w) if px(x, y) and bg(x + side, y)] for y in range(h)]
        used = set()
        for y0 in range(h):
            for x0 in edges[y0]:
                if (x0, y0) in used: continue
                chain = [(x0, y0)]; used.add((x0, y0)); x, y = x0, y0
                while y + 1 < h:                      # цепочка вниз: край следующей строки рядом (0 или 1)
                    nxt = [e for e in edges[y + 1] if abs(e - x) <= 1 and (e, y + 1) not in used]
                    if not nxt: break
                    x = min(nxt, key=lambda e: abs(e - x)); y += 1
                    chain.append((x, y)); used.add((x, y))
                segs = []                             # отрезки одинакового x
                for (x, y) in chain:
                    if segs and segs[-1][0] == x: segs[-1][2] = y
                    else: segs.append([x, y, y])
                for a, b in zip(segs, segs[1:]):
                    d = b[0] - a[0]
                    if abs(d) != 1: continue
                    n = a[2] - a[1] + 1
                    for yy in range(a[2] - n // 2 + 1, a[2] + 1):
                        x = a[0]; c = px(x, yy)
                        out_toward = (d == side)      # край уходит наружу — дорисовать, внутрь — стесать
                        if side == -1:
                            if out_toward:
                                if x > 0: out[yy][2 * x - 1] = c   # правая половина соседа слева
                            else: out[yy][2 * x] = 0                # левая половина края
                        else:
                            if out_toward:
                                if x < w - 1: out[yy][2 * x + 2] = c   # левая половина соседа справа
                            else: out[yy][2 * x + 1] = 0            # правая половина края
    return out
