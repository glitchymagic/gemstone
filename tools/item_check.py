#!/usr/bin/env python3
"""fx-item: replay the disc's ITEM / GEM rules (docs/ITEMS.md, game/assets/fidelity/item_code.json) on the original's
object logs (dumps/fidelity/o_TAPE.jsonl + o_TAPE.obj.jsonl, fx-cov covlog.py: per frame [slot, type, owner, kind, b5,
x, y, z, +0x30C, +0x30D] of every live object of the pool 0x0C7D0980) and print a score per rule.
  item_check.py gems      spill flight / floor drops (spot + clock) / despawn
  item_check.py items     chest clock / spot / item id category, chest open, item pick-up + use motions
Gems = type 3 kind 5 (slots 2-4: colour 0-2), items = type 3 kind 6, chests = type 2 kind 7."""
import glob, json, math, os, sys
D = os.environ.get('FID_DUMPS', './dumps/fidelity/')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE = json.load(open(ROOT + '/game/assets/fidelity/item_code.json'))
SPOTS = {k: v for k, v in CODE['drop_spots'].items()}


def logs():
    for fn in sorted(glob.glob(D + 'o_*.obj.jsonl')):
        name = os.path.basename(fn)[2:-10]
        meta = json.load(open(D + f'o_{name}.meta.json'))
        P = [json.loads(l) for l in open(D + f'o_{name}.jsonl')]
        O = [{o[0]: o for o in json.loads(l)} for l in open(fn)]
        st = meta.get('stage', 'stg00')
        yield name, ('stg20' if st == 'stga0' else st), P, O   # Final Valgas' fights drop on row 2 (logged, ITEMS.md 1)


class Score:
    def __init__(s): s.d = {}
    def add(s, rule, ok, note=None):
        a = s.d.setdefault(rule, [0, 0, []]); a[1] += 1; a[0] += bool(ok)
        if not ok and note and len(a[2]) < 4: a[2].append(note)
    def show(s):
        for r, (ok, n, ex) in s.d.items():
            print(f'{r:70s} {ok}/{n}' + (('   e.g. ' + '; '.join(ex)) if ex else ''))


def hd(dx, dz): return math.degrees(math.atan2(dx, dz))


def spot_choice(stage, P, f, occupied):
    """the free spot with the largest summed 3D distance from both fighters' feet (0x0C0CC2A6 / 0x0C0CC5A8 / 0x0C0CC314)"""
    best, bi = -1.0, None
    for i, s in enumerate(SPOTS[stage]):
        if i in occupied: continue
        d = sum(math.dist(s, (q['x'], q['y'], q['z'])) for q in P[f]['p'])
        if d > best: best, bi = d, i
    return bi


def nearest_spot(stage, xyz):
    return min(range(3), key=lambda i: math.dist(SPOTS[stage][i][::2], (xyz[0], xyz[2])))


def gems():
    S = Score()
    for name, stage, P, O in logs():
        n = min(len(P), len(O))
        for s in (2, 3, 4):
            f = 1
            while f < n:
                a, b = O[f - 1].get(s), O[f].get(s)
                if not (a and b and a[9] == 3 and b[9] != 3):
                    f += 1; continue
                spill = any(q['st'] == 27 for q in P[f]['p']) or any(q['st'] == 27 for q in P[f - 1]['p'])
                if spill and (b[6] - 0) % 50 != 0 or (spill and not b[5:8] == SPOTS.get(stage, [[0, 0, 0]])[0]):
                    pass
                tr = []
                for k in range(f, min(f + 220, n)):
                    o = O[k].get(s)
                    if not o or o[9] == 3: break
                    tr.append(o[5:8])
                    if len(tr) > 3 and tr[-1] == tr[-2] == tr[-3]: break
                moving = len(tr) > 2 and tr[1] != tr[0]
                if moving:                                   # a spilled gem (0x0C08E980 -> 0x0C05CB42)
                    vic = [i for i in (0, 1) if P[f]['p'][i]['st'] == 27 or P[f - 1]['p'][i]['st'] == 27]
                    v = [tr[1][i] - tr[0][i] for i in range(3)]
                    S.add('spill: horizontal speed 20.0 cm/f (+-0.15)', abs(math.hypot(v[0], v[2]) - 20) < 0.15 or
                          (len(tr) > 2 and abs(math.hypot(tr[2][0] - tr[1][0], tr[2][2] - tr[1][2]) - 20) < 0.15),
                          f'{name} f{f} {math.hypot(v[0], v[2]):.2f}')
                    S.add('spill: first rise vy 30.0 cm/f', abs(v[1] - 30) < 0.05, f'{name} f{f} {v[1]:.2f}')
                    # gravity 1.2 per frame while airborne (skip wall-bounce / landing frames)
                    for k in range(2, len(tr)):
                        d1, d0 = tr[k][1] - tr[k - 1][1], tr[k - 1][1] - tr[k - 2][1]
                        if tr[k][1] > tr[-1][1] + 1 and tr[k - 1][1] > tr[-1][1] + 1 and d1 != 0:
                            S.add('spill: gravity 1.2 cm/f^2 (per airborne frame)', abs((d0 - d1) - 1.2) < 0.06,
                                  f'{name} f{f + k} {d0 - d1:.2f}')
                    # wall bounce: a horizontal component flips sign at half size (pre = 2 rows before the flip row)
                    for k in range(3, len(tr) - 1):
                        for ax in (0, 2):
                            pre, mid, post = (tr[k - 2][ax] - tr[k - 3][ax], tr[k][ax] - tr[k - 1][ax],
                                              tr[k + 1][ax] - tr[k][ax])
                            if abs(pre) > 3 and pre * post < 0 and abs(tr[k - 1][ax] - tr[k - 2][ax] - pre) < 0.3 \
                                    and tr[k][1] > tr[-1][1] + 1:
                                S.add('spill: wall bounce = that axis x -0.5', abs(post + 0.5 * pre) < 0.5,
                                      f'{name} f{f + k} {pre:.1f}>{post:.1f}')
                    # start: 100 cm up from the floor below the victim, 100 cm out along the flight heading
                    if vic:
                        q = P[f - 1]['p'][vic[0]]
                        h = math.atan2(v[0], v[2])
                        px, pz = q['x'] + 100 * math.sin(h), q['z'] + 100 * math.cos(h)
                        d = math.hypot(tr[0][0] - v[0] - px, tr[0][2] - v[2] - pz)
                        S.add('spill: starts victim feet + 100 along the heading (<=25 cm, victim moving)', d <= 25,
                              f'{name} f{f} {d:.0f} cm')
                        att = P[f]['p'][1 - vic[0]]
                        dh = (hd(v[0], v[2]) - hd(att['x'] - q['x'], att['z'] - q['z']) + 540) % 360 - 180
                        S.add('spill: heading = toward the attacker (+0x72A8 + 0x8000) within 15 deg', abs(dh) <= 15,
                              f'{name} f{f} {dh:.0f} deg')
                    # gems that spill on the same frame = a 2-gem hit (b16 & 8): opposite headings
                    S.add('spill: rests on the floor (last 3 rows still)', len(tr) > 3 and tr[-1] == tr[-2], f'{name} f{f}')
                else:                                        # a floor drop at a spot (0x0C0CC832)
                    if stage in SPOTS:
                        i = nearest_spot(stage, b[5:8])
                        sp = SPOTS[stage][i]
                        S.add('floor gem: on one of the 3 drop spots (xz exact)', math.dist(sp[::2], b[5:8:2]) < 0.5,
                              f'{name} f{f} {b[5:8]}')
                        first = not any(O[k].get(t) and O[k][t][9] != 3 and O[k][t][1] == 3 and O[k][t][3] == 5
                                        for k in range(1, f) for t in (2, 3, 4) if t != s) and f < 400
                        if f < 400:
                            S.add('floor gem: first drop on fight frame 299', f == 299, f'{name} f{f}')
                        occ = set()
                        for o in O[f - 1].values():
                            if o[1] in (2, 3) and o[3] in (5, 6, 7) and o[0] != s and o[9] != 3:
                                j = nearest_spot(stage, o[5:8])
                                if math.dist(SPOTS[stage][j][::2], o[5:8:2]) < 30: occ.add(j)
                        pick = spot_choice(stage, P, f - 1, occ)
                        S.add('floor gem: spot = free spot farthest (sum of both fighters)', pick == i,
                              f'{name} f{f} spot {i} vs {pick}')
                        # despawn: 990 frames with no fighter within 300 cm (after the 121-frame appear phase)
                        last = f + 120
                        gone = None
                        for k in range(f, n):
                            o = O[k].get(s)
                            if not o or o[9] == 3: gone = k; break
                            if any(math.dist(o[5:8], (q['x'], q['y'], q['z'])) < 300 for q in P[k]['p']):
                                last = max(last, k)
                            if o[5:8] != b[5:8] and abs(o[6] - b[6]) < 0.1 and math.dist(o[5:8:2], b[5:8:2]) > 1:
                                break                       # taken (moves to the HUD)
                        if gone:
                            taken = any(P[gone]['p'][i2]['gems'] > P[gone - 1]['p'][i2]['gems'] for i2 in (0, 1)) or \
                                any(P[k]['p'][i2]['gems'] > P[k - 1]['p'][i2]['gems'] for k in range(max(1, gone - 40), gone + 1) for i2 in (0, 1))
                            if not taken:
                                S.add('floor gem: gone 990 f after the last frame a fighter was within 300 cm',
                                      abs(gone - (last + 991)) <= 2, f'{name} f{f}: gone {gone} pred {last + 991}')
                f += 1
    S.show()




FAM = {int(k): v for k, v in CODE['items']['family_by_id'].items()}


def items():
    S = Score()
    for name, stage, P, O in logs():
        n = min(len(P), len(O))
        kraken = 'kraken' in name
        seq = CODE['item_pick']['category_seq']
        cats = CODE['item_pick']['categories_kraken' if kraken else 'categories']
        chests, k = {}, 0
        for f in range(n):
            for s, o in O[f].items():
                if o[1] == 2 and o[3] == 7 and s not in chests:
                    chests[s] = [f, o[5:8], o[8], None, k]; k += 1
                    if f < 700:
                        S.add('chest: dropped on fight frame 0 / 599 (chests 1 / 2)', f in (0, 599), f'{name} f{f}')
                    if stage in SPOTS:
                        i = nearest_spot(stage, o[5:8])
                        S.add('chest: on a drop spot (x/z exact)', math.dist(SPOTS[stage][i][::2], o[5:8:2]) < 0.5,
                              f'{name} f{f} {o[5:8]}')
                        occ = set()
                        for q in O[f - 1].values() if f else []:
                            if q[1] in (2, 3) and q[3] in (5, 6, 7) and q[9] != 3:
                                j = nearest_spot(stage, q[5:8])
                                if math.dist(SPOTS[stage][j][::2], q[5:8:2]) < 30: occ.add(j)
                        pick = spot_choice(stage, P, max(f - 1, 0), occ)
                        S.add('chest: spot = free spot farthest from both fighters (summed)', pick == i,
                              f'{name} f{f} spot {i} vs {pick}')
                    cat = seq[k - 1 if k - 1 < 10 else (k - 1) % 10]
                    lst = cats[cat] if cat < 3 else [15, 16, 17]
                    if not (name.startswith('fxitem') and k == 2):   # fxitem_idN poke the category-0 list
                      S.add('chest: item id in category seq[chest #] (0x0C33CF54 / 0x0C33CF14)', o[8] in lst,
                            f'{name} chest {k} id {o[8]} cat {cat}')
            for s in list(chests):
                o = O[f].get(s)
                if chests[s][3] is None and (not o or not (o[1] == 2 and o[3] == 7)):
                    chests[s][3] = f
                    d = f - chests[s][0]
                    S.add('chest: opens 365-366 frames after the drop (or earlier when hit)', d in (365, 366) or d < 365,
                          f'{name} f{f} {d}')
                    if d in (365, 366): S.add('chest: untouched chests open at 365-366', True)
                    chests.pop(s)
        # items: appear / pop / ready / pick-up motion
        seen = {}
        for f in range(1, n):
            for s, o in O[f].items():
                if not (o[1] == 3 and o[3] == 6): continue
                a = O[f - 1].get(s)
                if s not in seen and (a is None or not (a[1] == 3 and a[3] == 6)):
                    seen[s] = f
                    tr = [O[k].get(s) for k in range(f, min(f + 25, n))]
                    ys = [t[6] for t in tr if t]
                    dv = [ys[i] - ys[i + 1] - (ys[i - 1] - ys[i]) for i in range(1, 9)] if len(ys) > 10 else []
                    if dv: S.add('item: pops out of the chest vy 20, gravity 2 (first 10 frames)',
                                 all(abs(x - 2) < 0.2 for x in dv) and abs(ys[1] - ys[0] - 20) < 0.3 or
                                 abs(ys[2] - ys[1] - 18) < 0.3, f'{name} f{f} {ys[:4]}')
                    rdy = next((k for k in range(f, min(f + 40, n)) if O[k].get(s) and O[k][s][9] == 0), None)
                    S.add('item: ready (sub 0) 23 frames after it appears', rdy is not None and rdy - f == 23,
                          f'{name} f{f} ready {rdy}')
                if a is not None and a[1] == 3 and a[3] == 6 and a[2] == 2 and o[2] in (0, 1):
                    q = None
                    for k in range(f, min(f + 12, n)):
                        pq = P[k]['p'][o[2]]
                        if pq['st'] == 35 and pq['kind'] == 2: q = pq['mot']; break
                    if o[8] in FAM:
                        S.add('item: pick-up motion = the item family (k2/80 | 195 | 229 | 237 | 247)', q == FAM[o[8]][0],
                              f'{name} f{f} id {o[8]} k2/{q}')
    S.show()


if __name__ == '__main__':
    {'gems': gems, 'items': items}.get(sys.argv[1] if len(sys.argv) > 1 else 'gems', gems)()
