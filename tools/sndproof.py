#!/usr/bin/env python3
"""BUG-36 proof: the disc's key-ons for a tape (tools/sndlog.py + sndmap.py) vs the samples the remaster started for the
same tape (PS_SFX_LOG of game/scripts/sfx_map.gd in game/tests/tape_run.gd). The announcer (NA bank) is left out: the
round flow says those lines (fight.gd). A disc key-on matches a remaster start of the same sample id (STGn0_xxx = STG_xxx)
at the same tape frame (exact) or within +-W frames (one remaster start matches one key-on at most).
  sndproof.py run NAME [NAME ...]   (remaster: $SND_RM/NAME.sfx; tools/snd_proof.sh writes them)
  sndproof.py rm NAME               run the remaster tape (headless Godot) for NAME"""
import collections, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndmap as S
import sndcues as C
import tapes

RM = os.environ.get('SND_RM', '/tmp/ps-fx-snd/rm/')
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
W = 3


def disc(name):
    banks, ev, rows = S.load(name)
    return [(e['f'], C.sid(e['bank'], e['s'])) for e in ev if e['bank'] not in ('NA', '?') and e['f'] >= 1]   # '?' = the music stream


def remaster(name):
    out = []
    for ln in open(RM + name + '.sfx'):
        w = ln.split()
        if len(w) >= 3 and int(w[0]) >= 1: out.append((int(w[0]), w[2]))
    return out


def match(d, r, w, only=None):
    used = [False] * len(r)
    hit = 0
    for i, (f, s) in enumerate(d):
        if only is not None and i not in only: continue
        best = None
        for j, (g, t) in enumerate(r):
            if not used[j] and t == s and abs(g - f) <= w and (best is None or abs(g - f) < abs(r[best][0] - f)): best = j
        if best is not None: used[best] = True; hit += 1
    return hit, used.count(False)


def aligned(name, d):
    """indices of the disc key-ons whose cue fighter shows the SAME motion (kind, id) in the remaster's tape log on that
    frame: what the sound module can be judged on when the remaster's motion timing differs (a gameplay gap, not sound)"""
    m = json.load(open(C.MAP))
    rows = [json.loads(l) for l in open(S.OUT + name + '.jsonl')]
    rr = [json.loads(l) for l in open(RM + name + '.jsonl')]
    r = C.load_run(name)
    out = set()
    for i, (f, s) in enumerate(d):
        if f >= len(rows) or f >= len(rr): continue
        for p in (0, 1):
            a, b = rows[f]['p'][p], rr[f]['p'][p]
            c = m['motion'].get(r['who'][p], {}).get(C.mkey(a), {}).get(str(a['fr']))
            h = any(rows[f]['p'][v]['hp'] < rows[f - 1]['p'][v]['hp'] for v in (0, 1))
            if (c and s in c['pick'] and (a['kind'], a['mot']) == (b['kind'], b['mot'])) or \
                    (h and any(rr[g]['p'][v]['hp'] < rr[g - 1]['p'][v]['hp'] for v in (0, 1) for g in range(max(1, f - W), min(len(rr), f + W + 1)))):
                out.add(i); break
    return out


def run_rm(name):
    meta = json.load(open(S.OUT + name + '.meta.json'))
    tm = tapes.meta(S.WT + f'game/tests/tapes/{name}.tape')
    os.makedirs(RM, exist_ok=True)
    env = dict(os.environ, PS_SFX_LOG=RM + name + '.sfx')
    cmd = [GODOT, '--headless', '--path', S.WT + 'game', '--fixed-fps', '60', '-s', 'res://tests/tape_run.gd', '--',
           S.OUT + f'tapes/{name}.txt', RM + name + '.jsonl', meta['stage'], f"{tm['p1']},{tm['p2']}", S.OUT + name + '.jsonl']
    subprocess.run(cmd, env=env, stdout=open(RM + name + '.log', 'w'), stderr=subprocess.STDOUT, timeout=1500)


if __name__ == '__main__':
    if sys.argv[1] == 'rm':
        for n in sys.argv[2:]: run_rm(n)
        sys.exit()
    tot = collections.Counter()
    print(f"{'tape':16} {'disc':>5} {'exact':>6} {'+-%d' % W:>6} {'extra':>6} | {'same-motion':>11} {'exact':>6} {'+-%d' % W:>6}")
    for n in sys.argv[2:]:
        d, r = disc(n), remaster(n)
        e, _ = match(d, r, 0)
        m, x = match(d, r, W)
        al = aligned(n, d)
        ae, _ = match(d, r, 0, al)
        am, _ = match(d, r, W, al)
        tot.update(disc=len(d), exact=e, near=m, extra=x, al=len(al), ae=ae, am=am)
        print(f'{n:16} {len(d):5d} {100 * e / max(1, len(d)):5.1f}% {100 * m / max(1, len(d)):5.1f}% {x:6d} | {len(al):11d} '
              f'{100 * ae / max(1, len(al)):5.1f}% {100 * am / max(1, len(al)):5.1f}%')
    d, a = tot['disc'], tot['al']
    print(f"{'ALL':16} {d:5d} {100 * tot['exact'] / max(1, d):5.1f}% {100 * tot['near'] / max(1, d):5.1f}% {tot['extra']:6d} | "
          f"{a:11d} {100 * tot['ae'] / max(1, a):5.1f}% {100 * tot['am'] / max(1, a):5.1f}%")
