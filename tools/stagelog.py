#!/usr/bin/env python3
"""The original on any stage, on an isolated Flycast instance (tools/fcinst.py): arcade as P1 vs the stage's owner on his
home stage (tools/reflog.py boot: fight 1 poked to that ladder entry), then both fighters the game's AI (P1 CPU flag
+0x71ED frozen at 1), healths frozen at 240 and the round timer held (the round never ends), and every frame:
  bytes   0..115  the camera frame tools/cam_zones.py reads (= tools/ref_londo.py CAM_SEGS): view matrix (12 f32), eye
                  +0x450, desired target +0x474, smoothed target +0x480, P1 / P2 hip x,y,z (+0x148), P1 / P2 state words
  bytes 116..187  extras: P1 / P2 feet x,y,z (+0x020), camera +0x3A0..+0x3BF (focal at +0x3AC), +0x440..+0x44F
                  (eye-height cap at +0x448)
A shot every SHOT frames (cap/TAG_NNN.png in the instance's shots/). Output moved to dumps/cap/TAG.bin of the main repo
(+ TAG.meta.json: stage, opponent, frames, frame size) and the shots to dumps/shots/.
  stagelog.py STG TAG FRAMES INST          e.g. stagelog.py stg80 cl80 18000 c1
  stagelog.py many INST FRAMES STG,STG,..   one instance, stages in turn (tags cl<NN>)
Used for: the per-stage camera presets (tools/cam_stage.py) and the playable area the original enforces."""
import json, os, shutil, sys, time
sys.path.insert(0, './tools')
from fcinst import Inst
import reflog
import ladder
R = './'
P1, P2 = 0x0C7E40C4, 0x0C7EB394
CAM = 0x0C7F2664
CAM_SEGS = [(CAM + 0x3C0, 48), (CAM + 0x450, 12), (CAM + 0x474, 12), (CAM + 0x480, 12), (P1 + 0x148, 12),
            (P2 + 0x148, 12), (P1 + 0x71B8, 4), (P2 + 0x71B8, 4)]
EXTRA = [(P1 + 0x020, 12), (P2 + 0x020, 12), (CAM + 0x3A0, 32), (CAM + 0x440, 16)]
FS = sum(n for _, n in CAM_SEGS + EXTRA)   # 188
TIMER = 0x0C7F304D   # the round timer (seconds, 99 down): held, so the round never ends (0x0C7F2F28 is another clock)
OWNER = {'stg00': 'falcon', 'stg10': 'ryoma', 'stg20': 'wangtang', 'stg30': 'jack', 'stg40': 'gunrock',
         'stg50': 'galuda', 'stg60': 'ayame', 'stg70': 'rouge', 'stg80': 'kraken', 'stg90': 'valgas',
         'stga0': 'finalvalgas'}
SHOT = 600


def boot_boss(fi, p1):
    """reflog.boot for Final Valgas (fight 1 poked to ladder entry 8 = him on stga0): his intro never sets state 22,
    so the healths / CPU flag / timer freezes go on before the fight loads (they hold through it) and the log starts
    600 frames after the last press. reflog.boot's wait for state 22 ran out on him and P1 lost the match unattended."""
    import arcade
    fi.start()
    fi.fc(['wait 1200'], 120)
    row, idx = reflog.route('finalvalgas')
    c = arcade.start(0)
    pick = max(i for i, x in enumerate(c) if x.startswith('press 1 A'))
    cur = reflog.SLOT_CURSOR[reflog.IDS.index(p1)]
    head = [x for x in c[:pick] if not x.startswith('press 1 RIGHT') and not (x == 'wait 10')]
    sel = [f'poke16 0x0C7F2E54 {cur}', 'wait 10', f'poke8 0x0C7F2E45 {row}', f'poke8 0x0C7F2E46 {idx}']
    tail = [x for x in c[pick:] if not x.startswith('freeze16')]
    fi.fc(head + sel + tail[:1] + [f'poke8 0x0C7F2E46 {idx}', 'wait 30', f'poke8 0x0C7F2E46 {idx}'], 300)
    fz = [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
    fz += [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'freeze8 0x{TIMER:08X} 99']
    fi.fc(fz + ['press 1 A 4', 'wait 60'] * 3 + ['wait 600'], 300)
    fi.wait_idle(120)


def run(stg, tag, frames, inst):
    fi = Inst(inst)
    p2 = OWNER[stg]
    p1 = 'ryoma' if p2 == 'falcon' else 'falcon'
    t0 = time.time()
    try:
        if p2 == 'finalvalgas': boot_boss(fi, p1)
        else: reflog.boot(fi, p1, p2)
        fi.fc([f'dump {tag}_ram.bin 0x0C000000 0x1000000'], 60)
        fi.wait_idle(60)
        opp, got = ladder.who(fi.root + f'{tag}_ram.bin')
        os.remove(fi.root + f'{tag}_ram.bin')
        print(f'{tag}: {opp} on {got} (wanted {stg}), boot {time.time() - t0:.0f} s', flush=True)
        segs = ','.join(f'0x{a:08X}:{n}' for a, n in CAM_SEGS + EXTRA)
        cmds = [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
        cmds += [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'freeze8 0x{TIMER:08X} 99', f'capseg {tag} {frames} {segs}']
        for k in range(frames // SHOT):
            cmds += [f'wait {SHOT}', f'shot {tag}_{k:03d}.png']
        fi.fc(cmds, 60)
        fi.wait_idle(frames / 60 * 4 + 600, poll=5)
        time.sleep(1)
        os.makedirs(R + 'dumps/cap', exist_ok=True); os.makedirs(R + 'dumps/shots', exist_ok=True)
        src = fi.root + f'cap/{tag}.bin'
        n = os.path.getsize(src) // FS
        shutil.move(src, R + f'dumps/cap/{tag}.bin')
        for f in os.listdir(fi.root + 'shots'):
            if f.startswith(tag + '_'): shutil.move(fi.root + 'shots/' + f, R + 'dumps/shots/' + f)
        json.dump({'stage': stg, 'got': got.lower(), 'p1': p1, 'p2': p2, 'opp_mdt': opp, 'frames': n, 'frame_size': FS,
                   'segs': segs, 'inst': inst, 'secs': round(time.time() - t0)},
                  open(R + f'dumps/cap/{tag}.meta.json', 'w'), indent=1)
        print(f'{tag}: done, {n} frames, {time.time() - t0:.0f} s', flush=True)
        return got
    finally:
        fi.stop()


if __name__ == '__main__':
    if sys.argv[1] == 'many':
        inst, n = sys.argv[2], int(sys.argv[3])
        for s in sys.argv[4].split(','):
            tag = os.environ.get('SL_PREFIX', 'cl') + s[3:]
            if os.path.exists(R + f'dumps/cap/{tag}.meta.json'): continue
            try:
                run(s, tag, n, inst)
            except Exception as e:   # one stage failing must not stop the others
                print(f'{tag}: FAILED {e!r}', flush=True)
    else:
        run(sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4])
