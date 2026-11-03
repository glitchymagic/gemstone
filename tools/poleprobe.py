#!/usr/bin/env python3
"""Find the game's pole swing (pass 3): in a running arcade fight, put P1 next to a real pole (the stage records tagged
1.4, see stage_layout.py) and try every button with and without a direction held, logging both players' motion bytes.
P1 x/y/z = player +0x148/+0x14C/+0x150 (floats, cm). Usage (Flycast in a fight):
  poleprobe.py run STGn0 TAG     -> dumps RAM, finds the poles, runs the probes (capseg dumps/cap/TAG.bin)
  poleprobe.py show TAG          -> per probe: the P1 motions that are not idle/run/walk"""
import json, struct, subprocess, sys
import numpy as np
R = './'
PY = 'python3'
sys.path.insert(0, R + 'tools')
import mocap
P1 = 0x0C7E40C4
X, Y, Z = P1 + 0x148, P1 + 0x14C, P1 + 0x150
B = 0x0C000000
PROBES = [(d, b) for b in ('A', 'X', 'Y', 'B', 'X+Y') for d in ('', 'UP', 'DOWN', 'LEFT', 'RIGHT')]


def fc(cmds, wait=600):
    return subprocess.run([PY, R + 'tools/fc.py', '-w', str(wait), *cmds], check=True, text=True, capture_output=True).stdout


def f32(v):
    return '0x%08X' % struct.unpack('<I', struct.pack('<f', v))[0]


def poles(ram, stg):
    parts, base, _ = mocap.find_records(ram, R + f'rip/fs/{stg}.MDL', 0)
    p2 = {base + p['ofs']: k for k, p in enumerate(parts)}
    a = np.frombuffer(ram[:len(ram) // 4 * 4], dtype='<u4')
    out = []
    for i in np.nonzero(np.isin(a, np.array(list(p2), dtype=np.uint32)))[0]:
        o = int(i) * 4
        M = np.array(struct.unpack_from('<16f', ram, o - 0x4C)).reshape(4, 4)
        if abs(M[3, 3] - 1) > 1e-3: continue
        if abs(struct.unpack_from('<f', ram, o - 4)[0] - 1.4) < 1e-4:
            out.append((p2[int(a[i])], float(M[3, 0]), float(M[3, 2])))
    return out


def run(stg, tag):
    fc([f'dump {tag}.bin 0x0C000000 0x1000000'], 120)
    ram = open(R + f'dumps/{tag}.bin', 'rb').read()
    ps = poles(ram, stg)
    print('poles', ps)
    part, px, pz = ps[0]
    y = struct.unpack_from('<f', ram, Y - B)[0]
    segs = subprocess.check_output([PY, R + 'tools/fightlog.py', 'segs'], text=True).strip()
    c = [f'capseg {tag} {len(PROBES) * 200 + 200} {segs}']
    for k, (d, b) in enumerate(PROBES):
        c += [f'mark probe{k}', f'poke32 0x{X:08X} {f32(px + 60)}', f'poke32 0x{Z:08X} {f32(pz)}', 'wait 30']
        if d: c += [f'hold 1 {d} 12', 'wait 6']
        c += [f'press 1 {b} 4', 'wait 160']
    json.dump({'stage': stg, 'pole': ps[0], 'probes': PROBES, 'frames': 200}, open(R + f'work/{tag}.json', 'w'))
    print(fc(c, 1200))


def show(tag):
    import fightlog
    meta = json.load(open(R + f'work/{tag}.json'))
    s = fightlog.seq(tag, 0)
    # probe k starts at frame ~ k*200 (+ the capture's start offset); print P1's non-locomotion motions per window
    for k, (d, b) in enumerate(meta['probes']):
        lo, hi = k * 200, (k + 1) * 200
        ms = [f'{f - lo}:k{kk}/{m}s{st}' for f, kk, m, sel, st, pc, g in s if lo <= f < hi and (kk, m) not in ((0, 0), (0, 25), (0, 26))]
        print(f'{k:2d} {d or "-":5s} {b:4s}', ' '.join(ms))


if __name__ == '__main__':
    run(sys.argv[2], sys.argv[3]) if sys.argv[1] == 'run' else show(sys.argv[2])
