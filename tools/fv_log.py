#!/usr/bin/env python3
"""Final Valgas's own AI (0x0C08D5CE, docs/CPU.md section 9 / "Final Valgas port") on the disc: CPU-vs-CPU matches on
his arena STGA0 logged every frame, both sides the game's AI (P1 Falcon +0x71ED frozen at 1), CPU level 0x0C7F305C
(+ rank 0x0C7F305D = level * 8) frozen, nothing else held (health, clock and rounds run as in the arcade).
Way in = tools/area_probe.py's boot_boss (fight 1 poked to Valgas and won, his arena next), copied here: area_probe is a
script. Rows = tools/cpu_stats.py's per-frame schema + `fv` = his 36-byte AI block (0x0C439E38 + player index * 36)
as hex, so `cpu_stats.py stats` reduces them like every other CPU log (keep only the rows with P2 ch 10: a log can
start in fight 1).
  fv_log.py INST LEVEL NAME [FRAMES]   -> LOGDIR/cpu_falcon_finalvalgas_L{LEVEL}_{NAME}.{bin,jsonl,meta.json}"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cpu_stats as CS
import reflog as RL
from fcinst import Inst

LOGDIR = os.environ.get('CPU_LOGDIR', '/tmp/ps-fx-fv/disc/')
FVB, FVN = 0x0C439E38, 72          # both players' 36-byte blocks


def boot_boss(fi):
    """Arcade as Falcon, fight 1 poked to ladder row 6 index 7 (Valgas), the game's AI drives P1 and P2's health is
    held at 0, so the first hit wins fight 1; then the Valgas change and Final Valgas's fight (P2 character byte +4 =
    10, round phase 3). Returns on his fight's first frame."""
    import arcade
    P1, P2 = RL.P1, RL.P2
    fi.start()
    fi.fc(['wait 1200'], 120)
    fi.fc(arcade.start(0), 300)
    fi.wait_idle(200)
    fi.fc(['poke8 0x0C7F2E45 6', 'poke8 0x0C7F2E46 7'], 30)

    def peek(addr, n=4):
        fi.fc([f'dump peek.bin 0x{addr:08X} {n}'], 60); fi.wait_idle(60); time.sleep(0.3)
        return open(fi.root + 'peek.bin', 'rb').read()
    fi.fc([f'freeze8 0x{P1 + 0x71ED:08X} 1'], 30)   # P1 = the game's AI too: it walks up and lands the KO hit itself
    # fight 1 (Valgas, his health held at 0) until its KO (round phase 4), frame-accurate in the Lua queue
    hold = [f'freeze16 0x{P2 + 0x71D4 + 2 * i:08X} 0' for i in range(3)]
    free = [f'unfreeze 0x{P2 + 0x71D4 + 2 * i:08X}' for i in range(3)]
    fi.fc(hold + ['until8 0x0C7F302C 4 30000'] + free, 900)
    fi.wait_idle(900)
    # story / loading screens wait for A; then Final Valgas's round (P2 character byte +4 = 10, round phase 3)
    for _ in range(150):
        fi.fc(['wait 30', 'press 1 A 4', 'wait 26'], 30)
        fi.wait_idle(30)
        if peek(P2 + 4)[0] == 10 and peek(0x0C7F302C)[0] in (2, 3): break
    fi.fc(['until8 0x0C7F302C 3 3000'], 300)
    fi.wait_idle(200)
    if peek(P2 + 4)[0] != 10: raise RuntimeError('fight 2 is not Final Valgas')


def decode(path):
    raw = open(path, 'rb').read()
    fs = CS.frame_size()
    n = len(raw) // (fs + FVN)
    core = b''.join(raw[i * (fs + FVN):i * (fs + FVN) + fs] for i in range(n))
    tmp = path + '.core'
    open(tmp, 'wb').write(core)
    rows = CS.decode(tmp)
    os.remove(tmp)
    for i, r in enumerate(rows):
        r['fv'] = raw[i * (fs + FVN) + fs + 36:(i + 1) * (fs + FVN)].hex()
    return rows


def run(inst, lvl, name, frames=21000):
    os.makedirs(LOGDIR, exist_ok=True)
    fi = Inst(inst)
    tag = f'cpu_falcon_finalvalgas_L{lvl}_{name}'
    t0 = time.time()
    try:
        boot_boss(fi)
        P1, P2 = RL.P1, RL.P2
        lines = [f'unfreeze 0x{P1 + 0x71D4 + 2 * k:08X}' for k in range(3)]
        lines += [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'freeze8 0x{P2 + 0x71ED:08X} 1',
                  f'freeze8 0x{CS.LEVEL:08X} {lvl}', f'freeze8 0x{CS.RANK:08X} {min(255, lvl * 8)}',
                  f'capseg {tag} {frames} {CS.segs()},0x{FVB:08X}:{FVN}']
        fi.fc(lines, 60)
        fi.wait_idle(frames / 60 * 8 + 600, 5)
        time.sleep(1)
        src = fi.root + f'cap/{tag}.bin'
        rows = decode(src)
        os.replace(src, LOGDIR + tag + '.bin')
        RL.write_jsonl(rows, LOGDIR + tag + '.jsonl')
        json.dump({'p1': 'falcon', 'p2': 'finalvalgas', 'level': lvl, 'fight': 8, 'frames': len(rows),
                   'wall_s': round(time.time() - t0)}, open(LOGDIR + tag + '.meta.json', 'w'))
        print(tag, len(rows), 'frames', round(time.time() - t0), 's', flush=True)
    finally:
        fi.stop()


if __name__ == '__main__':
    run(sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 21000)
