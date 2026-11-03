#!/usr/bin/env python3
"""The original arcade ladder -> game/assets/ripped/ladder.json for the remaster's arcade mode.
Rows: the game's own ladder table in 1ST_READ.BIN (mem 0x8C1525BF, 10 rows x 9 player ids; referenced from the
literal pools of 0x0C0A41D4 / 0c0a5042 / 0c0a8d6c / 0c0a9d12). Rows 0-7 are 6 regulars (mirror included) then
Kraken 8, Valgas 9, Final Valgas 10. Two logged runs as Falcon got rows 7 and 6, so the pick is not per fighter; the
remaster picks one of rows 0-7 at random (the pick rule itself is not decoded yet). Rows 8-9 are kept, use unknown.
Stages: work/ladder.json (tools/ladder.py: who and where, from RAM dumps of a real run)."""
import json
R = './'
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
PC = {'P%X0' % k: v for k, v in enumerate(IDS)}
b = open(R + 'rip/fs/1ST_READ.BIN', 'rb').read()
o = 0x8C1525BF - 0x8C010000
rows = [list(b[o + 9 * r:o + 9 * r + 9]) for r in range(10)]
logged = json.load(open(R + 'work/ladder.json'))
stage = {PC[e['opponent']]: e['stage'].lower() for e in logged if e['opponent'] in PC and e['stage'] != '?'}
out = {'rows': [[IDS[k] for k in r] for r in rows], 'pick_rows': list(range(8)), 'stage': stage,
       'logged_run': [PC.get(e['opponent'], '?') for e in logged]}
json.dump(out, open(R + 'game/assets/ripped/ladder.json', 'w'), indent=1)
print(json.dumps(out)[:600])
