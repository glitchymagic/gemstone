#!/usr/bin/env python3
"""The original's hit-reaction machine (state 27, 0x0C08ED56 + class handlers 0x0C338FF8) as a per-frame Python
simulation, plus the export of its tables, and a check against the logged hits of the reference tapes.
Spec + addresses: docs/REACT.md.

  react_sim.py export            -> game/assets/fidelity/react_code.json (tables + every fighter's records, from 1ST_READ)
  react_sim.py verify [-v]       -> replays every landed hit of dumps/fidelity/o_*.jsonl, match rate per class
  react_sim.py show TAPE ROW P   -> one hit: simulated vs logged rows (P = victim 1|2)

Simulation inputs per hit (all from the frame the hit lands, like the game has them): the attack record (20 bytes),
the attacker->victim direction (+0x72A8), the victim's yaw (+0x30, = his facing +0x7248 when he stands), position,
previous state (+0x71BB), health after the hit (KO), the victim's hip-bone world position (launch classes start
there: 0x0C0CCF32 copies a bone's world matrix into the position; the remaster takes its own skeleton's hip) and,
because walls are stage geometry, the row at which the victim's move was clamped by a wall (None = open floor)."""
import json, math, os, struct, sys, glob, collections

R = './'
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, 'game/assets/fidelity/react_code.json')
BASE = 0x0C010000
NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas',
         'finalvalgas', 'objects']
ANG = 2048          # one record angle unit (rec[0xd], rec[0xe]) = 737280.0 / 360.0 = 2048 / 65536 of a turn (11.25 deg)


def _bin():
    return open(R + 'rip/fs/1ST_READ.BIN', 'rb').read()


def export():
    B = _bin()
    u32 = lambda a: struct.unpack_from('<I', B, (a & 0x1FFFFFFF) - BASE)[0]
    f32s = lambda a, n: [round(x, 4) for x in struct.unpack_from(f'<{n}f', B, (a & 0x1FFFFFFF) - BASE)]
    kb = []
    for i in range(16):
        p = u32(0x0C338C34 + 4 * i); t = []
        for k in range(64):
            f = struct.unpack_from('<f', B, p - BASE + 4 * k)[0]
            t.append(round(f, 4))
            if f < 0: break
        kb.append(t)
    ptrs = [u32(0x0C338A98 + 4 * n) for n in range(12)]
    ends = sorted(ptrs) + [0x0C335450 + 140 * 20]
    recs = {}
    for n, p in enumerate(ptrs):
        nxt = min(q for q in ends if q > p)
        rows = []
        for i in range((nxt - p) // 20):
            r = B[p - BASE + 20 * i: p - BASE + 20 * i + 20]
            rows.append(r.hex())
        recs[NAMES[n]] = rows
    used = {}
    for n in range(11):
        f = R + 'game/assets/ripped/p%x0_hit.json' % n
        if os.path.exists(f):
            d = json.load(open(f))
            used[NAMES[n]] = sorted({s[2] for st in d['moves'].values() for s in st if s[2]})
    out = {
        'about': 'Hit-reaction machine tables from 1ST_READ (docs/REACT.md). Records: 20 bytes hex, index = hit id.',
        'record_fields': {'0': 'class (handler 0x0C338FF8[class], remapped by 0x0C08E704)', '1': 'damage (of 240)',
                          '2': 'hit-stop frames (+0x10B, both fighters)', '3': 'class 0: frames in state 27 + 1 (+0xF0)',
                          '4': 'type (1 = combo voice, 6/7 = special voices, 7 = no combo count)',
                          '5': 'non-zero = no hit sound', '6': 'class 0: motion column + 1 (0 = from attacker +0x103); class 1/2: 1 front/back by side, 2 inverted, 3/4 tumble k2/112',
                          '7': 'stun damage (& 63) taken from +0x7214', '0xb': 'guard kind (3/4/5/6)',
                          '0xc': 'level: knockback table (class 0) / launch speed (class 1/2/3)',
                          '0xd': 'launch elevation, units of 11.25 deg', '0xe': 'direction offset, units of 11.25 deg (bit 0x20 = object hit flag)',
                          '0x10': 'bit 0: no wall splat (bounce instead)', '0x11': 'status effect bits (0x18 / 0xE0)',
                          '0x12': 'hit sound id (99 = none)', '0x13': 'guard sound'},
        'class_handlers': ['0x%08X' % u32(0x0C338FF8 + 4 * i) for i in range(41)],
        'knockback': kb,
        'launch_speed': f32s(0x0C338CB4, 16),
        'motion_table': list(B[0x0C1507CE - BASE:0x0C1507CE - BASE + 24]),
        'motion_table_air': list(B[0x0C1507E6 - BASE:0x0C1507E6 - BASE + 24]),
        'knockdown_classes': [i for i in range(32) if B[0x0C1507A8 - BASE + i]],
        'gravity_launch': -2.0, 'gravity_wall_slide': -1.0, 'bounce_vy': 11.6, 'bounce_gravity': -0.97,
        'bounce_keep': 0.5, 'wall_stick_frames': 20, 'hitstop_record_byte': 2,
        'measured': MEASURED,
        'records': recs, 'used_hit_ids': used,
    }
    json.dump(out, open(OUT, 'w'), indent=1)
    print('wrote', OUT)


# constants that the logs give where the code calls into functions not decoded yet (see docs/REACT.md "Open")
MEASURED = {
    'recover_24_frames': 8,        # state 24 k0/0 then state 0 (o_*: 147 of 151)
    'lying_after_99': 5, 'lying_after_153': 5, 'lying_after_115': 5, 'lying_after_131': 5,   # 66 of 89 logged lyings; 10 in 23 (rule open)
    'getup_k2_146_frames': 23, 'getup_idle_frames': 7,
    'wall_drop': 119.0,            # 0x0C09B74C: the splat lowers the body by this (Falcon, Londo walls)
    'len': {0: 1, 1: 1, 3: 1, 4: 7, 6: 1, 7: 1, 9: 1, 10: 7, 12: 1, 13: 1, 15: 1, 16: 7, 18: 1, 19: 1,
            96: 12, 97: 1, 98: 20, 99: 35, 112: 15, 115: 12, 128: 10, 129: 1, 130: 24, 131: 35, 152: 99, 153: 40},
}


class Tables:
    def __init__(self):
        d = json.load(open(OUT))
        self.kb = d['knockback']; self.speed = d['launch_speed']
        self.mt = d['motion_table']; self.mt_air = d['motion_table_air']
        self.kd = set(d['knockdown_classes'])
        self.recs = d['records']


def s16(a):
    a &= 0xFFFF
    return a - 0x10000 if a & 0x8000 else a


def side_row(attack_dir, rec14, yaw):
    """0x0C08E8D6: +0x7205 = where the hit comes from relative to the victim's body yaw (+0x30)."""
    d = s16((attack_dir - rec14 * ANG) - yaw)
    row = 0                                   # front (|d| > 140 deg)
    if -0x1C71 <= d <= 0x1C71: row = 1        # behind (within 40 deg of the yaw)
    if 0x1C71 < d <= 0x638E: row = 2
    if -0x638E <= d < -0x1C71: row = 3
    return row


def remap(cls, rec, prev_state, hp_after, air, stun=1, prev_class=None, df=0):
    """0x0C08E704: the class the machine actually runs."""
    if rec[0] == 23: return cls
    if hp_after < 0: return 1                 # KO: always the launch
    if air == 2 and cls < 25:
        if cls in (0, 4, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18): cls = 1 if rec[4] == 0 else 2
        elif cls == 24: cls = 3
    elif air in (0, 1) and rec[0xb] == 3 and prev_state == 9: cls = 17
    elif air == 3: cls = 13
    if prev_state == 7: cls = 3
    if prev_state == 34: cls = 19
    if prev_state == 36: cls = 20
    if prev_state == 27 and prev_class in (11, 7): return 1
    if rec[0x11] & 0xE0 == 0x80: return 7
    if stun == 0 and (df or cls not in TABLES.kd): return 2   # stun meter empty: dizzy launch (level 6, elevation 7)
    return cls


def sim(rec, att_dir, yaw, pos, prev_state=0, hp_after=1, hip=None, wall_row=None, wall_pos=None, air=0, stun=20,
        n=400, ch=0):
    """-> list of rows (state, kind, motion, x, y, z), row 0 = the frame the hit is detected (motion unchanged)."""
    T = TABLES
    cls = remap(rec[0], rec, prev_state, hp_after, air, stun=stun)
    row = side_row(att_dir, rec[14] & 0x1F, yaw)
    lvl, elev = rec[0xc], rec[0xd]
    dizzy = stun == 0 and cls == 2 and rec[0] != 2
    if dizzy: lvl, elev = 6, 7                 # 0x0C08E704: +0x7213 = 6, +0x7211 = 7
    heading = (att_dir - (rec[14] & 0x1F) * ANG) & 0xFFFF
    sh, ch_ = math.sin(heading * math.pi / 32768), math.cos(heading * math.pi / 32768)
    x, y, z = pos
    out = [(27, None, None, x, y, z)]
    freeze = max(0, rec[2] - 2)
    L = MEASURED['len']

    def emit(st, m):
        out.append((st, 2 if m is not None and m < 1000 else 0, m if m is None or m < 1000 else m - 1000, x, y, z))

    def tail(state_rows):
        for st, m, k in state_rows:
            for _ in range(k): emit(st, m)

    if cls == 0:
        tbl = T.mt if air == 0 else T.mt_air
        if rec[6]: base = tbl[row * 6 + rec[6] - 1]
        else: base = tbl[row * 6 + (2 + (3 if lvl > 3 else 0))]
        kb = [v for v in T.kb[lvl] if v >= 0]
        f0 = max(1, rec[3] - 1)
        emit(27, base)
        for _ in range(freeze): emit(27, base)
        m, i, sub = base + 1, 0, 2
        while True:
            if sub == 2 and i >= len(kb):
                m = base + 2; sub = 3
                if f0 < 2: f0 += 1
            elif sub == 2:
                x += kb[i] * sh; z += kb[i] * ch_; i += 1
            f0 -= 1
            if f0 < 1: break
            emit(27, m)
        tail([(24, 1000, MEASURED['recover_24_frames']), (0, 1000, 1)])
        return cls, out
    if cls in (1, 2, 3):
        if hip is not None: x, y, z = hip
        el = elev * ANG * math.pi / 32768
        S = T.speed[lvl]
        vh, vy = S * math.cos(el), S * math.sin(el)
        vx, vz = vh * sh, vh * ch_
        g = -2.0
        if cls == 3: m0 = 112
        elif rec[0] in (1, 2) and cls in (1, 2) and rec[6] == 2: m0 = 96 if row == 1 else 128; row = 0 if row == 1 else 1
        elif rec[0] in (1, 2) and cls in (1, 2) and rec[6] in (3, 4): m0 = 112
        else: m0 = 128 if row == 1 else 96
        m, fr, ec, f0 = m0, 0, 0, 3
        emit(27, m)
        for _ in range(freeze): emit(27, m)
        k = len(out)          # rows since init
        phase, wall_hits = 'fly', 0
        while len(out) < n:
            r = len(out)
            if phase == 'fly':
                if cls != 3 and f0 > 0: f0 -= 1
                elif wall_row is not None and r == wall_row + 1 and wall_hits < 2 and not (rec[0x10] & 1):
                    # class 22: wall splat (handler 0x0C091B3C)
                    wall_hits += 1
                    y = max(0.0, y - MEASURED['wall_drop']); vx = vy = vz = 0.0
                    m = 152; emit(27, m)
                    stick = 20
                    while stick > 0: stick -= 1; emit(27, m)
                    g = -1.0
                    while True:
                        if vy < 0 and y <= 0: break
                        y += vy; y = max(y, 0.0); vy += g; emit(27, m)
                    m = 153
                    for _ in range(L[153]): emit(27, m)
                    tail([(15, 144, MEASURED['lying_after_153']), (16, 146, 23), (16, 1000, 7), (0, 1000, 1)])
                    return 22, out
                fr += 1
                if cls == 3:
                    if vy < 0 and y <= 0:
                        vx *= 0.5; vz *= 0.5; vy = 11.6; g = -0.97; m = 115; phase = 'bounce'
                        x += vx; y += vy; z += vz; vy += g; emit(27, m); continue
                elif m0 in (96, 128):
                    if ec == 0 and fr >= L[m0]: m = m0 + 1; ec = 1
                    elif ec == 1 and vy < 0: m = m0 + 2; ec = 2
                if cls != 3 and vy < 0 and y <= 0:
                    m = 131 if row == 1 else 99; phase = 'land'; emit(27, m)
                    for _ in range(L[m] - 1): emit(27, m)
                    lie = 145 if row == 1 else 144
                    tail([(15, lie, MEASURED['lying_after_131' if row == 1 else 'lying_after_99']),
                          (16, lie + 2, 23), (16, 1000, 7), (13, 175, 1) if dizzy else (0, 1000, 1)])
                    return cls, out
                x += vx; y += vy; z += vz; y = max(y, 0.0); vy += g
                if wall_pos is not None and r == wall_row: x, z = wall_pos     # stage collision (input)
                emit(27, m)
            else:   # class 3 bounce
                x += vx; y += vy; z += vz; y = max(y, 0.0); vy += g
                if vy < 0 and y <= 0:
                    tail([(15, 144, MEASURED['lying_after_115']), (16, 146, 23), (16, 1000, 7), (0, 1000, 1)])
                    return cls, out
                emit(27, m)
        return cls, out
    return cls, None


TABLES = None


def chain(rows):
    c = []
    for st, kind, m, *_ in rows:
        key = (st, kind, m)
        if c and c[-1][0] == key: c[-1][1] += 1
        else: c.append([key, 1])
    return c


def logged_hits():
    sys.path.insert(0, R + 'tools')
    import tapes
    B = _bin()
    u32 = lambda a: struct.unpack_from('<I', B, (a & 0x1FFFFFFF) - BASE)[0]
    CH = {w: i for i, w in enumerate(NAMES)}
    for f in sorted(glob.glob(R + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]
        src = R + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        o = [json.loads(l) for l in open(f)]
        for v in (0, 1):
            att = m.get('p2' if v == 0 else 'p1')
            stun, last = 20, -10**9
            for k in range(1, len(o) - 1):
                p, q = o[k]['p'][v], o[k - 1]['p'][v]
                if q['st'] == 13 and p['st'] != 13: stun = 20          # dizzy over: meter full again (0x0C0A1F52)
                if not (p['hp'] < q['hp'] and q['hp'] > 0): continue
                a = o[k - 1]['p'][1 - v]
                hid = a['hid'] or o[k]['p'][1 - v]['hid']
                pa = u32(0x0C338A98 + 4 * CH[att]) + 20 * hid
                r = B[pa - BASE:pa - BASE + 20]
                if k - last > 180: stun = 20                           # +0x7215 = 180: refill (assumed, see REACT.md)
                if hid: stun = max(0, stun - (r[7] & 63))
                last = k
                yield dict(tape=t, k=k, v=v, att=att, hid=hid, rec=r, o=o, stun=stun)


def observe(h, n=400):
    o, k, v = h['o'], h['k'], h['v']
    rows = []
    for j in range(k, min(len(o), k + n)):
        p = o[j]['p'][v]
        if j > k and p['hp'] < o[j - 1]['p'][v]['hp']: break      # the next hit starts a new reaction
        rows.append((p['st'], p['kind'], p['mot'], p['x'], p['y'], p['z']))
        if j > k + 2 and p['st'] in (0, 2, 31, 32, 4, 5, 6): break
    return rows


def inputs(h):
    o, k, v = h['o'], h['k'], h['v']
    q, a = o[k - 1]['p'][v], o[k - 1]['p'][1 - v]
    d = int(round(math.atan2(q['x'] - a['x'], q['z'] - a['z']) * 32768 / math.pi)) & 0xFFFF
    p1 = o[min(k + 1, len(o) - 1)]['p'][v]
    hip = (p1['x'], p1['y'], p1['z'])
    # wall contact: the first row of the flight where the logged horizontal move stops short of the free flight
    wall = wpos = None
    for j in range(k + 2, min(len(o) - 1, k + 200)):
        p, pp = o[j]['p'][v], o[j - 1]['p'][v]
        if p['st'] != 27: break
        if p['kind'] == 2 and p['mot'] == 152: wall = j - 1 - k; wpos = (pp['x'], pp['z']); break
    # body yaw +0x30: a standing fighter's facing; inside a reaction (27 / 24) the logged +0x7248 is the knockback
    # heading and the body still faces where it faced when the reaction began (toward the attacker)
    yaw = q['ang'] if q['st'] not in (27, 24, 13) else (d + 0x8000) & 0xFFFF
    p0 = o[k]['p'][v]
    return dict(att_dir=d, yaw=yaw, pos=(p0['x'], p0['y'], p0['z']), prev_state=q['st'],
                hp_after=p0['hp'], hip=hip, wall_row=wall, wall_pos=wpos, air=2 if q['st'] in (5, 14) else 0,
                stun=h.get('stun', 20))


def compare(sim_rows, obs):
    sc, oc = chain(sim_rows[1:]), chain(obs[1:])
    # the logged chain stops at the first free state; cut the sim the same way
    n = min(len(sim_rows), len(obs))
    keys_ok = [c[0] for c in sc[:len(oc)]] == [c[0] for c in oc]
    cut = len(oc) - 1 if obs_cut(obs) else len(oc)     # a chain cut by the next hit: its last segment is partial
    lens_ok = keys_ok and [c[1] for c in sc[:cut]] == [c[1] for c in oc[:cut]]
    for i in range(2, n):         # a tape '@place' teleports the fighter: compare travel only up to it
        if math.hypot(obs[i][3] - obs[i - 1][3], obs[i][5] - obs[i - 1][5]) > 60: n = i; break
    dpos = max(math.dist(s[3:6], o_[3:6]) for s, o_ in zip(sim_rows[:n], obs[:n]))
    return keys_ok, lens_ok, dpos, sc, oc


def obs_cut(obs):
    return obs[-1][0] not in (0, 2, 31, 32, 4, 5, 6)


def verify(verbose=False):
    stats = collections.defaultdict(lambda: [0, 0, 0, 0])
    bad = []
    for h in logged_hits():
        rec = h['rec']
        if h['hid'] == 0:
            stats['no record (hit id 0: objects / throws / projectiles)'][0] += 1
            continue
        inp = inputs(h)
        cls, rows = sim(rec, **inp)
        key = f'class {rec[0]}' + (f' -> {cls}' if cls != rec[0] else '')
        st = stats[key]; st[0] += 1
        if rows is None:
            bad.append((key, h['tape'], h['k'], 'not simulated')); continue
        obs = observe(h)
        ok_m, ok_n, dpos, sc, oc = compare(rows, obs)
        st[1] += ok_m; st[2] += ok_n; st[3] += dpos <= 1.0
        if not (ok_m and ok_n and dpos <= 1.0):
            bad.append((key, h['tape'], h['k'], h['v'] + 1, h['att'], h['hid'], f'd={dpos:.1f}',
                        fmt(sc[:len(oc) + 1]), fmt(oc)))
    print(f"{'class':40s} hits  chain  frames  travel<=1cm")
    for k, (n, a, b, c) in sorted(stats.items()):
        print(f'{k:40s} {n:4d}  {a:4d}  {b:4d}  {c:4d}')
    if verbose:
        for b in bad: print(*b)
    return stats, bad


def fmt(c):
    return ' > '.join(f's{k[0]} k{k[1]}/{k[2]} x{n}' for k, n in c)


def show(tape, row, p):
    for h in logged_hits():
        if h['tape'] == tape and h['k'] == int(row) and h['v'] == int(p) - 1:
            inp = inputs(h)
            print('rec', h['rec'].hex(), 'inputs', {k: v for k, v in inp.items() if k != 'pos'})
            cls, rows = sim(h['rec'], **inp)
            obs = observe(h)
            for i in range(max(len(rows or []), len(obs))):
                s = rows[i] if rows and i < len(rows) else None
                o_ = obs[i] if i < len(obs) else None
                f = lambda r: f's{r[0]:<3} k{r[1]}/{r[2]}  {r[3]:8.2f} {r[4]:8.2f} {r[5]:8.2f}' if r else '-'
                print(f'{i:4d}  sim {f(s):48s} log {f(o_)}')
            return


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'verify'
    if cmd == 'export': export(); sys.exit()
    TABLES = Tables()
    if cmd == 'verify': verify('-v' in sys.argv)
    elif cmd == 'show': show(*sys.argv[2:5])
