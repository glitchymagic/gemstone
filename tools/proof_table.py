#!/usr/bin/env python3
"""Before / after tables for docs/fx-cam.md and docs/fx-oom.md from tools/oom_proof.sh and tools/cam_proof.sh outputs.
  proof_table.py game BEFORE_SUMMARY[,MORE] AFTER_SUMMARY     seeded CPU-vs-CPU matches (oom_proof summary.txt lines)
  proof_table.py replay BEFORE_DIR AFTER_DIR                  the original's fights replayed (cam_proof summary.txt)"""
import json, re, sys


def game_rows(paths):
    out = {}
    for p in paths.split(','):
        for l in open(p):
            l = l.strip()
            if not l: continue
            tag = l.split()[0]
            kv = dict(re.findall(r'(\w+)=([\d.]+)%?', l))
            if kv.get('frames', '0') == '0': continue
            out[tag] = kv
    return out


def game(before, after):
    b, a = game_rows(before), game_rows(after)
    print('| run (look_stage_fighters) | frames before / after | hidden % before -> after | head cut % | feet cut % | out-of-map frames (fighters) before -> after | gems / throwables out |')
    print('|---|---|---|---|---|---|---|')
    for tag in sorted(set(a) | set(b)):
        x, y = b.get(tag, {}), a.get(tag, {})
        g = lambda d, k: d.get(k, '-')
        print(f"| {tag} | {g(x, 'frames')} / {g(y, 'frames')} | {g(x, 'occluded')} -> {g(y, 'occluded')} | {g(x, 'head_cut')} -> {g(y, 'head_cut')} | "
              f"{g(x, 'feet_cut')} -> {g(y, 'feet_cut')} | {g(x, 'out_of_map')} -> {g(y, 'out_of_map')} | {g(x, 'obj_out')} -> {g(y, 'obj_out')} |")


def rep_rows(d):
    out = {}
    for l in open(d + '/summary.txt'):
        st = l.split()[0]
        m = re.search(r'(\{.*\})', l)
        if m: out[st] = json.loads(m.group(1))
    return out


def replay(before, after):
    b, a = rep_rows(before), rep_rows(after)
    print('| stage | frames | hidden % before -> after | head / feet cut % after | under HUD % after | yaw err med (deg) live before -> after | distance err med (cm) live before -> after (rule) | eye height err med (cm) live before -> after (rule) |')
    print('|---|---|---|---|---|---|---|---|')
    for st in sorted(set(a) | set(b)):
        x, y = b.get(st, {}), a.get(st, {})
        g = lambda d, k: d.get(k, '-')
        print(f"| {st} | {g(y, 'frames')} | {g(x, 'hidden_pct')} -> {g(y, 'hidden_pct')} | {g(y, 'head_cut_pct')} / {g(y, 'feet_cut_pct')} | {g(y, 'under_hud_pct')} | "
              f"{g(x, 'live_yaw_med_deg')} -> {g(y, 'live_yaw_med_deg')} | {g(x, 'live_dist_med_cm')} -> {g(y, 'live_dist_med_cm')} ({g(y, 'base_dist_med_cm')}) | "
              f"{g(x, 'live_height_med_cm')} -> {g(y, 'live_height_med_cm')} ({g(y, 'base_height_med_cm')}) |")




def rescore(before_dirs, after_dir):
    """out-of-map frames of every run re-scored with tools/oom_rescore.py (this checkout's areas, one rule) before / after"""
    import glob, os, subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    print('| run | out-of-map frames, same rule (before -> after): feet outside the area / standing with no floor of the original |')
    print('|---|---|')
    for f in sorted(glob.glob(after_dir + '/*.jsonl')):
        tag = os.path.basename(f)[:-6]; st = tag.split('_')[1]
        b = next((d + '/' + tag + '.jsonl' for d in before_dirs.split(',') if os.path.exists(d + '/' + tag + '.jsonl')), None)
        def sc(p):
            if not p: return '-'
            o = subprocess.run([sys.executable, here + '/oom_rescore.py', p, st], capture_output=True, text=True).stdout.split()
            return f"{o[3]} / {o[5]}" if len(o) >= 6 else '?'
        print(f'| {tag} | {sc(b)} -> {sc(f)} |')


if __name__ == '__main__':
    {'game': game, 'replay': replay, 'rescore': rescore}[sys.argv[1]](sys.argv[2], sys.argv[3])
