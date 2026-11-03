#!/usr/bin/env python3
"""BUG-95: the original's breakable scenery (type-4 kind-15 objects) and the piece it drops. Spec: docs/BRK.md.
  breakables.py export [RAMDIR]   per-stage boxes from round-start RAM dumps -> game/assets/fidelity/breakables.json
  breakables.py check             scores the decoded rules on every logged object log (dumps/fidelity/o_*.obj.jsonl):
                                  trigger (a fighter in the wall splat, class 22, touching the box), the hang timer
                                  (the game's rand), the fall (y += vy, vy -= 1 from -2), the hit (first frame the
                                  victim is hittable at the start of the frame, piece still falling)
RAM layout (decoded, docs/BRK.md): object list *(0x0C7E4078 + 4*(type-2)) linked by +0x18; +0x20 x,y,z; +0x248 shape
(0 sphere, 1 cylinder = fighters, 2 box); +0x24C centre x,y,z + (radius, half height) / (half x, y, z); +0x308 stage
descriptor (byte 2 + 10 = the stage layout part that draws it)."""
import glob, json, math, os, struct, sys
R = './'
D = R + 'dumps/fidelity/'
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/game/assets/fidelity/breakables.json'
RAMDIR = '/tmp/ps-fx-cov/'
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
P1, P2 = 0x0C7E40C4, 0x0C7EB394


def ram(fn):
    b = open(fn, 'rb').read()
    return (lambda a: struct.unpack_from('<I', b, a & 0xFFFFFF)[0], lambda a: struct.unpack_from('<f', b, a & 0xFFFFFF)[0],
            lambda a: b[a & 0xFFFFFF])


def export(ramdir):
    stages, body = {}, {}
    for fn in sorted(glob.glob(ramdir + 'o_*_ready_ram.bin')):
        name = os.path.basename(fn).replace('_ready_ram.bin', '')
        mp = D + name + '.meta.json'
        if not os.path.exists(mp): continue
        m = json.load(open(mp))
        st = m['stage']
        u32, f32, u8 = ram(fn)
        for P in (P1, P2):   # fighters: cylinder radius / half height (+0x24C + 12 / + 16); char id = +0x71F0? use meta
            pass
        if st in stages: continue
        out = []
        a = u32(0x0C7E4080)
        while a:
            if u8(a + 4) == 15:
                desc = u32(a + 0x308)
                out.append({'home_cm': [round(f32(a + 0x20 + 4 * i), 2) for i in range(3)],
                            'box_c_cm': [round(f32(a + 0x24C + 4 * i), 2) for i in range(3)],
                            'box_h_cm': [round(f32(a + 0x258 + 4 * i), 2) for i in range(3)],
                            'shape': u8(a + 0x248), 'desc': '0x%08X' % desc, 'part': u8(desc + 2) + 10})
            a = u32(a + 0x18)
        stages[st] = out
    # fighter body cylinders: (radius, half height) read from the players' +0x24C in the same dumps
    for fn in sorted(glob.glob(ramdir + 'o_*_ready_ram.bin')):
        u32, f32, u8 = ram(fn)
        for P in (P1, P2):
            r, hh = round(f32(P + 0x258), 2), round(f32(P + 0x25C), 2)
            body.setdefault((r, hh), 0)
    rad = json.load(open(os.path.dirname(OUT) + '/fighter_radius.json'))['radius_cm']
    hh = {}
    for c, r in rad.items():
        for (rr, h) in body:
            if abs(rr - r) < 0.01 and not (c == 'ayame' and h != 63.0) and not (c == 'rouge' and h != 78.75):
                hh[c] = h
    # layout instance of each breakable's part nearest its home (the mesh the remaster hides / drops)
    for st, lst in stages.items():
        lp = R + f'game/assets/ripped/{st}_layout.json'
        lay = json.load(open(lp)) if os.path.exists(lp) else []
        used = set()
        for b in lst:
            best = None
            for i, l in enumerate(lay):
                if int(l['part']) != b['part'] or i in used: continue
                d = math.dist(l['M'][3][:3], b['home_cm'])
                if best is None or d < best[0]: best = (d, i)
            if best:
                used.add(best[1]); b['layout_index'] = best[1]
                b['layout_pos_cm'] = [round(v, 2) for v in lay[best[1]]['M'][3][:3]]
    doc = {'about': 'BUG-95 breakables (type-4 kind-15 objects, handler 0x0C0B1C24) per stage, read from round-start RAM '
                    'dumps (tools/breakables.py export). box = the object collision box (shape 2: centre + half extents, '
                    'cm); part = stage descriptor byte 2 + 10 = the stage layout part that draws it (layout_index = '
                    'its record in stgN0_layout.json). Spec docs/BRK.md.',
           'piece': {'timer': '70 + (u32)(rand() / 32768.0f * 255.0f) % 20 (frames hung; first fall frame = spawn + timer + 1)',
                     'vy0_cm': -2.0, 'gravity_cm': 1.0, 'attack_sphere_r_cm': 50.0, 'record': '0x0C33AB08 table',
                     'base_damage': 32, 'class': 3},
           'body_half_height_cm': hh, 'stages': stages}
    json.dump(doc, open(OUT, 'w'), indent=1)
    print(OUT, {k: len(v) for k, v in stages.items()}, hh)


def rnd20(s):
    s = (s * 0x41C64E6D + 0x3039) & 0xFFFFFFFF
    return s, (((s >> 16) & 0x7FFF) * 255 >> 15) % 20


def check(verbose=False):
    doc = json.load(open(OUT))
    rad = json.load(open(os.path.dirname(OUT) + '/fighter_radius.json'))['radius_cm']
    hh = doc['body_half_height_cm']
    tot = {'trig_ok': 0, 'trig_miss': 0, 'trig_extra': 0, 'timer_ok': 0, 'timer_bad': 0, 'fall_rows_ok': 0,
           'fall_rows_bad': 0, 'hit_ok': 0, 'hit_bad': 0, 'nohit_ok': 0}
    for fn in sorted(glob.glob(D + 'o_*.obj.jsonl')):
        name = os.path.basename(fn)[:-10]
        mp, lp = D + name + '.meta.json', D + name + '.jsonl'
        if not (os.path.exists(mp) and os.path.exists(lp)): continue
        meta = json.load(open(mp))
        st = meta['stage']
        boxes = doc['stages'].get(st, [])
        if not boxes: continue
        O = [json.loads(l) for l in open(fn)]
        P = [json.loads(l) for l in open(lp)]
        ids = [os.path.basename(name)[2:].split('_')[1] if name.startswith('o_moves_') else None, IDS[int(meta['p2'][1:3]) // 10] if meta.get('p2', '').startswith('P') else 'falcon']
        # P1's id: moves_<id> tapes (P1 = id); others from the tape header
        tp = R + 'game/tests/tapes/' + name[2:] + '.tape'
        if os.path.exists(tp):
            h = open(tp).readline()
            kv = dict(x.split('=') for x in h[2:].split() if '=' in x)
            ids = [kv.get('p1', ids[0]), kv.get('p2', ids[1])]
        # logged breaks: a type-4 kind-15 at a home position vanishes (no round reset that frame)
        homes = [tuple(b['home_cm']) for b in boxes]
        broken, logged = set(), []
        for f in range(1, min(len(O), len(P))):
            prev = {(o[5], o[6], o[7]) for o in O[f - 1] if o[1] == 4 and o[3] == 15}
            cur = {(o[5], o[6], o[7]) for o in O[f] if o[1] == 4 and o[3] == 15}
            if len(cur) >= len(prev) + 1 or (cur == {tuple(h) for h in homes} and prev != cur): broken = set()  # round reset
            ps = {(o[5], o[6], o[7]): o[0] for o in O[f - 1] if o[1] == 4 and o[3] == 15}
            cs = {(o[5], o[6], o[7]): o[0] for o in O[f] if o[1] == 4 and o[3] == 15}
            if any(ps[k] != cs[k] for k in ps if k in cs): continue   # the list was rebuilt (round end): not a break
            for h in prev - cur:
                if len(prev - cur) < 3: logged.append((f - 1, h))   # the frame the piece appears = 1 before the vanish
        # predicted: a fighter in class 22 (logged: state 27 with k2/152 or k2/153) whose cylinder overlaps the box
        pred, gone = [], set()
        for f in range(len(P)):
            if f < len(O) and f > 0:
                prev = {(o[5], o[6], o[7]) for o in O[f - 1] if o[1] == 4 and o[3] == 15}
                cur = {(o[5], o[6], o[7]) for o in O[f] if o[1] == 4 and o[3] == 15}
                if len(cur) > len(prev): gone = set()
            for pi in (0, 1):
                p = P[f]['p'][pi]
                if not (p['st'] == 27 and p['kind'] == 2 and p['mot'] in (152, 153)): continue
                r, h = rad.get(ids[pi], 30.0), hh.get(ids[pi], 75.0)
                for b in boxes:
                    hk = tuple(b['home_cm'])
                    if hk in gone: continue
                    c, e = b['box_c_cm'], b['box_h_cm']
                    if (e[0] + r - abs(c[0] - p['x']) >= 0 and e[2] + r - abs(c[2] - p['z']) >= 0
                            and min(c[1] + e[1], p['y'] + 2 * h) - max(c[1] - e[1], p['y']) >= 0):
                        pred.append((f, hk)); gone.add(hk)
        lf = {(f, h) for f, h in logged}
        pf = set(pred)
        ok = lf & pf
        tot['trig_ok'] += len(ok); tot['trig_miss'] += len(lf - pf); tot['trig_extra'] += len(pf - lf)
        if verbose or lf != pf: print(name, 'logged', sorted(lf), 'predicted', sorted(pf))
        # the pieces: timer by the logged rand, the fall, the hit
        sp = None
        for f in range(len(O)):
            pcs = [o for o in O[f] if o[1] == 2 and o[3] == 15]
            if not pcs: continue
            if sp is None or f > end:
                sp, y0, owner, x0, z0 = f, pcs[0][6], pcs[0][2], pcs[0][5], pcs[0][7]
                # timer: the first rand of the spawn frame
                s, t = rnd20(P[f - 1]['rand'] & 0xFFFFFFFF)
                T = 70 + t
                end = sp
                g = sp
                while g + 1 < len(O) and any(o[1] == 2 and o[3] == 15 for o in O[g + 1]): g += 1
                end = g
                ys = [[o for o in O[k] if o[1] == 2 and o[3] == 15][0][6] for k in range(sp, end + 1)]
                fall = next((k for k in range(len(ys)) if ys[k] != y0), None)
                if fall == T + 1: tot['timer_ok'] += 1
                else: tot['timer_bad'] += 1; print(name, 'timer', T, 'logged hang', fall)
                # fall: y0 - (2n + n(n-1)/2), floored at 0 (Londo's plaza; the floor under the piece)
                fl = 0.0
                for k in range(T + 1, len(ys)):
                    n = k - T
                    py = max(fl, y0 - (2 * n + n * (n - 1) / 2))
                    if abs(py - ys[k]) < 0.01: tot['fall_rows_ok'] += 1
                    else: tot['fall_rows_bad'] += 1
                land = next((k for k in range(T + 1, len(ys)) if ys[k] <= fl), None)
                # hit: victim (not the owner) hittable (state 0 / 2 / 31 / 32 ...) at the end of the previous frame and
                # this frame's start, piece still falling (spawn + T + 1 .. landing frame)
                vic = 1 - owner
                exp = None
                for k in range(T + 1, (land if land is not None else len(ys) - 1) + 1):
                    f2 = sp + k
                    if P[f2 - 1]['p'][vic]['st'] not in (8, 15, 16, 21, 22, 23, 27, 28, 29) and math.hypot(
                            P[f2 - 1]['p'][vic]['x'] - x0, P[f2 - 1]['p'][vic]['z'] - z0) < 120:
                        exp = f2; break
                got = next((k for k in range(sp, end + 3) if P[k]['p'][vic]['hp'] < P[k - 1]['p'][vic]['hp']
                            and P[k]['p'][vic]['hp'] - P[k - 1]['p'][vic]['hp'] == -32), None)
                if exp == got:
                    if exp is None: tot['nohit_ok'] += 1
                    else: tot['hit_ok'] += 1
                else:
                    tot['hit_bad'] += 1; print(name, 'hit expected', exp, 'logged', got)
                if verbose: print(name, 'spawn', sp, 'T', T, 'fall', sp + T + 1, 'land', sp + land if land else None, 'hit', got)
    print(json.dumps(tot))


if __name__ == '__main__':
    if sys.argv[1] == 'export': export(sys.argv[2] if len(sys.argv) > 2 else RAMDIR)
    elif sys.argv[1] == 'check': check('-v' in sys.argv)
