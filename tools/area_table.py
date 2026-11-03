#!/usr/bin/env python3
"""docs/fx-oom.md per-stage table: probe counts, the old clamp rectangle vs the original's measured area (m2), and the
remaster collision check (tests/area_check.gd AREA_CHECK lines).  area_table.py CHECKDIR [OLD_REV]"""
import base64, json, re, subprocess, sys, glob, os
import numpy as np
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
LONDO = (-770, -360, 740, 670)   # arena.gd BOUNDS (x0, z0, x1, z1 cm)
NAMES = {'stg00': 'Londo', 'stg10': 'Ryoma', 'stg20': 'Wang-Tang', 'stg30': 'Jack', 'stg40': 'Dawnvolta',
         'stg50': 'Galuda', 'stg60': 'Ayame', 'stg70': 'Rouge', 'stg80': 'Kraken ship', 'stg90': 'Valgas',
         'stga0': 'Final Valgas'}


def mask(a):
    g = a['sdf']; S = np.frombuffer(base64.b64decode(g['i16']), dtype='<i2').reshape(g['h'], g['w'])
    return S > 0, g


def main():
    chk, old = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
    print('| stage | probe samples (placed / inside points) | raised floors joined | old rectangle m2 | original area m2 (fx-oom -> now) | rectangle not in the area m2 | walled off by the rectangle m2 | stand spots | ok | missing | higher | blocked | on throwables |')
    print('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for st in NAMES:
        f = R + f'game/assets/fidelity/{st}_area.json'
        if not os.path.exists(f): continue
        a = json.load(open(f)); m, g = mask(a)
        info = json.load(open(R + f'game/assets/ripped/{st}_info.json'))
        b = LONDO if st == 'stg00' else info.get('bounds_cm')
        X = g['x0'] + np.arange(g['w']) * g['cell']; Z = g['z0'] + np.arange(g['h']) * g['cell']
        gx, gz = np.meshgrid(X, Z)
        inr = (gx >= b[0]) & (gx <= b[2]) & (gz >= b[1]) & (gz <= b[3])
        c2 = (g['cell'] / 100) ** 2
        rect = (b[2] - b[0]) * (b[3] - b[1]) / 1e4
        not_in = rect - float((inr & m).sum()) * c2
        walled = float((m & ~inr).sum()) * c2
        prev = '-'
        if old:
            try:
                pa = json.loads(subprocess.run(['git', '-C', R, 'show', f'{old}:game/assets/fidelity/{st}_area.json'],
                                               capture_output=True, text=True, check=True).stdout)
                prev = f"{pa['area_m2']:.1f}"
            except Exception: prev = '-'
        line = ''
        for fn in sorted(glob.glob(chk + f'/{st}_*.json')): pass
        lg = R + f'../_x'
        ac = {}
        for fn in sorted(glob.glob(chk + f'/../fin_{st}.log')):
            ls = [l for l in open(fn) if l.startswith('AREA_CHECK')]
            if ls: ac = dict(kv.split('=', 1) for kv in ls[-1].split()[2:] if '=' in kv)
        p = a['probes']
        print(f"| {st} {NAMES[st]} | {p['samples']} ({p['placed_points']} / {p['inside_points']}) | {p.get('raised_floors_joined', 0)} | {rect:.0f} | {prev} -> {a['area_m2']:.1f} | {not_in:.0f} | {walled:.1f} | "
              f"{ac.get('stand', '-')} | {ac.get('ok', '-')} | {ac.get('missing', '-')} | {ac.get('higher', '-')} | {ac.get('blocked', '-')} | {ac.get('prop_skip', '-')} |")


if __name__ == '__main__':
    main()
