#!/usr/bin/env python3
"""Coverage tapes (fx-cov, docs/COVERAGE.md): writes game/tests/tapes/{stg_*,mash_*}.tape. Re-running it rewrites the
same files (the mash tapes are seeded: the seed is in the file name).
  cov_tapes.py stages     11 stage tapes: P1 vs the stage's owner (P2's home stage), from the start points (spawns.json)
                          8 runs into every wall / edge with 3 jump presses at the end (ledges, wall kicks), running and
                          standing jumps, then both 100 cm apart in the middle trading punches / kicks / grabs
  cov_tapes.py mash       seeded random buttons + directions (both pads), fighters placed 150 cm apart
  cov_tapes.py all"""
import json, math, os, random, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
OUT = REPO + 'game/tests/tapes/'
SP = json.load(open(REPO + 'game/assets/fidelity/spawns.json'))
# P1 vs P2 per stage (P2 = the stage's owner): every fighter plays once as P1 and once as the owner
STAGES = [('stg00', 'ryoma', 'falcon'), ('stg10', 'falcon', 'ryoma'), ('stg20', 'gunrock', 'wangtang'),
          ('stg30', 'galuda', 'jack'), ('stg40', 'ayame', 'gunrock'), ('stg50', 'rouge', 'galuda'),
          ('stg60', 'kraken', 'ayame'), ('stg70', 'valgas', 'rouge'), ('stg80', 'wangtang', 'kraken'),
          ('stg90', 'jack', 'valgas'), ('stga0', 'ryoma', 'finalvalgas')]
OPP = {'UP': 'DOWN', 'DOWN': 'UP', 'LEFT': 'RIGHT', 'RIGHT': 'LEFT'}
DIRS = ['UP', 'RIGHT', 'DOWN', 'LEFT', 'UP+RIGHT', 'DOWN+RIGHT', 'DOWN+LEFT', 'UP+LEFT']
MASH = [(11, 'ryoma', 'falcon'), (22, 'jack', 'wangtang'), (33, 'rouge', 'ayame'), (44, 'gunrock', 'galuda'),
        (55, 'falcon', 'kraken')]


def opp(d):
    return '+'.join(OPP[x] for x in d.split('+'))


def ang(a, b):
    """u16 facing from a to b (0 = +z, 0x4000 = +x)"""
    return int(round(math.atan2(b[0] - a[0], b[2] - a[2]) / (2 * math.pi) * 65536)) % 65536


def place(stg, gap=None):
    """@place lines: the start points (gap None) or both gap cm apart round the start points' midpoint, facing."""
    if stg not in SP: return []
    a, b = SP[stg][0][:3], SP[stg][1][:3]
    if gap is not None:
        m = [(a[i] + b[i]) / 2 for i in range(3)]
        d = math.hypot(b[0] - a[0], b[2] - a[2]) or 1
        u = ((b[0] - a[0]) / d, (b[2] - a[2]) / d)
        a = [m[0] - u[0] * gap / 2, a[1], m[2] - u[1] * gap / 2]
        b = [m[0] + u[0] * gap / 2, b[1], m[2] + u[1] * gap / 2]
    f = lambda v: ' '.join(f'{x:g}' for x in (round(v[0]), round(v[1]), round(v[2])))
    return [f'@place 1 {f(a)} {ang(a, b)}', f'@place 2 {f(b)} {ang(b, a)}']


def stage_tape(stg, p1, p2):
    L = [f'#! p1={p1} p2={p2}', f'# fx-cov stage tape {stg} (tools/cov_tapes.py): walls / edges / ledges / wall kicks,',
         '# jumps, close-range attacks. Every block starts from the same @place (the start points) on both sides.', '10']
    for d in DIRS:
        L += [f'# run {d} into the wall / edge, then 3 jump presses there (wall kick / ledge)'] + place(stg)
        L += [f'90 p1={d} p2={opp(d)}', f'3 p1={d}+A p2={opp(d)}+A', f'12 p1={d} p2={opp(d)}',
              f'3 p1={d}+A p2={opp(d)}+A', f'12 p1={d} p2={opp(d)}', f'3 p1={d}+A p2={opp(d)}+A',
              f'20 p1={d} p2={opp(d)}', '25']
    for d in ('UP', 'RIGHT', 'LEFT'):
        L += [f'# running jump {d}'] + place(stg) + [f'15 p1={d} p2={opp(d)}', f'3 p1={d}+A p2={opp(d)}+A',
                                                       f'45 p1={d} p2={opp(d)}', '25']
    L += ['# standing jumps'] + place(stg) + ['3 p1=A p2=A', '60']
    L += ['# 100 cm apart in the middle: punch string, kick string, both, grab'] + place(stg, 100)
    L += ['tap 4 p1=X gap 10', '60', 'tap 3 p2=Y gap 12', '90', 'tap 3 p1=Y p2=X gap 9', '90']
    L += place(stg, 100) + ['3 p1=B', '120', '3 p2=B', '150']
    return '\n'.join(L) + '\n'


def mash_tape(seed, p1, p2, frames=1500):
    rnd = random.Random(seed)
    stg = {'falcon': 'stg00', 'ryoma': 'stg10', 'wangtang': 'stg20', 'jack': 'stg30', 'gunrock': 'stg40',
           'galuda': 'stg50', 'ayame': 'stg60', 'rouge': 'stg70', 'kraken': 'stg80', 'valgas': 'stg90'}[p2]
    L = [f'#! p1={p1} p2={p2}', f'# fx-cov seeded mash (seed {seed}, Python random.Random): both pads, every 6-14 frames a',
         '# random D-pad direction (or none) + 0-2 of A/X/Y/B, from 150 cm apart (tools/cov_tapes.py mash)', '10']
    L += place(stg, 150)
    n = 0
    while n < frames:
        k = rnd.randint(6, 14)
        side = []
        for p in ('p1', 'p2'):
            d = rnd.choice(['', '', 'UP', 'DOWN', 'LEFT', 'RIGHT', 'UP+LEFT', 'UP+RIGHT', 'DOWN+LEFT', 'DOWN+RIGHT'])
            b = rnd.sample(['A', 'X', 'Y', 'B', 'X', 'Y'], rnd.choice([0, 1, 1, 1, 2]))
            m = '+'.join([x for x in [d] if x] + sorted(set(b)))
            if m: side.append(f'{p}={m}')
        L.append(f'{k} ' + ' '.join(side) if side else str(k))
        n += k
    L.append('60')
    return f'mash_s{seed}_{p1}_{p2}', '\n'.join(L) + '\n'


def main(what):
    if what in ('stages', 'all'):
        for stg, p1, p2 in STAGES:
            open(OUT + f'stg_{stg[3:]}.tape', 'w').write(stage_tape(stg, p1, p2))
            print(f'stg_{stg[3:]}', p1, p2)
    if what in ('mash', 'all'):
        for seed, p1, p2 in MASH:
            name, t = mash_tape(seed, p1, p2)
            open(OUT + name + '.tape', 'w').write(t)
            print(name)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'all')
