#!/usr/bin/env python3
"""fx-reach: the disc's live attack-sphere centres (tools/reachlog.py, game RAM +0x148) vs the remaster's clip pose
(game/tests/reach_probe.gd: joints b00-b18 per clip frame, model space) under a drawn-pose rule, in the fighter's own
frame (side, up, forward cm from the feet; the disc's per-frame facing +0x7248).
  reach.py fit DISC_DIR CLIPS.jsonl TAPE...     per rule (clip frame offset k, pin = none / table travel): sphere error
  reach.py show DISC_DIR CLIPS.jsonl TAPE KEY   per frame: disc vs remaster centres for one motion (k1_016 ...)
  reach.py export DISC_DIR CLIPS OUTDIR TAPE...  -> OUTDIR/body_scale.json + hip_pin.json (game/assets/fidelity)
  reach.py runtime DISC_DIR REM_DIR TAPE...    disc spheres vs the remaster's runtime joints (tape_run PS_REACH=1)
  reach.py sizes DISC_DIR CLIPS OUT.json TAPE... per fighter / form: joint scale S, hip factor c, sphere error before / after
Rule: remaster centre(g) = clip sphere at clip frame g - k + pin(g); pin(g) = -(table travel rows 1..g) (motions.json)."""
import json, math, os, sys
import numpy as np
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
FILES = {'falcon': 'p00', 'ryoma': 'p10', 'wangtang': 'p20', 'jack': 'p30', 'gunrock': 'p40', 'galuda': 'p50',
         'ayame': 'p60', 'rouge': 'p70', 'kraken': 'p80', 'valgas': 'p90'}
_clips = {}


def clips(path):
    if path in _clips: return _clips[path]
    out = {}
    for pth in path.split(','):
        for ln in open(pth):
            r = json.loads(ln)
            out.setdefault((r['ch'], bool(r.get('pc')), r['c']), {})[r['f']] = r['j']
    _clips[path] = out
    return out


def hitdef(ch):
    return json.load(open(R + f'game/assets/ripped/{FILES[ch]}_hit.json'))


def motions():
    return json.load(open(R + 'game/assets/fidelity/motions.json'))


def local(p, c):
    a = p['ang'] / 65536.0 * 2 * math.pi
    fwd = np.array([math.sin(a), 0, math.cos(a)]); side = np.array([math.cos(a), 0, -math.sin(a)])
    d = np.array(c[:3]) - np.array([p['x'], p['y'], p['z']])
    return np.array([d @ side, d[1], d @ fwd])


def clip_sphere(J, joint, off):
    j = J[joint]
    if not j: return None
    o = np.array(j[:3]); B = np.array(j[3:]).reshape(3, 3).T   # columns x, y, z
    return o + B @ np.array(off[:3], float)


def prefix(ch, pc, cl):
    p = {k[2][:2] for k in cl if k[0] == ch and k[1] == bool(pc)}
    p = sorted(p)
    return p[-1] if pc else p[0]


def samples(disc_dir, clips_path, tape, who=0):
    """[(key, g, entry idx, disc local centre, joint, sphere offset, clip name, pc)] for every live attack sphere."""
    rows = [json.loads(l) for l in open(disc_dir + f'/o_{tape}.jsonl')]
    hdr = open(R + f'game/tests/tapes/{tape}.tape').readline()
    ch = dict(kv.split('=') for kv in hdr[2:].split())['p1' if who == 0 else 'p2']
    cl = clips(clips_path)
    H = hitdef(ch)
    out = []
    for r in rows:
        p = r['p'][who]
        if p['kind'] not in (1, 4): continue
        key = f"k{p['kind']}_{p['mot']:03d}"
        steps = H['moves'].get(key, [])
        g = p['fr']
        aset = p.get('aset')
        if aset is None:
            aset = 0
            for s in steps:
                if s[0] <= g < s[0] + s[1]: aset = s[3]; break
        live = [i for i, a in enumerate(p['att']) if a[3] > 0]
        if not live: continue
        ents = H['atk_sets'].get(str(aset), [])
        pre = prefix(ch, p['pc'], cl)
        for i in live:
            if i >= len(ents): continue
            jnt, e = ents[i]
            sp = H['spheres'][str(e)]
            if not sp[3]: continue
            out.append(dict(f=r['f'], key=key, g=g, i=i, disc=local(p, p['att'][i]), joint=jnt, off=sp, clip=pre + key,
                            ch=ch, pc=p['pc'], r=sp[3], rd=p['att'][i][3], hip=local(p, p['hip'])))
    return out


def predict(s, cl, mot, k, pin):
    fr = cl.get((s['ch'], bool(s['pc']), s['clip']))
    if not fr: return None
    cf = min(max(s['g'] - k, 0), max(fr))
    if s['joint'] == 255:
        c = np.array(s['off'][:3], float)
    else:
        c = clip_sphere(fr[cf], s['joint'], s['off'])
        if c is None: return None
    if pin == 'table':
        rows = (mot.get(s['ch'], {}).get(s['clip'], {}) or {}).get('d', [])
        t = np.zeros(3)
        for q in rows[1:s['g'] + 1]: t += np.array([q[1], q[2], q[0]])
        c = c - t
    return c


def fit(disc_dir, clips_path, tapes):
    cl = clips(clips_path); mot = motions()
    S = []
    for t in tapes: S += samples(disc_dir, clips_path, t)
    print(f'{len(S)} live attack spheres on the disc ({len(tapes)} tapes)')
    for pin in ('none', 'table'):
        for k in (-1, 0, 1, 2):
            e = []
            for s in S:
                c = predict(s, cl, mot, k, pin)
                if c is not None: e.append(np.linalg.norm(c - s['disc']))
            e = np.array(e)
            print(f'  pin {pin:5s} clip frame = g - {k:2d}: n {len(e)} median {np.median(e):6.1f} cm  p90 {np.percentile(e, 90):6.1f}  max {e.max():6.1f}')
    return S


def show(disc_dir, clips_path, tape, key, k=1):
    cl = clips(clips_path); mot = motions()
    for s in samples(disc_dir, clips_path, tape):
        if s['key'] != key: continue
        a = predict(s, cl, mot, k, 'none'); b = predict(s, cl, mot, k, 'table')
        f = lambda v: '(%5.0f %5.0f %5.0f)' % tuple(v) if v is not None else '-'
        print(f"f{s['f']} g{s['g']:3d} e{s['i']} j{s['joint']:3d} r{s['r']:3.0f} disc {f(s['disc'])} nopin {f(a)} pin {f(b)} hip {f(s['hip'])}")


def scales(disc_dir, clips_path, tapes):
    """Per fighter and form: limb scale (disc joint-to-joint / clip) from the live attack spheres' joints, joint scale
    (disc radius / file radius), and the hip ratio disc / clip (height above the feet, clip frame g - 1)."""
    cl = clips(clips_path); mot = motions()
    for t in tapes:
        rows = [json.loads(l) for l in open(disc_dir + f'/o_{t}.jsonl')]
        hdr = open(R + f'game/tests/tapes/{t}.tape').readline()
        ch = dict(kv.split('=') for kv in hdr[2:].split())['p1']
        H = hitdef(ch)
        for pc in (0, 1):
            pre = prefix(ch, pc, cl)
            hy, lim, rad = [], [], []
            for r in rows:
                p = r['p'][0]
                if p['pc'] != pc or p['kind'] != 1 or p['fr'] < 1: continue
                fr = cl.get((ch, bool(pc), pre + f"k1_{p['mot']:03d}"))
                if not fr: continue
                J = fr[min(p['fr'] - 1, max(fr))]
                hy.append((p['hip'][1] - p['y']) / J[0][1])
                ents = H['atk_sets'].get(str(p['aset']), [])
                live = [(i, ents[i][0]) for i in range(min(4, len(ents))) if p['att'][i][3] > 0 and ents[i][0] != 255]
                for a in range(len(live)):
                    for b in range(a + 1, len(live)):
                        ia, ja = live[a]; ib, jb = live[b]
                        if H['spheres'][str(ents[ia][1])][:3] != [0, 0, 0] or H['spheres'][str(ents[ib][1])][:3] != [0, 0, 0]: continue
                        dc = np.linalg.norm(np.array(J[ja][:3]) - np.array(J[jb][:3]))
                        if dc > 5: lim.append(np.linalg.norm(np.array(p['att'][ia][:3]) - np.array(p['att'][ib][:3])) / dc)
            if hy: print(f'{ch:9s} pc {pc} hip disc/clip median {np.median(hy):.3f} (n {len(hy)})  limb disc/clip {np.median(lim) if lim else 0:.3f} (n {len(lim)})')


def sphere_rule(s, cl, mot, S, c, k=1, pin=True):
    """Remaster centre under the size rule: hip x c (Motion Check's root scale -> the fight's), the limbs x S (the
    fight's joint scale), the table travel pinned out; clip frame g - k."""
    fr = cl.get((s['ch'], bool(s['pc']), s['clip']))
    if not fr: return None
    J = fr[min(max(s['g'] - k, 0), max(fr))]
    if s['joint'] == 255 or not J[s['joint']]: return None
    hip = np.array(J[0][:3]); j = J[s['joint']]
    o = np.array(j[:3]); B = np.array(j[3:]).reshape(3, 3).T
    cen = c * hip + S * (o - hip) + S * (B @ np.array(s['off'][:3], float))
    if pin:
        rows = (mot.get(s['ch'], {}).get(s['clip'], {}) or {}).get('d', [])
        t = np.zeros(3)
        for q in rows[1:s['g'] + 1]: t += np.array([q[1], q[2], q[0]])
        cen = cen - t
    return cen


def sizes(disc_dir, clips_path, tapes, out=None):
    """Per fighter and form: S = the disc's sphere radius / the file's (joint scale), c = the hip factor minimising the
    median live-sphere error; error before (S = c = 1, with / without the travel pin) and after."""
    cl = clips(clips_path); mot = motions()
    res = {}
    for t in tapes:
        S_all = samples(disc_dir, clips_path, t)
        ch = S_all[0]['ch'] if S_all else t
        for pc in (0, 1):
            ss = [s for s in S_all if s['pc'] == pc and s['joint'] != 255]
            if len(ss) < 5: continue
            Sc = float(np.median([s['rd'] / s['r'] for s in ss]))
            Sc = round(Sc, 3)
            def err(S, c, pin=True, k=1):
                e = [np.linalg.norm(p - s['disc']) for s in ss for p in [sphere_rule(s, cl, mot, S, c, k, pin)] if p is not None]
                return np.array(e)
            best = min((float(np.median(err(Sc, c))), c) for c in np.arange(0.70, 1.40, 0.005))
            c = round(best[1], 3)
            e0n, e0p, e1 = err(1, 1, False), err(1, 1, True), err(Sc, c)
            print(f'{ch:9s} pc {pc}: S {Sc:.3f} c {c:.3f} | live spheres {len(e1)}: before (no pin) median {np.median(e0n):5.1f} p90 '
                  f'{np.percentile(e0n, 90):5.1f} | before (pin) {np.median(e0p):5.1f} / {np.percentile(e0p, 90):5.1f} | after '
                  f'{np.median(e1):5.1f} / {np.percentile(e1, 90):5.1f} cm', flush=True)
            res.setdefault(ch, {})['pc' if pc else 'n'] = [Sc, c, len(e1)]
    if out: json.dump(res, open(out, 'w'), indent=1)
    return res


def joint_scale(rows, H, who, pc):
    """The fight's joint scale of one form: the mode of disc body-sphere radius / file radius (non-root entries)."""
    from collections import Counter
    bt = Counter()
    for r in rows:
        p = r['p'][who]
        if p['pc'] != pc: continue
        be = H['body_sets'].get(str(p['bset']), [])
        for i in range(1, min(4, len(be))):
            a = p['body'][i]; fr = H['spheres'][str(be[i][1])][3]
            if a[3] > 0 and fr and be[i][0] != 255: bt[round(a[3] / fr, 3)] += 1
    return bt.most_common(1)[0] if bt else None


def export(disc_dir, clips_path, tapes, out_dir):
    """game/assets/fidelity/body_scale.json (per fighter: [normal, Power Change] joint scale, the disc's spheres) and
    hip_pin.json (per normal-form attack clip whose drawn hip the table travel does not explain: per game frame g the
    hip's (side, fwd) cm the core must add to the clip's hip at clip frame g - 1, from the disc's hip joint)."""
    cl = clips(clips_path); mot = motions()
    scale, pins = {}, {}
    for t in tapes:
        rows = [json.loads(l) for l in open(disc_dir + f'/o_{t}.jsonl')]
        hdr = open(R + f'game/tests/tapes/{t}.tape').readline()
        ch = dict(kv.split('=') for kv in hdr[2:].split())['p1']
        H = hitdef(ch)
        sc = [joint_scale(rows, H, 0, 0), joint_scale(rows, H, 0, 1)]
        scale[ch] = [sc[0][0] if sc[0] else 1.0, sc[1][0] if sc[1] and sc[1][1] >= 100 else None]
        pre = prefix(ch, 0, cl)
        per = {}
        for r in rows:
            p = r['p'][0]
            if p['pc'] or p['kind'] != 1 or p['st'] not in (10, 11) or p['fr'] < 1: continue
            c = pre + 'k1_%03d' % p['mot']; fr = cl.get((ch, False, c))
            if not fr: continue
            g = p['fr']; J = fr[min(g - 1, max(fr))][0]
            d = (mot.get(ch, {}).get(c, {}) or {}).get('d', [])
            tr = np.zeros(3)
            for q in d[1:g + 1]: tr += np.array([q[1], q[2], q[0]])
            h = local(p, p['hip'])
            per.setdefault(c, {}).setdefault(g, []).append((h[0] - J[0], h[2] - J[2], float(np.linalg.norm((np.array(J[:3]) - tr) - h)), tr[0], tr[2]))
        for c, by in per.items():
            errs = [x[2] for v in by.values() for x in v]
            air = c[2:] in ('k1_010', 'k1_012')
            if np.median(errs) <= 3.0 and not air: continue
            n = max(by) + 1
            arr, last = [], [0.0, 0.0]
            for g in range(n):
                if g in by:
                    v = by[g]; last = [round(float(np.median([x[0] for x in v])), 1), round(float(np.median([x[1] for x in v])), 1)]
                arr.append(last)
            pins.setdefault(ch, {})[c] = arr
            print(f'{ch:9s} {c}: table-travel rule median {np.median(errs):5.1f} cm -> disc hip pin, {n} frames', flush=True)
    json.dump({'_doc': 'fx-reach: the fight draws each fighter at this joint scale (disc: body / attack sphere radius = the '
                       'file radius x the joint matrix scale; limbs disc / clip the same): [normal form, Power Change]',
               **scale}, open(out_dir + '/body_scale.json', 'w'), indent=1)
    json.dump({'_doc': 'fx-reach: per attack clip, per game frame g: (side, fwd) cm added to the clip hip at clip frame '
                       'g - 1 so the drawn hip sits where the disc draws it (clips whose hip the table travel does not '
                       'explain, and the air attacks)', **pins}, open(out_dir + '/hip_pin.json', 'w'))
    print(json.dumps(scale))


def runtime(disc_dir, rem_dir, tapes):
    """Disc vs the remaster's runtime pose (tape_run PS_REACH log): per live attack sphere on the disc (zero-offset limb
    spheres), the remaster's joint at the same motion and game frame (within 6 tape frames), both from their own feet."""
    allv = []
    for t in tapes:
        rows = [json.loads(l) for l in open(disc_dir + f'/o_{t}.jsonl')]
        rr = [json.loads(l) for l in open(rem_dir + f'/r_{t}.reach.jsonl')]
        by = {r['f']: r for r in rr}
        hdr = open(R + f'game/tests/tapes/{t}.tape').readline()
        ch = dict(kv.split('=') for kv in hdr[2:].split())['p1']
        H = hitdef(ch)
        e, hip = [], []
        for r in rows:
            p = r['p'][0]
            if p['kind'] != 1: continue
            key = f"k1_{p['mot']:03d}"
            ents = H['atk_sets'].get(str(p['aset']), [])
            live = [i for i in range(min(4, len(ents))) if p['att'][i][3] > 0 and ents[i][0] != 255 and H['spheres'][str(ents[i][1])][:3] == [0, 0, 0]]
            if not live: continue
            m = None
            for df in range(0, 7):
                for f in (r['f'] + df, r['f'] - df):
                    q = by.get(f)
                    if q and q['p'][0]['gmo'] == key and q['p'][0]['gmo_f'] == p['fr']: m = q['p'][0]; break
                if m: break
            if not m: continue
            for i in live:
                j = m['j'][ents[i][0]]
                if not j: continue
                e.append(np.linalg.norm(local(m, j[:3]) - local(p, p['att'][i])))
            hip.append(np.linalg.norm(local(m, m['j'][0][:3]) - local(p, p['hip'])))
        allv += e
        if e: print(f'{t:15s} live spheres matched {len(e):4d}: joint error median {np.median(e):5.1f} p90 {np.percentile(e, 90):5.1f} cm | hip median {np.median(hip):5.1f} p90 {np.percentile(hip, 90):5.1f}')
    if allv: print(f'ALL {len(allv)}: median {np.median(allv):.1f} p90 {np.percentile(allv, 90):.1f} cm')


if __name__ == '__main__':
    if sys.argv[1] == 'scales': scales(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif sys.argv[1] == 'sizes': sizes(sys.argv[2], sys.argv[3], sys.argv[5:], sys.argv[4])
    if sys.argv[1] == 'fit': fit(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif sys.argv[1] == 'show': show(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], int(sys.argv[6]) if len(sys.argv) > 6 else 1)
    elif sys.argv[1] == 'export': export(sys.argv[2], sys.argv[3], sys.argv[5:], sys.argv[4])
    elif sys.argv[1] == 'runtime': runtime(sys.argv[2], sys.argv[3], sys.argv[4:])
