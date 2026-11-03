#!/usr/bin/env python3
"""fx-cov: record the ORIGINAL for coverage tapes (reflog.boot / play) with the stage's object pool logged per frame
too: gems, items, item chests, throwables, poles (docs/COVERAGE.md).
  covlog.py orig INST TAPE...   -> dumps/fidelity/o_TAPE.jsonl (+ .meta.json, the same rows as reflog) and
                                   o_TAPE.obj.jsonl: per frame [[slot, type, owner, kind, b5, x, y, z, b30C, b30D], ...]
                                   for every live object (word 0 != 0)
  covlog.py objs NAME [KIND...]  print object timelines (spawn / despawn / moves) of a logged run
Object pool (Londo fight dump, 10-27): 0x0C7D0980 + slot * 0x31C, linked lists from heads 0x0C7E4078.. (+0x18 next):
+2 type (2 prop / item chest, 3 gem / item, 4 scenery, 5 players + effects, 6 ...), +3 owner (0 P1, 1 P2, 2 stage),
+4 kind (1 throwable, 2 pole, 5 gem, 6 item on the floor, 7 item chest, 8 ...), +0x20 x,y,z f32 cm, +0x30C item id,
+0x30D sub-state (docs/CPU.md "object lists")."""
import json, os, struct, sys, time
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
sys.path.insert(0, REPO + 'tools')
import reflog, tapes
D = './dumps/fidelity/'
POOL, STRIDE, SLOTS = 0x0C7D0980, 0x31C, int(os.environ.get('COV_SLOTS', '48'))
OSEGS = [(POOL + s * STRIDE + o, n) for s in range(SLOTS) for o, n in ((0x0, 8), (0x20, 12), (0x30C, 4))]


def segs():
    return reflog.segs() + ',' + ','.join(f'0x{a:08X}:{n}' for a, n in OSEGS)


def split(path):
    raw = open(path, 'rb').read()
    fs0 = reflog.frame_size()
    fs = fs0 + sum(n for _, n in OSEGS)
    std, objs = bytearray(), []
    for f in range(len(raw) // fs):
        fr = raw[f * fs:(f + 1) * fs]
        std += fr[:fs0]
        pos, row = fs0, []
        for s in range(SLOTS):
            h = fr[pos:pos + 8]; xyz = struct.unpack('<3f', fr[pos + 8:pos + 20]); t = fr[pos + 20:pos + 24]
            pos += 24
            if h[:4] != b'\0\0\0\0':
                row.append([s, h[2], h[3], h[4], h[5]] + [round(v, 1) for v in xyz] + [t[0], t[1]])
        objs.append(row)
    return bytes(std), objs


def play(fi, tape, name):
    lines = [f'freeze8 0x{reflog.P2 + 0x71ED:08X} 0', f'freeze8 0x{reflog.P1 + 0x71ED:08X} 0',
             'until8 0x0C7F302C 3 6000', 'poke32 0x0C346A50 1', f'tapelog {name} {segs()}', f'tape {os.path.abspath(tape)}',
             f'shot {name}_end.png']
    n = sum(1 for l in open(tape) if l.strip())
    fi.fc([f'dump {name}_ram.bin 0x0C000000 0x1000000'], 60)
    fi.wait_idle(60)
    import ladder
    opp, stg = ladder.who(fi.root + f'{name}_ram.bin')
    os.replace(fi.root + f'{name}_ram.bin', '/tmp/ps-fx-cov/' + name + '_ready_ram.bin')
    t0 = time.time()
    fi.fc(lines, 60)
    fi.wait_idle(n / 60 * 12 + 600)
    time.sleep(1)
    std, objs = split(fi.root + f'cap/{name}.bin')
    open(D + name + '.bin', 'wb').write(std)
    os.remove(fi.root + f'cap/{name}.bin')
    rows = reflog.decode(D + name + '.bin')
    reflog.write_jsonl(rows, D + name + '.jsonl')
    with open(D + name + '.obj.jsonl', 'w') as f:
        for r in objs: f.write(json.dumps(r, separators=(',', ':')) + '\n')
    json.dump({'p2': opp, 'stage': stg.lower(), 'tape': os.path.basename(tape), 'frames': len(rows),
               'objlog': f'{SLOTS} slots', 'secs': round(time.time() - t0)}, open(D + name + '.meta.json', 'w'))
    if os.path.exists(fi.root + f'shots/{name}_end.png'): os.replace(fi.root + f'shots/{name}_end.png', D + name + '_end.png')
    return rows


def orig(inst, names):
    from fcinst import Inst
    fi = Inst(inst)
    try:
        for t in names:
            src = REPO + f'game/tests/tapes/{t}.tape'
            out = D + f'cov/tapes/{t}.txt'
            tapes.build(src, out)
            m = tapes.meta(src)
            reflog.boot(fi, m['p1'], m['p2'])
            rows = play(fi, out, 'o_' + t)
            print(f'orig {t}: {len(rows)} frames', flush=True)
    finally:
        fi.stop()


def objs(name, kinds=None):
    prev = {}
    for f, ln in enumerate(open(D + f'o_{name}.obj.jsonl')):
        cur = {o[0]: o for o in json.loads(ln)}
        for s, o in cur.items():
            if kinds and o[3] not in kinds: continue
            p = prev.get(s)
            if p is None or p[1:5] != o[1:5] or p[8:] != o[8:]:
                print(f, 'slot', s, 'type/owner/kind/b5', o[1:5], 'xyz', o[5:8], 'id/sub', o[8:])
        for s in prev:
            if s not in cur and (not kinds or prev[s][3] in kinds): print(f, 'slot', s, 'GONE')
        prev = cur


if __name__ == '__main__':
    if sys.argv[1] == 'orig': orig(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == 'objs': objs(sys.argv[2], [int(k) for k in sys.argv[3:]] or None)
