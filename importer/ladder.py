#!/usr/bin/env python3
"""The original arcade ladder, from your 1ST_READ.BIN -> game/assets/ripped/ladder.json (read by Roster.load_ladder).
Rows: the game's ladder table at 0x8C1525BF, 10 rows x 9 player numbers (rows 0-7 are the ones the game picks, see
docs/ARCADE-ROW.md). Stage of each fight: the opponent's home stage (player Pk0 fights on STGk0: true for every fight of
the logged arcade runs, Final Valgas included). Usage: ladder.py 1ST_READ.BIN out.json"""
import json, sys

IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
TABLE = 0x8C1525BF


def build(b):
    o = TABLE - 0x8C010000
    rows = [list(b[o + 9 * r:o + 9 * r + 9]) for r in range(10)]
    return {'rows': [[IDS[k] for k in r] for r in rows], 'pick_rows': list(range(8)),
            'stage': {IDS[k]: 'stg%x0' % k for k in range(len(IDS))}}


if __name__ == '__main__':
    json.dump(build(open(sys.argv[1], 'rb').read()), open(sys.argv[2], 'w'), indent=1)
    print('ladder ->', sys.argv[2])
