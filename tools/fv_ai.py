#!/usr/bin/env python3
"""Final Valgas's own AI (1ST_READ 0x0C08D5CE, docs/CPU.md "Final Valgas port"): every table it reads, straight out of
1ST_READ.BIN -> game/assets/fidelity/fv_ai.json (read by game/scripts/cpu_fv.gd).
  fv_ai.py export        write the json
  fv_ai.py dis           print the command lists in words
Command list bytes (reader 0x0C08D33C; hi/lo words are (s8 hi << 8 | s8 lo) & 0xFFFF):
  00 hi lo   stand N frames (N 0 = from STAND[level bucket][rnd 16]); ends early when the zone class changes
  01 hi lo   steer toward the opponent N frames (N 0 = STEER[zone][rnd 16]); ends when the zone <= THR[rnd 16]
  0A hi lo   the same, away from him
  02 a hi lo b   press PADW[a] (pressed + held that frame), after N frames PADW[b], until his state leaves 11
  03         PCT[0x0C150774]: switch to the zone lists (state 1), else go on
  04 n m     wait n + rnd(m) + WAITADD[band] + 1 frames
  05         PCT[ZONE_PCT[zone]]: state 1 (zone lists), else reset (state 0, start list)
  06         +0x7204 = 2 (one frame), until his state leaves 33
  07 / 08    lock on / off (block +0x1E: no interrupts, no health-band re-pick)
  09         clear the interrupt latches and the lock
  other      reset (state 0)"""
import json, os, struct, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
B = open('./rip/fs/1ST_READ.BIN', 'rb').read()
BASE = 0x0C010000
OUT = os.path.join(ROOT, 'game/assets/fidelity/fv_ai.json')


def u8(a): return B[a - BASE]
def s8(a): v = B[a - BASE]; return v - 256 if v > 127 else v
def u16(a): return struct.unpack_from('<H', B, a - BASE)[0]
def u32(a): return struct.unpack_from('<I', B, a - BASE)[0]
def f32(a): return struct.unpack_from('<f', B, a - BASE)[0]
def w16(hi, lo): return ((hi << 8) | (lo & 0xFFFFFFFF)) & 0xFFFF   # s8 hi << 8 | s8 lo, as the reader builds it


def parse(a):
    """Command list at a -> (bytes up to and including the terminator, readable ops)."""
    out, ops = [], []
    while True:
        c = s8(a)
        if c in (0, 1, 10):
            n = w16(s8(a + 1), s8(a + 2)); out += [u8(a), u8(a + 1), u8(a + 2)]
            ops.append({0: f'stand {n}', 1: f'steer+ {n}', 10: f'steer- {n}'}[c]); a += 3
        elif c == 2:
            n = w16(s8(a + 2), s8(a + 3)); out += [u8(a + k) for k in range(5)]
            ops.append(f'press {s8(a + 1)} {n} {s8(a + 4)}'); a += 5
        elif c == 4:
            out += [u8(a), u8(a + 1), u8(a + 2)]; ops.append(f'wait {s8(a + 1)}+rnd{s8(a + 2)}'); a += 3
        elif c in (3, 6, 7, 8, 9):
            out.append(u8(a)); ops.append({3: 'maybe-zone', 6: 'special', 7: 'lock', 8: 'unlock', 9: 'clear'}[c]); a += 1
        else:
            out.append(u8(a)); ops.append('zone-or-reset' if c == 5 else f'reset({c})')
            return out, ops


def export():
    d = {'source': 'tools/fv_ai.py (1ST_READ.BIN, Final Valgas AI 0x0C08D5CE)'}
    d['padw'] = [u32(0x0C3383CC + 4 * i) for i in range(9)]
    d['tc'] = [s8(0x0C3383F9 - k) for k in range(10)]           # by clock / 10 (0x0C3383F9 - k)
    d['th'] = [s8(0x0C3383FA + 20 - h) for h in range(21)]      # by (240 + own - opp health) / 24
    lists, names = {}, {}

    def L(a):
        if a not in lists:
            lists[a] = parse(a)
        return f'{a:08X}'
    d['start'] = L(0x0C33852C)
    d['item'] = [L(0x0C338410), L(0x0C338412)]
    d['opp13'] = [L(u32(0x0C33844C + 4 * z)) for z in range(6)]
    d['opp23'] = [L(u32(0x0C338484 + 4 * z)) for z in range(6)]
    d['far_hit'] = [L(u32(0x0C3384F4 + 4 * i)) for i in range(4)]
    d['thr'] = [s8(0x0C338504 + i) for i in range(16)]
    d['wait_add'] = [s8(0x0C338514 + i) for i in range(4)]
    pct = lambda a: [u8(a + i) for i in range(-11, 12)]   # index (level - 20) % 12 + 11 (C remainder)
    d['pct_zone'] = [pct(u32(0x0C338540 + 4 * z)) for z in range(6)]
    d['pct_opp13'], d['pct_opp23'], d['pct_far_hit'], d['pct_maybe'] = (pct(0x0C150630), pct(0x0C15063C),
                                                                         pct(0x0C150648), pct(0x0C150774))
    d['stand_n'] = [[u16(0x0C150654 + 32 * b + 2 * i) for i in range(16)] for b in range(3)]
    d['steer_n'] = [[u16(0x0C1506B4 + 32 * z + 2 * i) for i in range(16)] for z in range(6)]
    d['dir'] = [[u32(0x0C1505F0 + 32 * w + 4 * i) for i in range(8)] for w in range(2)]
    rows, zl = [], []
    for z in range(6):
        r = u32(0x0C338A80 + 4 * z)
        rows.append([[s8(r + 16 * band + i) for i in range(16)] for band in range(4)])
        n = max(max(x) for x in rows[-1]) + 1
        zl.append([L(u32(u32(0x0C338A68 + 4 * z) + 4 * i)) for i in range(n)])
    d['rows'], d['zone_lists'] = rows, zl
    d['zone_cm'] = [f32(0x0C08CCE8), f32(0x0C08CCEC), f32(0x0C08CCF0), f32(0x0C08CCF4)]   # classes 0 1 2 3
    d['behind_cm'] = f32(0x0C08CBD8)
    d['behind_angle'] = [0x271C, 0x4E38]   # (angle off his facing + 0x271C) & 0xFFFF > 0x4E38 = outside +-55 deg
    # pad word -> the remaster's attack (motion chain) his fighter code starts: measured from the disc logs
    # (`fv_ai.py attacks LOGS`, kept in fv_attacks.json next to the export)
    am = os.path.join(os.path.dirname(OUT), 'fv_attacks.json')
    d['attacks'] = json.load(open(am))['attacks'] if os.path.exists(am) else {}
    d['lists'] = {f'{a:08X}': b for a, (b, _) in sorted(lists.items())}
    d['lists_readable'] = {f'{a:08X}': ' / '.join(o) for a, (_, o) in sorted(lists.items())}
    json.dump(d, open(OUT, 'w'), indent=1)
    print(OUT, len(lists), 'lists')
    return d


if __name__ == '__main__':
    if sys.argv[1] == 'export':
        export()
    elif sys.argv[1] == 'dis':
        d = export()
        for k in ('padw', 'tc', 'th', 'thr', 'wait_add', 'pct_zone', 'pct_opp13', 'pct_opp23', 'pct_far_hit',
                  'pct_maybe', 'stand_n', 'steer_n', 'dir', 'zone_cm', 'behind_cm', 'rows'):
            print(k, d[k] if k != 'padw' and k != 'dir' else [[hex(x) for x in r] if isinstance(r, list) else hex(r) for r in d[k]])
        for k in ('start', 'item', 'opp13', 'opp23', 'far_hit', 'zone_lists'):
            print(k, d[k])
        for a, t in d['lists_readable'].items():
            print(a, t)


# ------------------------------------------------------------------------------------------------ statistics
def _fv_rows(path):
    """Rows of the Final Valgas fight only (P2 character 10; a disc log can start in fight 1)."""
    import json as J
    rows = [J.loads(l) for l in open(path)]
    return [r for r in rows if r['p'][1].get('ch', 10) == 10]


def reduce_fv(path):
    """One log (disc: fv_log.py; remaster: tests/cpu_fv_test.gd PS_CPU_LOG) -> Final Valgas's numbers: attack starts
    (a kind-1 motion starting from a non-attack motion), the chain each one plays, the opponent's distance at the
    start, the gaps between attacks, damage both ways, his state on every hit he takes, rounds."""
    from collections import Counter
    rows = _fv_rows(path)
    A = dict(frames=0, starts=0, mix=Counter(), chains=Counter(), dist=[], gaps=[], dealt=0, taken=0, hits_taken=0,
             react=Counter(), rounds=[], turns=0, presses=Counter())
    seg, segs = [], []
    for r in rows:
        if r['phase'] == 3: seg.append(r)
        elif seg: segs.append(seg); seg = []
    if seg: segs.append(seg)
    for seg in segs:
        A['frames'] += len(seg)
        last_end, chain, d_r, t_r = None, None, 0, 0
        for i in range(1, len(seg)):
            a0, a1 = seg[i - 1]['p'][1], seg[i]['p'][1]
            o0, o1 = seg[i - 1]['p'][0], seg[i]['p'][0]
            if 0 < o0['hp'] - o1['hp'] < 200: d_r += o0['hp'] - o1['hp']
            if 0 < a0['hp'] - a1['hp'] < 200:
                t_r += a0['hp'] - a1['hp']; A['hits_taken'] += 1
                A['react'][f"st{a0['st']}>{a1['st']} k{a1['kind']}/{a1['mot']}"] += 1
            if a1.get('prs'): A['presses'][f"{a1['prs']:x}"] += 1
            if a1['st'] == 2 and a0['st'] != 2: A['turns'] += 1
            new = a1['kind'] == 1 and ((a0['kind'], a0['mot']) != (a1['kind'], a1['mot']) or a1['fr'] < a0['fr'])
            if new and a0['kind'] != 1:
                A['starts'] += 1
                A['mix'][f"k1/{a1['mot']}"] += 1
                A['dist'].append(((a1['x'] - o1['x']) ** 2 + (a1['z'] - o1['z']) ** 2) ** 0.5)
                if last_end is not None: A['gaps'].append(i - last_end)
                if chain: A['chains'][' > '.join(chain)] += 1
                chain = [str(a1['mot'])]
            elif new and chain is not None and chain[-1] != str(a1['mot']):
                chain.append(str(a1['mot']))
            if a0['kind'] == 1 and a1['kind'] != 1: last_end = i
        if chain: A['chains'][' > '.join(chain)] += 1
        A['dealt'] += d_r; A['taken'] += t_r
        end = seg[-1]['p']
        A['rounds'].append(dict(frames=len(seg), dealt=d_r, taken=t_r, fv_hp=end[1]['hp'], opp_hp=end[0]['hp'],
                                how='KO' if min(end[0]['hp'], end[1]['hp']) <= 0 else ('TIME' if seg[-1].get('clock', 1) <= 0 else 'cut')))
    return A


def _p(v, q):
    v = sorted(v)
    return round(v[min(len(v) - 1, int(q * len(v)))], 1) if v else None


def stats(paths):
    out = {}
    for p in paths:
        A = reduce_fv(p)
        mins = A['frames'] / 3600 or 1
        out[os.path.basename(p)] = {
            'fight_min': round(mins, 2), 'attack_starts_per_min': round(A['starts'] / mins, 1),
            'move_mix_share': {k: round(v / max(1, A['starts']), 3) for k, v in A['mix'].most_common()},
            'chains': dict(A['chains'].most_common(12)),
            'dist_at_start_cm': [_p(A['dist'], .1), _p(A['dist'], .5), _p(A['dist'], .9)],
            'gap_frames': [_p(A['gaps'], .1), _p(A['gaps'], .5), _p(A['gaps'], .9)],
            'damage_dealt_per_min': round(A['dealt'] / mins, 1), 'damage_taken_per_min': round(A['taken'] / mins, 1),
            'hits_taken': A['hits_taken'], 'react': dict(A['react'].most_common(8)),
            'turns_per_min': round(A['turns'] / mins, 1), 'presses_per_min': {k: round(v / mins, 1) for k, v in A['presses'].most_common()},
            'rounds': A['rounds']}
    return out


def attacks(paths):
    """pad word pressed from state 0 / 2 (the frame before) -> the motion chain that follows (kind-1 motions, repeats
    folded, until he leaves state 11), with the second press of the same command (+N frames) when there is one."""
    from collections import Counter, defaultdict
    res = defaultdict(Counter)
    for p in paths:
        rows = _fv_rows(p)
        for i in range(1, len(rows)):
            b, b0 = rows[i]['p'][1], rows[i - 1]['p'][1]
            if not b.get('prs') or b0['st'] not in (0, 2): continue
            ch, j, second = [], i + 1, ''
            while j < len(rows) and j < i + 600:
                c = rows[j]['p'][1]
                if c.get('prs') and not second: second = f" (+{j - i}: {c['prs']:x})"
                if c['kind'] == 1 and (not ch or ch[-1] != c['mot']): ch.append(c['mot'])
                if c['st'] != 11 and j > i + 2: break
                j += 1
            res[f"{b['prs']:x}"][' > '.join(map(str, ch)) + second] += 1
    return {k: dict(v.most_common()) for k, v in res.items()}


if __name__ == '__main__' and sys.argv[1] in ('stats', 'attacks'):
    import glob
    paths = sorted(sum((glob.glob(a) for a in sys.argv[2:]), []))
    print(json.dumps(stats(paths) if sys.argv[1] == 'stats' else attacks(paths), indent=1))


def verdict(disc, rem):
    """Markdown: Final Valgas's numbers per disc log (their spread = min..max) against the remaster's seeded matches
    (mean, min..max); PASS = the remaster's mean inside the disc's spread (each end widened by 10 %, shares by 0.02)."""
    D, R = stats(disc), stats(rem)
    def vals(S, f):
        out = []
        for v in S.values():
            x = f(v)
            if x is not None: out.append(x)
        return out
    def rnd_frames(v):
        r = [x['frames'] for x in v['rounds'] if x['how'] != 'cut']
        return sum(r) / len(r) if r else None
    def ko(v):
        r = [x for x in v['rounds'] if x['how'] != 'cut']
        return sum(1 for x in r if x['how'] == 'KO') / len(r) if r else None
    mixk = sorted({k for v in list(D.values()) + list(R.values()) for k in v['move_mix_share']})
    rows = [('attack starts /min', lambda v: v['attack_starts_per_min']),
            ('opponent distance at attack start p50 cm', lambda v: v['dist_at_start_cm'][1]),
            ('frames between attacks p50', lambda v: v['gap_frames'][1]),
            ('damage dealt /min', lambda v: v['damage_dealt_per_min']),
            ('damage taken /min', lambda v: v['damage_taken_per_min']),
            ('round frames (ended rounds)', rnd_frames), ('KO share of ended rounds', ko)]
    rows += [(f'move mix {k}', (lambda k: lambda v: v['move_mix_share'].get(k, 0.0))(k)) for k in mixk]
    print('| number | disc (%d logs) min..max | remaster (%d matches) mean (min..max) | verdict |' % (len(D), len(R)))
    print('|---|---|---|---|')
    tally = {}
    for name, f in rows:
        a, b = vals(D, f), vals(R, f)
        if not a or not b:
            print(f'| {name} | {a} | {b} | n/a |'); continue
        lo, hi = min(a), max(a)
        m = sum(b) / len(b)
        small = 0.02 if hi <= 1.0 else 0.0   # shares
        ok = lo - 0.1 * abs(lo) - small <= m <= hi + 0.1 * abs(hi) + small
        tally[ok] = tally.get(ok, 0) + 1
        print(f'| {name} | {lo:.3g}..{hi:.3g} | {m:.3g} ({min(b):.3g}..{max(b):.3g}) | {"PASS" if ok else "FAIL"} |')
    print(f'\nPASS {tally.get(True, 0)} / FAIL {tally.get(False, 0)}')


if __name__ == '__main__' and sys.argv[1] == 'verdict':
    import glob
    verdict(sorted(glob.glob(sys.argv[2])), sorted(glob.glob(sys.argv[3])))


def check(paths):
    """The disc's block against the exported tables (like cpu_ai.py check): every list pointer state 1 runs must be
    zone_lists[+9][+7] with +7 in rows[+9][band +8]; every state-2 list one of the interrupt lists; every running
    command's type / frame count must be what the list bytes at the pointer before it say."""
    import json as J, struct as S
    d = J.load(open(OUT))
    lists = {int(k, 16): v for k, v in d['lists'].items()}
    inter = {int(x, 16) for x in d['item'] + d['opp13'] + d['opp23'] + d['far_hit']}
    ok = bad = 0; why = {}
    sel_ok = sel_bad = 0
    for p in paths:
        prev = None
        for l in open(p):
            r = J.loads(l)
            if r['p'][1].get('ch') != 10 or r['phase'] != 3 or 'fv' not in r: continue
            b = bytes.fromhex(r['fv'])
            st, li, band, za = b[0], b[7], b[8], b[9]
            ptr = S.unpack_from('<I', b, 0x10)[0]
            if prev is not None and ptr != prev[1] and b[1] == 2:
                # the pointer moved on: it points past the command now running; find the list it belongs to
                base = max((a for a in lists if a <= ptr), default=None)
                if st == 1 and prev[0] != ptr:
                    want = int(d['zone_lists'][za][li], 16) if li < len(d['zone_lists'][za]) else None
                    inrow = li in d['rows'][za][band]
                    if base == want and inrow: sel_ok += 1
                    elif base != want or not inrow:
                        sel_bad += 1; why[f'st1 z{za} li{li} band{band} base {base and hex(base)} want {want and hex(want)} inrow {inrow}'] = 1
                if st == 2 and base is not None:
                    if base in inter: ok += 1
                    else: bad += 1; why[f'st2 base {hex(base)}'] = 1
            prev = (st, ptr)
    # command frame counts: a stand / steer / wait that just started (phase 1 on this frame) against the tables
    cn = {0: [0, 0], 1: [0, 0], 3: [0, 0]}
    lv = None
    for p in paths:
        prev = None
        for l in open(p):
            r = J.loads(l)
            if r['p'][1].get('ch') != 10 or r['phase'] != 3 or 'fv' not in r: continue
            b = bytes.fromhex(r['fv']); lv = r['lvl']
            cmd, ph, n, band = b[5], b[2], S.unpack_from('<H', b, 0xC)[0], b[8]
            if prev is not None and prev[2] == 0 and ph == 1 and b[1] == 2 and cmd in cn:
                bucket = (min(11, max(0, lv - 20)) >> 2) & 3
                lN = {10, 30, 60, 120}   # the N the lists give stand / steer themselves (fv_ai.py dis)
                if cmd == 0: good = n + 1 in d['stand_n'][bucket] or n + 1 in lN   # its first frame counts
                elif cmd == 1: good = n in sum(d['steer_n'], []) or n in lN
                else: good = n >= 1 + d['wait_add'][band]
                cn[cmd][0 if good else 1] += 1
            prev = (cmd, ph, ph if b[1] == 2 else 0)
    print('command frame counts in the tables (stand / steer / wait):', {k: f'{v[0]} / {sum(v)}' for k, v in cn.items()})
    print(f'state-1 list picks consistent {sel_ok} / {sel_ok + sel_bad}; state-2 lists = interrupt lists {ok} / {ok + bad}')
    for k in list(why)[:12]: print('  ', k)


if __name__ == '__main__' and sys.argv[1] == 'check':
    import glob
    check(sorted(glob.glob(sys.argv[2])))
