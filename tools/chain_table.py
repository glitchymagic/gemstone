#!/usr/bin/env python3
"""The original's move selection from the reference logs: which motion a press starts, and which motion a press during
a motion chains into, per fighter. Inputs: every dumps/fidelity/o_*.jsonl with its tape (the presses are known).
A motion change counts as a press-driven link when the button's press edge was 2-5 log frames before it (the logged
latency is 2; a held 4-frame tap can be taken up to 3 frames later), else as an automatic follow-up.
-> game/assets/fidelity/chains.json {fighter: {"first": {"X": .., "Y": .., "X_near": .., "Y_near": .., "AX": .., "AY": ..,
   "RX": .., "RY": ..}, "links": {"k1_016": {"X": "k1_017"}}, "auto": {"k1_026": "k1_027"}, "counts": ...}}
  chain_table.py"""
import collections, glob, json, math, os, sys
sys.path.insert(0, './tools')
import tapes
R = './'
ATK = {10, 11}
GROUND = {0, 2, 31, 32}
AIR = {4, 5, 14}
BTN = {'X': 0x400, 'Y': 0x200}


def mk(p): return f"k{p['kind']}_{p['mot']:03d}"


def main():
    first = collections.defaultdict(collections.Counter)
    links = collections.defaultdict(collections.Counter)
    auto = collections.defaultdict(collections.Counter)
    for f in sorted(glob.glob(R + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]
        src = R + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        rows = tapes.parse(open(src).read())
        o = [json.loads(l) for l in open(f)]
        for i, who in enumerate((m.get('p1'), m.get('p2'))):
            if not who: continue
            def press(k, b):
                for d in range(2, 6):
                    j = k - d
                    if 0 < j < len(rows) and rows[j][i] & BTN[b] and not rows[j - 1][i] & BTN[b]: return True
                return False
            for k in range(1, len(o)):
                p, q, opp = o[k]['p'][i], o[k - 1]['p'][i], o[k]['p'][1 - i]
                if p['st'] not in ATK or (mk(p) == mk(q) and q['st'] in ATK): continue
                btns = [b for b in BTN if press(k, b)]
                pre = 'P' if p['pc'] else ''
                if q['st'] in ATK:
                    if btns: links[who][(pre + mk(q), btns[0], pre + mk(p))] += 1
                    else: auto[who][(pre + mk(q), pre + mk(p))] += 1
                elif btns:
                    b = btns[0]
                    dist = math.hypot(p['x'] - opp['x'], p['z'] - opp['z'])
                    if q['st'] in AIR: cat = 'A' + b
                    elif q['st'] in (31, 32, 2) and q['st'] == 31: cat = 'R' + b
                    else: cat = b + ('_near' if dist < 170 and opp['st'] in (0, 2, 31, 32, 4, 5, 6) else '')
                    first[who][(pre + cat, pre + mk(p))] += 1
    out = {}
    for who in set(first) | set(links) | set(auto):
        d = {'first': {}, 'links': {}, 'auto': {}, 'counts': {}}
        best = {}
        for (cat, mo), n in first[who].items():
            if n > best.get(cat, (0, ''))[0]: best[cat] = (n, mo)
        d['first'] = {c: v[1] for c, v in best.items()}
        lb = {}
        for (a, b, n_), n in links[who].items():
            if n > lb.get((a, b), (0, ''))[0]: lb[(a, b)] = (n, n_)
        for (a, b), v in lb.items(): d['links'].setdefault(a, {})[b] = v[1]
        ab = {}
        for (a, n_), n in auto[who].items():
            if n > ab.get(a, (0, ''))[0]: ab[a] = (n, n_)
        d['auto'] = {a: v[1] for a, v in ab.items()}
        d['counts'] = {'first': sum(first[who].values()), 'links': sum(links[who].values()), 'auto': sum(auto[who].values())}
        out[who] = d
    # near X: every fighter's logged close move is k1/74 (moves_*.tape attempt 1, near_*.tape at 100 cm); the votes above
    # are polluted by attempts where the opponent was still down / turned away after a knockdown
    for who, d in out.items():
        if any(v == 'k1_074' for c in first[who] for v in [c[1]]): d['first']['X_near'] = 'k1_074'
    json.dump(out, open(R + 'game/assets/fidelity/chains.json', 'w'), indent=1, sort_keys=True)
    for w, d in sorted(out.items()): print(w, d['first'], d['counts'])


if __name__ == '__main__':
    main()
