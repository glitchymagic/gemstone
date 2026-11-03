#!/usr/bin/env python3
"""The original's round start points per stage: arcade P1 vs the stage's owner (fight 1 on his home stage), both fighters'
feet x, y, z and facing at the fight's first frame (round phase 3; nobody has moved since the intros).
-> game/assets/fidelity/spawns.json {stage: [[x, y, z, ang], [x, y, z, ang]]} (cm, u16 heading)
  spawns.py INST STAGE...      (e.g. spawns.py a stg00 stg10)"""
import json, os, struct, sys
sys.path.insert(0, './tools')
from fcinst import Inst
import reflog
R = './'
OUT = R + 'game/assets/fidelity/spawns.json'
OWNER = {'stg00': 'falcon', 'stg10': 'ryoma', 'stg20': 'wangtang', 'stg30': 'jack', 'stg40': 'gunrock', 'stg50': 'galuda',
         'stg60': 'ayame', 'stg70': 'rouge', 'stg80': 'kraken', 'stg90': 'valgas', 'stga0': 'finalvalgas'}


def one(fi, stg):
    p2 = OWNER[stg]
    reflog.boot(fi, 'ryoma' if p2 != 'ryoma' else 'falcon', p2)
    fi.fc([f'freeze8 0x{reflog.P2 + 0x71ED:08X} 0', 'until8 0x0C7F302C 3 6000', 'wait 2', 'dump sp.bin 0x0C7E40C4 0xE5A0'], 120)
    fi.wait_idle(120)
    b = open(fi.root + 'sp.bin', 'rb').read()
    out = []
    for base in (0, 0x72D0):
        x, y, z = struct.unpack_from('<3f', b, base + 0x20)
        a = struct.unpack_from('<H', b, base + 0x7248)[0]
        out.append([round(x, 1), round(y, 1), round(z, 1), a])
    return out


if __name__ == '__main__':
    fi = Inst(sys.argv[1])
    for stg in sys.argv[2:]:
        try:
            r = one(fi, stg)
        except Exception as e:
            print(stg, 'failed', e, flush=True); continue
        d = json.load(open(OUT)) if os.path.exists(OUT) else {}
        d[stg] = r
        json.dump(d, open(OUT, 'w'), indent=1, sort_keys=True)
        print(stg, r, flush=True)
    fi.stop()
