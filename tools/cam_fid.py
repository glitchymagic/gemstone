#!/usr/bin/env python3
"""Fight-camera numbers from game/tests/cam_replay.gd logs (the original's fighter positions replayed into the remaster's
stage, one JSON line per frame):
  what a player sees (scripts/cam_check.gd fields, the same limits as tools/cam_audit.py): hidden = >= 30% of a
  fighter's body spheres behind walls / solid scenery, head / feet / side cut by the frame, head under the HUD band;
  fidelity: the remaster's camera vs the original's on the same frame, median |error| of yaw (deg), horizontal distance
  (cm) and eye height over the aim point (cm); 'base' = the remaster's pure rule (scripts/fight_cam.gd _rule), 'live'
  = what the remaster shows (rule + fit / wall swing).
  cam_fid.py LOG.jsonl [LOG.jsonl ...] [--json OUT]"""
import json, math, sys

HUD = 0.115


def wrap(a): return (a + 180) % 360 - 180


def med(v):
    v = sorted(v)
    return round(v[len(v) // 2], 2) if v else None


def summary(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    n = len(rows)
    cnt = dict(hidden=0, head_cut=0, feet_cut=0, side_cut=0, under_hud=0)
    ey, ed, eh, by, bd, bh = [], [], [], [], [], []
    for r in rows:
        fl = set()
        for p in r['p']:
            b = p['box']
            if not b: fl.add('side_cut'); continue
            x0, y0, x1, y1 = b
            if y0 < -0.005: fl.add('head_cut')
            elif y0 < HUD: fl.add('under_hud')
            if y1 > 1.005: fl.add('feet_cut')
            if x0 < -0.005 or x1 > 1.005: fl.add('side_cut')
            if p['occ'] >= 0.3: fl.add('hidden')
        for k in fl: cnt[k] += 1
        ref = r['ref']
        c = r['cam']
        t = ref['tgt']
        live_hd = math.hypot(c[0] - t[0], c[2] - t[2]) * 100
        ey.append(abs(wrap(r['live']['yaw'] - ref['yaw'])))
        ed.append(abs(live_hd - ref['hd'] * 100))
        eh.append(abs((c[1] - t[1]) - (ref['eye'][1] - t[1])) * 100)
        if 'base' in r:
            b = r['base']
            by.append(abs(wrap(b['yaw'] - ref['yaw'])))
            bd.append(abs(b['hd'] - ref['hd']) * 100)
            bh.append(abs((b['eye_y'] - b['tgt'][1]) - (ref['eye'][1] - ref['tgt'][1])) * 100)
    out = dict(frames=n, **{k + '_pct': round(100 * v / max(n, 1), 1) for k, v in cnt.items()},
               live_yaw_med_deg=med(ey), live_dist_med_cm=med(ed), live_height_med_cm=med(eh))
    if by: out.update(base_yaw_med_deg=med(by), base_dist_med_cm=med(bd), base_height_med_cm=med(bh),
                      base_yaw_within_2deg=round(sum(1 for v in by if v < 2) / len(by), 3))
    return out


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    res = {}
    if '--json' in sys.argv:
        args.remove(sys.argv[sys.argv.index('--json') + 1])
    for p in args:
        res[p] = s = summary(p)
        print(p.split('/')[-1], json.dumps(s))
    if '--json' in sys.argv: json.dump(res, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
