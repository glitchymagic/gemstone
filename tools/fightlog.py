#!/usr/bin/env python3
"""Log both fighters' live motion in a real Flycast fight (pass 3).
Player structs: P1 0x0C7E40C4, P2 0x0C7EB394 (stride 0x72D0). Fields (offsets from the struct):
  +0x710A/B/C face / R hand / L hand variant   +0x71A4 kind  +0x71A5 motion (set by set_motion = 0x0C09A808)
  +0x71BA state  +0x71BB previous state         +0x71D4 s16 health (240 max; +0x71D6/8 display copies)
  +0x71F3 Power Change flag                      +0x7230 gem count  +0x7231 gem bitmask (1/2/4)
Usage: fightlog.py segs            -> the capseg segment string to send to flycast_drive.lua
       fightlog.py show NAME [P]   -> motion sequence (frame:kKIND/MOTION[face,R,L] sN) per player
       fightlog.py sel P NAME...   -> per motion, the face/hand selector held longest (make_clipmap.py SEL)"""
import sys
import numpy as np
BASES = [0x0C7E40C4, 0x0C7EB394]
FIELDS = [(0x710A, 3), (0x71A4, 2), (0x71BA, 1), (0x71F3, 1), (0x7230, 1)]   # (offset, bytes)


def segs():
    out = []
    for b in BASES:
        for o, n in FIELDS:
            a = b + o
            out.append(f'0x{a & ~3:08X}:{((a & 3) + n + 3) // 4 * 4}')
    return ','.join(out)


def layout():
    pos, res = 0, []
    for b in BASES:
        d = {}
        for o, n in FIELDS:
            a = b + o
            d[o] = pos + (a & 3)
            pos += ((a & 3) + n + 3) // 4 * 4
        res.append(d)
    return res, pos


def seq(name, p):
    lay, size = layout()
    a = np.fromfile(f'./dumps/cap/{name}.bin', dtype=np.uint8).reshape(-1, size)
    d = lay[p]
    out, prev = [], None
    for f, r in enumerate(a):
        sel = r[d[0x710A]:d[0x710A] + 3].tolist()
        cur = (int(r[d[0x71A4]]), int(r[d[0x71A4] + 1]), tuple(sel), int(r[d[0x71BA]]), int(r[d[0x71F3]]), int(r[d[0x7230]]))
        if cur != prev:
            out.append((f,) + cur); prev = cur
    return out


def dominant(names, p):
    """kKIND/MOTION -> the [face, R, L] selector held for the most frames over all logs (default [0,0,0] included)."""
    tot = {}
    for name in names:
        s = seq(name, p)
        for (f, k, m, sel, *_), nxt in zip(s, s[1:] + [(None,)]):
            if nxt[0] is None: break
            d = tot.setdefault(f'k{k}_{m:03d}', {})
            d[sel] = d.get(sel, 0) + nxt[0] - f
    return {mo: list(max(d, key=d.get)) for mo, d in sorted(tot.items())}


if __name__ == '__main__':
    if sys.argv[1] == 'segs':
        print(segs())
    elif sys.argv[1] == 'sel':
        print({k: v for k, v in dominant(sys.argv[3:], int(sys.argv[2]) - 1).items() if v != [0, 0, 0]})
    else:
        ps = [int(sys.argv[3]) - 1] if len(sys.argv) > 3 else [0, 1]
        for p in ps:
            s = seq(sys.argv[2], p)
            print(f'P{p + 1}:', ' '.join(f'{f}:k{k}/{m}{list(sel) if sel != (0, 0, 0) else ""}s{st}{"*" if pc else ""}g{g}'
                                       for f, k, m, sel, st, pc, g in s))
