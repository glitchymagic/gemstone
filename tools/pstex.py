#!/usr/bin/env python3
"""Power Stone (DC) *_MODEL.BIN texture blob: u16 header, then u16 tokens.
   token 0x10nn (count = low 12 bits): repeat next u16 pixel count times
   token 0x00nn: copy count literal u16s
Decompressed blob = textures back to back in the order/size of the .MDL texture table
(fmt high byte: 1 twiddled, 2 twiddled+mip, 3 VQ, 4 VQ+mip; low byte pixel fmt: 0 1555, 1 565, 2 4444)."""
import struct, sys
from PIL import Image

def decompress(d):
    out = bytearray(); o = 2; unk = {}
    while o + 2 <= len(d):
        t = struct.unpack_from('<H', d, o)[0]; o += 2
        kind, n = t >> 12, t & 0xfff
        if kind == 1:
            out += d[o:o + 2] * n; o += 2
        elif kind == 0:
            out += d[o:o + 2 * n]; o += 2 * n
        else:
            unk[kind] = unk.get(kind, 0) + 1
            break
    return bytes(out), o, unk

def untwiddle_index(x, y, w, h):
    # Morton order, square part; DC twiddle: bit interleave with y in low bit
    mn = min(w, h); idx = 0; bit = 0
    xx, yy = x % mn, y % mn
    k = 1; i = 0
    while k < mn:
        idx |= ((yy & k) << i) | ((xx & k) << (i + 1))
        k <<= 1; i += 1
    # rectangular: blocks of mn*mn
    if w > h: idx += (x // mn) * mn * mn
    elif h > w: idx += (y // mn) * mn * mn
    return idx

def px(v, fmt):
    if fmt == 1:  # 565
        return ((v >> 11 & 31) * 255 // 31, (v >> 5 & 63) * 255 // 63, (v & 31) * 255 // 31, 255)
    if fmt == 0:  # 1555
        return ((v >> 10 & 31) * 255 // 31, (v >> 5 & 31) * 255 // 31, (v & 31) * 255 // 31, 255 if v & 0x8000 else 0)
    if fmt == 2:  # 4444
        return ((v >> 8 & 15) * 17, (v >> 4 & 15) * 17, (v & 15) * 17, (v >> 12 & 15) * 17)
    return (255, 0, 255, 255)

# index bytes of all smaller levels: 1x1 and 2x2 take one byte each, then (s/2)^2 (fixed pass 2: was +6, garbled Londo's floor)
VQ_MIP = [0x0, 0x1, 0x2, 0x6, 0x16, 0x56, 0x156, 0x556, 0x1556, 0x5556, 0x15556]
TW_MIP = [0x3, 0x4, 0x8, 0x18, 0x58, 0x158, 0x558, 0x1558, 0x5558, 0x15558, 0x55558]

def decode(blob, w, h, fmt):
    pf = fmt & 0xff; kind = fmt >> 8
    lv = w.bit_length() - 1
    if kind == 4:   # VQ + mipmaps: keep codebook, jump to the top level
        blob = blob[:2048] + blob[2048 + VQ_MIP[lv]:]
    elif kind == 2:  # twiddled + mipmaps
        blob = blob[TW_MIP[lv] * 2:]
    vq = kind in (3, 4)
    img = Image.new('RGBA', (w, h)); P = img.load()
    if vq:
        cb = [struct.unpack_from('<4H', blob, i * 8) for i in range(256)]
        idx = blob[2048:]
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                c = cb[idx[untwiddle_index(x // 2, y // 2, w // 2, h // 2)]]
                # codebook entry: 2x2 texels in twiddled order (0:(0,0) 1:(0,1) 2:(1,0) 3:(1,1))
                P[x, y] = px(c[0], pf); P[x, y + 1] = px(c[1], pf)
                P[x + 1, y] = px(c[2], pf); P[x + 1, y + 1] = px(c[3], pf)
    else:
        for y in range(h):
            for x in range(w):
                P[x, y] = px(struct.unpack_from('<H', blob, untwiddle_index(x, y, w, h) * 2)[0], pf)
    return img

def tex_size(w, h, fmt):
    k = fmt >> 8; lv = w.bit_length() - 1
    if k == 3: return 2048 + w * h // 4
    if k == 4: return 2048 + VQ_MIP[lv] + w * h // 4
    if k == 2: return (TW_MIP[lv] + w * h) * 2
    return w * h * 2

if __name__ == '__main__':
    import os
    sys.path.insert(0, os.path.dirname(__file__))
    import psmdl
    mdl, mb, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(outdir, exist_ok=True)
    _, tex, _ = psmdl.parse(open(mdl, 'rb').read())
    blob, used, unk = decompress(open(mb, 'rb').read())
    base = tex[0][3]
    need = tex[-1][3] - base + tex_size(*tex[-1][:3])
    print('blob', len(blob), 'need', need, 'consumed', used, 'of', os.path.getsize(mb), 'unk', unk)
    for i, (w, h, fmt, addr) in enumerate(tex):
        o = addr - base
        decode(blob[o:o + tex_size(w, h, fmt)], w, h, fmt).save(f'{outdir}/t{i:02d}.png')
