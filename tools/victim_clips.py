#!/usr/bin/env python3
"""Throw-victim clips: the original stores a throw's victim motions (kind 4, e.g. Falcon's k4/49) in the THROWER's
motion file (the ids sit in the thrower's Pn0_MOT.MDT kind-4 table, never in the victim's) and plays them on the
VICTIM's skeleton. Motion Check can only play them on the thrower, so they are captured there (add_clips.py, kind 4) and
this copies them onto every fighter's skeleton the way the game does: the motion's local rotations of joints 0-18 (the
same joints on every fighter, docs/RIP.md) and its root channel, the victim's other parts held at his idle pose.
Clip name: <victim prefix>k4_<id>_<thrower prefix>, e.g. r0k4_049_f0 = Ryoma thrown by Falcon.
  victim_clips.py            (env PS_MOCAP = clip folders, as add_clips.py; reads game/assets/fidelity/throws.json)"""
import json, os, sys
import numpy as np
MAIN = './'
R = os.environ.get('PS_ROOT', MAIN)
MOCAP = os.environ.get('PS_MOCAP', R + 'rip/mocap/')
NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas']
THROWS = next(p for p in (R + 'game/assets/fidelity/throws.json', MAIN + 'game/assets/fidelity/throws.json') if os.path.exists(p))


def prefix(n):
    idx = json.load(open(MOCAP + f'clips_p{n:x}/index.json'))
    return next(iter(idx))[:2], idx


def logged_pairs():
    """(thrower, victim id) for every kind-4 motion a fighter plays while thrown (state 29) in the original's logs."""
    import glob
    sys.path.insert(0, MAIN + 'tools')
    import tapes
    out = set()
    srcs = [(f, tapes.meta(MAIN + f'game/tests/tapes/{os.path.basename(f)[2:-6]}.tape'))
            for f in glob.glob(MAIN + 'dumps/fidelity/o_*.jsonl')
            if os.path.exists(MAIN + f'game/tests/tapes/{os.path.basename(f)[2:-6]}.tape')]
    srcs += [(f, json.load(open(f[:-6] + '.meta.json')))
             for f in glob.glob(os.environ.get('CPU_LOGDIR', '/tmp/ps-fx-cpu/logs/') + 'cpu_*.jsonl')]
    for f, m in srcs:
        who = (m.get('p1'), m.get('p2'))
        for l in open(f):
            r = json.loads(l)
            for v in (0, 1):
                p = r['p'][v]
                if p['kind'] == 4 and p['st'] == 29 and who[1 - v] in NAMES: out.add((who[1 - v], p['mot']))
    return out


def main():
    th = json.load(open(THROWS))
    pairs = {(t, m[2]) for t in th for m in th[t]['victim'] if m[1] == 4} | logged_pairs()
    made = []
    for tn, tname in enumerate(NAMES):
        tpre, tidx = prefix(tn)
        ids = sorted({m for t, m in pairs if t == tname})
        for m in ids:
            src = MOCAP + f'clips_p{tn:x}/{tpre}k4_{m:03d}.npz'
            if not os.path.exists(src):
                print('no capture', src); continue
            c = np.load(src)
            for vn, vname in enumerate(NAMES):
                vpre, vidx = prefix(vn)
                idle = np.load(MOCAP + f'clips_p{vn:x}/{vpre}k0_000.npz')
                q = np.repeat(idle['q'][:1], c['q'].shape[0], 0).copy()
                q[:, :19] = c['q'][:, :19]
                name = f'{vpre}k4_{m:03d}_{tpre}'
                np.savez_compressed(MOCAP + f'clips_p{vn:x}/{name}.npz', q=q.astype(np.float32),
                                    t=c['t'].astype(np.float32), loop=np.array(False))
                vidx[name] = dict(tidx[f'{tpre}k4_{m:03d}'], src=name, loop=False, thrower=tname)
                json.dump(vidx, open(MOCAP + f'clips_p{vn:x}/index.json', 'w'), indent=1)
                made.append(name)
    print(len(made), 'victim clips:', ' '.join(sorted(made)))


if __name__ == '__main__':
    main()
