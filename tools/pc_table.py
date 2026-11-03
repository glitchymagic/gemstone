#!/usr/bin/env python3
"""Power Change timelines from the original's logs -> game/assets/fidelity/pc_moves.json (fx-pc, docs/PC.md "Port").
Per fighter, row by row (one row = one 1/60 s frame, exactly as Flycast logged it):
  tf.ground / tf.air   the transform (state 23 from normal form): [kind, mot, fr, fwd, side, up, pc] per row
  rv.ground / rv.air   the revert (state 23 from PC form), same rows
  moves.X/Y/AX/AY/FX/FY  Drives (X / Y on the ground, AX / AY in the air) and Fusions (A+X / A+Y): the rows from the
                       first state-11 frame (k1/16 for a Drive, the old motion for a Fusion) to the last one, plus
                       'cost' = [row, gauge taken there (-1 = all of it)], 'exit' = the state after, 'vy' = its fall speed
fwd / side / up = the body's travel that frame in cm, in the facing the move started with (side = fwd turned -90 deg).
Representative per move: a sample with no hit on either fighter and round phase 3 throughout, from the fx-pc tapes
(pc_*: the opponent stands 680 cm off) first, then the other reference tapes, then the CPU logs (by first motion).
  pc_table.py [OUT.json]   (default game/assets/fidelity/pc_moves.json)"""
import collections, glob, json, math, os, sys
MAIN = './'
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, HERE + 'tools')
import tapes
CPU = os.environ.get('CPU_LOGDIR', '/tmp/ps-fx-cpu/logs/')
A, X, Y = 0x4, 0x400, 0x200


def sources():
    out = []
    for f in sorted(glob.glob(MAIN + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]
        src = HERE + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): src = MAIN + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        rank = 0 if t.startswith('pc_') else 1
        pads = [(a, b) for a, b, _ in tapes.parse(open(src).read())]
        out.append((rank, 'tape ' + t, (m.get('p1'), m.get('p2')), f, pads))
    for f in sorted(glob.glob(CPU + 'cpu_*.jsonl')):
        m = json.load(open(f[:-6] + '.meta.json'))
        out.append((2, 'cpu ' + os.path.basename(f)[4:-6], (m['p1'], m['p2']), f, None))
    return out


def travel(rows, v, a, b, ang0):
    """per-row (fwd, side, up) cm of rows a..b-1 relative to the row before each"""
    t = ang0 / 65536.0 * 2 * math.pi
    fx, fz = math.sin(t), math.cos(t)
    sx, sz = fz, -fx
    out = []
    for j in range(a, b):
        p, q = rows[j]['p'][v], rows[j - 1]['p'][v]
        dx, dy, dz = p['x'] - q['x'], p['y'] - q['y'], p['z'] - q['z']
        out.append((round(dx * fx + dz * fz, 2), round(dx * sx + dz * sz, 2), round(dy, 2)))
    return out


def clean(rows, a, b):
    """no health change on either fighter and phase 3 on every row a-1..b"""
    for j in range(max(1, a - 1), min(b + 1, len(rows))):
        r, q = rows[j], rows[j - 1]
        if r.get('phase', 3) != 3: return False
        if any(r['p'][i]['hp'] != q['p'][i]['hp'] for i in (0, 1)): return False
    return True


def tl(rows, v, a, b):
    ang0 = rows[a]['p'][v]['ang']
    d = travel(rows, v, a, b, ang0)
    return [[rows[j]['p'][v]['kind'], rows[j]['p'][v]['mot'], rows[j]['p'][v]['fr'], *d[j - a], rows[j]['p'][v]['pc']]
            for j in range(a, b)]


def main(path):
    cand = collections.defaultdict(list)   # (fighter, what) -> [(rank, clean, -len, src, data)]
    first_of = {}                           # (fighter, first motion of the move, air) -> move name (from the tapes)
    srcs = sources()
    for rank, src, who, f, pads in srcs:
        rows = [json.loads(l) for l in open(f)]
        for v in (0, 1):
            nm = who[v]
            j = 1
            while j < len(rows):
                p, q = rows[j]['p'][v], rows[j - 1]['p'][v]
                if p['st'] == 23 and q['st'] != 23:
                    e = j
                    while e < len(rows) and rows[e]['p'][v]['st'] == 23: e += 1
                    what = ('rv' if q['pc'] else 'tf') + ('.air' if q['st'] in (5, 14) else '.ground')
                    if e < len(rows):
                        cand[(nm, what)].append((rank, clean(rows, j, e), -(e - j), src, tl(rows, v, j, e)))
                    j = e; continue
                if p['pc'] and p['st'] in (10, 11) and q['st'] not in (10, 11):
                    e = j
                    while e < len(rows) and rows[e]['p'][v]['st'] in (10, 11) and rows[e]['p'][v]['pc']: e += 1
                    if e >= len(rows): break
                    air = q['st'] in (4, 5, 14)
                    m1 = next(((rows[k]['p'][v]['kind'], rows[k]['p'][v]['mot']) for k in range(j, e)
                               if (rows[k]['p'][v]['kind'], rows[k]['p'][v]['mot']) not in ((1, 16), (q['kind'], q['mot']))), None)
                    name = None
                    if pads is not None:
                        btn = 0
                        for k in range(max(0, j - 6), j):
                            if k < len(pads): btn |= pads[k][v]
                        if btn & A and btn & X and not air and p['kind'] != 1: name = 'FX'
                        elif btn & A and btn & Y and not air and p['kind'] != 1: name = 'FY'
                        elif btn & X: name = 'AX' if air else 'X'
                        elif btn & Y: name = 'AY' if air else 'Y'
                        if name and m1: first_of.setdefault((nm, m1, air), name)
                    else:
                        name = ('cpu', m1, air)
                    nx = rows[e]['p'][v]
                    # leaving into the air (state 5 / 14): the core starts from this fall speed (the original resumes
                    # some jumps where the Drive froze them, e.g. Falcon's air k1/99: vy 21.5 again after it)
                    vy = 0.0
                    if nx['st'] in (5, 14) and e + 1 < len(rows): vy = rows[e + 1]['p'][v].get('vy', 0.0) + 2.0
                    data = dict(rows=tl(rows, v, j, e), exit=nx['st'], vy=round(vy, 3))
                    g = [rows[k]['p'][v]['gauge'] for k in range(j - 1, e)]
                    cost = None
                    for k in range(1, len(g)):
                        dg = g[k - 1] - g[k]
                        if dg > 1 or (g[k] == 0 and g[k - 1] > 1):
                            cost = [k - 1, -1 if g[k] == 0 and dg > 1 and dg >= g[k - 1] - 1 and dg - 1 > 600 else dg - 1]
                            break
                    capped = cost is not None and g[cost[0] + 1] == 0   # the gauge ran out on it
                    if cost is not None and capped and isinstance(name, str) and name.startswith('F'): cost[1] = -1
                    data['cost'] = cost
                    natural = nx['st'] in (0, 5, 6, 14) and all(rows[k]['p'][v]['hp'] == q['hp'] for k in range(j, e + 1)) \
                        and not (capped and not (isinstance(name, str) and name.startswith('F')))
                    if name: cand[(nm, name)].append(((not natural, rank, not clean(rows, j, e)), True, -(e - j), src, data))
                    j = e; continue
                j += 1
    # CPU samples: name them by the tape's first-motion map
    for key in list(cand):
        if isinstance(key[1], tuple):
            nm, (_, m1, air) = key[0], key[1]
            name = first_of.get((nm, m1, air))
            if name:
                for c in cand[key]:
                    co = c[4].get('cost')
                    if name.startswith('F') and co is not None and co[1] > 0:
                        g0 = None   # a Fusion takes the whole gauge: a CPU sample's drop to 0 is 'all'
                        c[4]['cost'] = [co[0], -1]
                    cand[(nm, name)].append(c)
            del cand[key]
    out = {'about': __doc__.split('\n')[0], 'rows': '[kind, mot, fr, fwd_cm, side_cm, up_cm, pc]', 'fighters': {}}
    for (nm, what), cs in sorted(cand.items()):
        # transforms / reverts: clean first, then source rank, then the longest; moves: ended by themselves with the
        # attacker untouched first, then source rank (the fx-pc tapes), then no hit on the opponent either
        # ... and among equals the motion chain logged most often (its (kind, mot, rows) runs)
        def sig(c):
            rr = c[4]['rows'] if isinstance(c[4], dict) else c[4]
            out = []
            for r in rr:
                if out and out[-1][:2] == (r[0], r[1]): out[-1] = (r[0], r[1], out[-1][2] + 1)
                else: out.append((r[0], r[1], 1))
            return tuple(out)
        freq = collections.Counter(sig(c) for c in cs)
        cs.sort(key=lambda c: (c[0][0], -freq[sig(c)], c[0][1:], c[2]) if isinstance(c[0], tuple)
                else (not c[1], -freq[sig(c)], c[0], c[2]))
        best = cs[0]
        fd = out['fighters'].setdefault(nm, {'tf': {}, 'rv': {}, 'moves': {}})
        if what.startswith(('tf.', 'rv.')):
            k, w = what.split('.')
            fd[k][w] = {'rows': best[4], 'src': best[3], 'clean': best[1], 'n': len(cs)}
        else:
            d = dict(best[4]); d.update(src=best[3], clean=best[1], n=len(cs))
            d['clean'] = not best[0][2]
            fd['moves'][what] = d
    json.dump(out, open(path, 'w'), separators=(',', ':'))
    for nm, fd in sorted(out['fighters'].items()):
        print(nm, 'tf', {w: (len(v['rows']), v['clean']) for w, v in fd['tf'].items()},
              'rv', {w: (len(v['rows']), v['clean']) for w, v in fd['rv'].items()},
              'moves', {w: (len(v['rows']), v['cost'], v['exit'], v['clean'], v['src'].split()[-1]) for w, v in sorted(fd['moves'].items())})
    print('wrote', path)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else HERE + 'game/assets/fidelity/pc_moves.json')
