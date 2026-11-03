#!/usr/bin/env python3
"""The original's hit-grabs: attacks that turn into a throw on contact (the attacker goes from state 10 / 11 with a kind-1
motion straight into state 28 with a kind-4 motion, no k1/84 grab): Galuda's near punch k1/74 > k4/4, Gunrock's air
punch k1/10 > k4/2, Wang-Tang's k1/16 > k4/3, Rouge's PC k1/107 > k4/9, Kraken's PC k1/108 > k4/3 (Final Valgas's
k1/10 > k4/3 is his own). Read off every disc log (dumps/fidelity/o_*.jsonl tapes + dumps/fidelity/cpu/cpu_*.jsonl
CPU fights). Per (fighter, attack motion) the first sample: the attack's motion frame on the contact row, then the same
schema as tools/throw_table.py from the contact row (thrower / victim (state, kind, motion, rows) chains, the victim's
feet relative to the thrower's per held row (forward along the thrower's heading at the contact, up, side), damage
events, the release row + the victim's first velocities), plus the number of samples.
  hitgrab_table.py -> game/assets/fidelity/hitgrabs.json"""
import glob, json, math, os, sys
R = './'
sys.path.insert(0, R + 'tools')
import tapes
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/game/assets/fidelity/hitgrabs.json'


def segs(rows, i, a, b):
    out = []
    for r in rows[a:b]:
        p = r['p'][i]
        k = (p['st'], p['kind'], p['mot'])
        if out and out[-1][0] == k: out[-1][1] += 1
        else: out.append([k, 1])
    return [[k[0], k[1], k[2], n] for k, n in out]


def logs():
    for f in sorted(glob.glob(R + 'dumps/fidelity/o_*.jsonl')):
        if f.endswith('.obj.jsonl'): continue
        t = os.path.basename(f)[2:-6]
        src = R + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        yield f, (m.get('p1'), m.get('p2'))
    for f in sorted(glob.glob(R + 'dumps/fidelity/cpu/cpu_*.jsonl')):
        n = os.path.basename(f).split('_')
        yield f, (n[1], n[2])


def sample(rows, g, i):
    """g = the attacker's first state-28 row, i = his index"""
    j = 1 - i
    end = g
    while end < len(rows) and rows[end]['p'][i]['st'] == 28: end += 1
    vend = g
    while vend < len(rows) and vend < g + 500:
        st = rows[vend]['p'][j]['st']
        if st in (15, 0, 16) and vend > end: break
        vend += 1
    t0 = rows[g]['p'][i]
    ang = t0['ang'] / 65536.0 * 2 * math.pi
    f = (math.sin(ang), math.cos(ang)); sd = (f[1], -f[0])
    held, dmg, tpath = [], [], []
    hp_prev = rows[g - 1]['p'][j]['hp']
    rel_start, fly_from = None, None
    for k in range(g, vend):
        a, v = rows[k]['p'][i], rows[k]['p'][j]
        if k < end:
            ex, ey, ez = a['x'] - t0['x'], a['y'] - t0['y'], a['z'] - t0['z']
            tpath.append([round(ex * f[0] + ez * f[1], 2), round(ey, 2), round(ex * sd[0] + ez * sd[1], 2)])
        dx, dy, dz = v['x'] - a['x'], v['y'] - a['y'], v['z'] - a['z']
        if v['st'] == 29:
            if rel_start is None: rel_start = k - g
            held.append([round(dx * f[0] + dz * f[1], 2), round(dy, 2), round(dx * sd[0] + dz * sd[1], 2)])
        if v['hp'] < hp_prev: dmg.append([k - g, hp_prev - v['hp']])
        hp_prev = v['hp']
        if fly_from is None and v['st'] != 29 and rel_start is not None: fly_from = k
    prev = rows[g - 1]['p'][i]
    out = dict(attack='k%d_%03d' % (prev['kind'], prev['mot']), attack_fr=rows[g]['p'][i]['fr'] if rows[g]['p'][i]['kind'] == 1 else prev['fr'] + 1,
               attack_st=prev['st'], air=prev['y'] > 1.0 or prev['vy'] != 0.0, contact_keeps_attack=rows[g]['p'][i]['kind'] == 1, thrower=segs(rows, i, g, end), victim=segs(rows, j, g, vend + 1),
               held_from=rel_start, held=held, damage=dmg, victim_hp0=rows[g - 1]['p'][j]['hp'], thrower_rows=end - g,
               thrower_path=tpath, victim_st_before=rows[g - 1]['p'][j]['st'])
    if fly_from is not None:
        vel = []
        for k in range(fly_from, min(fly_from + 6, len(rows) - 1)):
            a, b = rows[k]['p'][j], rows[k + 1]['p'][j]
            vel.append([round((b['x'] - a['x']) * f[0] + (b['z'] - a['z']) * f[1], 2), round(b['y'] - a['y'], 2)])
        out['release_row'] = fly_from - g
        out['release_vel'] = vel
    return out


if __name__ == '__main__':
    res, counts = {}, {}
    for path, ids in logs():
        rows = [json.loads(l) for l in open(path)]
        for g in range(1, len(rows)):
            for i in range(2):
                p, q = rows[g]['p'][i], rows[g - 1]['p'][i]
                if not (p['st'] == 28 and p['kind'] == 4 and q['kind'] == 1 and q['mot'] != 84):
                    continue
                if q['st'] == 28:   # Galuda's near punch: state 28 on the contact row with k1/74 still on, k4/4 the row after
                    g -= 1
                    q = rows[g - 1]['p'][i]
                if q['st'] not in (10, 11) or q['kind'] != 1: continue
                c = ids[i]
                if c is None or c == 'finalvalgas': continue
                key = 'k1_%03d' % q['mot']
                counts.setdefault(c, {}).setdefault(key, 0)
                counts[c][key] += 1
                if key in res.get(c, {}): continue
                s = sample(rows, g, i)
                s['src'] = '%s f%d P%d' % (os.path.basename(path), g, i + 1)
                res.setdefault(c, {})[key] = s
    for c in res:
        for k in res[c]:
            res[c][k]['samples'] = counts[c][k]
            s = res[c][k]
            print(c, k, 'x%d' % s['samples'], s['src'], 'fr', s['attack_fr'], 'air', s['air'], 'thrower', [(a[1], a[2], a[3]) for a in s['thrower']],
                  'victim', [(a[0], a[1], a[2], a[3]) for a in s['victim']][:5], 'dmg', s['damage'], 'rel', s.get('release_row'))
    json.dump(res, open(OUT, 'w'), separators=(',', ':'))
