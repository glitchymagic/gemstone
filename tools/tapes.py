#!/usr/bin/env python3
"""Fidelity tapes: per-frame input for BOTH pads, played into the original (tools/reflog.py, Flycast) and the remaster
(PS_TAPE, game/tests/tape_run.gd). Written from a tiny script language, one step per line:
  N                         N frames, nothing held
  N p1=X+UP p2=A            N frames with those buttons held (either side optional)
  tap K p1=X [gap G]        K taps of 4 frames held + G (default 8) frames released
  # comment
Buttons: A jump, X punch, Y kick, B action (punch+kick on the pad: pick up / grab), UP DOWN LEFT RIGHT (D-pad), START.
  tapes.py build SRC.tape OUT.txt      -> the per-frame "p1 p2" hex file both runners read
  tapes.py all                         -> every tests/tapes/*.tape -> dumps/fidelity/tapes/*.txt"""
import glob, os, sys
R = './'
BTN = {'C': 0x1, 'B': 0x2, 'A': 0x4, 'START': 0x8, 'UP': 0x10, 'DOWN': 0x20, 'LEFT': 0x40, 'RIGHT': 0x80,
       'Z': 0x100, 'Y': 0x200, 'X': 0x400, 'D': 0x800}


def mask(s):
    m = 0
    for b in s.split('+'):
        if b: m |= BTN[b]
    return m


def parse(src):
    """-> [(p1 mask, p2 mask, [row commands])]. A line starting with '@' adds a command to the NEXT frame:
    @place P X Y Z ANG (cm, feet, u16 facing) | @hp P V | @gems P N"""
    rows, pending = [], []
    for ln in src.splitlines():
        ln = ln.split('#')[0].strip()
        if not ln: continue
        if ln.startswith('@'):
            pending.append(ln[1:]); continue
        w = ln.split()
        n0 = len(rows)
        side = {'p1': 0, 'p2': 0}
        gap = 8
        for t in w[1:]:
            if '=' in t:
                k, v = t.split('=')
                side[k] = mask(v)
        if w[0] == 'tap':
            if 'gap' in w: gap = int(w[w.index('gap') + 1])
            for _ in range(int(w[1])):
                rows += [(side['p1'], side['p2'], [])] * 4 + [(0, 0, [])] * gap
        else:
            rows += [(side['p1'], side['p2'], [])] * int(w[0])
        if pending and len(rows) > n0:
            rows[n0] = (rows[n0][0], rows[n0][1], pending); pending = []
    return rows


def build(src_path, out_path):
    rows = parse(open(src_path).read())
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w') as f:
        for a, b, c in rows: f.write(f'{a:x} {b:x}' + ''.join(' ; ' + x for x in c) + '\n')
    return len(rows)


def meta(src_path):
    """'#! p1=falcon p2=ryoma' header line -> dict"""
    for ln in open(src_path):
        if ln.startswith('#!'):
            return dict(t.split('=') for t in ln[2:].split() if '=' in t)
    return {}


if __name__ == '__main__':
    if sys.argv[1] == 'build':
        print(build(sys.argv[2], sys.argv[3]))
    else:
        for p in sorted(glob.glob(R + 'game/tests/tapes/*.tape')):
            n = build(p, R + 'dumps/fidelity/tapes/' + os.path.basename(p)[:-5] + '.txt')
            print(os.path.basename(p), n)
