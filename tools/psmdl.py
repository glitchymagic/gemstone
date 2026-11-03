#!/usr/bin/env python3
"""Power Stone (DC) .MDL parser. Layout (all little-endian), reverse-engineered from the disc:
  part*  := u32 flag(1 | -1=empty) u32 kind f32 sphere[4] material* u32 0 u32 n
  material := u32 PCW(para type 4: 0x80-0x9F list types) u32 ISP u32 TSP u32 TCW f32 sphere[4] u32 texidx u32 0
              f32 face_argb[4] f32 offs_argb[4] u32 0 u32 strip_bytes strip*
  strip  := u32 flags u32 count vertex*count   (flags&8: triangle list, count = triangles -> 3*count vertices)
  vertex := f32 pos[3] f32 nrm[3] f32 uv[2]          (32 bytes)
          | u32 0x5Fxxxxxx(out-ofs) i32 in-ofs        (8 bytes: re-use vertex at end_of_ref+in-ofs)
  tail   := texture table, 16 bytes each: u16 w u16 h u32 fmt u32 ram_addr u32 0
"""
import struct, sys

def parse(d):
    u = lambda o: struct.unpack_from('<I', d, o)[0]
    o = 0; parts = []
    while o + 0x18 <= len(d):
        flag, kind = u(o), u(o + 4)
        if flag not in (1, 0xffffffff):
            break
        sph = struct.unpack_from('<4f', d, o + 8)
        p = {'ofs': o, 'flag': flag, 'kind': kind, 'sphere': sph, 'mats': []}
        o += 0x18
        while (u(o) >> 29) == 4:
            m = {'pcw': u(o), 'isp': u(o + 4), 'tsp': u(o + 8), 'tcw': u(o + 12),
                 'tex': u(o + 0x20), 'face': struct.unpack_from('<4f', d, o + 0x28),
                 'strips': []}
            size = u(o + 0x4c); s = o + 0x50; end = s + size
            while s < end:
                sf, cnt = u(s), u(s + 4); s += 8
                verts = []
                for _ in range(cnt * 3 if sf & 8 else cnt):
                    if (u(s) >> 24) == 0x5f:
                        rel = struct.unpack_from('<i', d, s + 4)[0]
                        r = s + 8 + rel
                        verts.append(struct.unpack_from('<8f', d, r)); s += 8
                    else:
                        verts.append(struct.unpack_from('<8f', d, s)); s += 32
                m['strips'].append((sf, verts))
            p['mats'].append(m); o = end
        assert u(o) == 0, hex(o)
        p['n'] = u(o + 4); o += 8; p['end'] = o
        parts.append(p)
    tex = []
    while o + 16 <= len(d):
        w, h, fmt, addr = struct.unpack_from('<HHII', d, o)
        if w == 0: break
        tex.append((w, h, fmt, addr)); o += 16
    return parts, tex, o

if __name__ == '__main__':
    d = open(sys.argv[1], 'rb').read()
    parts, tex, end = parse(d)
    print(len(parts), 'parts', len(tex), 'textures', 'end', hex(end), 'of', hex(len(d)))
    for i, p in enumerate(parts):
        nv = sum(len(v) for m in p['mats'] for _, v in m['strips'])
        print(i, hex(p['ofs']), hex(p['flag']), p['kind'], 'n=%d' % p['n'], 'verts=%d' % nv,
              'tex=', [m['tex'] for m in p['mats']], 'sph=%.2f,%.2f,%.2f r%.2f' % p['sphere'])
    for t in tex[:8]: print('tex', t[0], t[1], hex(t[2]), hex(t[3]))

def strips_to_tris(sf, verts):
    """Triangle strip (or list when sf&8) -> list of index triples into verts."""
    if sf & 8:
        return [(i, i + 1, i + 2) for i in range(0, len(verts) - 2, 3)]
    tris = []
    for i in range(len(verts) - 2):
        tris.append((i, i + 1, i + 2) if i % 2 == 0 else (i + 1, i, i + 2))
    return tris
