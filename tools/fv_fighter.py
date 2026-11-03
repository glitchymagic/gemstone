#!/usr/bin/env python3
"""Final Valgas's fighter code on the disc (docs/CPU.md "Final Valgas fighter port"), from fx-fv's logs
(tools/fv_log.py rows, P2 = him, character byte 10):
  fv_fighter.py moves  'GLOB'   frames each motion is on display -> the next one (motion-end = clip frames + 2)
  fv_fighter.py glide  'GLOB'   state-2 episodes: stick angle (+0x7248) vs the glide direction, speed, turn per frame
  fv_fighter.py reacts 'GLOB'   every state-27 start with his health before / after (the 100 / 50 thresholds)
  fv_fighter.py hits   'GLOB'   his hits on the opponent by his motion / frame / distance (most from effect objects)
  fv_fighter.py throws 'GLOB'   his kind-4 chains after a 0x600 press"""
import glob, json, math, sys
from collections import Counter, defaultdict


def rows_of(path):
    return [r for r in (json.loads(l) for l in open(path)) if r['p'][1]['ch'] == 10]


def wrap(a): return (a + 180) % 360 - 180


def moves(paths):
    dur = defaultdict(Counter)
    for p in paths:
        rows = rows_of(p); cur = None; st = 0
        for i, r in enumerate(rows):
            q = r['p'][1]; k = (q['kind'], q['mot'])
            if k != cur:
                if cur is not None: dur['k%d/%d' % cur][(i - st, 'k%d/%d st%d' % (k[0], k[1], q['st']))] += 1
                cur = k; st = i
    for m in sorted(dur): print(m, dict(dur[m].most_common(6)))


def glide(paths):
    for p in paths:
        rows = rows_of(p)
        for i in range(1, len(rows) - 1):
            a, b, c = rows[i - 1]['p'][1], rows[i]['p'][1], rows[i + 1]['p'][1]
            if b['st'] == 2 and a['st'] != 2:
                j = i; dirs = []; sp = []
                while j + 1 < len(rows) and rows[j]['p'][1]['st'] == 2:
                    u, v = rows[j]['p'][1], rows[j + 1]['p'][1]
                    dx, dz = v['x'] - u['x'], v['z'] - u['z']; s = math.hypot(dx, dz); sp.append(s)
                    if s > 0.01: dirs.append(math.degrees(math.atan2(dx, dz)))
                    j += 1
                turn = [wrap(y - x) for x, y in zip(dirs, dirs[1:])]
                S = b['ang'] * 360 / 65536
                print(p[-14:-6], 'f%d n%d k0/%d pad %x stick %.1f first %s off %s speed %.2f turn/f %+.3f' % (
                    rows[i]['f'], j - i, b['mot'], b['pad'], S, '%.1f' % dirs[0] if dirs else '-',
                    '%.1f' % wrap(S - dirs[0]) if dirs else '-', sorted(sp)[len(sp) // 2] if sp else 0,
                    sum(turn) / max(1, len(turn))))


def reacts(paths):
    for p in paths:
        rows = rows_of(p)
        ev = ['f%d %d>%d from st%d' % (rows[i]['f'], rows[i - 1]['p'][1]['hp'], rows[i]['p'][1]['hp'], rows[i - 1]['p'][1]['st'])
              for i in range(1, len(rows)) if rows[i]['p'][1]['st'] == 27 and rows[i - 1]['p'][1]['st'] != 27]
        print(p[-14:-6], ' | '.join(ev))


def hits(paths):
    agg = defaultdict(list)
    for p in paths:
        rows = rows_of(p)
        for i in range(1, len(rows)):
            a, b, q = rows[i - 1]['p'][0], rows[i]['p'][0], rows[i - 1]['p'][1]
            if b['hp'] < a['hp']:
                agg['st%d k%d/%d' % (q['st'], q['kind'], q['mot'])].append((q['fr'], a['hp'] - b['hp'], round(math.hypot(a['x'] - q['x'], a['z'] - q['z']))))
    for k, v in sorted(agg.items()):
        print(k, len(v), 'frames', sorted(set(x[0] for x in v)), 'dmg', sorted(set(x[1] for x in v)), 'cm', min(x[2] for x in v), max(x[2] for x in v))


def throws(paths):
    for p in paths:
        rows = rows_of(p)
        for i in range(1, len(rows)):
            a, b = rows[i - 1]['p'][1], rows[i]['p'][1]
            if b['kind'] == 4 and a['kind'] != 4:
                j, seq = i, []
                while j < len(rows) and rows[j]['p'][1]['st'] == 11:
                    q, o = rows[j]['p'][1], rows[j]['p'][0]
                    if not seq or seq[-1][0] != (q['kind'], q['mot']): seq.append([(q['kind'], q['mot']), 0, o['st'], o['kind'], o['mot']])
                    seq[-1][1] += 1; j += 1
                o = rows[i - 1]['p'][0]
                print(p[-14:-6], 'f%d %d cm' % (rows[i]['f'], math.hypot(o['x'] - a['x'], o['z'] - a['z'])),
                      ' > '.join('k%d/%d x%d (opp st%d k%d/%d)' % (s[0][0], s[0][1], s[1], s[2], s[3], s[4]) for s in seq),
                      'opp health', o['hp'], '->', rows[j - 1]['p'][0]['hp'])


if __name__ == '__main__':
    {'moves': moves, 'glide': glide, 'reacts': reacts, 'hits': hits, 'throws': throws}[sys.argv[1]](sorted(glob.glob(sys.argv[2])))
