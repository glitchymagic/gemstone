#!/usr/bin/env python3
"""BUG-31 (stga0, Final Valgas's arena): the area probe (tools/area_probe.py) placed Falcon on a lattice while Final
Valgas stood on his start point (950, 0, 950): his body pushed every placement within ~2.7 m away, so 123 of the
raster's 25 cm cells inside the playable area (x 700..1025, z 700..1025) have NO floor level. The fidelity core's
Arena.core_ground then finds nothing under a fighter there: it 'falls' in place for the rest of the round (the
remaster's seeded Falcon vs Final Valgas matches: Falcon DOWN / JUMP 14 at y -10 cm for 7,000+ frames, vy -4,000).
The disc's own CPU fights (tools/fv_log.py logs) stand fighters in those cells at y 0 (435 frames: run 31, dizzy 13,
reactions 27, get-up 16), so the floor there is the main floor, 0 cm. This fills every inside cell without a level with
0 and notes it in the area file.
  fv_area_fill.py [LOGGLOB]   (default: the fx-fv disc logs) -> game/assets/fidelity/stga0_area.json (in place)"""
import base64, glob, json, os, sys
import numpy as np
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'game/assets/fidelity/stga0_area.json')
logs = sorted(glob.glob(sys.argv[1] if len(sys.argv) > 1 else '/tmp/ps-fx-fv/disc/cpu_*.jsonl'))
d = json.load(open(P))
f, s = d['floor'], d['sdf']
fl = np.frombuffer(base64.b64decode(f['i16']), dtype='<i2').reshape(f['h'], f['w'], f['n']).copy()
sd = np.frombuffer(base64.b64decode(s['i16']), dtype='<i2').reshape(s['h'], s['w'])
# the disc's feet in hole cells (evidence for the level)
seen = {}
for p in logs:
    for l in open(p):
        r = json.loads(l)
        if r['p'][1].get('ch') != 10 or r['phase'] != 3: continue
        for a in r['p']:
            j = round((a['x'] - f['x0']) / f['cell']); i = round((a['z'] - f['z0']) / f['cell'])
            if 0 <= i < f['h'] and 0 <= j < f['w'] and (fl[i, j] == -32768).all() and a['st'] not in (4, 5, 27):
                seen.setdefault((i, j), set()).add(round(a['y']))
ys = sorted({y for v in seen.values() for y in v})
assert ys == [0], f'disc feet in the holes at {ys}: not one floor'
n = 0
for i in range(f['h']):
    for j in range(f['w']):
        x, z = f['x0'] + j * f['cell'], f['z0'] + i * f['cell']
        u, v = (x - s['x0']) / s['cell'], (z - s['z0']) / s['cell']
        jj, ii = int(np.floor(u)), int(np.floor(v))
        if not (0 <= ii < s['h'] and 0 <= jj < s['w']) or sd[ii, jj] <= 0: continue
        if (fl[i, j] == -32768).all():
            fl[i, j, 0] = 0; n += 1
f['i16'] = base64.b64encode(fl.astype('<i2').tobytes()).decode()
d['hole_fill'] = {'cells': n, 'level_cm': 0, 'disc_cells_seen': len(seen), 'tool': 'tools/fv_area_fill.py',
                  'note': 'inside cells with no floor level (the probe fighter was pushed off by Final Valgas standing '
                          'at his start point) set to 0 cm: the disc logs stand fighters there at y 0 (BUG-31)'}
json.dump(d, open(P, 'w'), separators=(',', ':'))
print('filled', n, 'cells; disc feet seen in', len(seen), 'of them at y', ys)
