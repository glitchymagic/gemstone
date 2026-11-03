#!/usr/bin/env python3
"""In-fight clip capture (generic): motions the disc plays in a real fight that Motion Check can't replay (their
Pn0_MOT.MDT slot is 0, so Motion Check shows idle): item motions, Falcon's air punch k1/10, ... Recorded from a REAL
fight played by a same-input tape (both pads human, rand 1: deterministic, tools/reflog.py), cut by the player
struct's own motion fields (+0x71A4/5 kind / id, +0x719E motion frame), turned into clips exactly like
tools/clips.py (local bone rotations from the game's world matrices) and merged like tools/add_clips.py build.

  fight_clips.py capture SLOT TAPE IDS [--from F --to T]
      SLOT = P1 | P2 (the fighter to record; its character = the tape header '#! p1=.. p2=..'), TAPE = a tape name in
      game/tests/tapes or a path, IDS = k2_237,k2_245,... Boots arcade p1 vs p2 on p2's home stage (reflog.boot), a RAM
      dump at the round intro -> that fighter's part records (mocap.find_records; the record group whose root sits
      nearest that player's position), then plays TAPE like reflog.play with
        * tapelog = reflog's per-frame player log of the whole tape (determinism check against dumps/fidelity/o_TAPE)
        * a capseg of the part records + the player struct (+0x7190..+0x71C0 motion fields, +0x020 feet, +0x7248
          facing, +0x06C model matrix) from tape row F to T (default: the wanted ids' rows in o_TAPE.jsonl +-12, else the whole tape)
      -> CAPS/<tape>_<slot>.bin + .json (segs, frame offset) + _log.jsonl     (CAPS = PS_FIGHTCAPS)
  fight_clips.py cut SLOT TAPE IDS PREFIX OUT     cut each id -> OUT/<PREFIX><id>.npz + index.json (clips.py format)
  fight_clips.py build SLOT TAPE IDS PREFIX       cut, then add_clips.build(..., pre=cut folder): merge + PC copy +
                                                  both forms' rigs + clip maps (env PS_ROOT / PS_MOCAP / PS_TMP)
  fight_clips.py compare SLOT TAPE IDS PREFIX     in-fight cut vs the Motion Check clip already in the clip folder
                                                  (max joint angle error, root offset) for ids Motion Check DID capture
Env: PS_FC_INST (fcinst instance, default cap1), PS_FIGHTCAPS (capture folder). Tapes may use the extra row commands
of tools/fight_clips.lua (loaded before every capture): @itemid N, @toitem P DX DZ ANG, @faceme P DIST.
Cut rule: every run where (kind, id) holds and the motion frame counts up by 1 each row; the longest run wins (the
first on a tie). A loop = the counter wraps to 0 while the id holds (period = the last count + 1): the clip is one
period. The base transform per frame is the player's own model matrix (+0x06C: feet position + the yaw the body is drawn
with), so the root keeps the motion's own hip offset however the game moves the player (jumps, knock-back): the same
convention as a Motion Check clip (fixed base at x = -70, facing +X)."""
import argparse, json, os, struct, sys, time
import numpy as np
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
MAIN = './'
sys.path.insert(0, REPO + 'tools')
import mocap, clips, tapes, reflog
sys.path.insert(0, REPO + 'tools')   # reflog puts the main checkout first: this checkout's add_clips / do_fighter win

PBASE = {'P1': reflog.P1, 'P2': reflog.P2}
# player struct segments appended after the part records: motion block, feet position, facing, and the model's base
# matrix +0x06C (4x4 row vectors, translation = the feet at +0x09C): the yaw the game draws the body with. +0x7248 is
# NOT it during attacks (Ryoma's k1/24 kick turns the body to the opponent while +0x7248 stays put)
PSEGS = [(0x7190, 0x30), (0x020, 12), (0x7248, 4), (0x06C, 64)]
CAPS = os.environ.get('PS_FIGHTCAPS', os.environ.get('LANE_TMP', '/tmp/ps-') + '/fightcaps').rstrip('/') + '/'
PAD = 12


def tape_path(t):
    return t if os.path.exists(t) else REPO + f'game/tests/tapes/{t}.tape'


def tape_name(t):
    return os.path.splitext(os.path.basename(t))[0]


def split_id(i):
    return int(i[1]), int(i[3:])


def fighter_of(slot, tape):
    m = tapes.meta(tape_path(tape))
    who = m[slot.lower()]
    return who, reflog.IDS.index(who)


def runs(kind, mot, fr, k, m):
    """[(first row, length, first count)] of rows where (kind, mot) == (k, m) and the counter goes +1 per row"""
    out, cur = [], None
    for i in range(len(kind)):
        if kind[i] == k and mot[i] == m:
            if cur and i == cur[0] + cur[1] and fr[i] == fr[i - 1] + 1: cur[1] += 1
            else:
                cur = [i, 1, int(fr[i])]; out.append(cur)
        else: cur = None
    return [tuple(r) for r in out]


def period(kind, mot, fr, k, m):
    """loop period: the count reached before the counter wrapped to 0 with the id held (None if it never wrapped)"""
    for i in range(1, len(kind)):
        if kind[i] == k and mot[i] == m and kind[i - 1] == k and mot[i - 1] == m and fr[i] == 0 and fr[i - 1] > 0:
            return int(fr[i - 1]) + 1
    return None


def window(tape, slot, ids):
    """tape rows to capture: the wanted ids' rows in the disc log (+-PAD), longest run per id + one loop period"""
    p = MAIN + f'dumps/fidelity/o_{tape_name(tape)}.jsonl'
    if not os.path.exists(p): return None
    rows = [json.loads(l) for l in open(p)]
    pi = 0 if slot == 'P1' else 1
    kind = [r['p'][pi]['kind'] for r in rows]; mot = [r['p'][pi]['mot'] for r in rows]; fr = [r['p'][pi]['fr'] for r in rows]
    lo, hi = len(rows), 0
    for i in ids:
        k, m = split_id(i)
        rr = runs(kind, mot, fr, k, m)
        if not rr: print('not in the disc log:', i, flush=True); continue
        per = period(kind, mot, fr, k, m)
        best = max(rr, key=lambda r: r[1])
        lo = min(lo, rr[0][0]); hi = max(hi, best[0] + best[1] + (per or 0))
    return (max(0, lo - PAD), min(len(rows), hi + PAD)) if hi else None


def pick_records(ram_path, mdl_path, slot):
    """part records of the SLOT fighter: every loaded copy of its MDL x every record group, the group whose root world
    matrix sits nearest that player's feet position in the same dump"""
    ram = open(ram_path, 'rb').read()
    pb = PBASE[slot] - mocap.B
    feet = np.array(struct.unpack_from('<3f', ram, pb + 0x20))
    best = None
    for which in range(4):
        try:
            parts, base, recs = mocap.find_records(ram, mdl_path, which)
        except IndexError:
            break
        for root in sorted(recs.get(0, [])):
            W = np.array(struct.unpack_from('<16f', ram, root - 0x40 - mocap.B)).reshape(4, 4)
            dist = float(np.linalg.norm(W[3, [0, 2]] - feet[[0, 2]]))
            if best is None or dist < best[0]:
                pick = []
                for k in range(len(parts)):
                    c = sorted(recs.get(k, []), key=lambda r: abs(r - root))
                    pick.append(c[0] if c and abs(c[0] - root) < 0x8000 else None)
                best = (dist, which, base, pick)
    dist, which, base, pick = best
    return dict(mdl=os.path.basename(mdl_path), base=hex(base), which=which, root_dist_cm=round(dist, 1),
                parts=[hex(r) if r else None for r in pick])


def seg_string(sj, slot):
    s = [f'0x{int(r, 16) - 0x40:08X}:{mocap.SEG}' for r in sj['parts'] if r]
    s += [f'0x{PBASE[slot] + o:08X}:{n}' for o, n in PSEGS]
    return ','.join(s)


def capture(slot, tape, ids, lo=None, hi=None, inst=None):
    from fcinst import Inst
    who, n = fighter_of(slot, tape)
    m = tapes.meta(tape_path(tape))
    name = f'{tape_name(tape)}_{slot.lower()}'
    os.makedirs(CAPS, exist_ok=True)
    txt = CAPS + f'{tape_name(tape)}.txt'
    N = tapes.build(tape_path(tape), txt)
    if lo is None:
        w = window(tape, slot, ids)
        lo, hi = w if w else (0, N)
    hi = min(hi, N)
    fi = Inst(inst or os.environ.get('PS_FC_INST', 'cap1'))
    try:
        reflog.boot(fi, m['p1'], m['p2'])
        fi.fc([f'dump {name}_ram.bin 0x0C000000 0x1000000'], 60)
        fi.wait_idle(60); time.sleep(1)
        os.replace(fi.root + f'{name}_ram.bin', CAPS + f'{name}_ram.bin')
        import ladder
        opp, stg = ladder.who(CAPS + f'{name}_ram.bin')
        sj = pick_records(CAPS + f'{name}_ram.bin', MAIN + f'rip/fs/P{n:X}0.MDL', slot)
        segs = seg_string(sj, slot)
        # the capseg starts as a row command of tape row lo-1: its first frame = tapelog row lo (checked in cut)
        rows = open(txt).read().splitlines()
        k = max(lo - 1, 0)
        rows[k] += f' ; capseg {name} {hi - k - 1} {segs}'
        ptxt = CAPS + f'{name}.txt'
        open(ptxt, 'w').write('\n'.join(rows) + '\n')
        lines = [f'freeze8 0x{reflog.P2 + 0x71ED:08X} 0', f'freeze8 0x{reflog.P1 + 0x71ED:08X} 0',
                 'until8 0x0C7F302C 3 6000', 'poke32 0x0C346A50 1', f'lua {REPO}tools/fight_clips.lua',
                 f'tapelog {name}_log {reflog.segs()}', f'tape {ptxt}']
        t0 = time.time()
        fi.fc(lines, 60)
        fi.wait_idle(N / 60 * 8 + 600)
        time.sleep(1)
        os.replace(fi.root + f'cap/{name}.bin', CAPS + f'{name}.bin')
        os.replace(fi.root + f'cap/{name}_log.bin', CAPS + f'{name}_log.bin')
        log = reflog.decode(CAPS + f'{name}_log.bin')
        reflog.write_jsonl(log, CAPS + f'{name}_log.jsonl')
        sj.update(slot=slot, fighter=who, tape=tape_name(tape), tape_rows=N, rows=[k + 1, hi], ids=ids, opp=opp,
                  stage=stg.lower(), psegs=[[hex(o), l] for o, l in PSEGS], secs=round(time.time() - t0))
        json.dump(sj, open(CAPS + f'{name}.json', 'w'), indent=1)
        print(name, sj['mdl'], 'root', sj['root_dist_cm'], 'cm from the feet; rows', k + 1, '..', hi, 'stage', stg,
              'opp', opp, f"{sj['secs']} s", flush=True)
    finally:
        fi.stop()
    return CAPS + f'{name}.json'


def decode(slot, tape):
    name = f'{tape_name(tape)}_{slot.lower()}'
    sj = json.load(open(CAPS + f'{name}.json'))
    present = [k for k, r in enumerate(sj['parts']) if r]
    n = len(sj['parts'])
    raw = open(CAPS + f'{name}.bin', 'rb').read()
    psegs = [(int(o, 16), l) for o, l in sj['psegs']]
    at, a = {}, len(present) * mocap.SEG
    for o, l in psegs: at[o] = a; a += l
    fsz = a
    F = len(raw) // fsz
    W = np.zeros((F, n, 4, 4), np.float64)
    kind = np.zeros(F, int); mot = np.zeros(F, int); fr = np.zeros(F, int); st = np.zeros(F, int)
    pos = np.zeros((F, 3)); ang = np.zeros(F, int); base = np.zeros((F, 4, 4))
    for f in range(F):
        o = f * fsz
        for j, k in enumerate(present):
            W[f, k] = np.array(struct.unpack_from('<16f', raw, o + j * mocap.SEG)).reshape(4, 4)
        b = o + at[0x7190]
        fr[f] = struct.unpack_from('<H', raw, b + 0x0E)[0]
        kind[f], mot[f] = raw[b + 0x14], raw[b + 0x15]
        st[f] = raw[b + 0x2A]
        pos[f] = struct.unpack_from('<3f', raw, o + at[0x020])
        ang[f] = struct.unpack_from('<H', raw, o + at[0x7248])[0]
        if 0x06C in at:
            base[f] = np.array(struct.unpack_from('<16f', raw, o + at[0x06C])).reshape(4, 4)
            base[f][:, 3] = (0, 0, 0, 1)
        else:   # older captures: feet + the +0x7248 facing
            base[f] = clips.mchar(int(ang[f]), tuple(pos[f]))
    d = dict(W=W, kind=kind, mot=mot, fr=fr, st=st, pos=pos, ang=ang, base=base, sj=sj, row0=sj['rows'][0])
    # alignment + determinism: this capture's motion fields vs the tapelog of the same run and the disc's o_ log
    pi = 0 if slot == 'P1' else 1
    for lp in (CAPS + f'{name}_log.jsonl', MAIN + f"dumps/fidelity/o_{sj['tape']}.jsonl"):
        if not os.path.exists(lp): continue
        L = [json.loads(x) for x in open(lp)]
        best = None
        for sh in range(-3, 4):
            r0 = d['row0'] + sh
            ok = sum(1 for f in range(F) if 0 <= r0 + f < len(L) and (L[r0 + f]['p'][pi]['kind'], L[r0 + f]['p'][pi]['mot'],
                     L[r0 + f]['p'][pi]['fr']) == (kind[f], mot[f], fr[f]))
            if best is None or ok > best[1]: best = (sh, ok)
        d.setdefault('check', []).append((os.path.basename(lp), best[0], best[1], F))
    return d


def cut_one(d, skel, k, m, c0=1):
    """clip frame 0 = motion count c0 (1 = the Motion Check clips' convention: they start one frame after set_motion,
    the remaster reads hit steps at clip frame + 1). One-shot: counts c0..last of the longest run + the last pose held
    once (= Motion Check's stopped playhead), so a clip is last + 1 frames like the Motion Check ones. Loop: one period
    from count c0 round to count c0 - 1."""
    rr = runs(d['kind'], d['mot'], d['fr'], k, m)
    if not rr: return None
    per = period(d['kind'], d['mot'], d['fr'], k, m)
    s, length, f0 = max(rr, key=lambda r: r[1])
    loop = False
    held = set(int(d['fr'][g]) for g in range(len(d['kind'])) if d['kind'][g] == k and d['mot'][g] == m)
    if per and all(c in held for c in range(per)):     # every count of one period was seen (a walk restarts at 1)
        # the game blends the first ~3 frames after a motion switch (k1/24 > k0/0: 25 deg, 0.03 from frame 3 on), so
        # each count comes from the row held longest (a later cycle of the same hold where there is one)
        hold = np.zeros(len(d['kind']), int)
        for i in range(1, len(hold)):
            if d['kind'][i] == d['kind'][i - 1] and d['mot'][i] == d['mot'][i - 1]: hold[i] = hold[i - 1] + 1
        rows = []
        for i in range(per):
            c = (c0 + i) % per
            cand = [g for g in range(len(hold)) if d['kind'][g] == k and d['mot'][g] == m and d['fr'][g] == c]
            rows.append(max(cand, key=lambda g: hold[g]))
        loop = True
    else:
        rows = [s + i for i in range(length) if f0 + i >= c0] or [s]
        rows.append(rows[-1])
    # parts the game does not pose in this motion (a fight never zero-scales them like Motion Check does: their world
    # matrix just stays as it was while the root moves = not drawn, e.g. the unselected hand variants, Ryoma's sword
    # while he holds an item): posed at their rest offset on the parent (= a hidden part in a Motion Check clip), so
    # their children stay right; listed as 'stale' in the index
    par = skel['parent']
    n = d['W'].shape[1]
    Wall = d['W']
    seen = sorted(set(rows))
    act = np.zeros((len(seen), n), bool)
    for f, g in enumerate(seen):
        for j in range(n):
            if abs(np.linalg.det(Wall[g, j, :3, :3])) < 1e-3: continue
            if par[j] < 0 or g == 0: act[f, j] = True; continue
            act[f, j] = not (np.abs(Wall[g, j] - Wall[g - 1, j]).max() < 1e-7 and      # unchanged while the root moved
                             np.abs(Wall[g, 0] - Wall[g - 1, 0]).max() > 1e-5)
    live = np.abs(np.linalg.det(Wall[seen][:, :, :3, :3])).min(0) > 1e-3
    stale = [j for j in range(n) if live[j] and par[j] >= 0 and act[:, j].mean() < 0.5]
    W = Wall[rows].copy()
    L = len(rows)
    for j in sorted(stale, key=lambda j: (depth(par, j), j)):
        T = np.eye(4); T[3, :3] = skel['offset'][j]
        for f in range(L): W[f, j] = T @ W[f, par[j]]
    sel = None
    if n >= 10 and [par[j] for j in range(n - 10, n)] == [4, 4, 8, 8, 8, 8, 12, 12, 12, 12]:
        sel = [int(np.argmax([act[:, j].mean() for j in grp])) for grp in
               (range(n - 10, n - 8), range(n - 8, n - 4), range(n - 4, n))]
    # base per frame = the player's model matrix (feet + drawn yaw); W' = W inv(B) M keeps every local rotation and
    # puts the root relative to B (clips.to_clip takes the root relative to M)
    M = clips.mchar()
    for f in range(L):
        W[f] = W[f] @ np.linalg.inv(d['base'][rows[f]]) @ M
    q, t, err, tl, free = clips.to_clip({'W': W}, skel, 0, L, M)
    info = dict(src=f"fight:{d['sj']['tape']}:{d['sj']['slot']}", start=int(d['row0'] + rows[0]), frames=int(L),
                loop=bool(loop), offset_err=round(err, 3), free=free, ph0=int(d['fr'][rows[0]]),
                root_y=[round(float(t[:, 1].min()), 1), round(float(t[:, 1].max()), 1)],
                runs=[[int(d['row0'] + a), int(b), int(c)] for a, b, c in rr], period=per,
                states=sorted(set(int(d['st'][g]) for g in seen)), stale=stale,
                next=None if loop or s + length >= len(d['kind']) else [int(d['kind'][s + length]), int(d['mot'][s + length])])
    if sel is not None: info['sel'] = sel
    return q, t, tl, free, loop, info


def depth(par, k):
    n = 0
    while par[k] >= 0: k = par[k]; n += 1
    return n


def cut(slot, tape, ids, prefix, out):
    who, n = fighter_of(slot, tape)
    d = decode(slot, tape)
    for c in d.get('check', []): print('frame check', c[0], 'shift', c[1], 'match', c[2], '/', c[3], flush=True)
    skel = json.load(open(MAIN + f'rip/skel/p{n:x}0.json'))
    os.makedirs(out, exist_ok=True)
    ip = out + '/index.json'
    index = json.load(open(ip)) if os.path.exists(ip) else {}
    for i in ids:
        k, m = split_id(i)
        r = cut_one(d, skel, k, m)
        if r is None:
            print(prefix + i, 'NOT in the capture', flush=True); continue
        q, t, tl, free, loop, info = r
        bad = (not np.all(np.isfinite(q))) or (not np.all(np.isfinite(t))) or np.abs(np.linalg.norm(q, axis=2) - 1).max() > 1e-3
        info['sane'] = not bad
        np.savez_compressed(f'{out}/{prefix}{i}.npz', q=q.astype(np.float32), t=t.astype(np.float32), loop=loop,
                            tl=tl[:, free].astype(np.float32), free=np.array(free, dtype=np.int32))
        index[prefix + i] = info
        print(prefix + i, info, flush=True)
    json.dump(index, open(ip, 'w'), indent=1)
    return index


def compare(slot, tape, ids, prefix, c0=1):
    """in-fight cut vs the Motion Check clip of the same id (game joints 0-18 and every part both show), best of
    clip offsets -2..2 (one-shots; 0 = the same convention) or of every phase (Motion Check loops)"""
    who, n = fighter_of(slot, tape)
    d = decode(slot, tape)
    skel = json.load(open(MAIN + f'rip/skel/p{n:x}0.json'))
    cd = os.environ.get('PS_MOCAP', MAIN + 'rip/mocap/').rstrip('/') + f'/clips_p{n:x}'
    hid = set(skel.get('hidden', []) + skel.get('missing', []))
    res = {}
    for i in ids:
        k, m = split_id(i)
        r = cut_one(d, skel, k, m, c0)
        if r is None or not os.path.exists(f'{cd}/{prefix}{i}.npz'):
            print(prefix + i, 'nothing to compare'); continue
        q, t = r[0], r[1]
        mc = np.load(f'{cd}/{prefix}{i}.npz'); qm, tm = mc['q'], mc['t']
        # parts Motion Check shows (non-identity somewhere) and not hidden
        shown = [j for j in range(q.shape[1]) if j not in hid and np.abs(qm[:, j, :3]).max() > 1e-6]
        best = None
        mloop = bool(mc['loop'])
        for o in (range(len(qm)) if mloop else range(-2, 3)):   # a Motion Check loop starts on any phase
            if mloop:
                L = min(len(q), len(qm)); a0 = 0; mi = (np.arange(L) + o) % len(qm)
            else:
                a0, b0 = max(0, o), max(0, -o)
                L = min(len(q) - a0, len(qm) - b0); mi = np.arange(b0, b0 + max(L, 0))
            if L < 4: continue
            dot = np.abs(np.sum(q[a0:a0 + L] * qm[mi], axis=2)).clip(0, 1)
            ang = np.degrees(2 * np.arccos(dot))
            core = ang[:, [j for j in range(19) if j in shown]]
            allp = ang[:, shown]
            nohead = ang[:, [j for j in shown if j != 4]]
            dt = np.abs(t[a0:a0 + L] - tm[mi]).max()
            e = (float(np.median(allp)), float(core.max()), float(allp.max()), float(nohead.max()), float(ang[:, 4].max()),
                 float(dt), o, L)
            if best is None or e[0] < best[0]: best = e
        if best is None:
            print(prefix + i, 'too short to compare'); continue
        # joint 4 = the head: in a fight the original turns it to the opponent on top of idle / hold motions
        res[prefix + i] = dict(median_deg=round(best[0], 3), core_max_deg=round(best[1], 2), all_max_deg=round(best[2], 2),
                               max_without_head_deg=round(best[3], 2), head_max_deg=round(best[4], 2),
                               root_max_cm=round(best[5], 2), offset=best[6], frames=best[7], fight_frames=len(q),
                               mc_frames=len(qm))
        print(prefix + i, res[prefix + i], flush=True)
    return res


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd'); ap.add_argument('slot'); ap.add_argument('tape'); ap.add_argument('ids')
    ap.add_argument('prefix', nargs='?'); ap.add_argument('out', nargs='?')
    ap.add_argument('--from', dest='lo', type=int); ap.add_argument('--to', dest='hi', type=int)
    a = ap.parse_args()
    ids = a.ids.split(',')
    slot = a.slot.upper()
    if a.cmd == 'capture':
        capture(slot, a.tape, ids, a.lo, a.hi)
    elif a.cmd == 'cut':
        cut(slot, a.tape, ids, a.prefix, a.out)
    elif a.cmd == 'compare':
        compare(slot, a.tape, ids, a.prefix)
    elif a.cmd == 'build':
        import add_clips
        who, n = fighter_of(slot, a.tape)
        pre = (a.out or f"{os.environ.get('PS_TMP', '/tmp')}/fightclips_{a.prefix}").rstrip('/')
        cut(slot, a.tape, ids, a.prefix, pre)
        add_clips.build(n, a.prefix, ids, pre=pre)
