#!/usr/bin/env python3
"""The original's per-fighter movement table (1ST_READ 0x0C339540 + char * 0x98 + PC * 0x4C: 19 floats, found by fx-obj
from the wall-kick code) -> game/assets/fidelity/move_table.json. Checked on the disc's 16 CPU-vs-CPU fights
(dumps/fidelity/cpu): standing AND moving jumps start at [4] with gravity [6] every fighter (Jack 27 / 1.08, Gunrock
25.8 / 1.15, Rouge 30 / 1.3, Kraken 27 / 1.2, Wang-Tang / Ayame 40 / 2, Valgas 37 / 2.1, the rest 35.5 / 2), the moving
jump flies [14] + [13] (run + 0.25), runs at [14] (8.5 - 10.5), the standing jump's air control is [7] (10.5), the wall
kick-off [10] up (25) and [11] out (2.0) with gravity [6]; falls off an edge (states 14 / 31) use 2 for everyone.
  move_table.py"""
import json, os, struct
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
FIELDS = {4: 'jump_vy', 6: 'jump_g', 7: 'air_ctrl', 10: 'wallkick_vy', 11: 'wallkick_out', 13: 'mjump_add', 14: 'run'}
B = open(R + 'rip/fs/1ST_READ.BIN', 'rb').read()
out = {'source': '1ST_READ 0x0C339540 + char*0x98 + pc*0x4C, 19 f32 (tools/move_table.py)', 'fields': {str(k): v for k, v in FIELDS.items()}}
for c, n in enumerate(NAMES):
    out[n] = {f'pc{pc}': [round(x, 4) for x in struct.unpack_from('<19f', B, 0x0C339540 + c * 0x98 + pc * 0x4C - 0x0C010000)] for pc in (0, 1)}
json.dump(out, open(R + 'game/assets/fidelity/move_table.json', 'w'), indent=1)
print({n: out[n]['pc0'][14] for n in NAMES})
