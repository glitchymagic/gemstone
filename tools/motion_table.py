#!/usr/bin/env python3
"""The original's per-motion travel, from every reference log (dumps/fidelity/o_*.jsonl): for each fighter, form and
motion (kind/id), the fighter's displacement on each motion frame, in the frame of its facing when the motion started
toward the other fighter at the motion's first frame (fwd, side, up; cm). Hit-stop frames (motion frame repeated) carry no travel and are skipped; frames where the fighter
touches the other one (feet < 90 cm apart) are left out (the push between bodies is not motion data); the median over
all clean samples is kept. Sources: the tape logs + the disc's CPU-vs-CPU fights (dumps/fidelity/cpu). -> game/assets/fidelity/motions.json  {fighter: {"f0k1_017": {"n": frames, "d": [[f,s,u],..]}}}
  motion_table.py [--all]"""
import glob, json, math, os, sys
sys.path.insert(0, './tools')
import tapes
R = './'
OUT = R + 'game/assets/fidelity/motions.json'
PREFIX = {'falcon': 'f', 'ryoma': 'r', 'wangtang': 'w', 'jack': 'j', 'gunrock': 'g', 'galuda': 'l', 'ayame': 'a',
          'rouge': 'o', 'kraken': 'k', 'valgas': 'v', 'finalvalgas': 'z'}
MOVE_STATES = {10, 11, 24, 27, 28, 29, 35, 37, 15, 16, 23, 21, 8}


def samples():
    for f in sorted(glob.glob(R + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]
        src = R + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        rows = [json.loads(l) for l in open(f)]
        for i, who in enumerate((m.get('p1'), m.get('p2'))):
            if who: yield who, i, rows, 'tape'
    # the disc's own CPU-vs-CPU fights (tools/cpu_stats.py log: both sides AI, 48 fights): every move the CPUs use
    for f in sorted(glob.glob(R + 'dumps/fidelity/cpu/cpu_*.jsonl')):
        mf = f[:-6] + '.meta.json'
        if not os.path.exists(mf): continue
        m = json.load(open(mf))
        rows = [json.loads(l) for l in open(f)]
        for i, who in enumerate((m.get('p1'), m.get('p2'))):
            if who: yield who, i, rows, 'cpu'


def main():
    acc = {}
    for who, i, rows, src in samples():
        cur = None
        for k in range(1, len(rows)):
            p, q = rows[k]['p'][i], rows[k - 1]['p'][i]
            o = rows[k]['p'][1 - i]
            key = f"{PREFIX[who]}{p['pc']}k{p['kind']}_{p['mot']:03d}"
            if p['st'] not in MOVE_STATES:
                cur = None; continue
            if cur is None or cur['key'] != key or p['fr'] < cur['last']:
                # reference direction: toward the other fighter (the game turns attacks / reactions to face it; the
                # +0x7248 angle is the movement heading and stays put)
                cur = {'key': key, 'a': math.atan2(o['x'] - p['x'], o['z'] - p['z']), 'last': -1, 'd': {}, 'ok': True, 'src': src}
                acc.setdefault(who, {}).setdefault(key, []).append(cur)
                if p['fr'] != 0: cur['ok'] = False
                cur['last'] = p['fr']
                if q['st'] in MOVE_STATES:   # a chained motion's own first-frame jump (k1/18 starts 33 cm back)
                    a = cur['a']; dx, dz = p['x'] - q['x'], p['z'] - q['z']
                    cur['d'][0] = (dx * math.sin(a) + dz * math.cos(a), dx * math.cos(a) - dz * math.sin(a), p['y'] - q['y'])
                continue
            if p['fr'] == cur['last']: continue   # hit-stop: no travel
            if math.hypot(p['x'] - o['x'], p['z'] - o['z']) < 90: cur['ok'] = False
            dx, dz, dy = p['x'] - q['x'], p['z'] - q['z'], p['y'] - q['y']
            a = cur['a']
            cur['d'][p['fr']] = (dx * math.sin(a) + dz * math.cos(a), dx * math.cos(a) - dz * math.sin(a), dy)
            cur['last'] = p['fr']
    out = {}
    for who, d in acc.items():
        for key, ss in d.items():
            # the tape logs (controlled, checked by the tape diffs) win; the CPU fights fill the motions no tape played
            ss = [s for s in ss if s['src'] == 'tape' and s['d']] or ss
            good = [s for s in ss if s['ok'] and s['d']] or [s for s in ss if s['d']]
            if not good: continue
            n = max(max(s['d']) for s in good) + 1
            rows = []
            for fr in range(n):
                vals = sorted((s['d'][fr] for s in good if fr in s['d']), key=lambda v: v[0])
                rows.append([round(c, 2) for c in vals[len(vals) // 2]] if vals else [0.0, 0.0, 0.0])
            out.setdefault(who, {})[key] = {'n': n, 'samples': len(good), 'src': good[0]['src'], 'd': rows}
    # entries already in the table stay as they are (checked by the tape diffs, atk_ground ...; later probe tapes push the
    # medians of a few, e.g. Ryoma's kicks with the victim behind him); --all rebuilds every entry
    if os.path.exists(OUT) and '--all' not in sys.argv:
        old = json.load(open(OUT))
        for who, d in old.items():
            for key, e in d.items():
                out.setdefault(who, {})[key] = e
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, 'w'), separators=(',', ':'))
    print({w: len(v) for w, v in out.items()})


if __name__ == '__main__':
    main()
