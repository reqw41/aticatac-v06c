#!/usr/bin/env python3
"""Заставка: экран загрузки CPC (build/cpcnew/loading.bin: режим 0, 160x200, строки по 80 байт; перья — таблица
pens загрузчика ref/cpc/loader.asm, цвета прошивки) -> экран Вектора: картинка 256 x 200 (растяжение по ширине
со сглаживанием, по вертикали — как есть), ниже — полоска загрузки и надпись «НАЖМИТЕ ПРОБЕЛ» (шрифт меню CPC,
Ж И П Б Л дорисованы); 8 цветов (3 плоскости, 4-я — код), набор SPLASH_COLS.
  python3 tools/mksplash.py build/game [предпросмотр.png]  -> splash01_kv.bin, splash2_kv.bin, splash.inc
"""
import os, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from cpcpal import mode0
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
PENS = [0, 1, 2, 9, 11, 18, 3, 4, 23, 6, 7, 8, 15, 16, 24, 26]          # ref/cpc/loader.asm pens
fw = lambda n: tuple((0, 128, 255)[v] for v in ((n // 3) % 3, n // 9, n % 3))   # цвет прошивки -> RGB

def cpc_image():
    d = open(os.path.join(ROOT, 'build/cpcnew/loading.bin'), 'rb').read()
    img = Image.new('RGB', (160, 200))
    for y in range(200):
        for x in range(80):
            p0, p1 = mode0(d[y * 80 + x])
            img.putpixel((2 * x, y), fw(PENS[p0])); img.putpixel((2 * x + 1, y), fw(PENS[p1]))
    return img

# цвета Вектора: %BBGGGRRR
VEC = [((b & 7) * 255 // 7, ((b >> 3) & 7) * 255 // 7, ((b >> 6) & 3) * 255 // 3) for b in range(256)]
def vbyte(rgb):
    return min(range(256), key=lambda b: sum((VEC[b][i] - rgb[i]) ** 2 for i in range(3)))

def best8():
    """8 из 16 цветов загрузчика: перебор сочетаний (чёрный всегда) по ошибке на исходной картинке"""
    import itertools, collections
    src = cpc_image()
    hist = collections.Counter(src.getdata())
    cols = sorted(set(fw(PENS[i]) for i in range(16)))
    d2 = lambda a, b: (a[0] - b[0]) ** 2 * 2 + (a[1] - b[1]) ** 2 * 4 + (a[2] - b[2]) ** 2 * 3
    best = None
    others = [c for c in cols if c != (0, 0, 0)]
    for sub in itertools.combinations(others, 7):
        sel = ((0, 0, 0),) + sub
        e = sum(n * min(d2(c, s) for s in sel) for c, n in hist.items())
        if best is None or e < best[0]: best = (e, sel)
    return list(best[1])

def convert(dither=True, smooth=Image.LANCZOS, cols=None):
    cols = cols or best8()
    vb = [vbyte(c) for c in cols]
    big = cpc_image().resize((256, 256), smooth)
    pimg = Image.new('P', (1, 1)); pimg.putpalette(sum((list(VEC[b]) for b in vb), []) + [0] * (768 - 24))
    q = big.quantize(palette=pimg, dither=Image.FLOYDSTEINBERG if dither else Image.NONE)
    return q, vb

# набор (сравнение 26.10): балахон пурпурный, лягушки и Ultimate зелёные; оранжевый -> красный/жёлтый
SPLASH_COLS = [(0, 0, 0), (0, 0, 128), (0, 0, 255), (255, 0, 0), (255, 255, 0), (255, 255, 255), (0, 255, 0), (255, 0, 128)]
SPLASH_P01, SPLASH_P2 = 0x5C00, 0xCC00                 # квазидиск стр. 0: плоскости 0-1 после меню, 2 и надпись — после звука
IMG_Y = 4                                            # картинка 256 x 200 со строки 4; ниже — полоска и надпись
TEXT = 'НАЖМИТЕ ПРОБЕЛ'
TEXT_Y, TEXT_COL = 236, (32 - len(TEXT)) // 2
WHITE = 5                                            # индекс белого в SPLASH_COLS
# буквы шрифта меню CPC (font_data_mode1) по латинским двойникам; Ж, И, П, Б, Л — нарисованы в том же стиле
OWN = {
 'И': ['........', '@@..@@..', '@@..@@@.', '@@..@@@.', '@@.@.@@.', '@@@..@@.', '@@@..@@.', '.@@..@@.'],
 'П': ['........', '@@@@@@@.', '@@...@@.', '@@...@@.', '@@...@@.', '@@...@@.', '@@@..@@.', '.@@..@@.'],
 'Л': ['........', '..@@@@@.', '.@@..@@.', '.@@..@@.', '.@@..@@.', '.@@..@@.', '@@@..@@.', '@@...@@.'],
 'Б': ['........', '@@@@@@..', '@@......', '@@.@@...', '@@@.@@..', '@@...@@.', '@@@..@@.', '@@.@@@..'],
 'Ж': ['........', '@@.@.@@.', '.@@@@@..', '..@@@...', '.@@@@@..', '@@.@.@@.', '@@.@.@@.', '@@.@.@@.'],
}
LAT = {'Н': 'H', 'А': 'A', 'М': 'M', 'Т': 'T', 'Е': 'E', 'Р': 'P', 'О': 'O', ' ': ' '}

def glyph(ch):
    if ch in OWN: return [[c == '@' for c in r] for r in OWN[ch]]
    import roomref as rr
    rooms = open(os.path.join(ROOT, 'build/cpcnew/rooms.bin'), 'rb').read()
    g = rr.SYM['font_data_mode1'] - 0x4000 + 16 * (ord(LAT[ch]) - 32)
    out = []
    for y in range(8):
        row = []
        for b in (rooms[g + 2 * y], rooms[g + 2 * y + 1]):
            for i in range(4): row.append(bool(((b >> (7 - i)) & 1) | ((b >> (3 - i)) & 1)))
        out.append(row)
    return out

def main():
    out = sys.argv[1]
    vb = [vbyte(c) for c in SPLASH_COLS]
    pic = cpc_image().resize((256, 200), Image.BICUBIC)       # по вертикали не растягивается
    pimg = Image.new('P', (1, 1)); pimg.putpalette(sum((list(VEC[b]) for b in vb), []) + [0] * (768 - 24))
    q = pic.quantize(palette=pimg, dither=Image.NONE)
    canvas = Image.new('P', (256, 256), 0); canvas.paste(q, (0, IMG_Y))
    px = canvas.load()
    planes = []
    for k in range(3):
        blob = bytearray()
        for c in range(32):
            for y in range(256):                     # сверху вниз: строка памяти 255 - y
                v = 0
                for j in range(8):
                    if (px[c * 8 + j, y] >> (2 - k)) & 1: v |= 0x80 >> j
                blob.append(v)
        planes.append(blob)
    text = bytearray()                               # надпись: 3 плоскости x столбцы x 8 строк
    gl = [glyph(ch) for ch in TEXT]
    for k in range(3):
        for g in gl:
            for y in range(8):
                v = 0
                if (WHITE >> (2 - k)) & 1:
                    for j in range(8):
                        if g[y][j]: v |= 0x80 >> j
                text.append(v)
    open(os.path.join(out, 'splash01_kv.bin'), 'wb').write(bytes(planes[0] + planes[1]))
    open(os.path.join(out, 'splash2_kv.bin'), 'wb').write(bytes(planes[2] + text))
    pal = [vb[i >> 1] for i in range(16)]
    open(os.path.join(out, 'splash.inc'), 'w').write('; сгенерировано tools/mksplash.py\nSPLASH_P01\tequ 0x%04X\nSPLASH_P2\tequ 0x%04X\nSPLASH_TEXT\tequ 0x%04X\nSPL_TEXT_N\tequ %d\nSPL_TEXT_DST\tequ 0x%02X%02X\npal_splash:\tDB %s\n' % (
        SPLASH_P01, SPLASH_P2, SPLASH_P2 + 8192, len(TEXT), 0x80 + TEXT_COL, 255 - TEXT_Y, ', '.join('0x%02X' % v for v in pal)))
    if len(sys.argv) > 2:
        canvas.convert('RGB').resize((512, 512), Image.NEAREST).save(sys.argv[2])

if __name__ == '__main__':
    main()
