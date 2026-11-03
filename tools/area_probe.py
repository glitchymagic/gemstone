#!/usr/bin/env python3
"""The playable area the ORIGINAL enforces on a stage, measured in Flycast (fx-oom lane, docs/fx-oom.md).
Boot arcade P1 (Falcon; Ryoma on Londo) vs the stage owner on his home stage (tools/reflog.py boot), both fighters
human-driven and idle, gems / health / round timer frozen; then a probe tape: each job places a fighter (`place`, feet
x y z cm) and lets the game's own collision settle it for a window, then puts both back on their start points for 3
frames (a placed fighter keeps the fall speed it had; that stops it). Flood fill on a 50 cm lattice from the round's
start points: A = placed 30 cm over the start floor (14 frames), B = dropped from 7 m (40 frames, where A failed),
C = 17 cm higher where the game held the fighter at its placement height (Londo: inside some collision volumes it gets
no gravity and no push: no floor), then every lattice edge with a class change refined at 25 cm, then a radius
calibration (the same clean wall pushes with P2).
  area_probe.py STAGE INST cal|fill   redo only the radius calibration / the 25 cm fill pass of an earlier run
  area_probe.py STAGE INST [MAXN]     -> dumps/area/STAGE_probe.json (every sample: placed point, frame 1 / mid / last
                                         feet x y z, state, vertical speed)
INST = a tools/fcinst.py instance name. tools/stage_area.py turns the samples into game/assets/fidelity/STAGE_area.json."""

import json, math, os, struct, sys, time
sys.path.insert(0, './tools')
from fcinst import Inst
import reflog
P1, P2 = reflog.P1, reflog.P2
OUT = os.environ.get('AREA_OUT', './dumps/area/')   # lane runs: a scratch dir
PF = [(0x020, 12), (0x7264, 12), (0x7270, 12), (0x71B8, 4), (0x148, 12)]
OWNER = {'stg00': 'falcon', 'stg10': 'ryoma', 'stg20': 'wangtang', 'stg30': 'jack', 'stg40': 'gunrock',
         'stg50': 'galuda', 'stg60': 'ayame', 'stg70': 'rouge', 'stg80': 'kraken', 'stg90': 'valgas',
         'stga0': 'finalvalgas'}


def segs():
    return ','.join(f'0x{b + o:08X}:{n}' for b in (P1, P2) for o, n in PF)


FS = 2 * sum(n for _, n in PF)


def decode(path):
    raw = open(path, 'rb').read()
    rows = []
    for f in range(len(raw) // FS):
        fr = raw[f * FS:(f + 1) * FS]
        pos = 0; ps = []
        for _ in (P1, P2):
            d = {}
            for o, n in PF:
                d[o] = fr[pos:pos + n]; pos += n
            x, y, z = struct.unpack('<3f', d[0x20]); px, py, pz = struct.unpack('<3f', d[0x7264])
            vx, vy, vz = struct.unpack('<3f', d[0x7270]); hx, hy, hz = struct.unpack('<3f', d[0x148])
            ps.append(dict(x=x, y=y, z=z, px=px, py=py, pz=pz, vx=vx, vy=vy, vz=vz, st=d[0x71B8][2], pst=d[0x71B8][3],
                           hy=hy))
        rows.append(ps)
    return rows


def boot_boss(fi):
    """Final Valgas's arena (reflog.boot's direct poke of fight index 8 lands elsewhere): arcade as Falcon, fight 1 poked
    to ladder row 6 index 7 (Valgas), won with his health held at 0 while P1 mashes, so fight 2 is Final Valgas on STGA0;
    stops at his round's first free frame (his intro never sets state 22: wait on P1)."""
    import arcade
    fi.start()
    fi.fc(['wait 1200'], 120)
    fi.fc(arcade.start(0), 300)
    fi.wait_idle(200)
    fi.fc(['poke8 0x0C7F2E45 6', 'poke8 0x0C7F2E46 7'], 30)
    def p2_mdt():
        fi.fc(['dump p2mdt.bin 0x0C7C58A0 0x200'], 60); fi.wait_idle(60); time.sleep(0.5)
        import ladder
        b = open(fi.root + 'p2mdt.bin', 'rb').read()
        return next((k for k, v in ladder.MDTS.items() if b == v), '?')
    first = p2_mdt()
    hp0 = [f'poke16 0x{P2 + 0x71D4 + 2 * i:08X} 0' for i in range(3)]
    for _ in range(200):
        fi.fc((hp0 + ['press 1 X 4', 'wait 8', 'press 1 A 4', 'wait 8']) * 8, 120)
        fi.wait_idle(60)
        if p2_mdt() not in (first, '?'): break
    fi.fc(['press 1 A 4', 'wait 60'] * 4 + [f'until8 0x{P1 + 0x71BA:08X} 22 3000'], 300)
    fi.wait_idle(200)


def to_fight(fi, p1, stage):
    """Boot arcade P1 vs the stage owner on his home stage, both human, at the first frame P1 is free (state 0)."""
    if stage == 'stga0':
        boot_boss(fi)
        lines = [f'freeze8 0x{P1 + 0x71ED:08X} 0', f'freeze8 0x{P2 + 0x71ED:08X} 0', f'until8 0x{P1 + 0x71BA:08X} 0 4000', 'freeze8 0x0C7F304D 99', 'wait 60']
        fi.fc(lines, 200); fi.wait_idle(200)
        fi.fc(['dump who_ram.bin 0x0C000000 0x1000000'], 60); fi.wait_idle(60)
        import ladder
        opp, stg = ladder.who(fi.root + 'who_ram.bin')
        return opp, ('stga0' if opp == 'PA0' else stg.lower())   # his arena's MDL chunks also match STG60's
    reflog.boot(fi, p1, OWNER[stage])
    lines = [f'freeze8 0x{P2 + 0x71ED:08X} 0', f'freeze8 0x{P1 + 0x71ED:08X} 0',
             f'until8 0x{P2 + 0x71BA:08X} 22 4000', f'until8n 0x{P2 + 0x71BA:08X} 22 4000',
             f'until8 0x{P1 + 0x71BA:08X} 0 900', 'freeze8 0x0C7F304D 99', 'wait 30']
    fi.fc(lines, 200)
    fi.wait_idle(200)
    fi.fc(['dump who_ram.bin 0x0C000000 0x1000000'], 60)
    fi.wait_idle(60)
    import ladder
    opp, stg = ladder.who(fi.root + 'who_ram.bin')
    return opp, stg.lower()


def write_tape(rows, path):
    with open(path, 'w') as f:
        for a, b, c in rows: f.write(f'{a:x} {b:x}' + ''.join(' ; ' + x for x in c) + '\n')


def run_tape(fi, rows, name):
    tp = OUT + name + '.tape.txt'
    write_tape(rows, tp)
    fi.fc([f'tapelog {name} {segs()}', f'tape {tp}'], 2)
    fi.wait_idle(len(rows) / 60 * 8 + 120)
    time.sleep(1)
    src = fi.root + f'cap/{name}.bin'
    os.replace(src, OUT + name + '.bin')
    return decode(OUT + name + '.bin')


def freeze_lines():
    out = ['freeze8 0x0C7F304D 99']
    for b in (P1, P2):
        out += [f'freeze8 0x{b + 0x7230:08X} 0', f'freeze8 0x{b + 0x7231:08X} 0']
        out += [f'freeze16 0x{b + 0x71D4 + 2 * i:08X} 240' for i in range(3)]
    return out


def probe(fi, jobs, name, window, park=None):
    """jobs: list of (p1 point | None, p2 point | None), point = (x, y, z) cm. One window per job: both placed on its
    first row; None = parked at park[k] (re-placed each window). -> per job [(r1, r2)] with r = dict(first=frame-1
    state, last=last-frame state, mid=frame window//2)."""
    rows = []
    for a, b in jobs:
        c = []
        for k, p in ((1, a), (2, b)):
            q = p if p is not None else (park[k - 1] if park else None)
            if q is not None: c.append(f'place {k} {q[0]:.1f} {q[1]:.1f} {q[2]:.1f} 0')
        rows.append((0, 0, c))
        rows += [(0, 0, [])] * (window - 1)
    r = run_tape(fi, rows, name)
    out = []
    for i in range(len(jobs)):
        seg = r[i * window:(i + 1) * window]
        if len(seg) < window: out.append(None); continue
        out.append([dict(first=seg[1][k], mid=seg[window // 2][k], last=seg[-1][k]) for k in (0, 1)])
    return out

RESET = 3


def probe_jobs(fi, jobs, name, park):
    """jobs: list of (p1 point | None, p2 point | None, window). Both placed on the job's first row; a None side is
    placed at its park point; after the window both go back to their park points for RESET frames (stops any fall)."""
    rows, spans = [], []
    for a, b, w in jobs:
        c = []
        for k, p in ((1, a), (2, b)):
            q = p if p is not None else park[k - 1]
            if q is not None: c.append(f'place {k} {q[0]:.1f} {q[1]:.1f} {q[2]:.1f} 0')
        spans.append((len(rows), w))
        rows.append((0, 0, c)); rows += [(0, 0, [])] * (w - 1)
        c = [f'place {k} {q[0]:.1f} {q[1]:.1f} {q[2]:.1f} 0' for k, q in ((1, park[0]), (2, park[1])) if q is not None]
        rows.append((0, 0, c)); rows += [(0, 0, [])] * (RESET - 1)
    r = run_tape(fi, rows, name)
    out = []
    for s, w in spans:
        seg = r[s:s + w]
        if len(seg) < w: out.append(None); continue
        out.append([dict(first=seg[1][k], mid=seg[w // 2][k], last=seg[-1][k]) for k in (0, 1)])
    return out


if __name__ != '__main__': raise ImportError('area_probe.py is a script')
os.makedirs(OUT, exist_ok=True)
stage, inst = sys.argv[1], sys.argv[2]
STEP = 50
WA, WB = 14, 40
MAXN = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 9000
fi = Inst(inst)
p1 = 'ryoma' if stage == 'stg00' else 'falcon'
boss = stage == 'stga0'
res = {'stage': stage, 'p1': p1, 'p2': OWNER[stage], 'samples': [], 't0': time.time(), 'step': STEP}
CAL_ONLY = len(sys.argv) > 3 and sys.argv[3] == 'cal'   # area_probe.py STAGE INST cal: redo only the calibration
FILL_ONLY = len(sys.argv) > 3 and sys.argv[3] == 'fill'   # ... fill: only the 25 cm fill pass
# ... resume: an earlier run stopped during the refine pass (its Flycast died): the refine B points not probed yet
# (RA samples that did not stay and have no RB sample), RC, then the fill pass and the calibration
RESUME = len(sys.argv) > 3 and sys.argv[3] == 'resume'
if CAL_ONLY or FILL_ONLY or RESUME: res = json.load(open(OUT + f'{stage}_probe.json'))
OUTF = OUT + f'{stage}_probe.json'


def log(*a):
    print(f'[{stage} {time.strftime("%H:%M:%S")}]', *a, flush=True)


def save():
    json.dump(res, open(OUTF, 'w'))


def key(s):
    return dict(x=round(s['x'], 2), y=round(s['y'], 2), z=round(s['z'], 2), st=s['st'], vy=round(s['vy'], 3))


def frozen(s):
    """Londo: placed inside some collision volumes the game holds a fighter where it was put (no gravity, no push):
    that is no floor. A real floor exactly at the placement height looks the same: re-probed 17 cm higher (C)."""
    return math.hypot(s['last']['x'] - s['p'][0], s['last']['z'] - s['p'][2]) < 3 and s['last']['st'] in (0, 6) \
        and abs(s['last']['vy']) < 0.01 and abs(s['last']['y'] - s['p'][1]) < 0.5


def stayed(s):
    return math.hypot(s['last']['x'] - s['p'][0], s['last']['z'] - s['p'][2]) < 3 and s['last']['st'] in (0, 6) \
        and abs(s['last']['vy']) < 0.01 and not frozen(s)


def pair(pts, park):
    """(point, pas, window) list -> jobs with P1 and P2 points >= 3 m apart (P2 = owner; never on the boss stage)."""
    jobs, left = [], list(pts)
    while left:
        a = left.pop(0)
        b = None
        if not boss:
            for i, q in enumerate(left):
                if q[2] == a[2] and math.hypot(q[0][0] - a[0][0], q[0][2] - a[0][2]) >= 300 \
                        and math.hypot(q[0][0] - park[0][0], q[0][2] - park[0][2]) >= 250 \
                        and math.hypot(a[0][0] - park[1][0], a[0][2] - park[1][2]) >= 250:
                    b = left.pop(i); break
        if b is None and not boss and math.hypot(a[0][0] - park[1][0], a[0][2] - park[1][2]) < 250:
            jobs.append((None, a, a[2]))   # too close to P2's park: P2 probes it, P1 stays parked
        else:
            jobs.append((a, b, a[2]))
    return jobs


def run(name, pts, park):
    """pts: list of ((x, y, z), pas, window)"""
    jobs = pair(pts, park)
    r = probe_jobs(fi, [((a[0] if a else None), (b[0] if b else None), w) for a, b, w in jobs], f'{stage}_{name}', park)
    new = []
    for (a, b, w), rr in zip(jobs, r):
        if rr is None: continue
        for k, p in ((0, a), (1, b)):
            if p is None: continue
            s = dict(pas=p[1], k=k + 1, p=list(p[0]), first=key(rr[k]['first']), mid=key(rr[k]['mid']), last=key(rr[k]['last']))
            res['samples'].append(s); new.append(s)
    save()
    bad = sum(1 for s in new if s['last']['st'] in (21, 22) or s['first']['st'] in (21, 22))
    if bad: log(f'WARNING {name}: {bad} samples in a round end / intro state (round clock not frozen?)')
    return new


def calibrate(park):
    """Radius calibration: P1's clean wall pushes at the start floor (pushed 8-40 cm sideways, landed on the floor it
    was put 30 cm over) re-probed by P2 and again by P1, same placed points."""
    cands = [s for s in res['samples'] if s['k'] == 1 and s['pas'] in ('A', 'RA') and s['last']['st'] in (0, 6)
             and 8 < math.hypot(s['last']['x'] - s['p'][0], s['last']['z'] - s['p'][2]) < 40
             and abs(s['last']['y'] - (s['p'][1] - 30)) < 2]
    cands = cands[::max(1, len(cands) // 20)][:20]
    rows = [(None, tuple(s['p']), WA) for s in cands] + [(tuple(s['p']), None, WA) for s in cands]
    r = probe_jobs(fi, rows, f'{stage}_cal', park)
    cal = []
    n = len(cands)
    for i, s in enumerate(cands):
        if r[i] is None or r[n + i] is None: continue
        cal.append(dict(p=s['p'], f1=key(r[n + i][0]['last']), f2=key(r[i][1]['last']), f1_first=s['last']))
    res['cal'] = cal
    save()
    log('calibration', len(cal), 'pushes')


def fill(park, yA, yB):
    """Floor heights at 25 cm everywhere inside: every 25 cm lattice point next to an inside 50 cm node that no pass
    probed yet (A, then B where A fails, C where the game held it)."""
    done = {(round(s['p'][0], 1), round(s['p'][2], 1)) for s in res['samples']}
    ins = {(int(s['p'][0]), int(s['p'][2])) for s in res['samples'] if s['pas'] in ('A', 'B', 'C') and stayed(s)}
    pts = set()
    for x, z in ins:
        for dx in (-25, 0, 25):
            for dz in (-25, 0, 25):
                q = (float(x + dx), float(z + dz))
                if q not in done: pts.add(q)
    pts = sorted(pts, key=lambda q: (q[1], q[0]))
    log('fill', len(pts), 'points')
    failA, failC = [], []
    for i in range(0, len(pts), 800):
        for s in run(f'fa{i // 800}', [((x, yA, z), 'FA', WA) for x, z in pts[i:i + 800]], park):
            if not stayed(s): failA.append((s['p'][0], s['p'][2]))
            if frozen(s): failC.append((s['p'][0], s['p'][1] + 17, s['p'][2]))
    for i in range(0, len(failA), 400):
        for s in run(f'fb{i // 400}', [((x, yB, z), 'FB', WB) for x, z in failA[i:i + 400]], park):
            if frozen(s): failC.append((s['p'][0], s['p'][1] + 17, s['p'][2]))
    if failC: run('fc', [(p, 'FC', WA) for p in failC], park)
    res['fill_n'] = len(pts)
    save()

try:
    for attempt in range(2):
        opp, stg = to_fight(fi, p1, stage)
        log('fight', opp, stg)
        if stg == stage: break
        fi.stop()
    res['who'] = [opp, stg]
    _b = open(fi.root + 'who_ram.bin', 'rb').read()
    open(OUT + f'{stage}_structs.bin', 'wb').write(_b[P1 - 0x0C000000:P1 - 0x0C000000 + 0x72D0] + _b[P2 - 0x0C000000:P2 - 0x0C000000 + 0x72D0])
    if stg != stage: raise SystemExit('wrong stage')
    fi.fc(freeze_lines(), 5)
    r = probe(fi, [(None, None)], f'{stage}_s0', 4)
    s1, s2 = r[0][0]['last'], r[0][1]['last']
    sp = [(s1['x'], s1['y'], s1['z']), (s2['x'], s2['y'], s2['z'])]
    res['spawn'] = sp
    y0 = s1['y']
    park = [sp[0], None if boss else sp[1]]
    if boss: park = [sp[0], None]
    if CAL_ONLY:
        calibrate(park); raise SystemExit
    yA, yB = y0 + 30, y0 + 700
    if FILL_ONLY:
        fill(park, yA, yB); raise SystemExit
    if RESUME:
        rb = {(round(q['p'][0], 1), round(q['p'][2], 1)) for q in res['samples'] if q['pas'] == 'RB'}
        failA = [(q['p'][0], q['p'][2]) for q in res['samples'] if q['pas'] == 'RA' and not stayed(q)
                 and (round(q['p'][0], 1), round(q['p'][2], 1)) not in rb]
        log('resume: refine B', len(failA))
        failC = []
        for i in range(0, len(failA), 400):
            for q in run(f'xb{i // 400}', [((x, yB, z), 'RB', WB) for x, z in failA[i:i + 400]], park):
                if frozen(q): failC.append((q['p'][0], q['p'][1] + 17, q['p'][2]))
        if failC: run('xc', [(p_, 'RC', WA) for p_ in failC], park)
        fill(park, yA, yB)
        if not boss: calibrate(park)
        res['t1'] = time.time(); save()
        log('done', len(res['samples']), 'samples'); raise SystemExit
    res['yA'], res['yB'] = yA, yB
    log('spawn', sp)
    # flood fill on a 50 cm lattice: a node is inside when a fighter placed there (A: 30 cm over the start floor,
    # B: dropped from 7 m over it, only where A failed) settles without being moved sideways; the fill also crosses
    # nodes the game nudges < 25 cm (step edges), never deeper into a wall
    snap = lambda v: int(round(v / STEP)) * STEP
    seen, inside = set(), set()
    front, pendB = set(), set()
    for p in sp:
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1): front.add((snap(p[0]) + dx * STEP, snap(p[2]) + dz * STEP))
    # AREA_SEEDS="x,z;x,z;..." (cm): extra flood starts on floors the round's start points never join (Kraken's 2.2 m
    # deck: placed or dropped at its front face the disc pushes the fighter back onto the main deck, w9); seeded nodes
    # are probed like the rest (A, then B = dropped from 7 m where A fails)
    for q in [t for t in os.environ.get('AREA_SEEDS', '').split(';') if t]:
        x, z = (float(v) for v in q.split(','))
        front.add((snap(x), snap(z)))
    rnd = 0
    def passable(s):
        return stayed(s) or (s['last']['st'] in (0, 6) and abs(s['last']['vy']) < 0.01 and not frozen(s) and
                             math.hypot(s['last']['x'] - s['p'][0], s['last']['z'] - s['p'][2]) < 25)
    pendC = set()
    while (front or pendB or pendC) and len(seen) < MAXN:
        rnd += 1
        pa = sorted(front, key=lambda q: (q[1], q[0])); pb = sorted(pendB, key=lambda q: (q[1], q[0]))
        pc = sorted(pendC)
        seen |= front
        new = run(f'r{rnd}', [((x, yA, z), 'A', WA) for x, z in pa] + [((x, yB, z), 'B', WB) for x, z in pb] +
                  [((x, y, z), 'C', WA) for x, z, y in pc], park)
        grow, pendB, pendC = [], set(), set()
        for s in new:
            k = (int(s['p'][0]), int(s['p'][2]))
            if stayed(s): inside.add(k)
            if passable(s): grow.append(k)
            elif frozen(s) and s['pas'] in ('A', 'B'): pendC.add((k[0], k[1], s['p'][1] + 17))
            elif s['pas'] == 'A': pendB.add(k)
            if frozen(s) and s['pas'] == 'A': pendB.add(k)
        front = set()
        for x, z in grow:
            for dx in (-STEP, 0, STEP):
                for dz in (-STEP, 0, STEP):
                    n = (x + dx, z + dz)
                    if n not in seen: front.add(n)
        log(f'round {rnd}: A {len(pa)} B {len(pb)}, grow {len(grow)}, seen {len(seen)} inside {len(inside)}')
    res['rounds'] = rnd
    # refine at 25 cm around class changes and floor steps (neighbours settling > 5 cm apart in height)
    lvl = {}
    for s in res['samples']:
        if stayed(s) and s['pas'] in ('A', 'C'): lvl.setdefault((int(s['p'][0]), int(s['p'][2])), s['last']['y'])
    ref = set()
    for (x, z) in seen:
        v = (x, z) in inside
        for dx, dz in ((STEP, 0), (0, STEP)):
            n = (x + dx, z + dz)
            step = (x, z) in lvl and n in lvl and abs(lvl[(x, z)] - lvl[n]) > 5
            if n in seen and ((n in inside) != v or step):
                for ox in (-25, 0, 25):
                    for oz in (-25, 0, 25):
                        q = (x + dx / 2 + ox, z + dz / 2 + oz)
                        if (q[0] % STEP, q[1] % STEP) != (0, 0): ref.add(q)
    ref = sorted(ref, key=lambda q: (q[1], q[0]))
    log('refine', len(ref), 'points')
    res['refine_n'] = len(ref)
    failA, failC = [], []
    for i in range(0, len(ref), 800):
        chunk = ref[i:i + 800]
        for s in run(f'ra{i // 800}', [((x, yA, z), 'RA', WA) for x, z in chunk], park):
            if not stayed(s): failA.append((s['p'][0], s['p'][2]))
            if frozen(s): failC.append((s['p'][0], s['p'][1] + 17, s['p'][2]))
    log('refine B', len(failA))
    for i in range(0, len(failA), 400):
        chunk = failA[i:i + 400]
        for s in run(f'rb{i // 400}', [((x, yB, z), 'RB', WB) for x, z in chunk], park):
            if frozen(s): failC.append((s['p'][0], s['p'][1] + 17, s['p'][2]))
    if failC: run('rc', [(p, 'RC', WA) for p in failC], park)
    fill(park, yA, yB)
    if not boss: calibrate(park)
    res['t1'] = time.time()
    save()
    log('done', len(res['samples']), 'samples', round((res['t1'] - res['t0']) / 60, 1), 'min')
finally:
    fi.stop()
