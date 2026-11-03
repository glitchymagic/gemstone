#!/usr/bin/env python3
"""The original's grab-throws per fighter, read off the same-input reference logs (dumps/fidelity/o_moves_<id>.jsonl:
every tape grabs at row 978, P1 = the fighter, P2 = the stage owner's opponent, both on open floor).
Per fighter: the thrower's (state, kind, motion, rows) chain from the grab (state 37) to idle, the victim's chain over
the same rows, the victim's feet relative to the thrower's feet per row (cm: forward along the thrower's heading at the
grab, up, side) while the victim is in state 29 (held), the damage events (row, amount), and the victim's flight after
the release (first rows of velocity, the gravity it falls with) until he lands.
  throw_table.py -> game/assets/fidelity/throws.json"""
import json, math, os, sys
R = './'
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas']


def segs(rows, i, a, b):
    out = []
    for r in rows[a:b]:
        p = r['p'][i]
        k = (p['st'], p['kind'], p['mot'])
        if out and out[-1][0] == k: out[-1][1] += 1
        else: out.append([k, 1])
    return [[k[0], k[1], k[2], n] for k, n in out]


def one(fid):
    path = R + f'dumps/fidelity/o_moves_{fid}.jsonl'
    if not os.path.exists(path): return None
    rows = [json.loads(l) for l in open(path)]
    g = next((i for i, r in enumerate(rows) if r['p'][0]['st'] == 37 and (i == 0 or rows[i - 1]['p'][0]['st'] != 37)), None)
    if g is None: return None
    end = g
    while end < len(rows) and rows[end]['p'][0]['st'] != 0: end += 1
    vend = g
    seen_air = False
    while vend < len(rows) and vend < g + 400:
        st = rows[vend]['p'][1]['st']
        if st in (15, 0, 16) and vend > end: break
        vend += 1
    t0 = rows[g]['p'][0]
    ang = t0['ang'] / 65536.0 * 2 * math.pi
    f = (math.sin(ang), math.cos(ang)); sd = (f[1], -f[0])
    held, dmg, fly, tpath = [], [], [], []
    hp_prev = rows[g]['p'][1]['hp']
    rel_start = None
    for j in range(g, vend):
        a, v = rows[j]['p'][0], rows[j]['p'][1]
        if j <= end:
            ex, ey, ez = a['x'] - t0['x'], a['y'] - t0['y'], a['z'] - t0['z']
            tpath.append([round(ex * f[0] + ez * f[1], 2), round(ey, 2), round(ex * sd[0] + ez * sd[1], 2)])
        dx, dy, dz = v['x'] - a['x'], v['y'] - a['y'], v['z'] - a['z']
        if v['st'] == 29:
            if rel_start is None: rel_start = j - g
            held.append([round(dx * f[0] + dz * f[1], 2), round(dy, 2), round(dx * sd[0] + dz * sd[1], 2)])
        if v['hp'] < hp_prev: dmg.append([j - g, hp_prev - v['hp']])
        hp_prev = v['hp']
        if v['st'] == 27 and rows[j - 1]['p'][1]['st'] == 29:
            fly_from = j
    out = dict(grab_row=g, thrower=segs(rows, 0, g, end + 1), victim=segs(rows, 1, g, vend + 1),
               held_from=rel_start, held=held, damage=dmg, victim_hp0=rows[g]['p'][1]['hp'],
               thrower_rows=end - g, thrower_path=tpath)
    if 'fly_from' in locals():
        k = fly_from
        vel = []
        for j in range(k, min(k + 6, len(rows) - 1)):
            a, b = rows[j]['p'][1], rows[j + 1]['p'][1]
            vel.append([round((b['x'] - a['x']) * f[0] + (b['z'] - a['z']) * f[1], 2), round(b['y'] - a['y'], 2)])
        out['release_row'] = k - g
        out['release_vel'] = vel
    return out


if __name__ == '__main__':
    res = {}
    for fid in IDS:
        o = one(fid)
        if o: res[fid] = o
        if o: print(fid, 'thrower', [(s[1], s[2], s[3]) for s in o['thrower']], 'victim', [(s[0], s[1], s[2], s[3]) for s in o['victim']][:6],
                    'dmg', o['damage'], 'rel', o.get('release_row'), o.get('release_vel', [])[:3])
    json.dump(res, open(R + 'game/assets/fidelity/throws.json', 'w'), separators=(',', ':'))
