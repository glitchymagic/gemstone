#!/usr/bin/env python3
"""Run fidelity tapes on both sides and diff them.
  fidelity_run.py orig INST TAPE...   the original (Flycast instance INST) -> dumps/fidelity/o_TAPE.jsonl (+ .meta.json)
  fidelity_run.py rem TAPE...         the remaster (headless Godot)        -> dumps/fidelity/r_TAPE.jsonl
  fidelity_run.py diff TAPE...        -> dumps/fidelity/reports/TAPE.txt / .json
  fidelity_run.py rem -j 3 TAPE...    three Godot runs at once
Tapes are game/tests/tapes/TAPE.tape ('#! p1=ID p2=ID' header; the stage is P2's home stage).
Tapes and the Godot project come from THIS checkout (a worktree runs its own code); the originals (o_*.jsonl) always
live in the main checkout's dumps/fidelity. FID_OUT=dir puts r_*.jsonl + reports/ there instead (parallel helpers
don't overwrite each other's remaster runs). FID_GAME=dir runs that Godot project instead (e.g. a git-archive snapshot of
master's game/ with APFS clones of the untracked assets)."""
import os, subprocess, sys
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, REPO + 'tools')
import tapes, reflog, fidelity_diff as FD
R = REPO
D = './dumps/fidelity/'
OUTD = os.environ.get('FID_OUT', D).rstrip('/') + '/'
G = '/Applications/Godot.app/Contents/MacOS/Godot'
HOME_STAGE = {'falcon': 'stg00', 'ryoma': 'stg10', 'wangtang': 'stg20', 'jack': 'stg30', 'gunrock': 'stg40',
              'galuda': 'stg50', 'ayame': 'stg60', 'rouge': 'stg70', 'kraken': 'stg80', 'valgas': 'stg90',
              'finalvalgas': 'stga0'}


def built(t):
    src = R + f'game/tests/tapes/{t}.tape'
    out = OUTD + f'tapes/{t}.txt'
    tapes.build(src, out)
    return out, tapes.meta(src)


def orig(inst, names):
    from fcinst import Inst
    fi = Inst(inst)
    for t in names:
        out, m = built(t)
        reflog.boot(fi, m['p1'], m['p2'])
        rows = reflog.play(fi, out, 'o_' + t)
        print(f'orig {t}: {len(rows)} frames', flush=True)
    fi.stop()


def rem_one(t):
    out, m = built(t)
    stg = HOME_STAGE[m['p2']]
    cmd = [G, '--headless', '--path', os.environ.get('FID_GAME', R + 'game'), '--fixed-fps', '60', '-s', 'res://tests/tape_run.gd', '--', out,
           OUTD + f'r_{t}.jsonl', stg, f"{m['p1']},{m['p2']}"]
    if os.path.exists(D + f'o_{t}.jsonl'): cmd.append(D + f'o_{t}.jsonl')
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1500)
        log, rc = r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired as e:
        log, rc = f'TIMEOUT {e}', 'timeout'
    errs = [l for l in log.splitlines() if 'ERROR' in l or 'WARNING' in l or 'SCRIPT' in l]
    open(OUTD + f'r_{t}.godot.log', 'w').write(log)
    print(f'rem {t}: rc {rc}, {len(errs)} error/warning lines', flush=True)


def rem(names):
    os.makedirs(OUTD, exist_ok=True)
    jobs = 1
    if names and names[0] == '-j': jobs, names = int(names[1]), names[2:]
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(jobs) as ex: list(ex.map(rem_one, names))


def diff(names):
    os.makedirs(OUTD + 'reports', exist_ok=True)
    for t in names:
        if not os.path.exists(OUTD + f'r_{t}.jsonl') or not os.path.exists(D + f'o_{t}.jsonl'):
            print(t, 'missing a side'); continue
        o, r = FD.load(D + f'o_{t}.jsonl'), FD.load(OUTD + f'r_{t}.jsonl')
        if not r: print(t, 'empty remaster log'); continue
        res = FD.diff(o, r)
        res['frames_orig'], res['frames_rem'] = len(o), len(r)
        import json
        json.dump(res, open(OUTD + f'reports/{t}.json', 'w'), indent=1)
        open(OUTD + f'reports/{t}.txt', 'w').write(FD.report(o, r, res))
        print(t, ' '.join(f"P{i+1} {f}={res['players'][i][f]['match']*100:.0f}%" for i in range(2) for f in ('st', 'mot', 'x', 'hp')))


if __name__ == '__main__':
    if sys.argv[1] == 'orig': orig(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == 'rem': rem(sys.argv[2:])
    else: diff(sys.argv[2:])
