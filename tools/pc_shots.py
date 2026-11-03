#!/usr/bin/env python3
"""fx-shot: the Power Drive / Fusion shots (effect / projectile objects, type 1 in the object pool) of the ORIGINAL.
  pc_shots.py tapes                 -> game/tests/tapes/shot_<fighter>.tape (PC section of moves_<f>: P2 240 cm ahead,
                                       then the same with P2 farther and to the side, then Fusion A+Y)
  pc_shots.py log INST FIGHTER...   Flycast (fcinst INST): boot + play shot_<f> with the object pool (64 slots), the
                                    victims' object-hit fields (+0xF8 record, +0x71BD hit id) and the whole pool
                                    (0x0C7D0980, 64 x 0x31C) dumped every frame after each Drive / Fusion press
                                    -> dumps/fidelity/shots/o_shot_<f>.{jsonl,obj.jsonl,hit.jsonl} + pool/<f>/NNNNN.bin
Object pool slot (0x31C bytes): +2 type (1 = shot / effect), +3 owner (0 P1), +4 kind, +0x1C target player,
+0x20 x,y,z, +0x100 hit id (0x0C08DEEC: victim +0x71BD = it, +0xF8 = 0x0C338A98[obj +4 char] + id * 20)."""
import json, os, struct, sys, time
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
R = './'
sys.path.insert(0, R + 'tools')
os.environ.setdefault('COV_SLOTS', '64')
import tapes
D = R + 'dumps/fidelity/shots/'
FIGHTERS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas']
POOL, STRIDE, NSLOT = 0x0C7D0980, 0x31C, 64
P1, P2 = 0x0C7E40C4, 0x0C7EB394
XSEGS = [(P1 + 0xF8, 4), (P1 + 0x71BC, 4), (P2 + 0xF8, 4), (P2 + 0x71BC, 4)]
# the homing target (Ryoma's Fusion X handler 0x0C0B8F9A): the player's joint matrix at +0x300 (+0xDC0 in PC form),
# its translation row +0x330 (SHOT_JOINT=1 logs both forms of both players -> o_shot_<f>.joint.jsonl)
JSEGS = [(b + 0x330 + o, 12) for b in (P1, P2) for o in (0, 0xDC0)] if os.environ.get('SHOT_JOINT') else []
# the draw nodes the shots point at (+0x2E0 / +0x2E4: 0xA4-byte nodes, matrix + part pointer into the fighter's
# EFn0.MDL); SHOT_NODES=1 logs that node region every frame -> o_shot_<f><SHOT_TAG>.nodes.bin (shots' look, w8).
# The region ends at 0x0C374000; Valgas' / Gunrock's busy Fusions reach down to 0x0C369BB8 (SHOT_NODES=48: 48 KB)
NSEGS = [(0x0C374000 - int(os.environ['SHOT_NODES']) * 1024 if int(os.environ['SHOT_NODES']) > 1 else 0x0C36C000,
          int(os.environ['SHOT_NODES']) * 1024 if int(os.environ['SHOT_NODES']) > 1 else 0x8000)] if os.environ.get('SHOT_NODES') else []
TAG = os.environ.get('SHOT_TAG', '')
PICS = set(os.environ.get('SHOT_PICS', '').split(','))
CAPS = {'X': 110, 'Y': 160, 'AX': 110, 'AY': 160, 'FX': 420, 'FY': 420}


def tape_src_v1(f):
    """v1 (first log run, archived): the moves_<f> PC part as it is, then with P2 farther / to the side, Fusion A+Y."""
    src = open(REPO + f'game/tests/tapes/moves_{f}.tape').read().splitlines()
    head = src[0]
    i = max(k for k, l in enumerate(src) if l.startswith('@gems')) - 1   # the last @gems = the Fusion A+Y part
    j = min(k for k, l in enumerate(src) if l.startswith('@gems')) - 2   # the first = the PC part
    pc = src[j:i - 1]
    fy = src[i - 1:]
    p1 = [float(v) for v in pc[0].split()[2:5]]; p2 = [float(v) for v in pc[1].split()[2:5]]
    far = [p2[0] + (p2[0] - p1[0]) * 0.75, p2[1], p2[2] + 150]
    pc_b = [pc[0], f'@place 2 {far[0]:.0f} {far[1]:.0f} {far[2]:.0f} 49152'] + pc[2:]
    out = [head, '# fx-shot: Drive / Fusion shots (tools/pc_shots.py). A = moves_ PC part, B = P2 farther + to the side,',
           '# C = Fusion A+Y (moves_ last part); both at full health in every part (no KO)', '10']
    for l in pc + pc_b + fy:
        out.append(l)
        if l.startswith('@gems'): out += ['@hp 1 240', '@hp 2 240']
    return '\n'.join(out) + '\n'


def tape_src(f):
    """shot_<f>: the moves_<f> Power Change presses, each from a fresh placement (P1 / P2 as the moves_ PC part, both at
    full health): part A with P2 240 cm ahead (Falcon: Ryoma's stage, as moves_falcon), part B with P2 farther and to
    the side, part C = 3 gems again + Fusion A+Y."""
    src = open(REPO + f'game/tests/tapes/moves_{f}.tape').read().splitlines()
    head = src[0]
    j = min(k for k, l in enumerate(src) if l.startswith('@gems'))
    p1l, p2l = src[j - 2], src[j - 1]
    p1 = [float(v) for v in p1l.split()[2:5]]; p2 = [float(v) for v in p2l.split()[2:5]]
    far = [p2[0] + (p2[0] - p1[0]) * 0.75, p2[1], p2[2] + 150]
    p2b = f'@place 2 {far[0]:.0f} {far[1]:.0f} {far[2]:.0f} 49152'
    presses_ = [('X', ['tap 1 p1=X', '150']), ('Y', ['tap 1 p1=Y', '200']), ('AX', ['3 p1=A', '8', '4 p1=X', '150']),
                ('AY', ['3 p1=A', '8', '4 p1=Y', '200']), ('FX', ['6 p1=A+X', '450'])]
    out = [head, '# fx-shot: every Power Drive / Fusion of moves_ from a fresh placement (tools/pc_shots.py tapes).',
           '# A = P2 240 cm ahead, B = P2 farther + to the side, C = Fusion A+Y; full health before every press', '10']
    for part, q2 in (('A', p2l), ('B', p2b)):
        out += [f'# part {part}', p1l, q2, '@gems 1 3', '@hp 1 240', '@hp 2 240', '260']
        for nm, ln in presses_:
            out += [f'# {nm}', p1l, q2, '@hp 2 240', '2'] + ln
    out += ['# part C', p1l, p2l, '@gems 1 3', '@hp 1 240', '@hp 2 240', '260', p1l, p2l, '@hp 2 240', '2', '6 p1=A+Y', '600']
    return '\n'.join(out) + '\n'


def write_tapes():
    for f in FIGHTERS:
        open(REPO + f'game/tests/tapes/shot_{f}.tape', 'w').write(tape_src(f))
        print('shot_' + f, len(tapes.parse(tape_src(f))), 'frames')


def presses(rows):
    """[(row, name)] Drive / Fusion presses of a parsed tape (X/Y on the ground, AX/AY after a jump, FX/FY = A+X/A+Y)."""
    out, prev, air = [], 0, -99
    for k, (a, b, c) in enumerate(rows):
        if a and not prev:
            if a == tapes.mask('A'): air = k
            elif a == tapes.mask('A+X'): out.append((k, 'FX'))
            elif a == tapes.mask('A+Y'): out.append((k, 'FY'))
            elif a in (tapes.mask('X'), tapes.mask('Y')):
                nm = 'X' if a == tapes.mask('X') else 'Y'
                out.append((k, ('A' + nm) if k - air < 20 else nm))
        prev = a
    return out


def build_txt(f, out):
    """The Flycast tape file with a whole-pool `cap` on every press row."""
    rows = tapes.parse(tape_src(f))
    pr = dict(presses(rows))
    with open(out, 'w') as fo:
        for k, (a, b, c) in enumerate(rows):
            cmds = list(c)
            if k in pr: cmds.append(f'cap {f}_{k}_{pr[k]} 0x{POOL:08X} 0x{STRIDE * NSLOT:X} {CAPS[pr[k]]}')
            if str(k) in PICS: cmds.append(f'shot {f}{TAG}_{k:05d}.png')   # SHOT_PICS=row,row: the disc's own frame there
            for c0 in c:   # `place` writes +0x7248 only; the model heading the moves use is the pool object's +0x30
                w = c0.split()
                if w[0] == 'place': cmds.append(f'poke16 0x{POOL + (int(w[1]) - 1) * STRIDE + 0x30:08X} {int(w[5])}')
            fo.write(f'{a:x} {b:x}' + ''.join(' ; ' + x for x in cmds) + '\n')
    return rows, pr


def play(fi, f):
    import covlog, reflog, ladder
    os.makedirs(D + 'pool/' + f + TAG, exist_ok=True)
    txt = D + f'shot_{f}.txt'
    rows, pr = build_txt(f, txt)
    name = f'o_shot_{f}{TAG}'
    segs = covlog.segs() + ',' + ','.join(f'0x{a:08X}:{n}' for a, n in XSEGS + JSEGS + NSEGS)
    lines = [f'freeze8 0x{reflog.P2 + 0x71ED:08X} 0', f'freeze8 0x{reflog.P1 + 0x71ED:08X} 0',
             'until8 0x0C7F302C 3 6000', 'poke32 0x0C346A50 1', f'tapelog {name} {segs}', f'tape {txt}',
             f'shot {name}_end.png']
    fi.fc([f'dump {name}_ram.bin 0x0C000000 0x1000000'], 60)
    fi.wait_idle(60)
    opp, stg = ladder.who(fi.root + f'{name}_ram.bin')
    os.replace(fi.root + f'{name}_ram.bin', D + f'{name}_ready_ram.bin')
    t0 = time.time()
    fi.fc(lines, 60)
    fi.wait_idle(len(rows) / 60 * 12 + 600)
    time.sleep(2)
    raw = open(fi.root + f'cap/{name}.bin', 'rb').read()
    fs0 = reflog.frame_size() + sum(n for _, n in covlog.OSEGS)
    xs = sum(n for _, n in XSEGS)
    js = sum(n for _, n in JSEGS)
    fs = fs0 + xs + js + sum(n for _, n in NSEGS)
    std, hits, joints, nodes = bytearray(), [], [], bytearray()
    for k in range(len(raw) // fs):
        fr = raw[k * fs:(k + 1) * fs]
        std += fr[:fs0]
        x = fr[fs0:]
        hits.append([[struct.unpack('<I', x[0:4])[0], x[5]], [struct.unpack('<I', x[8:12])[0], x[13]]])
        if JSEGS: joints.append([[round(v, 1) for v in struct.unpack('<3f', x[xs + 12 * i:xs + 12 * i + 12])] for i in range(4)])
        if NSEGS: nodes += x[xs + js:]
    open(D + name + '.cbin', 'wb').write(std)
    if NSEGS: open(D + name + '.nodes.bin', 'wb').write(nodes)
    os.replace(fi.root + f'cap/{name}.bin', D + name + '.raw.bin')
    # covlog.split on the standard part
    tmp = D + name + '.std.bin'
    open(tmp, 'wb').write(std)
    s2, objs = covlog.split(tmp)
    open(D + name + '.bin', 'wb').write(s2)
    rws = reflog.decode(D + name + '.bin')
    reflog.write_jsonl(rws, D + name + '.jsonl')
    with open(D + name + '.obj.jsonl', 'w') as fo:
        for r in objs: fo.write(json.dumps(r, separators=(',', ':')) + '\n')
    with open(D + name + '.hit.jsonl', 'w') as fo:
        for r in hits: fo.write(json.dumps(r) + '\n')
    if JSEGS:
        with open(D + name + '.joint.jsonl', 'w') as fo:
            for r in joints: fo.write(json.dumps(r) + '\n')
    for k, nm in pr.items():
        src = fi.root + f'cap/{f}_{k}_{nm}'
        dst = D + f'pool/{f}{TAG}/{k}_{nm}'
        if os.path.isdir(src):
            if os.path.isdir(dst):   # a re-log: the old dump goes to scratch (never deleted here)
                import shutil
                shutil.move(dst, os.environ.get('TMPDIR', '/tmp').rstrip('/') + f'/old_pool_{f}{TAG}_{k}_{nm}_{int(time.time())}')
            os.replace(src, dst)
    json.dump({'p2': opp, 'stage': stg.lower(), 'frames': len(rws), 'presses': pr, 'secs': round(time.time() - t0)},
              open(D + name + '.meta.json', 'w'))
    if os.path.exists(fi.root + f'shots/{name}_end.png'): os.replace(fi.root + f'shots/{name}_end.png', D + name + '_end.png')
    return rws


def log(inst, names):
    from fcinst import Inst
    import reflog
    fi = Inst(inst)
    os.makedirs(D, exist_ok=True)
    try:
        for f in names:
            m = tapes.meta(REPO + f'game/tests/tapes/shot_{f}.tape')
            reflog.boot(fi, m['p1'], m['p2'])
            rws = play(fi, f)
            print(f'shot {f}: {len(rws)} frames', flush=True)
    finally:
        fi.stop()


# ---------------------------------------------------------------------------------------------------------------------
# build: the table (game/assets/fidelity/pc_shots.json) from the shot logs
SPH = [(0x148 + 16 * i) for i in range(5)]   # the object's attack spheres (world x, y, z, r cm; r 0 = off)
OUT = REPO + 'game/assets/fidelity/pc_shots.json'


def _jl(p):
    return [json.loads(l) for l in open(p)]


def _frame(p):
    import math
    a = p['ang'] / 65536 * 2 * math.pi
    return (p['x'], p['y'], p['z']), (math.sin(a), math.cos(a)), p['ang']


def _rel(x, y, z, org, fw):
    dx, dy, dz = x - org[0], y - org[1], z - org[2]
    return [round(dx * fw[0] + dz * fw[1], 1), round(dx * fw[1] - dz * fw[0], 1), round(dy, 1)]


def _pool(f, k, nm):
    d = D + f'pool/{f}/{k}_{nm}/'
    if not os.path.isdir(d): return []
    out = []
    for fn in sorted(os.listdir(d)):
        B = open(d + fn, 'rb').read()
        row = {}
        for s in range(NSLOT):
            o = s * STRIDE
            h = B[o:o + 8]
            if h[2] != 1 or h[3] != 0 or h[:4] == b'\0\0\0\0': continue
            x, y, z = struct.unpack('<3f', B[o + 0x20:o + 0x2C])
            sp = []
            for a in SPH:
                sx, sy, sz, r = struct.unpack('<4f', B[o + a:o + a + 16])
                if 0.5 < r < 400: sp.append((sx, sy, sz, r))
            row[s] = dict(kind=h[4], fn=struct.unpack('<I', B[o + 0x10:o + 0x14])[0], xyz=(x, y, z),
                          ang=struct.unpack('<H', B[o + 0x30:o + 0x32])[0], hid=B[o + 0x100], act=B[o + 0x101],
                          nhit=struct.unpack('<I', B[o + 0x144:o + 0x148])[0], sp=sp)
        row['ang'] = struct.unpack('<H', B[0x30:0x32])[0] if B[2] == 5 and B[3] == 0 else None   # P1's model heading
        out.append(row)
    return out


def drives(f):
    """Every press of a shot log: name, t0 (the attack's first row), the attacker's frame, its shots, P2's hits."""
    pre = D + f'o_shot_{f}'
    rows = _jl(pre + '.jsonl'); hits = _jl(pre + '.hit.jsonl')
    meta = json.load(open(pre + '.meta.json'))
    pr = sorted((int(k), v) for k, v in meta['presses'].items())
    res = []
    for j, (k, nm) in enumerate(pr):
        end = pr[j + 1][0] if j + 1 < len(pr) else len(rows)
        t0 = next((r for r in range(k, min(k + 12, end)) if rows[r]['p'][0]['st'] in (10, 11)
                   and rows[r - 1]['p'][0]['st'] not in (10, 11)), None)
        if t0 is None: continue
        org, fw, ang = _frame(rows[t0]['p'][0])
        v = rows[t0]['p'][1]
        victim = _rel(v['x'], v['y'], v['z'], org, fw)
        pool = _pool(f, k, nm)
        shots, cur = [], {}
        for i, prow in enumerate(pool):
            r = k + 1 + i
            hd = prow.pop('ang')
            for s, o in prow.items():
                c = cur.get(s)
                if c is None or c['fn'] != o['fn'] or c['kind'] != o['kind'] or c['last'] != r - 1:
                    # the shot's frame: the attacker's feet at the move's first row, his model heading (pool +0x30)
                    # on the shot's first frame (the move turns him toward the opponent first)
                    import math
                    a = (hd if hd is not None else ang) / 65536 * 2 * math.pi
                    c = dict(slot=s, fn=o['fn'], kind=o['kind'], t=r - t0, hid=o['hid'], rows=[], nhit=0, hit_rows=[],
                             fw=(math.sin(a), math.cos(a)), hd=hd if hd is not None else ang)
                    cur[s] = c; shots.append(c)
                fw = c['fw']; ang_s = c['hd']
                c['last'] = r
                if o['nhit'] > c['nhit']: c['hit_rows'].append(r - t0)
                c['nhit'] = max(c['nhit'], o['nhit'])
                c['rows'].append([_rel(*o['xyz'], org, fw), (o['ang'] - ang_s) & 0xFFFF, o['act'], o['nhit'],
                                  [_rel(sx, sy, sz, org, fw) + [round(rr, 1)] for sx, sy, sz, rr in o['sp']]])
        p2 = []
        for r in range(max(t0, 1), end):
            a, b = rows[r - 1]['p'][1]['hp'], rows[r]['p'][1]['hp']
            if b < a: p2.append([r - t0, a - b, hits[r][1][1]])
        res.append(dict(name=nm, press=k, t0=t0, org=org, ang=ang, p2=p2, shots=shots, cap=len(pool), victim=victim))
    return res


def _s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


def turns(f):
    """The heading rule of each move from the v1 logs' part B (shots/_v1: @place left the model heading stale, so the
    move's own turn shows): the attacker's pool +0x30 per row from the move's first row. -> {name: {row, snap, rate, n}}
    snap = on that row he faces the opponent; else n rows of `rate` (u16) toward him; n 0 = the move keeps the heading."""
    import math
    V1 = D + '_v1/'
    meta = json.load(open(V1 + f'o_shot_{f}.meta.json'))
    pr = sorted((int(k), v) for k, v in meta['presses'].items())
    out = {}
    for k, nm in pr:
        if nm in out and out[nm]['n'] or k < 1500 and nm not in ('AX', 'AY'): continue   # part B (+ C's Fusion Y)
        d = V1 + f'pool/{f}/{k}_{nm}/'
        if not os.path.isdir(d): continue
        hs, tg = [], []
        for fn in sorted(os.listdir(d))[:60]:
            B = open(d + fn, 'rb').read()
            hs.append(struct.unpack('<H', B[0x30:0x32])[0])
            p1 = struct.unpack('<3f', B[0x20:0x2C]); p2 = struct.unpack('<3f', B[STRIDE + 0x20:STRIDE + 0x2C])
            tg.append(int(round(math.atan2(p2[0] - p1[0], p2[2] - p1[2]) / (2 * math.pi) * 65536)) & 0xFFFF)
        dl = [_s16(hs[i] - hs[i - 1]) for i in range(2, len(hs))]   # dl[j] = change onto row j + 1 (file i = row i - 1)
        ch = [j for j, x in enumerate(dl) if x]
        if not ch:   # no turn: kept a stale heading (rule = keep) or already faced him (no evidence: the common rule)
            out[nm] = dict(row=0, snap=False, rate=0, n=0) if abs(_s16(hs[1] - tg[1])) > 64 else \
                dict(row=1, snap=True, rate=0, n=1, assumed=True)
            continue
        j0 = ch[0]
        if abs(_s16(hs[j0 + 2] - tg[j0 + 2])) <= 16 and (len(ch) == 1 or ch[1] > j0 + 1):
            out[nm] = dict(row=j0 + 1, snap=True, rate=0, n=1)
        else:
            run = [j for j in ch if j >= j0]
            n = 0
            while j0 + n < len(dl) and dl[j0 + n] and abs(dl[j0 + n]) == abs(dl[j0]): n += 1
            out[nm] = dict(row=j0 + 1, snap=False, rate=abs(dl[j0]), n=n)
    return out


def build(names):
    tab = json.load(open(OUT)) if os.path.exists(OUT) else {}
    tab['about'] = ('fx-shot (tools/pc_shots.py build): the Power Drive / Fusion shots of the original (type-1 pool objects '
                    'owned by the attacker), per fighter and move from the shot_<f> logs part A (P2 240 cm ahead). Per shot: t = '
                    'spawn row from the move\'s first row (k1/16 or the Fusion\'s first), hid = its attack record (victim +0x71BD), '
                    'rows = per frame [[fwd, side, up] cm of the object from the attacker\'s feet at row 0 in his heading '
                    'then, object heading - his (u16), active byte +0x101, hits landed +0x144, attack spheres [[fwd, side, '
                    'up, r] cm] (+0x148, r 0 = off)]. A shot hits each victim once (+0x144). turn = the move\'s heading rule '
                    '(pc_shots.py turns: row, snap = face the opponent on that row, else n rows of rate u16 toward him).')
    fs = tab.setdefault('fighters', {})
    for f in names:
        dv = drives(f)
        mv, nmax = {}, 0
        by = {}
        for d in dv: by.setdefault(d['name'], []).append(d)
        for nm, ds in by.items():
            a = ds[0]   # part A (the moves_ geometry); part B extends a shot the victim stopped early (same spawn row,
            # kind and start in the attacker's frame = a fixed path)
            sh = []
            for s in a['shots']:
                if not any(r[4] for r in s['rows']) or s['t'] < 0: continue   # t < 0: alive before the press (not its shot)
                rows = s['rows']
                for b in ds[1:]:
                    for o in b['shots']:
                        if (o['t'], o['kind']) == (s['t'], s['kind']) and len(o['rows']) > len(rows) and \
                                max(abs(o['rows'][0][0][i] - rows[0][0][i]) for i in range(3)) < 25 and not s['nhit']:
                            rows = rows + [[r[0], r[1], r[2], 0, r[4]] for r in o['rows'][len(rows):]]
                nmax = max(nmax, s['nhit'])
                sh.append(dict(t=s['t'], hid=s['hid'], kind=s['kind'], rows=[[r[0], r[1], r[4]] for r in rows]))
            mv[nm] = dict(shots=sh, p2=a['p2'], victim=a['victim'], n=len(a['shots']))
        try:
            for nm, tr in turns(f).items():
                mv.setdefault(nm, dict(shots=[], p2=[], victim=None, n=0))['turn'] = tr
        except (OSError, ValueError, KeyError) as e:
            print(f, 'no turn data', e)
        fs[f] = mv
        print(f, 'max hits per shot', nmax, {k: (len(v['shots']), len(v['p2'])) for k, v in mv.items()})
    json.dump(tab, open(OUT + '.tmp', 'w'), separators=(',', ':'))
    os.replace(OUT + '.tmp', OUT)   # atomic: Godot runs may be reading it


# ---------------------------------------------------------------------------------------------------------------------
# spins: the moves whose code turns the model round and round (w8). The disc turns the player pool object's +0x30 per
# row (the heading the joints and hit spheres are built from) while the body stays put: Falcon's Drive Y / air Y (4
# turns), Ayame's Drive Y / air Y (2), Jack's Fusion X (12+: +182 a row up to 6735 a row; his 4-sphere bar on joint 1
# sweeps the victim: 14 hits on the disc, none without it). -> game/assets/fidelity/pc_spin.json
SPIN_OUT = REPO + 'game/assets/fidelity/pc_spin.json'


def spins(names):
    out = {'about': 'pc_shots.py spins: per fighter / Power Change move whose model heading turns a full turn or more '
                    '(v2 shot logs part A, pool +0x30): row0 = first PC row (from the move\'s first row) the list starts '
                    'on, d = u16 heading change per row from there (rows 0-2 = the start turn, pc_shots turn: left out)',
           'fighters': {}}
    for f in names:
        for d in drives(f):
            if d['name'] in out['fighters'].get(f, {}): continue
            pdir = D + f'pool/{f}/{d["press"]}_{d["name"]}/'
            hs = [struct.unpack('<H', open(pdir + fn, 'rb').read()[0x30:0x32])[0] for fn in sorted(os.listdir(pdir))]
            # file i = log row press + 1 + i; PC row r = log row t0 + r -> file t0 + r - press - 1
            o = d['t0'] - d['press'] - 1
            dl = [_s16(hs[o + r] - hs[o + r - 1]) for r in range(3, len(hs) - o)]
            if abs(sum(dl)) < 65536: continue
            last = max(i for i, x in enumerate(dl) if x)
            out['fighters'].setdefault(f, {})[d['name']] = dict(row0=3, d=dl[:last + 1])
            print(f, d['name'], 'rows', last + 1, 'turns', round(sum(dl) / 65536, 2))
    json.dump(out, open(SPIN_OUT, 'w'), separators=(',', ':'))


# ---------------------------------------------------------------------------------------------------------------------
# check: replay the table on every logged Drive / Fusion and score spawn rows, paths and P2's hits
def _logged(f, src):
    """[(name, t0, org, heading u16, [(t, [xyz...])], [(t, dmg, hid)])] of one log (shot_<f> with its pool caps, or
    moves_<f> with the object log: heading = +0x7248 there)."""
    import math
    if src == 'shot':
        out = []
        for d in drives(f):
            sh = [(s['t'], [r[0] for r in s['rows']], s['hd']) for s in d['shots'] if any(r[4] for r in s['rows'])]
            out.append((d['name'], d['t0'], sh, d['p2'], 'shot'))
        return out
    pre = R + f'dumps/fidelity/o_moves_{f}'
    if not os.path.exists(pre + '.obj.jsonl'): return []
    rows = _jl(pre + '.jsonl'); objs = [{o[0]: o for o in json.loads(l)} for l in open(pre + '.obj.jsonl')]
    trs = tapes.parse(open(REPO + f'game/tests/tapes/moves_{f}.tape').read())
    pr = presses(trs[[k for k, r in enumerate(trs) if any(c.startswith('gems') for c in r[2])][0]:])
    off = [k for k, r in enumerate(trs) if any(c.startswith('gems') for c in r[2])][0]
    pr = [(k + off, nm) for k, nm in pr]
    out = []
    for j, (k, nm) in enumerate(pr):
        end = pr[j + 1][0] if j + 1 < len(pr) else min(len(rows), k + 450)
        t0 = next((r for r in range(k, min(k + 12, end)) if rows[r]['p'][0]['st'] in (10, 11)
                   and rows[r - 1]['p'][0]['st'] not in (10, 11)), None)
        if t0 is None: continue
        org, fw, ang = _frame(rows[t0]['p'][0])
        sh, cur = [], {}
        for r in range(t0, min(end, len(objs))):
            for sl, o in objs[r].items():
                if o[1] != 1 or o[2] != 0: continue
                c = cur.get(sl)
                if c is None or c['last'] != r - 1 or c['kind'] != o[3]:
                    c = dict(t=r - t0, kind=o[3], xyz=[], last=r); cur[sl] = c; sh.append(c)
                c['last'] = r; c['xyz'].append(_rel(*o[5:8], org, fw))
        p2 = [[r - t0, rows[r - 1]['p'][1]['hp'] - rows[r]['p'][1]['hp'], rows[r]['p'][1]['hid']] for r in range(t0 + 1, end)
              if rows[r]['p'][1]['hp'] < rows[r - 1]['p'][1]['hp']]
        out.append((nm, t0, [(c['t'], c['xyz'], ang) for c in sh], p2, 'moves'))
    return out


def check(names):
    import math
    tab = json.load(open(OUT))['fighters']
    tot = dict(n=0, spawn=0, err=[], dmg_log=0, dmg_tab=0)
    for f in names:
        for src in ('shot', 'moves'):
            for nm, t0, sh, p2, kind in _logged(f, src):
                mv = tab.get(f, {}).get(nm)
                if mv is None: continue
                want = mv['shots']
                used, ok, errs = set(), 0, []
                for w in want:
                    p0 = w['rows'][0][0]
                    best = None
                    for i, (t, xyz, hd) in enumerate(sh):
                        if i in used or t != w['t']: continue
                        # the logged path in the table's frame (shot logs: the heading on the shot's first frame)
                        e = max(abs(xyz[0][k] - p0[k]) for k in range(3))
                        if best is None or e < best[0]: best = (e, i)
                    if best is None: continue
                    used.add(best[1]); ok += 1
                    xyz = sh[best[1]][1]
                    n = min(len(xyz), len(w['rows']))
                    errs += [math.dist(xyz[j], w['rows'][j][0]) for j in range(n)]
                dl = sum(x[1] for x in p2); dt = sum(x[1] for x in mv['p2'])
                e = f'{sum(errs) / len(errs):.1f}/{max(errs):.1f}' if errs else '-'
                print(f'{f:9s} {kind:5s} {nm:2s} t0 {t0:5d} shots table {len(want):2d} logged {len(sh):2d} spawn-matched {ok:2d}  '
                      f'path err mean/max cm {e:>11s}  P2 dmg logged {dl:3d} (hits {len(p2):2d}) table-run {dt:3d}')
                tot['n'] += len(want); tot['spawn'] += ok; tot['err'] += errs
    if tot['n']:
        print(f"TOTAL shots {tot['n']} spawn-matched {tot['spawn']} ({100 * tot['spawn'] / tot['n']:.1f}%), path err mean "
              f"{sum(tot['err']) / max(1, len(tot['err'])):.1f} cm over {len(tot['err'])} shot-frames")


if __name__ == '__main__':
    if sys.argv[1] == 'tapes': write_tapes()
    elif sys.argv[1] == 'log': log(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == 'build': build(sys.argv[2:] or FIGHTERS)
    elif sys.argv[1] == 'check': check(sys.argv[2:] or FIGHTERS)
    elif sys.argv[1] == 'spins': spins(sys.argv[2:] or FIGHTERS)
