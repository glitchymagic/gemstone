#!/usr/bin/env python3
"""The original's hit reactions from the reference logs: for every landed hit (the victim's health drops), the attacker's
fighter + hit id (+0x100 = attack record) and the victim's reaction motions until he is free again, with the freeze
frames (motion frame held) and his travel. Grouped by the record's bytes (pN0_hit.json "hits": react / level / class /
type) so unlogged records can be mapped by kind. -> game/assets/fidelity/reactions.json + a summary on stdout.
  react_table.py"""
import collections, glob, json, math, os, sys
sys.path.insert(0, './tools')
import tapes
R = './'
FILE = {'falcon': 'p00', 'ryoma': 'p10', 'wangtang': 'p20', 'jack': 'p30', 'gunrock': 'p40', 'galuda': 'p50',
        'ayame': 'p60', 'rouge': 'p70', 'kraken': 'p80', 'valgas': 'p90', 'finalvalgas': 'pa0'}
FREE = {0, 2, 31, 32, 4, 5, 6}


def main():
    recs = {w: json.load(open(R + f'game/assets/ripped/{f}_hit.json')).get('hits', {}) for w, f in FILE.items()
            if os.path.exists(R + f'game/assets/ripped/{f}_hit.json')}
    by_hit = collections.defaultdict(list)
    for f in sorted(glob.glob(R + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]
        src = R + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        o = [json.loads(l) for l in open(f)]
        for v in (0, 1):
            att = m.get('p2' if v == 0 else 'p1')
            for k in range(1, len(o) - 1):
                p, q = o[k]['p'][v], o[k - 1]['p'][v]
                if not (p['hp'] < q['hp'] and q['hp'] > 0): continue
                a = o[k - 1]['p'][1 - v]
                hid = a['hid'] or o[k]['p'][1 - v]['hid']
                chain, frz, last, j = [], 0, None, k
                x0 = (p['x'], p['y'], p['z'])
                ymax = p['y']
                while j < len(o) and j < k + 400:
                    s = o[j]['p'][v]
                    if j > k + 2 and s['st'] in FREE: break
                    key = f"k{s['kind']}/{s['mot']}"
                    if not chain or chain[-1][0] != key: chain.append([key, 0, s['st']])
                    chain[-1][1] += 1
                    if last and last == (key, s['fr']): frz += 1
                    last = (key, s['fr']); ymax = max(ymax, s['y'])
                    j += 1
                end = o[min(j, len(o) - 1)]['p'][v]
                rec = recs.get(att, {}).get(str(hid), {})
                by_hit[(att, hid)].append({'dmg': q['hp'] - p['hp'], 'chain': chain, 'frames': j - k, 'freeze': frz,
                    'travel': round(math.hypot(end['x'] - x0[0], end['z'] - x0[2])), 'up': round(ymax - x0[1]),
                    'rec': {kk: rec.get(kk) for kk in ('react', 'level', 'class', 'type', 'dmg')}, 'victim_st0': q['st'],
                    'tape': t, 'frame': k})
    out = {f'{a}/{h}': v for (a, h), v in by_hit.items()}
    json.dump(out, open(R + 'game/assets/fidelity/reactions.json', 'w'), indent=1)
    kinds = collections.Counter()
    for (a, h), v in sorted(by_hit.items()):
        c = ' > '.join(f'{x[0]}' for x in v[0]['chain'][:6])
        kinds[(str(v[0]['rec'].get('react')), str(v[0]['rec'].get('level')), v[0]['chain'][0][0] if v[0]['chain'] else '')] += 1
    for k, n in sorted(kinds.items(), key=lambda x: -x[1])[:30]: print('react', k[0], 'level', k[1], 'first', k[2], 'x', n)
    print(len(out), 'attacker/hit ids,', sum(len(v) for v in out.values()), 'hits')


if __name__ == '__main__':
    main()
