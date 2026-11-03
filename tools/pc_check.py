#!/usr/bin/env python3
"""Power Change in the original's logs (docs/PC.md): every transform / revert (state 23), the gauge (+0x71F4) per
frame, and every attack motion started in PC form with the gauge drop it costs, per fighter.
  pc_check.py [summary|events] | export OUT.json   reads dumps/fidelity/o_*.jsonl + CPU_LOGDIR/cpu_*.jsonl"""
import collections, glob, json, os, sys
MAIN = './'
sys.path.insert(0, MAIN + 'tools')
import tapes
CPU = os.environ.get('CPU_LOGDIR', '/tmp/ps-fx-cpu/logs/')


def logs():
    for f in sorted(glob.glob(MAIN + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]; src = MAIN + f'game/tests/tapes/{t}.tape'
        if os.path.exists(src):
            m = tapes.meta(src); yield 'tape ' + t, (m.get('p1'), m.get('p2')), f
    for f in sorted(glob.glob(CPU + 'cpu_*.jsonl')):
        m = json.load(open(f[:-6] + '.meta.json')); yield 'cpu ' + os.path.basename(f)[4:-6], (m['p1'], m['p2']), f


def segs(rows, v, a, b):
    out = []
    for j in range(a, b):
        p = rows[j]['p'][v]; k = (p['st'], f"k{p['kind']}/{p['mot']}")
        if out and out[-1][0] == k: out[-1][1] += 1
        else: out.append([k, 1])
    return out


def events():
    ev = []
    for src, who, f in logs():
        rows = [json.loads(l) for l in open(f)]
        for v in (0, 1):
            nm = who[v]
            for j in range(1, len(rows)):
                p, q = rows[j]['p'][v], rows[j - 1]['p'][v]
                if p['st'] == 23 and q['st'] != 23:                       # transform or revert begins
                    e = j
                    while e < len(rows) and rows[e]['p'][v]['st'] == 23: e += 1
                    kind = 'revert' if q['pc'] else 'transform'
                    g = [rows[x]['p'][v]['gauge'] for x in range(j - 1, min(e + 3, len(rows)))]
                    ev.append(dict(src=src, who=nm, kind=kind, row=j, frames=e - j, chain=segs(rows, v, j, min(e + 1, len(rows))),
                                   gems_before=q['gems'], gems_after=rows[min(e, len(rows) - 1)]['p'][v]['gems'],
                                   pc_after=rows[min(e, len(rows) - 1)]['p'][v]['pc'], gauge_end=g[-1], prev_state=q['st'],
                                   gauge_before=q['gauge']))
                if p['pc'] and q['pc'] and p['kind'] == 1 and (q['kind'], q['mot']) != (1, p['mot']) and p['st'] in (10, 11):
                    e = j
                    while e < len(rows) and rows[e]['p'][v]['st'] == p['st'] and rows[e]['p'][v]['pc']: e += 1
                    ev.append(dict(src=src, who=nm, kind='pc_attack', row=j, frames=e - j, chain=segs(rows, v, j, e),
                                   gauge_drop=q['gauge'] - p['gauge'], gauge_before=q['gauge'], air=q['st'] in (5, 14)))
    return ev


def gauge_rate():
    """frames where the gauge drops by exactly 1 vs other drops while in PC"""
    c = collections.Counter()
    for src, who, f in logs():
        rows = [json.loads(l) for l in open(f)]
        for v in (0, 1):
            for j in range(1, len(rows)):
                p, q = rows[j]['p'][v], rows[j - 1]['p'][v]
                if q['pc'] and p['pc'] and q['gauge'] > 0: c[q['gauge'] - p['gauge']] += 1
    return c


def main():
    ev = events()
    if len(sys.argv) > 1 and sys.argv[1] == 'events':
        for e in ev: print(json.dumps({k: v for k, v in e.items()}, default=str))
        return
    print('gauge change per PC frame:', dict(gauge_rate().most_common(8)))
    for kind in ('transform', 'revert'):
        print(f'== {kind}')
        for e in ev:
            if e['kind'] != kind: continue
            ch = ' > '.join(f's{k[0]} {k[1]} x{n}' for k, n in e['chain'])
            print(f"{e['who']:9s} {e['src']:28s} row {e['row']:5d} st23 {e['frames']:3d} f  gems {e['gems_before']}->{e['gems_after']} "
                  f"gauge {e['gauge_before']}->{e['gauge_end']} prev st {e['prev_state']}  {ch}")
    print('== PC attacks (first motion, frames in the attack state, gauge drop on the first frame)')
    agg = collections.defaultdict(list)
    for e in ev:
        if e['kind'] == 'pc_attack':
            agg[(e['who'], e['chain'][0][0][1], e['air'])].append((e['frames'], e['gauge_drop'], ' > '.join(f'{k[1]} x{n}' for k, n in e['chain'][:5])))
    for k, v in sorted(agg.items()):
        print(f"{k[0]:9s} {k[1]:7s} {'air' if k[2] else 'gnd'} n={len(v):2d} frames {sorted({x[0] for x in v})} drop {sorted({x[1] for x in v})}  e.g. {v[0][2]}")


def export(path):
    """game/assets/fidelity/pc_code.json: per fighter, the logged transform / revert chains and each PC attack's gauge
    cost (first-frame drop minus the 1/frame tick; 'all' = the rest of the gauge, i.e. a Fusion)."""
    ev = events()
    out = {'about': 'Power Change from the original logs (tools/pc_check.py export) + code (docs/PC.md)',
           'gauge_full': 2400, 'gauge_tick': 1, 'transform_frames': 130, 'fighters': {}}
    for e in ev:
        f = out['fighters'].setdefault(e['who'], {'transform': {}, 'revert': {}, 'attack_cost': {}})
        if e['kind'] in ('transform', 'revert'):
            key = ' > '.join(f'{k[1]} x{n}' for k, n in e['chain'] if k[0] == 23)
            where = 'air' if e['prev_state'] in (5, 14) else 'ground'
            d = f[e['kind']].setdefault(where, collections.Counter()); d[key] += 1
            if e['kind'] == 'transform' and where == 'ground' and e['frames'] >= 120:
                f.setdefault('gauge_at_transform_end', set()).add(e['gauge_end'])
        else:
            cost = e['gauge_drop'] - 1
            if e['gauge_drop'] >= e['gauge_before'] - 2 and cost > 600: cost = 'all'
            if cost != 0 and cost != -1:
                f['attack_cost'].setdefault(e['chain'][0][0][1], collections.Counter())[str(cost)] += 1
    for f in out['fighters'].values():
        for k in ('transform', 'revert'):
            f[k] = {w: dict(c.most_common()) for w, c in f[k].items()}
        f['attack_cost'] = {m: dict(c.most_common()) for m, c in sorted(f['attack_cost'].items())}
        if 'gauge_at_transform_end' in f: f['gauge_at_transform_end'] = sorted(f['gauge_at_transform_end'])
    json.dump(out, open(path, 'w'), indent=1)
    print('wrote', path)


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'export': export(sys.argv[2])
    else: main()
