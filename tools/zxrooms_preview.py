#!/usr/bin/env python3
"""Превью: предметы комнат из ZX-рисунков (ref/zx) с цветами CPC, как спрайты GFX_ZX (tools/zxgfx.py): для каждого
варианта CPC (стена, поворот) подбирается поворот/отражение ZX-рисунка по силуэту, дыры внутри — цветом CPC.
В сборку не подключено. python3 tools/zxrooms_preview.py -> build/zx_rooms.png (CPC | наш | ZX), цвета — CPC."""
import sys, os, collections
ROOT=os.path.expanduser('~/projects/aticatac-v06c'); sys.path.insert(0, ROOT+'/tools')
import roomref as rr, zxgfx, pixsmooth
from cpcpal import mode0, rgb
from PIL import Image, ImageDraw, ImageFont
S=os.path.join(ROOT, 'build')
def variant(t, rot):
    meta = rr.w16(rr.I, rr.SYM['item_bank_items'] + 2 * t)
    size = rr.w16(rr.I, meta + 2)
    if rot & 0x40: rows, nb, data = rr.I(meta) * 4, rr.I(meta + 1) >> 2, rr.w16(rr.I, meta + 6)
    else: rows, nb, data = rr.I(meta + 1), rr.I(meta), rr.w16(rr.I, meta + 4)
    flip = bool(rot & 0x80); k = data + size - 1 if flip else data; px = []
    for r in range(rows):
        row = []
        for i in range(nb):
            p0, p1 = mode0(rr.I(k)); k += -1 if flip else 1
            row += [p1, p0] if flip else [p0, p1]
        px.append(row)
    return px
used=set()
item_list = rr.SYM['room_bank_item_list']; end = rr.SYM['room_bank_items_per_room']
for ix in range(item_list, end, 8):
    t, st, rot = rr.R(ix), rr.R(ix + 2), rr.R(ix + 5) & 0xC0
    for s in (0, 0x80): used.add((rr.convert_door_type(t, s), rot))
M={1:'g_cave_door_frame',35:'g_cave_door_frame',2:'g_door_frame',33:'g_door_frame',3:'g_bigdoor_frame',
   8:'g_door_locked',9:'g_door_locked',10:'g_door_locked',11:'g_door_locked',12:'g_cave_locked',13:'g_cave_locked',14:'g_cave_locked',15:'g_cave_locked',
   16:'g_clock',17:'g_ghost_picture',37:'g_pumpkin_picture',18:'g_table',21:'g_wall_antlers',22:'g_wall_trophy',23:'g_bookcase',24:'g_trap_open',25:'g_trap_closed',
   26:'g_barrel',27:'g_rug',28:'g_acg_shield',29:'g_wall_shield',30:'g_suit_armour',32:'g_door_shut',34:'g_cave_door_shut',36:'g_acg_door',38:'g_skeleton',39:'g_barrel_stack'}
def ibits(name):
    d=zxgfx.ZX[name]; wb,h=d[0],d[1]
    return [[(d[2+y*wb+x//8]>>(7-x%8))&1 for x in range(wb*8)] for y in range(h)]
def transforms(b):
    out=[]
    for k in range(4):
        for f in (0,1):
            m=[r[::-1] for r in b] if f else [r[:] for r in b]
            for _ in range(k): m=[list(r) for r in zip(*m[::-1])]
            out.append(((k,f),m))
    return out
def best_fit(rows, name):
    hc, wc = len(rows), 2*len(rows[0])
    cp = lambda X,Y: rows[Y][X//2] if 0<=Y<hc and 0<=X<wc else 0
    best=None
    cpc_n=sum(1 for y in range(hc) for x in range(wc) if cp(x,y))
    for tr,zb in transforms(ibits(name)):
        h,w=len(zb),len(zb[0])
        if h>hc+4 or w>wc+4: continue
        for dy in range(min(0,hc-h), max(0,hc-h)+1):
            for dx in range(min(0,wc-w), max(0,wc-w)+1):
                on=off=0
                for y in range(h):
                    for x in range(w):
                        if zb[y][x]:
                            if cp(x+dx,y+dy): on+=1
                            else: off+=1
                sc=on-0.5*off-0.3*(cpc_n-on)
                if best is None or sc>best[0]: best=(sc,tr,dx,dy,zb)
    return best
def colorize(rows, fit):
    sc,tr,dx,dy,zb=fit
    hc, wc = len(rows), 2*len(rows[0])
    cp = lambda X,Y: rows[Y][X//2] if 0<=Y<hc and 0<=X<wc else 0
    h,w=len(zb),len(zb[0])
    allp=[p for r in rows for p in r if p]; common=collections.Counter(allp).most_common(1)[0][0] if allp else 13
    out=[[0]*wc for _ in range(hc)]; zm=[[0]*wc for _ in range(hc)]
    for y in range(h):
        for x in range(w):
            X,Y=x+dx,y+dy
            if not zb[y][x] or not (0<=X<wc and 0<=Y<hc): continue
            zm[Y][X]=1; p=cp(X,Y)
            if not p:
                for r in (1,2,3):
                    c=[cp(X+i,Y+j) for i in range(-r,r+1) for j in range(-r,r+1) if cp(X+i,Y+j)]
                    if c: p=collections.Counter(c).most_common(1)[0][0]; break
            out[Y][X]=p or common
    for Y,X in zxgfx.holes(zm):
        p=cp(X,Y)
        if p: out[Y][X]=p
    return out
cells=[]
for (t,rot) in sorted(used):
    if t not in M or M[t] not in zxgfx.ZX: continue
    rows=variant(t,rot)
    if not rows or not rows[0]: continue
    fit=best_fit(rows,M[t])
    if not fit: continue
    cells.append(('%d %s r%02X %s'%(t,M[t][2:],rot,fit[1]),rows,pixsmooth.smooth2x(rows),colorize(rows,fit)))
F=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 11)
PW,PH=2,2
cw=max(2*len(c[1][0]) for c in cells)*PW*3+40; ch=max(len(c[1]) for c in cells)*PH+20
NC=max(1,1900//cw)
o=Image.new('RGB',(NC*cw,((len(cells)+NC-1)//NC)*ch+20),(40,40,40)); d=ImageDraw.Draw(o)
d.text((4,4),'CPC-оригинал | наш (CPC, сглажен) | формы ZX с цветами CPC, дыры закрашены',fill=(230,230,230),font=F)
for i,(name,rows,hi,zx) in enumerate(cells):
    x0=(i%NC)*cw+4; y0=(i//NC)*ch+20
    d.text((x0,y0),name,fill=(200,200,200),font=F)
    W=2*len(rows[0])*PW+10
    for k,img in enumerate((None,hi,zx)):
        for y in range(len(rows)):
            for x in range(2*len(rows[0])):
                p=rows[y][x//2] if img is None else img[y][x]
                if p: d.rectangle((x0+k*W+x*PW,y0+14+y*PH,x0+k*W+x*PW+PW-1,y0+14+y*PH+PH-1),fill=rgb(p))
o.save(os.path.join(S, 'zx_rooms.png')); print(o.size,len(cells),'нет ZX:',sorted({t for t,r in used if t not in M}))
