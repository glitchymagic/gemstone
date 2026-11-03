#!/usr/bin/env python3
"""fx-obj: the ORIGINAL's object / pole / wall / ledge machines (docs/OBJ.md) scored against the disc's own CPU-vs-CPU logs.

  obj_check.py [score] [LOGDIR]     every rule in game/assets/fidelity/obj_code.json replayed on the 48 disc logs
                                    (dumps/fidelity/cpu/cpu_*.jsonl, both fighters AI-driven) -> a score per rule
  obj_check.py show RULE [N]        the first N episodes of a rule frame by frame (vault, k78, pole, wallkick, fall)
  obj_check.py objlog BIN META      decode an fx-obj object log (per-frame object records, see docs/OBJ.md section 6)
  obj_check.py objscore BIN META    the section-6b rules (release frame, level / aimed flights, respawn) on such a log

Rows: tools/cpu_stats.py decode (feet x/y/z cm, velocity +0x7270 cm/frame = the velocity the game integrates this frame,
kind/mot/fr motion, st state, pad = the AI's virtual pad (0x400 punch, 0x200 kick, 0x004 jump, 0xF0 stick)).
Game order inside one frame (what the rules use): the globals (fighter distance 0x0C494D1C) are computed before the
players update, P1 updates before P2, a state's init runs on the row whose motion changes, its velocity shows from the
next row on."""
import glob, json, math, os, pickle, sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LOGDIR = os.environ.get('OBJ_LOGDIR', './dumps/fidelity/cpu/')
CACHE = '/tmp/ps-fx-obj/cache.pkl'
CODE = json.load(open(os.path.join(ROOT, 'game/assets/fidelity/obj_code.json')))
K = ('x', 'y', 'z', 'vx', 'vy', 'vz', 'ang', 'kind', 'mot', 'fr', 'st', 'pst', 'pad', 'prs', 'hp', 'ch', 'mode', 'tgt')
X, Y, Z, VX, VY, VZ, ANG, KIND, MOT, FR, ST, PST, PAD, PRS, HP, CH = range(16)
NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']


def load(logdir=LOGDIR):
    if os.path.exists(CACHE) and logdir == LOGDIR:
        return pickle.load(open(CACHE, 'rb'))
    res = {}
    for p in sorted(glob.glob(logdir + 'cpu_*.jsonl')):
        rows = []
        for l in open(p):
            r = json.loads(l)
            rows.append((r['f'], r['phase'], r['clock'], [tuple(q[k] for k in K) for q in r['p']]))
        res[os.path.basename(p)[:-6]] = dict(meta=json.load(open(p[:-6] + '.meta.json')), rows=rows)
    return res


def km(q): return (q[KIND], q[MOT])


def chains(C, first, members):
    """(log, pi, f0, f1): contiguous runs whose first motion is FIRST and that stay inside MEMBERS."""
    for name, d in C.items():
        rows = d['rows']
        n = len(rows)
        for pi in (0, 1):
            f = 1
            while f < n:
                if km(rows[f][3][pi]) == first and km(rows[f - 1][3][pi]) != first:
                    g = f
                    while g < n and km(rows[g][3][pi]) in members: g += 1
                    yield name, pi, f, g
                    f = g
                else:
                    f += 1


def seg_len(rows, pi, f, m):
    g = f
    while g < len(rows) and km(rows[g][3][pi]) == m: g += 1
    return g - f


def heading(a, b):
    """u16 heading from a to b (0 = +z, 0x4000 = +x), as 0x0C09DC1C."""
    return int(round(math.degrees(math.atan2(b[X] - a[X], b[Z] - a[Z])) / 360 * 65536)) & 0xFFFF


def hdist(a, b): return math.hypot(b[X] - a[X], b[Z] - a[Z])


def angdiff(a, b):
    d = (a - b) & 0xFFFF
    return d - 0x10000 if d >= 0x8000 else d


def opp_view(rows, f, pi):
    """the opponent as player PI sees it during its update on row F (P1 sees P2's previous row, P2 sees P1's current)."""
    return rows[f - 1][3][1 - pi] if pi == 0 else rows[f][3][0]


class Score:
    def __init__(self): self.ok = Counter(); self.n = Counter(); self.bad = defaultdict(list)

    def add(self, key, good, where=None):
        self.n[key] += 1
        if good: self.ok[key] += 1
        elif where is not None and len(self.bad[key]) < 4: self.bad[key].append(where)

    def table(self):
        out = []
        for k in self.n:
            out.append((k, self.ok[k], self.n[k], self.bad[k]))
        return out


# ---------------------------------------------------------------- 1. object punch: vault k1/153 > k1/154, k1/78, k1/59
def check_vault(C, S):
    r = CODE['object_punch']['vault']
    spd = r['k1_154_speed_cm_f']
    for name, pi, f0, f1 in chains(C, (1, 153), {(1, 153), (1, 154)}):
        rows = C[name]['rows']
        L153 = seg_len(rows, pi, f0, (1, 153))
        hit = km(rows[f0 + L153][3][pi]) != (1, 154)
        S.add('vault: k1/153 lasts 10 f', hit or L153 == r['k1_153_frames'], (name, pi, f0, L153))
        # the init (row f0) fixes +0x30 = heading to the opponent + 0x8000 (0x0C063EAC)
        me = rows[f0][3][pi]
        h = (heading(me, rows[f0][3][1 - pi]) + 0x8000) & 0xFFFF   # both fighters' positions on the k1/153 row fit best (3572 vs 3476 game order)
        S.add('vault: no horizontal move in k1/153', all(abs(rows[k][3][pi][VX]) + abs(rows[k][3][pi][VZ]) < 0.01
                                                        for k in range(f0 + 1, f0 + L153)), (name, pi, f0))
        if hit: continue
        g = f0 + L153
        L154 = seg_len(rows, pi, g, (1, 154))
        end = km(rows[g + L154][3][pi]) if g + L154 < len(rows) else None
        S.add('vault: k1/154 lasts 49 f (or a hit)', L154 == r['k1_154_frames'] or (end and end[0] == 2), (name, pi, g, L154, end))
        ex = (spd * math.sin(h / 65536 * 2 * math.pi), spd * math.cos(h / 65536 * 2 * math.pi))
        for k in range(g + 1, g + L154):
            q = rows[k][3][pi]
            S.add('vault: k1/154 velocity 4.0816 cm/f away from the opponent (frames, 0.05 cm/f)',
                  math.hypot(q[VX] - ex[0], q[VZ] - ex[1]) < 0.05, (name, pi, k, q[VX], q[VZ], ex))
        if end:
            S.add('vault: ends in idle k0/0 (or a hit)', end == (0, 0) or end[0] == 2, (name, pi, g + L154, end))


def check_object_moves(C, S):
    r = CODE['object_punch']
    for m, key in (((1, 78), 'k1_78_frames'), ((1, 59), 'k1_59_frames'), ((1, 60), 'k1_60_frames'),
                   ((2, 219), 'k2_219_frames'), ((2, 226), 'k2_226_frames'), ((2, 225), None)):
        for name, pi, f0, f1 in chains(C, m, {m}):
            rows = C[name]['rows']
            L = f1 - f0
            nxt = km(rows[f1][3][pi]) if f1 < len(rows) else None
            if nxt is None: continue
            hit = nxt[0] == 2 and nxt[1] in (96, 112, 118, 120, 128, 171, 12, 0, 27, 15) or nxt[0] == 4
            lab = f'k{m[0]}/{m[1]}'
            if key:
                S.add(f'{lab}: {r[key]} f (or a hit)', hit or L == r[key], (name, pi, f0, L, nxt))
            if m in ((1, 78), (1, 59), (1, 60), (2, 219), (2, 226)):
                S.add(f'{lab}: no horizontal move after its first frame', all(
                    abs(rows[k][3][pi][VX]) + abs(rows[k][3][pi][VZ]) < 0.01 for k in range(f0 + 1, f1)), (name, pi, f0))
            if m == (2, 225):
                # air throw of the carried object (0x0C063CB2 kind 5 airborne): vx,vz = -sin/-cos(heading to opp) * 1.6?
                S.add('k2/225: ends in the landing k0/9 (or a hit)', hit or nxt == (0, 9), (name, pi, f0, nxt))


# ---------------------------------------------------------------- 2. poles
def check_pole(C, S):
    r = CODE['pole']
    for name, pi, f0, f1 in chains(C, (2, 211), {(2, 211), (2, 212), (1, 150), (1, 151), (1, 152)}):
        rows = C[name]['rows']
        meta = C[name]['meta']
        ch = rows[f0][3][pi][CH]
        prev = rows[f0 - 1][3][pi]
        pads = rows[f0][3][pi][PAD] | prev[PAD]
        S.add('pole catch: airborne (state 4/5/27 or a wall-kick flight) before k2/211', prev[ST] in (4, 5, 27), (name, pi, f0, prev[ST]))
        S.add('pole catch: the action press (punch+kick 0x600) on the catch frame', (rows[f0][3][pi][PAD] & 0x600) == 0x600,
              (name, pi, f0, hex(rows[f0][3][pi][PAD])))
        # k1/150 start
        g = f0
        while g < f1 and km(rows[g][3][pi]) in ((2, 211), (2, 212)): g += 1
        if g >= f1 or km(rows[g][3][pi]) != (1, 150): continue
        S.add('pole: k1/150 starts on the punch/kick press (0x600 bits)', (rows[g][3][pi][PAD] | rows[g - 1][3][pi][PAD]) & 0x600 != 0,
              (name, pi, g, hex(rows[g][3][pi][PAD])))
        L150 = seg_len(rows, pi, g, (1, 150))
        pole = rows[g + 1][3][pi]
        S.add('pole: k1/150 holds still on the pole axis', all(hdist(rows[k][3][pi], pole) < 0.2 and abs(rows[k][3][pi][Y] - pole[Y]) < 0.01
                                                           for k in range(g + 1, g + L150)), (name, pi, g))
        if km(rows[g + L150][3][pi]) != (1, 151):
            continue
        S.add('pole: k1/150 lasts 10 f (Ryoma / Wang-Tang 18 f)', L150 == (r['k1_150_frames_ryoma_wangtang'] if ch in (1, 2) else r['k1_150_frames']),
              (name, pi, g, L150, ch))
        s = g + L150          # k1/151 row: the solver ran during this row's update
        me = rows[s][3][pi]
        op = opp_view(rows, s, pi)
        # 0x0C494D1C = the fighters' horizontal distance from the rows before this frame's updates
        D = hdist(rows[s - 1][3][0], rows[s - 1][3][1])
        vy0, g_ = (r['vy0_galuda'], r['g_galuda']) if ch == 5 else (r['vy0_kraken'], r['g_kraken']) if ch == 8 else (r['vy0'], r['g'])
        Dc = D + (r['gunrock_extra_cm'] if ch == 4 else 0.0)
        if Dc < r['near_cm'] and vy0 > r['halve_above']: vy0 /= 2
        Dc = min(max(Dc, 1.0), r['max_cm'])
        t_up = -vy0 / g_
        H = (vy0 * t_up - g_ * t_up * t_up) / 2
        dy = abs(me[Y] - op[Y])
        T = t_up + math.sqrt((H + dy) * 2 / -g_)
        vh = Dc / T
        h = heading(me, op)
        q = rows[s + 1][3][pi]
        S.add('pole flight: launch vy0 = 35 (Galuda 45, Kraken 8), halved when the opponent is < 200 cm away (0.01)', abs(q[VY] - vy0) < 0.01,
              (name, pi, s, q[VY], vy0, round(D, 1)))
        got = math.hypot(q[VX], q[VZ])
        S.add('pole flight: horizontal speed = D / T (0x0C0641A0), within 2 %', abs(got - vh) <= 0.02 * vh + 0.05,
              (name, pi, s, round(got, 3), round(vh, 3), round(D, 1), round(dy, 1)))
        dirg = int(round(math.degrees(math.atan2(q[VX], q[VZ])) / 360 * 65536)) & 0xFFFF
        S.add('pole flight: aimed at the opponent (within 1 deg)', abs(angdiff(dirg, h)) < 182, (name, pi, s, dirg, h))
        L151 = seg_len(rows, pi, s, (1, 151))
        # hit-stop freezes the motion frame and zeroes the velocity: only frames whose motion advanced on both rows
        gr = [rows[k + 1][3][pi][VY] - rows[k][3][pi][VY] for k in range(s + 1, s + L151 - 1)
              if rows[k + 1][3][pi][FR] == rows[k][3][pi][FR] + 1 and rows[k][3][pi][FR] == rows[k - 1][3][pi][FR] + 1]
        for j, x in enumerate(gr[:-2]):   # the last rows meet the floor
            S.add('pole flight: gravity 3.5 cm/f^2 (Galuda 2.8, Kraken 0.75) (flight frames)', abs(x - g_) < 0.01, (name, pi, s + 1 + j, round(x, 2)))
        end = km(rows[s + L151][3][pi]) if s + L151 < len(rows) else None
        if end == (1, 152):
            L152 = seg_len(rows, pi, s + L151, (1, 152))
            nx = km(rows[s + L151 + L152][3][pi])
            S.add(f'pole: k1/152 landing then idle (lengths {r["k1_152_note"]})', nx[0] != 1, (name, pi, s + L151, L152, nx))


# ---------------------------------------------------------------- 3. wall kick
def check_wallkick(C, S):
    r = CODE['wall_kick']
    tab = r['jump_table']
    for name, pi, f0, f1 in chains(C, (2, 206), {(2, 206), (0, 13)}):
        rows = C[name]['rows']
        meta = C[name]['meta']
        ch = rows[f0][3][pi][CH]
        prev = rows[f0 - 1][3][pi]
        q0 = rows[f0][3][pi]
        S.add('wall kick: from the air (state 4/5) or a reaction flight', prev[ST] in (4, 5, 27), (name, pi, f0, prev[ST]))
        S.add('wall kick: jump pressed + stick held on the kick frame', (q0[PAD] & 0x4) and (q0[PAD] & 0xF0), (name, pi, f0, hex(q0[PAD])))
        L = seg_len(rows, pi, f0, (2, 206))
        nx = km(rows[f0 + L][3][pi])
        S.add('wall kick: frozen (velocity 0) through k2/206', all(abs(rows[k][3][pi][VX]) + abs(rows[k][3][pi][VY]) + abs(rows[k][3][pi][VZ]) < 0.01
                                                             for k in range(f0 + 1, f0 + L)), (name, pi, f0))
        if nx == (0, 13):
            S.add('wall kick: k2/206 lasts 8 f before the kick-off k0/13', L == r['k2_206_frames'], (name, pi, f0, L))
            k = f0 + L + 1
            q = rows[k][3][pi]
            S.add('wall kick: kick-off vy = 25 cm/f (table +40)', abs(q[VY] - tab[NAMES[ch]]['vy']) < 0.01, (name, pi, k, q[VY]))
            L13 = seg_len(rows, pi, f0 + L, (0, 13))
            gr = [rows[j + 1][3][pi][VY] - rows[j][3][pi][VY] for j in range(k, min(k + 6, f0 + L + L13 - 1))]
            S.add('wall kick: gravity = the fighter table +24 (Falcon 2.0, Rouge 1.3 ...)', all(abs(x - tab[NAMES[ch]]['g']) < 0.01 for x in gr),
                  (name, pi, k, gr[:3], tab[NAMES[ch]]['g']))
            if not (q[PAD] & 0xF0):
                S.add('wall kick: no stick -> 2.0 cm/f straight off the wall (table +44)', abs(math.hypot(q[VX], q[VZ]) - tab[NAMES[ch]]['h']) < 0.02,
                      (name, pi, k, math.hypot(q[VX], q[VZ])))
        elif nx[0] == 1:
            S.add('wall kick: punch/kick during k2/206 -> air attack (state 10 kind 1)', rows[f0 + L][3][pi][ST] == 10, (name, pi, f0 + L, nx))


# ---------------------------------------------------------------- 4. ledges (state 14) and run-offs
def check_fall(C, S):
    for name, d in C.items():
        rows = d['rows']
        for pi in (0, 1):
            for f in range(1, len(rows) - 2):
                q, p = rows[f][3][pi], rows[f - 1][3][pi]
                if q[ST] == 14 and p[ST] != 14:
                    S.add('fall (state 14): entered from idle / stop (state 0/32/24) or a carry idle', p[ST] in (0, 1, 32, 24), (name, pi, f, p[ST]))
                    S.add('fall (state 14): motion k0/6 (carrying: k2/223)', km(q) in ((0, 6), (2, 223)), (name, pi, f, km(q)))
                    g = f + 1
                    ok = True
                    while g < len(rows) and rows[g][3][pi][ST] == 14:
                        a = rows[g][3][pi]
                        if abs(a[VX]) + abs(a[VZ]) > 0.01 or abs(a[VY] - rows[g - 1][3][pi][VY] + 2.0) > 0.01 and g > f + 1: ok = False
                        g += 1
                    S.add('fall (state 14): straight down, gravity 2 cm/f^2 from vy 0', ok, (name, pi, f))
                    S.add('fall (state 14): ends in the landing state 6', g < len(rows) and rows[g][3][pi][ST] in (6, 29, 27), (name, pi, g))
                if q[ST] == 31 and p[ST] == 31 and q[VY] < -0.5 and p[VY] > -0.5 and p[Y] > q[Y]:
                    # a runner whose floor ended: still state 31, falling (no edge stop)
                    S.add('run-off: a runner leaves a raised floor still running (state 31, falling)', True)


def score(logdir=LOGDIR):
    C = load(logdir)
    S = Score()
    for fn in (check_vault, check_object_moves, check_pole, check_wallkick, check_fall):
        fn(C, S)
    rows = S.table()
    for k, ok, n, bad in rows:
        print(f'{ok:5d}/{n:<5d} {100 * ok / max(1, n):5.1f}%  {k}')
        for b in bad[:2]:
            print('            e.g.', b)
    return rows


def show(rule, n=3):
    C = load()
    first = {'vault': ((1, 153), {(1, 153), (1, 154)}), 'k78': ((1, 78), {(1, 78)}),
             'pole': ((2, 211), {(2, 211), (2, 212), (1, 150), (1, 151), (1, 152)}),
             'wallkick': ((2, 206), {(2, 206), (0, 13)})}[rule]
    for i, (name, pi, f0, f1) in enumerate(chains(C, *first)):
        if i >= n: break
        rows = C[name]['rows']
        print(name, 'p%d' % (pi + 1), f0)
        for k in range(f0 - 2, min(f1 + 2, len(rows))):
            q, o = rows[k][3][pi], rows[k][3][1 - pi]
            print(f'  {k - f0:4d} k{q[KIND]}/{q[MOT]:<3d} fr{q[FR]:<3d} st{q[ST]:<3d} pos {q[X]:8.1f} {q[Y]:7.1f} {q[Z]:8.1f} '
                  f'v {q[VX]:7.2f} {q[VY]:7.2f} {q[VZ]:7.2f} to-opp {heading(q, o) * 360 / 65536:6.1f} d {hdist(q, o):6.1f} pad {q[PAD]:x}')


def objlog(binf, metaf):
    """per-frame object records of an fx-obj object log -> printed episodes of each object's +0x30D sub-state."""
    import struct
    sys.path.insert(0, HERE)
    import reflog as RL
    meta = json.load(open(metaf))
    raw = open(binf, 'rb').read()
    fs = meta['fsize']
    base = RL.frame_size()
    px = sum(n for _, n in meta['px'])
    objs = meta['objs']
    nfr = len(raw) // fs
    print(nfr, 'frames,', len(objs), 'objects')
    last = {}
    for f in range(nfr):
        fr = raw[f * fs:(f + 1) * fs]
        pos = base + 2 * px
        for a in objs:
            head = fr[pos:pos + 8]; xyz = struct.unpack('<3f', fr[pos + 8:pos + 20]); tail = fr[pos + 20:pos + 28]; pos += 28
            st = (head[2], head[3], head[4], tail[0], tail[1])
            if last.get(a) != st:
                print(f'f{f:5d} {a} type {head[2]} owner {head[3]} kind {head[4]} 30c {tail[0]} 30d {tail[1]} pos ({xyz[0]:.0f},{xyz[1]:.0f},{xyz[2]:.0f})')
                last[a] = st


def objrows(binf, metaf):
    """fx-obj object log -> (players[f][2] dicts incl. +0x30 heading 'h30', objects[f][n] dicts, object addresses)."""
    import struct
    sys.path.insert(0, HERE)
    import reflog as RL
    meta = json.load(open(metaf))
    raw = open(binf, 'rb').read()
    fs, base = meta['fsize'], RL.frame_size()
    P, O = [], []
    for f in range(len(raw) // fs):
        fr = raw[f * fs:(f + 1) * fs]
        pos, ps = 0, []
        for _ in range(2):
            d = {}
            for o, n in RL.PFIELDS: d[o] = fr[pos:pos + n]; pos += n
            ps.append(RL._player(d))
        pos = base
        for i in range(2):
            ps[i]['h30'] = struct.unpack('<I', fr[pos + 4:pos + 8])[0] & 0xFFFF; pos += 32
        os_ = []
        for a in meta['objs']:
            hd = fr[pos:pos + 8]; xyz = struct.unpack('<3f', fr[pos + 8:pos + 20]); tl = fr[pos + 20:pos + 28]; pos += 28
            os_.append(dict(t=hd[2], own=hd[3], k=hd[4], x=xyz, sub=tl[1]))
        P.append(ps); O.append(os_)
    return P, O, meta['objs']


def objscore(binf, metaf):
    """section 6b rules on an object log: release frame, level / aimed flight, respawn timing."""
    P, O, objs = objrows(binf, metaf)
    meta = json.load(open(metaf))
    who = (meta['p1'], meta['p2'])
    spd = CODE['object_throws']['speed_table']
    b7 = spd['byte7_by_prop']
    props = {}
    for st in CODE.get('stage_throwables', {}).get('stg00', {}).get('throwables', []):
        props[tuple(st['home'])] = st['prop']
    S = Score()
    N = len(P)
    K1 = [i for i, o in enumerate(O[0]) if o['t'] == 2 and o['k'] == 1]
    hd = lambda a, b: int(round(math.degrees(math.atan2(b[0] - a[0], b[2] - a[2])) / 360 * 65536)) & 0xFFFF
    for i in K1:
        for f in range(1, N - 3):
            a, b = O[f - 1][i], O[f][i]
            if b['sub'] == a['sub']: continue
            own = b['own']
            if b['sub'] in (10, 11, 8) and own < 2:
                me, op = P[f][own], P[f][1 - own]
                mo = (me['kind'], me['mot'], me['fr'])
                exp = {10: (1, 78, 8), 11: (1, 154, 6), 8: (2, 225, 15)}[b['sub']]
                S.add(f'object: sub {b["sub"]} starts on k{exp[0]}/{exp[1]} frame {exp[2]} (k1/60 for a floor carry throw)',
                      mo == exp or (b['sub'] == 8 and mo[:2] == (1, 60)), (f, objs[i], mo))
                x0, x1 = O[f + 1][i]['x'], O[f + 2][i]['x']
                v = [x1[k] - x0[k] for k in range(3)]
                sp = math.sqrt(sum(c * c for c in v))
                if sp < 0.5: continue          # hit on its first frame
                prop = props.get(tuple(round(c) for c in O[0][i]['x']))
                if prop is not None:
                    col = (0 if b['sub'] == 8 else 2) + (1 if b7[str(prop)] else 0)
                    want = spd['per_fighter'][who[own]][col]
                    S.add('object speed = throw-speed table 0x0C33C05C[thrower][kind, property byte 7]', abs(sp - want) < 0.05,
                          (f, objs[i], who[own], prop, round(sp, 2), want))
                if b['sub'] in (10, 11):
                    S.add('object fling (k1/78, k1/154): level flight (vy 0)', abs(v[1]) < 0.01, (f, objs[i], v))
                    S.add('object fling: speed 15 / 20 / 25 / 30 cm/f (a multiple of 5)', abs(sp / 5 - round(sp / 5)) < 0.01, (f, objs[i], sp))
                    want = me['h30'] if b['sub'] == 10 else (me['h30'] + 0x8000) & 0xFFFF
                    dirv = int(round(math.degrees(math.atan2(v[0], v[2])) / 360 * 65536)) & 0xFFFF
                    S.add('object fling: along the thrower +0x30 (k1/154: +0x30 + 180 deg), within 1 deg', abs(angdiff(dirv, want)) < 182,
                          (f, objs[i], dirv, want))
                else:
                    tgt = (op['x'], op['y'] + 100, op['z'])
                    dirv = int(round(math.degrees(math.atan2(v[0], v[2])) / 360 * 65536)) & 0xFFFF
                    S.add('carry throw: aimed at the opponent horizontally (within 2 deg)', abs(angdiff(dirv, hd(x0, tgt))) < 364,
                          (f, objs[i], dirv, hd(x0, tgt)))
                    S.add('carry throw: speed a multiple of 5 cm/f', abs(sp / 5 - round(sp / 5)) < 0.01, (f, objs[i], sp))
            if b['sub'] == 3:
                g = f
                while g < N and O[g][i]['sub'] == 3: g += 1
                if g < N and O[g][i]['sub'] == 0:
                    L = g - f
                    S.add('respawn: 991 f (900 hidden + 90 blink + 1), longer only by game freezes', L == 991 or L in (1031, 1121, 1161),
                          (f, objs[i], L))
                    S.add('respawn: back at its home spot', math.dist(O[g][i]['x'], O[0][i]['x']) < 1, (f, objs[i]))
    for k, ok, n, bad in S.table():
        print(f'{ok:5d}/{n:<5d} {100 * ok / max(1, n):5.1f}%  {k}')
        for e in bad[:2]: print('            e.g.', e)


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] == 'score': score(a[1] if len(a) > 1 else LOGDIR)
    elif a[0] == 'show': show(a[1], int(a[2]) if len(a) > 2 else 3)
    elif a[0] == 'objlog': objlog(a[1], a[2])
    elif a[0] == 'objscore': objscore(a[1], a[2])
    else: print(__doc__)
