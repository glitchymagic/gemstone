#!/usr/bin/env python3
"""Fidelity pass: the per-frame reference log of the ORIGINAL (Flycast) and the tape runner.
Both fighters are human-driven by one input tape (P2's CPU flag +0x71ED held at 0, a controller on port B), so a run is
deterministic and the same tape can be played into the remaster (PS_TAPE, game/tests/tape_run.gd) and diffed
(tools/fidelity_diff.py). Schema (one row per frame, both players + globals) = SCHEMA below; the remaster writes the same
names as JSON lines.

Player struct fields (P1 0x0C7E40C4, P2 0x0C7EB394, stride 0x72D0), found by full-struct captures (docs/FIDELITY.md):
  +0x020 x,y,z f32 (cm, FEET: y = 0 on Londo's plaza)   +0x7270 velocity x,y,z f32 (cm/frame)
  +0x7248 u16 facing (0 = +z, 0x4000 = +x)              +0x719E u16 motion frame counter   +0x71A4/5 kind / motion
  +0x71BA state (+0x71BB previous)  +0x71D4 s16 health  +0x71ED CPU flag  +0x71F3 Power Change  +0x71F4 s16 gauge
  +0x720E combo count  +0x7230 gems, +0x7231 gem mask   +0x100 hit id / attack set / body set
Globals: 0x0C7F304D u8 round clock (99 s), 0x0C7F302C round phase (2 ready, 3 fight), 0x0C346A50 C rand state, camera 0x0C7F2664 (+0x450 eye, +0x480 target).

  reflog.py tape TAPE NAME P1 P2 [INST]   boot arcade P1 (fighter id) vs P2 on P2's home stage, both human, play TAPE
                                          from the fight's first free frame -> dumps/fidelity/NAME.jsonl
  reflog.py decode NAME                   .bin -> .jsonl (dumps/fidelity)
Tape file: one line per frame "P1MASK P2MASK" hex, bits = flycast_drive.lua BUTTONS (C 1, B 2, A 4, START 8, UP 10,
DOWN 20, LEFT 40, RIGHT 80, Y 200, X 400). Tools/tapes.py writes them."""
import json, os, struct, sys, time
sys.path.insert(0, './tools')
R = './'
OUT = R + 'dumps/fidelity/'
P1, P2 = 0x0C7E40C4, 0x0C7EB394
BASES = (P1, P2)
CAM = 0x0C7F2664
# (name, offset, bytes, unpacker on the captured bytes)
PFIELDS = [(0x020, 12), (0x7270, 12), (0x7248, 4), (0x719C, 12), (0x71B8, 4), (0x71D4, 4), (0x71EC, 12), (0x720C, 4),
           (0x7230, 4), (0x100, 4)]
GFIELDS = [(0x0C7F2F20, 16), (0x0C346A50, 4), (CAM + 0x450, 12), (CAM + 0x480, 12), (0x0C7F305C, 4), (0x0C7F302C, 4),
           (0x0C7F304C, 4)]
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']
SLOT_CURSOR = {8: 0, 0: 1, 6: 2, 2: 3, 4: 4, 3: 5, 5: 6, 7: 7, 1: 8, 9: 9}   # player number -> select cursor
LADDER = [[0, 6, 5, 7, 1, 4, 8, 9, 10], [2, 7, 1, 4, 6, 0, 8, 9, 10], [1, 2, 5, 6, 3, 4, 8, 9, 10],
          [3, 0, 7, 4, 5, 6, 8, 9, 10], [6, 3, 5, 1, 2, 0, 8, 9, 10], [4, 5, 2, 0, 7, 1, 8, 9, 10],
          [5, 0, 1, 3, 2, 7, 8, 9, 10], [7, 1, 4, 2, 5, 3, 8, 9, 10]]


def segs():
    out = [f'0x{b + o:08X}:{n}' for b in BASES for o, n in PFIELDS]
    return ','.join(out + [f'0x{a:08X}:{n}' for a, n in GFIELDS])


def frame_size():
    return 2 * sum(n for _, n in PFIELDS) + sum(n for _, n in GFIELDS)


def _player(d):
    x, y, z = struct.unpack('<3f', d[0x020])
    vx, vy, vz = struct.unpack('<3f', d[0x7270])
    ang = struct.unpack('<H', d[0x7248][:2])[0]
    fr = struct.unpack('<H', d[0x719C][2:4])[0]
    kind, mot = d[0x719C][8], d[0x719C][9]
    st, pst = d[0x71B8][2], d[0x71B8][3]
    hp = struct.unpack('<h', d[0x71D4][:2])[0]
    cpu, pc = d[0x71EC][1], d[0x71EC][7]
    gauge = struct.unpack('<h', d[0x71EC][8:10])[0]
    return dict(x=round(x, 2), y=round(y, 2), z=round(z, 2), vx=round(vx, 3), vy=round(vy, 3), vz=round(vz, 3), ang=ang,
                kind=kind, mot=mot, fr=fr, st=st, pst=pst, hp=hp, cpu=cpu, pc=pc, gauge=gauge, combo=d[0x720C][2],
                gems=d[0x7230][0], hid=d[0x100][0])


def decode(path):
    raw = open(path, 'rb').read()
    fs = frame_size()
    rows = []
    for f in range(len(raw) // fs):
        fr = raw[f * fs:(f + 1) * fs]
        pos, ps = 0, []
        for _ in BASES:
            d = {}
            for o, n in PFIELDS:
                d[o] = fr[pos:pos + n]; pos += n
            ps.append(_player(d))
        g = {}
        for a, n in GFIELDS:
            g[a] = fr[pos:pos + n]; pos += n
        cam_eye = struct.unpack('<3f', g[CAM + 0x450]); cam_t = struct.unpack('<3f', g[CAM + 0x480])
        rows.append(dict(f=f, p=ps, timer=struct.unpack('<H', g[0x0C7F2F20][8:10])[0], tsub=list(g[0x0C7F2F20]),
                         rand=struct.unpack('<I', g[0x0C346A50])[0], eye=[round(v, 1) for v in cam_eye],
                         tgt=[round(v, 1) for v in cam_t], lvl=g[0x0C7F305C][0], phase=g[0x0C7F302C][0],
                         clock=g[0x0C7F304C][1]))
    return rows


def write_jsonl(rows, path):
    with open(path, 'w') as f:
        for r in rows: f.write(json.dumps(r, separators=(',', ':')) + '\n')


def route(p2):
    """(row, fight index) whose ladder entry is P2's player number (fight 1 of an arcade run)."""
    n = IDS.index(p2)
    for r, row in enumerate(LADDER):
        if row[0] == n: return r, 0
    for r, row in enumerate(LADDER):
        if n in row: return r, row.index(n)
    raise ValueError(p2)


def boot(fi, p1, p2):
    """Flycast instance FI up, arcade as P1, fight 1 = P2 on P2's home stage, at the round's ready state (P1 state 22)."""
    import arcade
    fi.start()
    fi.fc(['wait 1200'], 120)
    row, idx = route(p2)
    c = arcade.start(0)
    pick = max(i for i, x in enumerate(c) if x.startswith('press 1 A'))
    cur = SLOT_CURSOR[IDS.index(p1)]
    head = [x for x in c[:pick] if not x.startswith('press 1 RIGHT') and not (x == 'wait 10')]
    sel = [f'poke16 0x0C7F2E54 {cur}', 'wait 10', f'poke8 0x0C7F2E45 {row}', f'poke8 0x0C7F2E46 {idx}']
    # no frozen health: the tape plays the whole fight as it is
    tail = [x for x in c[pick:] if not x.startswith('freeze16')]
    fi.fc(head + sel + tail[:1] + [f'poke8 0x0C7F2E46 {idx}', 'wait 30', f'poke8 0x0C7F2E46 {idx}'], 300)
    fi.fc(['press 1 A 4', 'wait 60'] * 3 + [f'until8 0x{P1 + 0x71BA:08X} 22 4000'], 300)


def play(fi, tape, name, start='ready'):
    """From P1's ready state (22): P2 human (CPU flag 0), the rand state set to 1 (a fixed start), then the tape and the
    log start together on the first frame P1 leaves state 22 (start='ready': the tape covers the input lock too)."""
    os.makedirs(OUT, exist_ok=True)
    cap = f'{name}'
    lines = [f'freeze8 0x{P2 + 0x71ED:08X} 0', f'freeze8 0x{P1 + 0x71ED:08X} 0']
    if start == 'ready':   # round phase byte 0x0C7F302C: 2 = both intros done ("Ready"), 3 = fight on (attacks unlock)
        lines += [f'until8 0x0C7F302C 3 6000']
    lines += ['poke32 0x0C346A50 1', f'tapelog {cap} {segs()}', f'tape {os.path.abspath(tape)}', f'shot {name}_end.png']
    n = sum(1 for l in open(tape) if l.strip())
    fi.fc([f'dump {name}_ram.bin 0x0C000000 0x1000000'], 60)
    fi.wait_idle(60)
    import ladder
    opp, stg = ladder.who(fi.root + f'{name}_ram.bin')
    os.remove(fi.root + f'{name}_ram.bin')
    fi.fc(lines, 60)
    fi.wait_idle(n / 60 * 6 + 300)
    time.sleep(1)
    src = fi.root + f'cap/{cap}.bin'
    rows = decode(src)
    os.replace(src, OUT + name + '.bin')
    write_jsonl(rows, OUT + name + '.jsonl')
    json.dump({'p2': opp, 'stage': stg.lower(), 'tape': os.path.basename(tape), 'frames': len(rows)},
              open(OUT + name + '.meta.json', 'w'))
    if os.path.exists(fi.root + f'shots/{name}_end.png'): os.replace(fi.root + f'shots/{name}_end.png', OUT + name + '_end.png')
    return rows


if __name__ == '__main__':
    from fcinst import Inst
    if sys.argv[1] == 'decode':
        write_jsonl(decode(OUT + sys.argv[2] + '.bin'), OUT + sys.argv[2] + '.jsonl')
    elif sys.argv[1] == 'tape':
        tape, name, p1, p2 = sys.argv[2:6]
        fi = Inst(sys.argv[6] if len(sys.argv) > 6 else 'a')
        boot(fi, p1, p2)
        rows = play(fi, tape, name)
        print(name, len(rows), 'frames', flush=True)
        fi.stop()
