#!/usr/bin/env python3
"""fx-fv2: Final Valgas's own beams / shots / effect objects on the disc (docs/CPU.md "Final Valgas shots").
His fight logged like tools/fv_log.py (boot_boss, both sides the game's AI, level frozen) plus the whole object pool
(0x0C7D0980, 64 slots x 0x31C) every frame (`cap`) and both players' object-hit fields (+0xF8 record, +0x71BD hit id).
  fv_shots.py log INST LEVEL NAME [FRAMES]   -> LOGDIR/fvshot_L{LEVEL}_{NAME}.{jsonl,hit.jsonl,meta.json} + pool/ dir
  fv_shots.py objs NAME                       his type-1 objects (owner 1) per attack: spawn row, kind, path, spheres
  fv_shots.py build NAME...                   -> game/assets/fidelity/fv_shots.json in fx-shot's pc_shots.json schema
Pool slot (fx-shot, tools/pc_shots.py): +2 type (1 shot / effect, 5 player / model), +3 owner (1 = P2 = him), +4 kind,
+0x10 handler, +0x20 x,y,z f32 cm, +0x30 u16 heading, +0x100 hit id, +0x101 active, +0x144 hits landed, +0x148 attack
spheres (5 x world x,y,z,r cm; r 0 = off)."""
import json, math, os, struct, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE) + '/'
sys.path.insert(0, HERE)
import cpu_stats as CS
import reflog as RL

LOGDIR = os.environ.get('FV_SHOT_DIR', '/tmp/ps-fx-fv2/shots/')
POOL, STRIDE, NSLOT = 0x0C7D0980, 0x31C, 64
FVB, FVN = 0x0C439E38, 72
P1, P2 = RL.P1, RL.P2
XSEGS = [(P1 + 0xF8, 4), (P1 + 0x71BC, 4), (P2 + 0xF8, 4), (P2 + 0x71BC, 4), (P2 + 0x30, 4), (P1 + 0x30, 4)]
SPH = [(0x148 + 16 * i) for i in range(5)]
OUT = REPO + 'game/assets/fidelity/fv_shots.json'


def run(inst, lvl, name, frames=4200):
    from fcinst import Inst
    import fv_log as FL
    os.makedirs(LOGDIR, exist_ok=True)
    fi = Inst(inst)
    tag = f'fvshot_L{lvl}_{name}'
    t0 = time.time()
    try:
        FL.boot_boss(fi)
        lines = [f'unfreeze 0x{P1 + 0x71D4 + 2 * k:08X}' for k in range(3)]
        lines += [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'freeze8 0x{P2 + 0x71ED:08X} 1',
                  f'freeze8 0x{CS.LEVEL:08X} {lvl}', f'freeze8 0x{CS.RANK:08X} {min(255, lvl * 8)}',
                  f'capseg {tag} {frames} {CS.segs()},0x{FVB:08X}:{FVN},' + ','.join(f'0x{a:08X}:{n}' for a, n in XSEGS),
                  f'cap {tag}_pool 0x{POOL:08X} 0x{STRIDE * NSLOT:X} {frames}']
        fi.fc(lines, 60)
        fi.wait_idle(frames / 60 * 14 + 900, 5)
        time.sleep(2)
        raw = open(fi.root + f'cap/{tag}.bin', 'rb').read()
        fs = CS.frame_size(); xs = sum(n for _, n in XSEGS)
        n = len(raw) // (fs + FVN + xs)
        core = b''.join(raw[i * (fs + FVN + xs):i * (fs + FVN + xs) + fs] for i in range(n))
        tmp = LOGDIR + tag + '.core'
        open(tmp, 'wb').write(core)
        rows = CS.decode(tmp)
        os.remove(tmp)
        extra = []
        for i, r in enumerate(rows):
            b = raw[i * (fs + FVN + xs):(i + 1) * (fs + FVN + xs)]
            r['fv'] = b[fs + 36:fs + FVN].hex()
            x = b[fs + FVN:]
            r['hit'] = [[struct.unpack('<I', x[0:4])[0], x[5]], [struct.unpack('<I', x[8:12])[0], x[13]]]
            r['h30'] = [struct.unpack('<H', x[20:22])[0], struct.unpack('<H', x[16:18])[0]]   # P1, P2 model heading
        os.replace(fi.root + f'cap/{tag}.bin', LOGDIR + tag + '.bin')
        RL.write_jsonl(rows, LOGDIR + tag + '.jsonl')
        if os.path.isdir(fi.root + f'cap/{tag}_pool'): os.replace(fi.root + f'cap/{tag}_pool', LOGDIR + f'{tag}_pool')
        json.dump({'p1': 'falcon', 'p2': 'finalvalgas', 'level': lvl, 'fight': 8, 'frames': len(rows),
                   'wall_s': round(time.time() - t0)}, open(LOGDIR + tag + '.meta.json', 'w'))
        print(tag, len(rows), 'frames', round(time.time() - t0), 's', flush=True)
    finally:
        fi.stop()


if __name__ == '__main__' and sys.argv[1] == 'log':
    run(sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 4200)


# ---------------------------------------------------------------------------------------------------------------------
# reduce: his type-1 objects per motion
def _jl(p):
    return [json.loads(l) for l in open(p)]


def _rel(x, y, z, org, fw):
    dx, dy, dz = x - org[0], y - org[1], z - org[2]
    return [round(dx * fw[0] + dz * fw[1], 1), round(dx * fw[1] - dz * fw[0], 1), round(dy, 1)]


def _pool_frame(B):
    out = {}
    for s in range(NSLOT):
        o = s * STRIDE
        h = B[o:o + 8]
        if h[:4] == b'\0\0\0\0' or h[2] != 1 or h[3] != 1: continue
        x, y, z = struct.unpack('<3f', B[o + 0x20:o + 0x2C])
        sp = []
        for a in SPH:
            sx, sy, sz, r = struct.unpack('<4f', B[o + a:o + a + 16])
            if 0.5 < r < 2000: sp.append((sx, sy, sz, r))
        out[s] = dict(kind=h[4], fn=struct.unpack('<I', B[o + 0x10:o + 0x14])[0], xyz=(x, y, z),
                      ang=struct.unpack('<H', B[o + 0x30:o + 0x32])[0], hid=B[o + 0x100], act=B[o + 0x101],
                      nhit=struct.unpack('<I', B[o + 0x144:o + 0x148])[0], sp=sp)
    return out


def objects(name):
    """[(shot dict)] every type-1 object he owned in log NAME, tied to the motion he was in when it appeared."""
    pre = LOGDIR + name
    rows = _jl(pre + '.jsonl')
    pd = pre + '_pool/'
    files = sorted(os.listdir(pd))
    n = min(len(rows), len(files))
    # motion runs of him: start frame of the run each frame belongs to
    mstart, cur = [], None
    for i in range(n):
        q = rows[i]['p'][1]; k = (q['st'], q['kind'], q['mot'])
        if cur is None or (q['kind'], q['mot']) != cur[1:] or (q['fr'] < rows[i - 1]['p'][1]['fr'] and q['fr'] <= 1):
            cur = (i,) + (q['kind'], q['mot'])
        mstart.append(cur[0])
    live, shots = {}, []
    for i in range(n):
        objs = _pool_frame(open(pd + files[i], 'rb').read())
        for s, o in objs.items():
            c = live.get(s)
            if c is None or c['fn'] != o['fn'] or c['kind'] != o['kind'] or c['last'] != i - 1:
                q = rows[i]['p'][1]
                m0 = mstart[i]; q0 = rows[m0]['p'][1]
                hd = rows[i]['h30'][1]
                a = hd / 65536 * 2 * math.pi
                fw = (math.sin(a), math.cos(a))
                c = dict(slot=s, fn=o['fn'], kind=o['kind'], f=i, st=q['st'], mo='k%d_%03d' % (q['kind'], q['mot']),
                         t=i - m0, hid=o['hid'], hd=hd, fw=fw, org=(q0['x'], q0['y'], q0['z']), rows=[], hits=[],
                         nhit=0, opp=[])
                live[s] = c; shots.append(c)
            c['last'] = i
            p1 = rows[i]['p'][0]
            if o['hid'] and not c['hid']: c['hid'] = o['hid']   # some set their hit id after the spawn row
            if o['nhit'] > c['nhit']: c['hits'].append(i - c['f'])
            c['nhit'] = max(c['nhit'], o['nhit'])
            c['rows'].append([_rel(*o['xyz'], c['org'], c['fw']), (o['ang'] - c['hd']) & 0xFFFF,
                              [_rel(sx, sy, sz, c['org'], c['fw']) + [round(rr, 1)] for sx, sy, sz, rr in o['sp']]])
            c['opp'].append(_rel(p1['x'], p1['y'], p1['z'], c['org'], c['fw']))
        for s in [s for s, c in live.items() if c['last'] != i]: live.pop(s)
    return rows, shots


def objs(name):
    rows, shots = objects(name)
    for c in shots:
        r = c['rows']
        p0, p1 = r[0][0], r[min(len(r) - 1, 5)][0]
        sp = math.dist(p0, p1) / max(1, min(len(r) - 1, 5))
        o0 = c['opp'][0]
        print(f"f{c['f']:5d} {c['mo']} st{c['st']} t{c['t']:4d} slot{c['slot']:2d} kind{c['kind']:3d} fn{c['fn']:08x} hid{c['hid']:3d} "
              f"life{len(r):4d} from {p0} v~{sp:.1f} cm/f, opp at {o0} sph {[q[3] for q in r[0][2]]} hits {c['hits']}")


def _aim(c):
    """degrees between the object's first travel and the opponent at its spawn (in his heading frame): ~0 = aimed at
    him; its first travel off his heading (the frame's +fwd axis)"""
    r = c['rows']
    k = next((j for j in range(1, len(r)) if math.dist(r[j][0], r[0][0]) > 1.0), None)
    if k is None: return None, None, 0.0
    d = [r[k][0][i] - r[0][0][i] for i in range(3)]
    o = [c['opp'][0][i] - r[0][0][i] for i in range(3)]
    ang = lambda v: math.degrees(math.atan2(v[1], v[0]))
    pitch = lambda v: math.degrees(math.atan2(v[2], math.hypot(v[0], v[1])))
    return round(((ang(d) - ang(o)) + 180) % 360 - 180, 1), round(ang(d), 1), round(math.dist(r[k][0], r[0][0]) / k, 2)


def build(names):
    """fv_shots.json: fx-shot's schema (fighters.finalvalgas[motion].shots = [{t, hid, kind, rows: [[fwd, side, up],
    heading - his, spheres]}]), keyed by his MOTION (t = rows from the motion's first frame: his attacks chain motions and
    the shots of each start on that motion's own rows); one logged instance per (motion, t, kind) = the first one with
    spheres; plus 'stats' per motion (every instance: spawn rows, life, speed, aim, hits, damage)"""
    tab = {'about': ('fx-fv2 (tools/fv_shots.py build): Final Valgas\'s own shots / beams (type-1 pool objects owned by him, '
                     'owner byte 1) from the fvshot_* disc logs (his fight, both sides the game\'s AI). Schema = fx-shot\'s '
                     'pc_shots.json, keyed by his motion (k1_097 ...): t = spawn row from that motion\'s first frame, rows = '
                     'per frame [[fwd, side, up] cm from his feet at the motion\'s first frame in his heading (+0x30) on the '
                     'shot\'s first frame, object heading - his (u16), attack spheres [[fwd, side, up, r] cm]]. He never moves '
                     'while attacking. stats: every logged instance (aim = degrees between the first travel and the opponent '
                     'at spawn; hits = rows after spawn where +0x144 rose).'), 'fighters': {'finalvalgas': {}}, 'stats': {}}
    mv = tab['fighters']['finalvalgas']; st = tab['stats']
    # the missiles' flight, measured on every logged one (fv_shots.py objs; 4 logs, 80 missiles): for a homing mode
    tab['homing'] = {'fn': '0x0C0CA67E', 'hid': 114, 'r': 22.5,
                     'hold_f': [46, 201], 'hold_note': 'on his body (sphere follows it), staggered in a volley',
                     'eject': {'f': 20, 'v0': 29.0, 'dv': -1.0, 'pitch_deg': 54, 'yaw': 'his heading + 180 deg'},
                     'home': {'v': 20.0, 'yaw_step_u16': 910, 'pitch_step_deg': 5, 'toward': "the opponent's hip"},
                     'dive': {'v': [51, 56], 'yaw_step_u16': 145, 'pitch_step_deg': 1, 'note': 'once pointing almost straight down'},
                     'blast': {'f': 20, 'r': [2.2, 45.0], 'note': 'in place after a hit (+0x144) or at the end'},
                     'landed': '80 of 146 (8 logs), 71-75 frames after the launch'}
    for name in names:
        rows, shots = objects(name)
        for c in shots:
            if c['st'] != 11 and c['mo'][:2] != 'k1': continue
            key = c['mo']
            aim, dirn, spd = _aim(c)
            S = st.setdefault(key, {})
            g = S.setdefault('t%d_fn%08x' % (c['t'], c['fn']), dict(n=0, life=[], speed=[], aim=[], dir=[], hits=[], r=[], hid=c['hid']))
            g['n'] += 1; g['life'].append(len(c['rows'])); g['speed'].append(spd); g['aim'].append(aim); g['dir'].append(dirn)
            g['hits'].append(c['hits']); g['r'].append(sorted(set(q[3] for row in c['rows'] for q in row[2])))
            m = mv.setdefault(key, {'shots': []})
            if not any(r[2] for r in c['rows']) or not c['hid']: continue   # no spheres / no record: a look, never hits
            old = next((d for d in m['shots'] if (d['t'], d['fn']) == (c['t'], c['fn'])), None)
            if old is not None and (old['hit'] or not c['hits']): continue   # keep one that landed (homing: it ends on him)
            if old is not None: m['shots'].remove(old)
            m['shots'].append(dict(t=c['t'], hid=c['hid'], kind=c['kind'], fn=c['fn'], hit=bool(c['hits']), log=name, f=c['f'],
                                   rows=[[r[0], r[1], r[2]] for r in c['rows']]))
    for k in list(mv):
        mv[k]['shots'].sort(key=lambda d: (d['t'], d['kind']))
        if not mv[k]['shots']: mv.pop(k)
    json.dump(tab, open(OUT, 'w'), separators=(',', ':'))
    for k in sorted(st):
        print(k, {t: dict(n=g['n'], life=sorted(set(g['life']))[:6], v=sorted(set(g['speed']))[:4], aim=g['aim'][:6],
                         dir=g['dir'][:4], hits=[h for h in g['hits'] if h][:4], r=g['r'][0], hid=g['hid'])
                  for t, g in sorted(st[k].items())})


if __name__ == '__main__' and sys.argv[1] == 'objs':
    objs(sys.argv[2])
if __name__ == '__main__' and sys.argv[1] == 'build':
    build(sys.argv[2:])


def table():
    """markdown summary of fv_shots.json stats: per motion and object class"""
    tab = json.load(open(OUT))
    st = tab['stats']; recs = None
    try:
        recs = json.load(open(REPO + 'game/assets/fidelity/react_code.json'))['records']['finalvalgas']
    except Exception:
        pass
    print('| motion | object (handler) | spawned at motion rows | n | life frames | speed cm/f | sphere r cm | hit id (base dmg) | landed |')
    print('|---|---|---|---|---|---|---|---|---|')
    for mo in sorted(st):
        by = {}
        for k, g in st[mo].items():
            t, fn = k.split('_fn')
            b = by.setdefault(fn, dict(t=[], n=0, life=[], v=[], r=set(), hid=0, hits=0))
            b['t'].append(int(t[1:])); b['n'] += g['n']; b['life'] += g['life']; b['v'] += [v for v in g['speed'] if v]
            for rr in g['r']: b['r'].update(rr)
            b['hid'] = b['hid'] or g['hid']; b['hits'] += sum(1 for h in g['hits'] if h)
        for fn, b in sorted(by.items()):
            dmg = int(recs[b['hid']][2:4], 16) if recs and b['hid'] and b['hid'] < len(recs) else 0
            r = sorted(b['r'])
            rs = '%g' % r[0] if len(r) == 1 else ('%g..%g' % (r[0], r[-1]) if r else '-')
            v = sorted(b['v'])
            print('| %s | 0x%s | %s | %d | %d..%d | %s | %s | %s | %d / %d |' % (
                mo, fn.upper().replace('0C0', '0C0', 1), ' '.join(str(x) for x in sorted(set(b['t']))[:12]) + (' ...' if len(set(b['t'])) > 12 else ''),
                b['n'], min(b['life']), max(b['life']), ('%g' % v[len(v) // 2]) if v else '0', rs,
                ('%d (%d)' % (b['hid'], dmg)) if b['hid'] else 'none (a look)', b['hits'], b['n']))


if __name__ == '__main__' and sys.argv[1] == 'table':
    table()
