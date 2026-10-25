"""Палитра CPC-версии (pens из utils/utils.asm) и перевод в RGB и в байт палитры Вектора %BBGGGRRR."""
HW = {  # аппаратный номер цвета CPC -> (R,G,B), уровни 0/1/2
 0x54:(0,0,0),0x44:(0,0,1),0x55:(0,0,2),0x56:(0,1,0),0x46:(0,1,1),0x57:(0,1,2),0x52:(0,2,0),0x5c:(1,0,0),
 0x5b:(1,2,2),0x4c:(2,0,0),0x4e:(2,1,0),0x47:(2,1,1),0x4a:(2,2,0),0x4b:(2,2,2),0x5d:(1,1,2),0x4d:(2,0,2),
 0x58:(1,0,1)}
PENS = [0x54,0x44,0x55,0x56,0x46,0x57,0x52,0x5c,0x5b,0x4c,0x4e,0x47,0x4a,0x4b,0x5d,0x4d]
def rgb(pen):
    return tuple((0, 128, 255)[c] for c in HW[PENS[pen]])
def vecbyte(pen):
    r, g, b = HW[PENS[pen]]
    return ((0, 2, 3)[b] << 6) | ((0, 4, 7)[g] << 3) | (0, 4, 7)[r]
def mode0(b):  # байт Mode 0 -> (левый, правый) номер пера
    p0 = ((b>>7)&1) | ((b>>3)&1)<<1 | ((b>>5)&1)<<2 | ((b>>1)&1)<<3
    p1 = ((b>>6)&1) | ((b>>2)&1)<<1 | ((b>>4)&1)<<2 | ((b>>0)&1)<<3
    return p0, p1
def cpc_pixels(mem, base):  # 192 строки x 128 перьев из дампа 0x8000..0xFFFF
    out = []
    for y in range(192):
        a = base - 0x8000 + (y >> 3) * 64 + (y & 7) * 0x800
        row = []
        for x in range(64): row += mode0(mem[a + x])
        out.append(row)
    return out
