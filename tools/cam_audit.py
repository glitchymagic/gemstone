#!/usr/bin/env python3
"""Summarise a PS_AUDIT log (tests/match_movie.gd + scripts/cam_check.gd: one JSON line per video frame) into what a
player would complain about: fighters cut by the frame edges or under the HUD, fighters hidden behind scenery, clutter
right in front of the lens, bodies sinking into each other, framing too far / too close, camera jumps.
  cam_audit.py LOG.jsonl [--md] [--json OUT]     time = (frame - 1) / 60 s into the video"""
import json, sys

HUD = 0.115
OV = 0.10
LIM = {'head_cut': 'top of a fighter above the frame', 'under_hud': 'a fighter\'s head under the HUD band',
       'feet_cut': 'feet below the frame', 'side_cut': 'a fighter cut by the left/right edge',
       'occluded': '>=30% of a fighter hidden by scenery', 'foreground': '>=10% of the frame is clutter <3 m from the lens',
       'overlap': 'bodies sink >=10 cm into each other', 'too_small': 'fighter <12% of the frame height (fight cam)',
       'too_big': 'fighter >80% of the frame height', 'cam_jump': 'camera moves >0.6 m in one frame (no cut intended)',
       'void': 'indoor stage: >=10% of the frame shows the empty outside',
       'out_of_map': 'a fighter\'s feet not over the stage floor inside the original\'s playable area (any phase)',
       'obj_out': 'a gem / throwable not over the stage floor inside the playable area'}
PH = {0: 'intro', 1: 'fight', 2: 'ko', 3: 'round_end', 4: 'done'}


def flags(r, prev):
    out = {}
    hud_on = r['cine'] in ('', 'fusion') and r['ph'] in (0, 1, 2)
    for i, p in enumerate(r['p']):
        if r['cine'] and 'cs' in r and i not in r['cs']: continue   # a cinematic about someone else
        b = p['box']
        if not b:
            out['side_cut'] = max(out.get('side_cut', 0), 1.0); continue
        x0, y0, x1, y1 = b
        if y0 < -0.005: out['head_cut'] = max(out.get('head_cut', 0), -y0)
        elif hud_on and y0 < HUD: out['under_hud'] = max(out.get('under_hud', 0), HUD - y0)
        if y1 > 1.005: out['feet_cut'] = max(out.get('feet_cut', 0), y1 - 1)
        if x0 < -0.005 or x1 > 1.005: out['side_cut'] = max(out.get('side_cut', 0), max(-x0, x1 - 1))
        if p['occ'] >= 0.3: out['occluded'] = max(out.get('occluded', 0), p['occ'])
        h = y1 - y0
        if r['cine'] == '' and r['ph'] == 1 and h < 0.12 and p['st'] not in (7, 11): out['too_small'] = max(out.get('too_small', 0), 0.12 - h)
        if h > 0.8: out['too_big'] = max(out.get('too_big', 0), h)
    if any(p.get('oom') for p in r['p']): out['out_of_map'] = max(-min(p.get('sd', 0) for p in r['p']), 0.01)
    if r.get('oomo', 0) > 0: out['obj_out'] = r['oomo']
    if r['fg'] >= 0.10: out['foreground'] = r['fg']
    if r.get('ov', 0) >= OV: out['overlap'] = r['ov']
    if r.get('void', 0) >= 0.10: out['void'] = r['void']
    if prev is not None and r['cine'] == prev['cine'] and r['ph'] == prev['ph']:
        d = sum((a - b) ** 2 for a, b in zip(r['cam'], prev['cam'])) ** 0.5
        if d > 0.6: out['cam_jump'] = d
    return out


def segments(rows, key, gap=12):
    segs = []
    for r in rows:
        v = r['_fl'].get(key)
        if v is None: continue
        if segs and r['f'] - segs[-1]['end'] <= gap:
            s = segs[-1]; s['end'] = r['f']; s['n'] += 1
            if v > s['worst']: s['worst'] = v; s['worst_f'] = r['f']
            s['ctx'].add(r['cine'] or PH.get(r['ph'], '?'))
        else:
            segs.append({'start': r['f'], 'end': r['f'], 'n': 1, 'worst': v, 'worst_f': r['f'], 'ctx': {r['cine'] or PH.get(r['ph'], '?')}})
    for s in segs: s['ctx'] = ','.join(sorted(s['ctx']))
    return segs


def t(f): return (f - 1) / 60.0


def main():
    rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
    prev = None
    for r in rows:
        r['_fl'] = flags(r, prev); prev = r
    n = len(rows); nf = sum(1 for r in rows if r['ph'] == 1 and r['cine'] == '')
    res = {'frames': n, 'fight_cam_frames': nf, 'types': {}}
    for k in LIM:
        allf = sum(1 for r in rows if k in r['_fl'])
        fight = sum(1 for r in rows if k in r['_fl'] and r['ph'] == 1 and r['cine'] == '')
        res['types'][k] = {'frames': allf, 'pct_all': round(100 * allf / max(n, 1), 1), 'fight_cam_frames': fight,
                           'pct_fight_cam': round(100 * fight / max(nf, 1), 1), 'segments': segments(rows, k)}
    if '--json' in sys.argv: json.dump(res, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
    md = '--md' in sys.argv
    print(f"{n} frames ({n / 60:.1f} s), fight camera {nf} frames")
    print('| issue | what | frames (all) | % all | % of fight-cam frames | runs |' if md else '')
    if md: print('|---|---|---|---|---|---|')
    for k, v in res['types'].items():
        if md: print(f"| {k} | {LIM[k]} | {v['frames']} | {v['pct_all']} | {v['pct_fight_cam']} | {len(v['segments'])} |")
        else: print(f"{k:11s} {v['frames']:5d} frames {v['pct_all']:5.1f}% all {v['pct_fight_cam']:5.1f}% fight-cam  {len(v['segments'])} runs")
    if '--runs' in sys.argv:
        for k, v in res['types'].items():
            for s in sorted(v['segments'], key=lambda s: -s['n'])[:8]:
                print(f"  {k:11s} {t(s['start']):6.2f}-{t(s['end']):6.2f}s n={s['n']:4d} worst {s['worst']:.2f} at {t(s['worst_f']):.2f}s [{s['ctx']}]")


if __name__ == '__main__':
    main()
