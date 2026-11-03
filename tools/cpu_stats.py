#!/usr/bin/env python3
"""The ORIGINAL's CPU (AI) by the numbers: CPU-vs-CPU fights in Flycast (both players driven by the game's own AI,
P1 +0x71ED frozen at 1, the CPU level 0x0C7F305C (+ rank counter 0x0C7F305D = level * 8) frozen), logged every frame,
then reduced to per-fighter / per-level statistics the remaster's CPU can be held to (docs/CPU.md).

  cpu_stats.py log INST JOBS...        JOBS = p1,p2,level[,frames] (fighter ids as tools/reflog.py IDS), e.g.
                                       falcon,ryoma,9  -> LOGDIR/cpu_falcon_ryoma_L9.{bin,jsonl,meta.json}
  cpu_stats.py plan                    the standard job list (5 pairs x 3 levels + Final Valgas), one line per instance
  cpu_stats.py run INST K [FRAMES]     log half K (0/1) of the plan on instance INST
  cpu_stats.py stats [LOGDIR]          every cpu_*.jsonl -> game/assets/fidelity/cpu_stats.json
  cpu_stats.py stats DIR OUT           the same for other logs (the remaster: tests/cpu_game_test.gd PS_CPU_LOG=...)
  cpu_stats.py compare A.json B.json   key numbers side by side (disc vs remaster)
  cpu_stats.py verdict A.json B.json   the same as a markdown table with a verdict per row (docs/CPU.md section 12)
  cpu_stats.py table [STATS.json]      markdown summary (docs/CPU.md section 10)

Per-frame row (decode): reflog.py's player fields + the struct head (+3 player index, +4 character id), the virtual
pad words the AI writes (+0x2DC on / +0x2E0 previous / +0x2E4 pressed / +0x2E8 released, logical bits: see docs/CPU.md)
and the AI work record (0x0C366F40 + index * 0x254: +4 Mode, +6 IntLv, +8 Mask, +0xC script pointer, +0x10, +0x2C
Table, +0x6C target pointer, +0x70 RET depth)."""
import json, os, struct, sys, time
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import reflog as RL

LOGDIR = os.environ.get('CPU_LOGDIR', '/tmp/ps-fx-cpu/logs/')
OUT = os.path.join(os.path.dirname(HERE), 'game/assets/fidelity/cpu_stats.json')
P1, P2 = RL.P1, RL.P2
AIW, AISZ = 0x0C366F40, 0x254
LEVEL, RANK = 0x0C7F305C, 0x0C7F305D
PF = [(0x000, 8)] + RL.PFIELDS + [(0x2DC, 16)]
AF = [(0x04, 16), (0x2C, 4), (0x6C, 8)]
GF = RL.GFIELDS + [(0x0C7F3050, 4), (0x0C7F2E44, 4)]
# The scripts branch on the arcade fight index (op 22 REG_FIGHT = 0x0C7F2E46 for P1): fight 1 / 2 run gentler library
# scripts (e.g. Falcon's 0.19 masks the attack / counter / evade interrupts off). A level is logged with the fight index
# the arcade pairs it with (levels: fight 1 = 9, ~13/17/19/22/25/27/28, 29-30 at Final Valgas; RIP.md), frozen.
FIGHT_OF_LEVEL = {9: 0, 13: 1, 17: 2, 19: 3, 22: 4, 25: 5, 27: 6, 28: 7, 29: 7, 30: 8}


def segs():
    out = []
    for i, b in enumerate((P1, P2)):
        out += [f'0x{b + o:08X}:{n}' for o, n in PF]
        out += [f'0x{AIW + i * AISZ + o:08X}:{n}' for o, n in AF]
    return ','.join(out + [f'0x{a:08X}:{n}' for a, n in GF])


def frame_size():
    return 2 * (sum(n for _, n in PF) + sum(n for _, n in AF)) + sum(n for _, n in GF)


def decode(path):
    raw = open(path, 'rb').read()
    fs = frame_size()
    rows = []
    for f in range(len(raw) // fs):
        fr = raw[f * fs:(f + 1) * fs]
        pos, ps = 0, []
        for _ in (P1, P2):
            d = {}
            for o, n in PF:
                d[o] = fr[pos:pos + n]; pos += n
            a = {}
            for o, n in AF:
                a[o] = fr[pos:pos + n]; pos += n
            p = RL._player(d)
            on, prev, prs, rel = struct.unpack('<4I', d[0x2DC])
            mode, intlv, mask = a[0x04][0], struct.unpack('<H', a[0x04][2:4])[0], struct.unpack('<H', a[0x04][4:6])[0]
            script = struct.unpack('<I', a[0x04][8:12])[0]
            table = struct.unpack('<H', a[0x2C][:2])[0]
            tgt, ret = struct.unpack('<I', a[0x6C][:4])[0], struct.unpack('<H', a[0x6C][4:6])[0]
            p.update(idx=d[0x000][3], ch=d[0x000][4], pad=on, prs=prs, mode=mode, intlv=intlv, mask=mask,
                     scr=script, tbl=table, tgt=tgt, ret=ret)
            ps.append(p)
        g = {}
        for ad, n in GF:
            g[ad] = fr[pos:pos + n]; pos += n
        rows.append(dict(f=f, p=ps, rand=struct.unpack('<I', g[0x0C346A50])[0], lvl=g[0x0C7F305C][0],
                         rank=g[0x0C7F305C][1], phase=g[0x0C7F302C][0], clock=g[0x0C7F304C][1],
                         mvok=g[0x0C7F3050][0], fight=g[0x0C7F2E44][2] if 0x0C7F2E44 in g else None))
    return rows


def log(inst, jobs):
    from fcinst import Inst
    os.makedirs(LOGDIR, exist_ok=True)
    fi = Inst(inst)
    try:
        for job in jobs:
            p1, p2, lvl, *rest = job.split(',')
            lvl = int(lvl); frames = int(rest[0]) if rest else 12000
            fight = int(rest[1]) if len(rest) > 1 else FIGHT_OF_LEVEL.get(lvl, 0)
            name = f'cpu_{p1}_{p2}_L{lvl}'
            if os.path.exists(LOGDIR + name + '.jsonl'):
                continue
            t0 = time.time()
            RL.boot(fi, p1, p2)
            lines = [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'freeze8 0x{P2 + 0x71ED:08X} 1',
                     f'freeze8 0x{LEVEL:08X} {lvl}', f'freeze8 0x{RANK:08X} {min(255, lvl * 8)}',
                     f'freeze8 0x0C7F2E46 {fight}', f'capseg {name} {frames} {segs()}']
            fi.fc(lines, 60)
            fi.wait_idle(frames / 60 * 8 + 600, 5)
            time.sleep(1)
            src = fi.root + f'cap/{name}.bin'
            rows = decode(src)
            os.replace(src, LOGDIR + name + '.bin')
            RL.write_jsonl(rows, LOGDIR + name + '.jsonl')
            json.dump({'p1': p1, 'p2': p2, 'level': lvl, 'fight': fight, 'frames': len(rows),
                       'wall_s': round(time.time() - t0)},
                      open(LOGDIR + name + '.meta.json', 'w'))
            print(name, len(rows), 'frames', round(time.time() - t0), 's', flush=True)
            fi.stop()
    finally:
        fi.stop()


MODES = {0x10: 'default', 0x30: 'item_held/pole', 0x31: 'item_new', 0x32: 'item_target', 0x40: 'close', 0x41: 'close_once',
         0x50: 'counter', 0x60: 'stuck', 0x70: 'opp_pole', 0x80: 'zone', 0x90: 'down/projectile', 0x91: 'state13',
         0x00: 'object_above', 0x01: 'object_target'}
PIDS = {P1: 0, P2: 1}


def _rounds(rows):
    """[(start, end)] of contiguous fight frames (round phase 3)."""
    out, s = [], None
    for i, r in enumerate(rows):
        if r['phase'] == 3 and s is None: s = i
        if r['phase'] != 3 and s is not None: out.append((s, i)); s = None
    if s is not None: out.append((s, len(rows)))
    return out


def _starts(seq):
    """Indices where a new motion starts (kind/motion changes or the frame counter restarts)."""
    out = []
    for i in range(1, len(seq)):
        a, b = seq[i - 1], seq[i]
        if (a['kind'], a['mot']) != (b['kind'], b['mot']) or b['fr'] < a['fr']:
            out.append(i)
    return out


def reduce_log(path):
    """One CPU-vs-CPU log -> per-side records keyed (fighter, level)."""
    rows = [json.loads(l) for l in open(path)]
    res = []
    for k in (0, 1):
        o = 1 - k
        acc = defaultdict(lambda: dict(frames=0, rounds=[], motions=Counter(), dist=[], jumps=0, pickups=0,
                                       carry_frames=0, obj_throws=0, grabs=0, gem_gain=0, gem_loss=0, pc=[], pc_frames=0,
                                       modes=Counter(), target_obj_frames=0, tables=Counter(), hits_taken=0,
                                       press=Counter(), runs=0, idle_frames=0))
        rounds = _rounds(rows)
        ref = (rows[rounds[0][0]]['p'][0]['ch'], rows[rounds[0][0]]['p'][1]['ch']) if rounds else None
        for a, b in rounds:
            seg = rows[a:b]
            me = [r['p'][k] for r in seg]; op = [r['p'][o] for r in seg]
            if not seg or me[0]['ch'] > 10 or op[0]['ch'] > 10: continue
            # only the booted match (P1 vs P2 at the logged fight index): a won match moves on to another fight
            if (seg[0]['p'][0]['ch'], seg[0]['p'][1]['ch']) != ref: continue
            key = (RL.IDS[me[0]['ch']], seg[0]['lvl'])
            A = acc[key]
            A['frames'] += len(seg)
            dealt = taken = 0
            for i in range(1, len(seg)):
                if seg[i]['p'][k]['ch'] != me[0]['ch']: break
                m0, m1, o0, o1 = me[i - 1], me[i], op[i - 1], op[i]
                if 0 < o0['hp'] - o1['hp'] < 200: dealt += o0['hp'] - o1['hp']
                if 0 < m0['hp'] - m1['hp'] < 200: taken += m0['hp'] - m1['hp']
                if m1['st'] == 4 and m0['st'] != 4: A['jumps'] += 1
                if m1['st'] == 31 and m0['st'] != 31: A['runs'] += 1
                if m1['st'] == 28 and m0['st'] != 28: A['grabs'] += 1
                if m1['st'] == 27 and m0['st'] != 27: A['hits_taken'] += 1
                if m1['gems'] > m0['gems']: A['gem_gain'] += m1['gems'] - m0['gems']
                if m1['gems'] < m0['gems']: A['gem_loss'] += m0['gems'] - m1['gems']
                if m1['pc'] and not m0['pc']: A['pc'].append(dict(t=round(i / 60, 2), hp=m1['hp'], opp_hp=o1['hp']))
                if m1['pc']: A['pc_frames'] += 1
                if m1['st'] == 0: A['idle_frames'] += 1
                if m1['kind'] == 2 and 220 <= m1['mot'] <= 225: A['carry_frames'] += 1
                A['modes'][MODES.get(m1['mode'], hex(m1['mode']))] += 1
                if m1['tgt'] not in (P1, P2) and m1['tgt'] != 0: A['target_obj_frames'] += 1
                A['tables'][f"{m1['mode']:02x}/{m1['tbl']}"] += 1
                for bit, nm in ((0x400, 'punch'), (0x200, 'kick'), (0x4, 'jump')):
                    if m1['prs'] & bit: A['press'][nm] += 1
                A['dist'].append(((m1['x'] - o1['x']) ** 2 + (m1['z'] - o1['z']) ** 2) ** 0.5)
            for i in _starts(me):
                m = me[i]
                if m['kind'] == 2 and m['mot'] in (219, 226): A['pickups'] += 1     # pick-up (st 35) / heavy (st 25)
                if m['kind'] == 2 and m['mot'] == 225: A['obj_throws'] += 1         # carried object thrown (st 10)
                A['motions'][f"k{m['kind']}/{m['mot']}"] += 1
            end = seg[-1]
            A['rounds'].append(dict(frames=len(seg), dealt=dealt, taken=taken, hp_end=me[-1]['hp'], opp_hp_end=op[-1]['hp'],
                                    ko=op[-1]['hp'] <= 0, clock_end=end['clock'], opponent=RL.IDS[op[0]['ch']]))
        res += [(key, A) for key, A in acc.items()]
    return res


def _pct(v, q):
    v = sorted(v)
    return round(v[min(len(v) - 1, int(q * len(v)))], 1) if v else None


def stats(logdir, out_path=None):
    import glob
    merged = defaultdict(list)
    for f in sorted(glob.glob(os.path.join(logdir, 'cpu_*.jsonl'))):
        for key, A in reduce_log(f):
            merged[key].append((os.path.basename(f)[:-6], A))
    out = {'source': 'tools/cpu_stats.py stats (CPU-vs-CPU logs of the original in Flycast, both sides the game AI, '
                     'level frozen at 0x0C7F305C)', 'units': 'per minute of fight time (round phase 3), cm, frames',
           'fighters': {}}
    for (ch, lvl), parts in sorted(merged.items()):
        T = dict(frames=0, rounds=[], motions=Counter(), dist=[], modes=Counter(), tables=Counter(), press=Counter(),
                 pc=[])
        for k in ('jumps', 'pickups', 'carry_frames', 'obj_throws', 'grabs', 'gem_gain', 'gem_loss', 'pc_frames',
                  'target_obj_frames', 'hits_taken', 'runs', 'idle_frames'):
            T[k] = 0
        for _, A in parts:
            for k, v in A.items():
                if isinstance(v, Counter): T[k].update(v)
                elif isinstance(v, list): T[k] += v
                else: T[k] += v
        mins = T['frames'] / 3600 or 1
        full = [r for r in T['rounds'] if r['ko'] or r['hp_end'] <= 0 or r['clock_end'] == 0]
        attacks = Counter({m: n for m, n in T['motions'].items() if m.startswith('k1/')})
        rec = {
            'logs': [n for n, _ in parts], 'fight_minutes': round(mins, 2), 'rounds_logged': len(T['rounds']),
            'move_mix_per_min': {m: round(n / mins, 2) for m, n in attacks.most_common(25)},
            'attack_starts_per_min': round(sum(attacks.values()) / mins, 1),
            'motion_starts_per_min_by_kind': {f'k{k}': round(sum(n for m, n in T['motions'].items()
                                                                  if m.startswith(f'k{k}/')) / mins, 1) for k in range(5)},
            'spacing_cm': {'mean': round(sum(T['dist']) / max(1, len(T['dist'])), 1), 'p10': _pct(T['dist'], 0.1),
                           'p50': _pct(T['dist'], 0.5), 'p90': _pct(T['dist'], 0.9)},
            'jumps_per_min': round(T['jumps'] / mins, 2), 'runs_per_min': round(T['runs'] / mins, 2),
            'idle_share': round(T['idle_frames'] / max(1, T['frames']), 3),
            'pickups_per_min': round(T['pickups'] / mins, 2), 'object_throws_per_min': round(T['obj_throws'] / mins, 2),
            'carry_share': round(T['carry_frames'] / max(1, T['frames']), 3),
            'grabs_per_min': round(T['grabs'] / mins, 2), 'hits_taken_per_min': round(T['hits_taken'] / mins, 2),
            'gems_gained_per_min': round(T['gem_gain'] / mins, 2), 'gems_lost_per_min': round(T['gem_loss'] / mins, 2),
            'ai_target_object_share': round(T['target_obj_frames'] / max(1, T['frames']), 3),
            'power_change': {'count': len(T['pc']), 'per_min': round(len(T['pc']) / mins, 2),
                             'first_t_s': [p['t'] for p in T['pc']][:12],
                             'share_of_time': round(T['pc_frames'] / max(1, T['frames']), 3)},
            'presses_per_min': {k: round(v / mins, 1) for k, v in T['press'].items()},
            'rounds': {'count': len(T['rounds']), 'ended': len(full),
                       'mean_frames': round(sum(r['frames'] for r in full) / max(1, len(full)), 1) if full else None,
                       'mean_damage_dealt': round(sum(r['dealt'] for r in T['rounds']) / max(1, len(T['rounds'])), 1),
                       'mean_damage_taken': round(sum(r['taken'] for r in T['rounds']) / max(1, len(T['rounds'])), 1),
                       'damage_dealt_per_min': round(sum(r['dealt'] for r in T['rounds']) / mins, 1),
                       'list': T['rounds']},
            'ai_mode_share': {m: round(n / max(1, T['frames']), 3) for m, n in T['modes'].most_common()},
            'ai_mode_table_share': {m: round(n / max(1, T['frames']), 3) for m, n in T['tables'].most_common(20)},
        }
        out['fighters'].setdefault(ch, {})[f'L{lvl}'] = rec
    out_path = out_path or OUT
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    json.dump(out, open(out_path, 'w'), indent=1)
    print(out_path, {c: list(v) for c, v in out['fighters'].items()})


KEYS = ['attack_starts_per_min', 'spacing_cm.mean', 'spacing_cm.p50', 'jumps_per_min', 'runs_per_min', 'idle_share',
        'pickups_per_min', 'object_throws_per_min', 'grabs_per_min', 'gems_gained_per_min', 'ai_target_object_share',
        'power_change.per_min', 'presses_per_min.punch', 'presses_per_min.kick', 'presses_per_min.jump',
        'rounds.mean_frames', 'rounds.damage_dealt_per_min']


def compare(a_path, b_path):
    """Side by side: the disc's numbers (A, e.g. cpu_stats.json) and another run's (B, e.g. the remaster's CPU through
    game/tests/cpu_game_test.gd PS_CPU_LOG + cpu_stats.py stats DIR OUT)."""
    A, B = json.load(open(a_path))['fighters'], json.load(open(b_path))['fighters']
    def get(r, k):
        for part in k.split('.'):
            r = r.get(part) if isinstance(r, dict) else None
        return r
    for ch in sorted(set(A) & set(B)):
        for lv in sorted(set(A[ch]) & set(B[ch])):
            print(f'== {ch} {lv}')
            for k in KEYS:
                print(f'   {k:32s} {get(A[ch][lv], k)!s:>10} {get(B[ch][lv], k)!s:>10}')


# verdict rows: (label, key, kind). kind: 'ai' = the AI's own choices, 'core' = needs fighter-core mechanics not ported
# yet (items / throws / Power Change / reactions: the lead's queue), 'out' = an outcome of both (damage, round length)
VERDICT_ROWS = [('attack starts /min', 'attack_starts_per_min', 'ai'), ('punch presses /min', 'presses_per_min.punch', 'ai'),
                ('kick presses /min', 'presses_per_min.kick', 'ai'), ('jump presses /min', 'presses_per_min.jump', 'ai'),
                ('jumps /min', 'jumps_per_min', 'ai'), ('runs /min', 'runs_per_min', 'ai'),
                ('spacing p50 cm', 'spacing_cm.p50', 'ai'), ('object-target share', 'ai_target_object_share', 'ai'),
                ('grabs /min', 'grabs_per_min', 'core'), ('pick-ups /min', 'pickups_per_min', 'core'),
                ('object throws /min', 'object_throws_per_min', 'core'), ('PC /min', 'power_change.per_min', 'core'),
                ('damage dealt /min', 'rounds.damage_dealt_per_min', 'out'), ('round frames', 'rounds.mean_frames', 'out')]


def _mix_overlap(a, b):
    """Move mix similarity: sum over motions of min(share A, share B), shares of each side's attack motions (0..1)."""
    ta, tb = sum(a.values()) or 1, sum(b.values()) or 1
    return round(sum(min(a.get(k, 0) / ta, b.get(k, 0) / tb) for k in set(a) | set(b)), 2)


def verdict(a_path, b_path):
    """Markdown table: the disc (A) vs the port (B) per fighter and level, with a verdict per row: PASS = within 25 %
    (or 1.0 /min for small rates), else FAIL tagged ai / core / out (see VERDICT_ROWS)."""
    A, B = json.load(open(a_path))['fighters'], json.load(open(b_path))['fighters']
    def get(r, k):
        for part in k.split('.'):
            r = r.get(part) if isinstance(r, dict) else None
        return r
    print('| fighter | level | number | disc | port | verdict |')
    print('|---|---|---|---|---|---|')
    tally = Counter()
    for ch in RL.IDS:
        for lv in sorted(set(A.get(ch, {})) & set(B.get(ch, {})), key=lambda x: int(x[1:])):
            a, b = A[ch][lv], B[ch][lv]
            ov = _mix_overlap(a.get('move_mix_per_min', {}), b.get('move_mix_per_min', {}))
            v = 'PASS' if ov >= 0.5 else 'FAIL (core: the moves the core starts)'
            tally[v.split(' ')[0]] += 1
            print(f'| {ch} | {lv[1:]} | move mix overlap | 1.00 | {ov} | {v} |')
            for label, k, kind in VERDICT_ROWS:
                x, y = get(a, k), get(b, k)
                if x is None or y is None:
                    v = 'n/a (no round ended)' if k.startswith('rounds') else 'n/a'
                else:
                    small = 0.5 if '/min' in label else (0.05 if 'share' in label else 0)
                    ok = abs(y - x) <= max(0.25 * abs(x), small)
                    v = 'PASS' if ok else f'FAIL ({kind})'
                tally[v.split(' ')[0]] += 1
                print(f'| {ch} | {lv[1:]} | {label} | {x} | {y} | {v} |')
    print()
    print('verdicts:', dict(tally))


PAIRS = {9: [('falcon', 'ryoma'), ('wangtang', 'jack'), ('gunrock', 'galuda'), ('ayame', 'rouge'), ('kraken', 'valgas')],
         19: [('falcon', 'wangtang'), ('ryoma', 'gunrock'), ('jack', 'ayame'), ('galuda', 'kraken'), ('rouge', 'valgas')],
         29: [('falcon', 'gunrock'), ('ryoma', 'ayame'), ('wangtang', 'kraken'), ('jack', 'valgas'), ('galuda', 'rouge')]}


def plan():
    jobs = [f'{a},{b},{lv}' for lv, ps in PAIRS.items() for a, b in ps] + ['falcon,finalvalgas,29']
    return jobs[0::2], jobs[1::2]


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'log':
        log(sys.argv[2], sys.argv[3:])
    elif cmd == 'run':
        fr = sys.argv[4] if len(sys.argv) > 4 else '18000'
        log(sys.argv[2], [j + ',' + fr for j in plan()[int(sys.argv[3])]])
    elif cmd == 'plan':
        for half in plan(): print(' '.join(half))
    elif cmd == 'stats':
        stats(sys.argv[2] if len(sys.argv) > 2 else LOGDIR, sys.argv[3] if len(sys.argv) > 3 else None)
    elif cmd == 'table':
        d = json.load(open(sys.argv[2] if len(sys.argv) > 2 else OUT))['fighters']
        print('| fighter | level | min | attacks/min | spacing cm (p50) | jumps/min | runs/min | pick-ups/min | '
              'obj throws/min | gems/min | PC (count, first s) | rounds | round frames | dmg dealt/min | object-target share |')
        print('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
        for ch in RL.IDS:
            for lv in sorted(d.get(ch, {}), key=lambda x: int(x[1:])):
                r = d[ch][lv]
                pc = r['power_change']
                print(f"| {ch} | {lv[1:]} | {r['fight_minutes']} | {r['attack_starts_per_min']} | {r['spacing_cm']['mean']} "
                      f"({r['spacing_cm']['p50']}) | {r['jumps_per_min']} | {r['runs_per_min']} | {r['pickups_per_min']} | "
                      f"{r['object_throws_per_min']} | {r['gems_gained_per_min']} | {pc['count']}, {pc['first_t_s'][:3]} | "
                      f"{r['rounds']['count']} | {r['rounds']['mean_frames']} | {r['rounds']['damage_dealt_per_min']} | "
                      f"{r['ai_target_object_share']} |")
    elif cmd == 'compare':
        compare(sys.argv[2], sys.argv[3])
    elif cmd == 'verdict':
        verdict(sys.argv[2], sys.argv[3])
