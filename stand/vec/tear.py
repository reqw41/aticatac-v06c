# Артефакты луча: доля пикселей спрайтов, показанных не так, как в памяти ни в начале, ни в конце кадра.
#   python3 stand/vec/tear.py <каталог с fr.raw, fr.raw.mem, bg.raw> build/proto/bg.bin
import numpy as np, sys
S, BG = sys.argv[1], sys.argv[2]; W, H = 576, 288
bgb = np.frombuffer(open(S + '/bg.raw', 'rb').read(), np.uint32).reshape(H, W)
fr = np.frombuffer(open(S + '/fr.raw', 'rb').read(), np.uint32).reshape(-1, H, W)
mem = np.frombuffer(open(S + '/fr.raw.mem', 'rb').read(), np.uint8).reshape(-1, 4, 32, 256)
bgm = np.frombuffer(open(BG, 'rb').read(), np.uint8).reshape(4, 32, 256)
def vecmask(m):  # (4,32,256) -> маска 256x256 [y][x], отличие от фона
    d = np.bitwise_or.reduce(m ^ bgm, axis=0)          # (32 столбца, 256 строк памяти)
    bits = np.unpackbits(d[:, :, None], axis=2)         # (32,256,8)
    img = bits.transpose(1, 0, 2).reshape(256, 256)     # [строка памяти][x]
    return img[::-1].astype(bool)                       # y = 255 - строка
def vecimg(m):
    bits = np.unpackbits(m[:, :, :, None], axis=3)      # (4,32,256,8)
    idx = (bits[0] << 3) | (bits[1] << 2) | (bits[2] << 1) | bits[3]
    return idx.transpose(1, 0, 2).reshape(256, 256)[::-1]
# выравнивание bmp и памяти по фону: ищем X0,Y0 с наилучшим совпадением «не чёрное»
bgi = vecimg(bgm) != 0; bgd = bgb != bgb[0, 0]
best = None
for y0 in range(0, H - 255):
    for x0 in range(0, W - 511, 2):
        s = (bgd[y0:y0 + 256, x0:x0 + 512:2] == bgi).mean()
        if best is None or s > best[0]: best = (s, x0, y0)
s, X0, Y0 = best; print('выравнивание: совпадение %.4f при X0=%d Y0=%d' % (s, X0, Y0))
tot = []; bad = []; worst = []
for i, f in enumerate(fr):
    disp = (f != bgb)[Y0:Y0 + 256, X0:X0 + 512:2]
    a, b = vecmask(mem[i]), vecmask(mem[i + 1])
    p = disp & ~a & ~b | ~disp & a & b                  # нет ни в начале, ни в конце / пропал, хотя был в обоих
    tot.append(int((a | b).sum())); bad.append(int(p.sum()))
tot = np.array(tot); bad = np.array(bad)
r = bad / np.maximum(tot, 1)
r2 = r[int(np.argmax(tot > 0)) + 1:]                    # до первого спрайта в памяти — загрузка (палитра, квазидиск)
print('после загрузки: кадров %d, чистых %d, с артефактами %d, худший %.1f%%, средний %.2f%%'
      % (len(r2), (r2 == 0).sum(), (r2 > 0).sum(), r2.max() * 100, r2.mean() * 100))
