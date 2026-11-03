#!/usr/bin/env python3
"""Which (kind, motion) the ORIGINAL plays per fighter (reference tape logs dumps/fidelity/o_*.jsonl + the original's
CPU-vs-CPU logs CPU_LOGDIR/cpu_*.jsonl) vs the clips the remaster has (rip/mocap/clips_pN/index.json = what the GLBs
export), and which of the missing ones Motion Check can play (non-zero in the fighter's Pn0_MOT.MDT kind table, or id 0).
The stage camera logs (dumps/cap/cl*, cm*) hold no motion fields, so they add nothing here.
  clip_inventory.py [md OUT.md] [todo OUT.json]"""
import collections, glob, json, os, struct, sys
R = os.environ.get('PS_ROOT', './')
MAIN = './'
sys.path.insert(0, MAIN + 'tools')
import tapes
CPU = os.environ.get('CPU_LOGDIR', '/tmp/ps-fx-cpu/logs/')
MOCAP = os.environ.get('PS_MOCAP', R + 'rip/mocap/')
NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
# what the ported reaction machine (docs/REACT.md) plays: class-0 tables (+1, +2), launches, tumble, splat, lying, dizzy
REACT = sorted({b + i for b in (0, 3, 6, 9, 12, 15, 18, 21, 27, 33, 36, 39, 42, 45, 48, 51, 60, 63, 69, 75) for i in range(3)}
               | {96, 97, 98, 99, 111, 112, 115, 117, 128, 129, 130, 131, 144, 145, 146, 147, 152, 153, 163, 173, 175})


def mdt(n, kind):
    b = open(MAIN + f'rip/fs/P{n:X}0_MOT.MDT', 'rb').read()
    if (kind + 1) * 0x200 > len(b): return set()
    return {i for i, v in enumerate(struct.unpack_from('>256H', b, kind * 0x200)) if v} | {0}


def played():
    out = {n: collections.defaultdict(lambda: [0, 0, set()]) for n in NAMES}

    def scan(rows, who, src):
        for v in (0, 1):
            if who[v] not in out: continue
            prev = None
            for r in rows:
                p = r['p'][v]; key = (p['kind'], p['mot'])
                e = out[who[v]][key]; e[1] += 1; e[2].add(src)
                if key != prev: e[0] += 1
                prev = key
    for f in sorted(glob.glob(MAIN + 'dumps/fidelity/o_*.jsonl')):
        t = os.path.basename(f)[2:-6]; src = MAIN + f'game/tests/tapes/{t}.tape'
        if not os.path.exists(src): continue
        m = tapes.meta(src)
        scan([json.loads(l) for l in open(f)], (m.get('p1'), m.get('p2')), 'tape ' + t)
    for f in sorted(glob.glob(CPU + 'cpu_*.jsonl')):
        m = json.load(open(f[:-6] + '.meta.json'))
        scan([json.loads(l) for l in open(f)], (m['p1'], m['p2']), 'cpu ' + os.path.basename(f)[4:-6])
    return out


def have(n):
    f = MOCAP + f'clips_p{n:x}/index.json'
    idx = json.load(open(f)) if os.path.exists(f) else {}
    s, pre = set(), None
    for k, v in idx.items():
        for name in (k, v.get('src', k)):
            if len(name) >= 8 and name[2] == 'k' and name[3].isdigit():
                s.add((int(name[3]), int(name[5:8]))); pre = name[:2]
    return pre, s


def kind4_section():
    """Throws (game/assets/fidelity/throws.json, tools/throw_table.py): which kind-4 ids are reachable in Motion Check."""
    f = next((p for p in (R + 'game/assets/fidelity/throws.json', MAIN + 'game/assets/fidelity/throws.json') if os.path.exists(p)), None)
    if not f: return []
    th = json.load(open(f))
    L = ['', '## Throws (kind 4)', '',
         "A throw's victim motions sit in the THROWER's Pn0_MOT.MDT kind-4 table (e.g. Falcon's table holds his own k4/0",
         'slot and the victim id 49; no fighter has another thrower\'s victim ids), and the game plays them on the victim\'s',
         "skeleton. So they are captured on the thrower in Motion Check (pass C: the fighter's whole kind-4 table + id 0)",
         'and tools/victim_clips.py copies them onto every fighter like the game does (joints 0-18 local rotations + the',
         'root channel; the victim\'s other parts at his idle pose): clip <victim prefix>k4_<id>_<thrower prefix>, e.g.',
         'r0k4_049_f0 = Ryoma thrown by Falcon. Slot 0 is the first entry of every table (offset 0), so k4/0 is real.', '',
         '| thrower | thrower chain (k4) | victim chain (k4) | MDT kind-4 table | not in the table |', '|---|---|---|---|---|']
    for n, nm in enumerate(NAMES):
        t4 = sorted(mdt(n, 4))
        thr = [m[2] for m in th.get(nm, {}).get('thrower', []) if m[1] == 4]
        vic = [m[2] for m in th.get(nm, {}).get('victim', []) if m[1] == 4]
        miss = [i for i in thr + vic if i not in t4]
        L.append(f"| {nm} | {', '.join(map(str, thr)) or '(no throw logged)'} | {', '.join(map(str, vic)) or '-'} | "
                 f"{', '.join(map(str, t4))} | {', '.join(map(str, miss)) or '-'} |")
    L += ['', 'Ayame\'s and Rouge\'s thrower motion k4/1 is not in their kind-4 table: captured anyway (Motion Check may',
          'fall back to another slot: check the clip before trusting it). The victim chains also use k2/111, k2/117 (thrown',
          'flight), k2/96, k2/131, k2/152/153, k2/144/145 (all in pass A).']
    return L


def main(a):
    P = played()
    rows, todo = [], {}
    for n, nm in enumerate(NAMES):
        pre, hv = have(n)
        miss = sorted((k for k in P[nm] if k not in hv), key=lambda x: x)
        cap = [k for k in miss if k[1] in mdt(n, k[0]) and k[0] in (0, 1, 2, 3)]
        no = [k for k in miss if k not in cap]
        todo[nm] = {'n': n, 'prefix': pre, 'capture': [f'k{k}_{m:03d}' for k, m in sorted(cap, key=lambda x: (x[0] != 2 or x[1] not in REACT, x))]}
        rows.append((nm, pre, len(hv), len(P[nm]), miss, cap, no, P[nm]))
    if 'todo' in a: json.dump(todo, open(a[a.index('todo') + 1], 'w'), indent=1)
    if 'md' in a:
        L = ['# Clips: what the original plays vs what the remaster has', '',
             'Generated by `tools/clip_inventory.py md docs/CLIPS.md` (fx-react, 2026-10-27). Played = every (kind, motion) a',
             "fighter shows in the original's per-frame logs: the 31 reference tapes (dumps/fidelity/o_*.jsonl) and the 16",
             "CPU-vs-CPU logs (fx-cpu logs/cpu_*.jsonl). Have = clips in rip/mocap/clips_pN (exported to pN0.glb / pN1.glb).",
             'Capturable = non-zero in the fighter\'s Pn0_MOT.MDT kind table (Motion Check plays it). The stage camera logs',
             '(dumps/cap/cl*, cm*) carry no motion fields. Kind 2 = the shared bank (hit reactions, knockdowns, items, poles),',
             'kind 4 = being thrown (only the ids in the fighter\'s own MDT kind-4 table are playable in Motion Check).',
             '"(frames)" = logged frames in that motion. ★ = played by the ported reaction machine (docs/REACT.md).', '',
             '| fighter | prefix | clips | played | missing | capturable |', '|---|---|---|---|---|---|']
        for nm, pre, h, p, miss, cap, no, _ in rows:
            L.append(f'| {nm} | {pre} | {h} | {p} | {len(miss)} | {len(cap)} |')
        for nm, pre, h, p, miss, cap, no, pl in rows:
            L += ['', f'## {nm} ({pre})', '']
            f = lambda k: f"k{k[0]}/{k[1]}{'★' if k[0] == 2 and k[1] in REACT else ''} ({pl[k][1]})"
            L.append('Capturable: ' + (', '.join(f(k) for k in cap) or '-'))
            L.append('')
            L.append('Not in Motion Check (MDT slot empty): ' + (', '.join(f(k) for k in no) or '-'))
        L += kind4_section()
        open(a[a.index('md') + 1], 'w').write('\n'.join(L) + '\n')
    for nm, pre, h, p, miss, cap, no, _ in rows:
        print(f'{nm:12s} {pre} have {h:3d} played {p:3d} missing {len(miss):3d} capturable {len(cap):3d}')


if __name__ == '__main__':
    main(sys.argv[1:])
