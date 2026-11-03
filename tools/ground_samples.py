#!/usr/bin/env python3
"""The original's ground / wall cases for tests/ground_check.gd (Arena.core_ground), picked from the Flycast probe samples
(tools/area_probe.py, $AREA_OUT/STAGE_probe.json) and the step-up run tests (fx-oom runtest*.py: a fighter running into a
floor step in the original, per-frame feet + state):
  settle  placed over a floor, dropped, settled where it was put: placed point + resting feet (cm)
  push    placed past a wall / edge, moved sideways by the game and settled: placed point + resting feet
  run     the original's run into a step: the trace (x, y, z, state per frame), the step's lower / upper floor, outcome
  ground_samples.py OUT.json [STAGE ...]   (AREA_OUT = the probe folder, RUN_DIR = the run-test folder)"""
import glob, json, math, os, random, sys

AREA = os.environ.get('AREA_OUT', '/tmp/ps-fx-oom/')
RUNS = os.environ.get('RUN_DIR', '/tmp/ps-fx-oom/')
OWNER = {'stg00': 'falcon', 'stg10': 'ryoma', 'stg20': 'wangtang', 'stg30': 'jack', 'stg40': 'gunrock',
         'stg50': 'galuda', 'stg60': 'ayame', 'stg70': 'rouge', 'stg80': 'kraken', 'stg90': 'valgas',
         'stga0': 'finalvalgas'}
N_SETTLE, N_PUSH = 120, 120


def moved(s): return math.hypot(s['last']['x'] - s['p'][0], s['last']['z'] - s['p'][2])
def settled(s): return s['last']['st'] in (0, 6) and abs(s['last']['vy']) < 0.01
def frozen(s): return moved(s) < 3 and settled(s) and abs(s['last']['y'] - s['p'][1]) < 0.5


def main():
    out, stages = sys.argv[1], sys.argv[2:] or list(OWNER)
    rnd = random.Random(7)
    res = {'note': __doc__.split('\n')[0], 'stages': {}}
    for st in stages:
        f = None
        for d in (AREA, os.environ.get('AREA_OUT2', '')):
            if d and os.path.exists(d + f'{st}_probe.json'): f = d + f'{st}_probe.json'; break
        if not f: print(st, 'no probe file'); continue
        d = json.load(open(f))
        chars = {1: d.get('p1', 'falcon'), 2: d.get('p2', OWNER[st])}
        sm = [s for s in d['samples'] if settled(s) and not frozen(s)]
        stay = [s for s in sm if moved(s) < 1]
        push = [s for s in sm if 5 < moved(s) < 80 and s['p'][1] - s['last']['y'] < 40 and s['k'] == 1]
        rnd.shuffle(stay); rnd.shuffle(push)
        e = {'settle': [[s['k'], s['p'], [s['last'][k] for k in 'xyz']] for s in stay[:N_SETTLE]],
             'push': [[s['k'], s['p'], [s['last'][k] for k in 'xyz']] for s in push[:N_PUSH]],
             'chars': chars, 'runs': []}
        for rf in sorted(glob.glob(RUNS + f'runtest*_{st}.json')):
            for r in json.load(open(rf)).get('runs', []):
                tr = [[round(v, 2) for v in t[:3]] + [int(t[3])] for t in r['tr']]
                e['runs'].append({'yl': r['yl'], 'yh': r['yh'], 'edge': r['edge'], 'dir': r['dir'],
                                  'climbed': r['climbed'], 'tr': tr, 'src': os.path.basename(rf)})
        res['stages'][st] = e
        print(st, len(e['settle']), 'settle', len(e['push']), 'push', len(e['runs']), 'runs')
    json.dump(res, open(out, 'w'), separators=(',', ':'))


if __name__ == '__main__':
    main()
