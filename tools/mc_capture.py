#!/usr/bin/env python3
"""Motion Check bulk capture (pass 3): every motion of one fighter form, straight from the game's motion player.
Motion lists come from the fighter's Pn0_MOT.MDT tables (kind k at k*0x200: kind 0/1/3 = its own, kind 2 = the shared
bank, of which the game uses the 22 ids in K2). Prints fc.py command lines; Motion Check must be open with the
right player/form loaded (tools/arcade.py mc N, then the Metamor field).
Usage: mc_capture.py PREFIX Pn0 segs.json KINDS [FRAMES]     e.g.  mc_capture.py a0 P60 rip/mocap/segs_p60_f0.json 0,1"""
import json, struct, sys
ROOT = './'
K2 = [106, 107, 112, 115, 118, 120, 128, 129, 130, 144, 145, 146, 147, 148, 152, 153, 158, 159, 175, 219, 220, 221]


def motions(pn, kind):
    if kind == 2:
        return K2
    t = struct.unpack_from('>256H', open(f'{ROOT}rip/fs/{pn}_MOT.MDT', 'rb').read(), kind * 0x200)
    return sorted(set([0] + [i for i, v in enumerate(t) if v]))


def commands(prefix, pn, segs, kinds, frames=240):
    seg = json.load(open(segs))['seg']
    c = []
    for k in kinds:
        n = frames + 60 if k == 3 else frames
        c += [f'poke8 0x0C49492E {k}', 'poke8 0x0C49492F 3', 'wait 10']
        for m in motions(pn, k):
            c += [f'poke32 0x0C49493C {(m - 1) & 0xFFFFFFFF if m else 0xFFFFFFFF}', f'capseg {prefix}k{k}_{m:03d} {n} {seg}',
                  'press 1 RIGHT 2', f'wait {n}']
    return c


if __name__ == '__main__':
    a = sys.argv[1:]
    print('\n'.join(commands(a[0], a[1], a[2], [int(x) for x in a[3].split(',')], int(a[4]) if len(a) > 4 else 240)))
