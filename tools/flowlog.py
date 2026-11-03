#!/usr/bin/env python3
"""fx-flow: the ORIGINAL's round + game flow, frame by frame, from an isolated Flycast (tools/fcinst.py).
One capseg per run: round phase 0x0C7F302C, round clock 0x0C7F304D, MV_OK 0x0C7F3050, the arcade block, both players'
feet x/y/z, motion kind/id/frame, state, health, CPU flag, gems, plus three raw global blocks (0x0C7F2E40, 0x0C7F2F00,
0x0C7F3000) for finding screen bytes; a screenshot every EVERY frames (tools/flow_shots.lua, same frame count).
  flowlog.py round INST P1 P2 NAME   arcade P1 vs P2 on P2's home stage: 2-round KO match (P1 = the game's AI, P2 at 20
                                    health each round), the next fight's screens + intro, a TIME OVER round, round 2
  flowlog.py screens INST NAME       power-on > title > ARCADE > select > VS > fight; P1 idle and at 10 health -> loses
                                    2 rounds -> continue countdown left alone -> game over -> title -> attract demo
  flowlog.py ladder INST P1 IDX NAME  arcade P1, fight index poked to IDX (6 = Kraken), P1 = AI, every opponent at 20
                                    health: the boss transitions, Final Valgas, the ending
  flowlog.py decode NAME             .bin -> .jsonl
Output: /tmp/ps-fx-flow/NAME.{bin,jsonl,meta.json} + shots/NAME_*.png"""
import json, os, struct, sys, time
sys.path.insert(0, './tools')
OUT = '/tmp/ps-fx-flow/'
HERE = os.path.dirname(os.path.abspath(__file__))
P1, P2 = 0x0C7E40C4, 0x0C7EB394
PH, CLK, MVOK = 0x0C7F302C, 0x0C7F304D, 0x0C7F3050
PF = [(0x020, 12), (0x719C, 12), (0x71B8, 4), (0x71D4, 4), (0x71EC, 4), (0x7230, 4)]
GB = [(0x0C7F2E40, 0x40), (0x0C7F2F00, 0x40), (0x0C7F3000, 0x80)]
EVERY = 30


def segs():
    return ','.join([f'0x{b + o:08X}:{n}' for b in (P1, P2) for o, n in PF] + [f'0x{a:08X}:{n}' for a, n in GB])


def fsize():
    return 2 * sum(n for _, n in PF) + sum(n for _, n in GB)


def decode(path):
    raw = open(path, 'rb').read()
    fs = fsize()
    rows = []
    for f in range(len(raw) // fs):
        b = raw[f * fs:(f + 1) * fs]
        pos, ps = 0, []
        for _ in (P1, P2):
            d = {}
            for o, n in PF:
                d[o] = b[pos:pos + n]; pos += n
            x, y, z = struct.unpack('<3f', d[0x020])
            ps.append(dict(x=round(x, 1), y=round(y, 1), z=round(z, 1), fr=struct.unpack('<H', d[0x719C][2:4])[0],
                           kind=d[0x719C][8], mot=d[0x719C][9], st=d[0x71B8][2], hp=struct.unpack('<h', d[0x71D4][:2])[0],
                           cpu=d[0x71EC][1], gems=d[0x7230][0]))
        g = {}
        for a, n in GB:
            g[a] = b[pos:pos + n]; pos += n
        blk = g[0x0C7F3000]
        rows.append(dict(f=f, phase=blk[PH - 0x0C7F3000], clock=blk[CLK - 0x0C7F3000], mvok=blk[MVOK - 0x0C7F3000],
                         row=g[0x0C7F2E40][5], fidx=g[0x0C7F2E40][6], p=ps,
                         g=(g[0x0C7F2E40] + g[0x0C7F2F00] + blk).hex()))
    return rows


def write(name):
    rows = decode(OUT + name + '.bin')
    with open(OUT + name + '.jsonl', 'w') as f:
        for r in rows: f.write(json.dumps(r, separators=(',', ':')) + '\n')
    return rows


def hook(name):
    p = OUT + f'hook_{name}.lua'
    open(p, 'w').write(f'FLOW_TAG = "{name}"\nFLOW_EVERY = {EVERY}\ndofile("{HERE}/flow_shots.lua")\n')
    return p


def hp(base, v):
    return [f'poke16 0x{base + 0x71D4 + 2 * i:08X} {v}' for i in range(3)]


def cpu(base, v):
    return f'freeze8 0x{base + 0x71ED:08X} {v}'


def until_ph(v, mx=6000):
    return f'until8 0x{PH:08X} {v} {mx}'


def collect(fi, name, frames):
    os.makedirs(OUT + 'shots', exist_ok=True)
    src = fi.root + f'cap/{name}.bin'
    os.replace(src, OUT + name + '.bin')
    for f in os.listdir(fi.root + 'shots'):
        if f.startswith(name + '_'): os.replace(fi.root + 'shots/' + f, OUT + 'shots/' + f)
    rows = write(name)
    json.dump({'frames': len(rows), 'requested': frames, 'every': EVERY}, open(OUT + name + '.meta.json', 'w'))
    return rows


def run_round(fi, p1, p2, name, frames=16000):
    import reflog
    reflog.boot(fi, p1, p2)   # stops on P1's first intro frame (state 22)
    st1 = f'0x{P1 + 0x71BA:08X}'
    q = [f'lua {hook(name)}', f'capseg {name} {frames} {segs()}', cpu(P1, 1),
         until_ph(3), *hp(P2, 20), *hp(P1, 200), 'mark r1_fight', until_ph(4), 'mark r1_call',
         until_ph(3), *hp(P2, 20), 'mark r2_fight', until_ph(4), 'mark r2_call',
         f'until8 {st1} 22 4000', 'mark fight2_intro', cpu(P1, 0), cpu(P2, 0),
         until_ph(3), f'poke8 0x{CLK:08X} 4', 'mark f2r1_clock4', until_ph(4), 'mark f2r1_time',
         until_ph(3), 'mark f2r2_fight']
    fi.fc(q, 60)
    fi.wait_idle(frames / 60 * 4 + 600)
    time.sleep(2)
    return collect(fi, name, frames)


def run_spots(fi, p1, p2, name, frames=3200):
    """one KO round on P2's home stage (P1 = the game's AI, P2 at 20 health): the stage's phase-5 win / lose spots"""
    import reflog
    reflog.boot(fi, p1, p2)
    q = [f'lua {hook(name)}', f'capseg {name} {frames} {segs()}', cpu(P1, 1), until_ph(3), *hp(P2, 20), *hp(P1, 200),
         'mark r1_fight', until_ph(5, 4000), 'mark r1_poses']
    fi.fc(q, 60)
    fi.wait_idle(frames / 60 * 4 + 600)
    time.sleep(2)
    return collect(fi, name, frames)


def run_screens(fi, name, frames=24000):
    fi.start()
    q = [f'lua {hook(name)}', f'capseg {name} {frames} {segs()}', 'wait 1200', 'mark start1',
         'press 1 START 5', 'wait 120', 'press 1 START 5', 'wait 150', 'press 1 A 5', 'wait 270', 'mark pick', 'press 1 A 5',
         until_ph(3, 4000), *hp(P1, 10), 'mark r1_fight', until_ph(4), 'mark r1_call',
         until_ph(3), *hp(P1, 10), 'mark r2_fight', until_ph(4), 'mark r2_call']
    fi.fc(q, 60)
    fi.wait_idle(frames / 60 * 4 + 600)
    time.sleep(2)
    return collect(fi, name, frames)


def run_cont(fi, name, frames=16000):
    """screens + START during the continue countdown (what follows), then a TIME OVER won on health (P1 ahead)"""
    fi.start()
    q = [f'lua {hook(name)}', f'capseg {name} {frames} {segs()}', 'wait 1200', 'mark start1',
         'press 1 START 5', 'wait 120', 'press 1 START 5', 'wait 150', 'press 1 A 5', 'wait 270', 'mark pick', 'press 1 A 5',
         until_ph(3, 4000), *hp(P1, 10), 'mark r1_fight', until_ph(4), 'mark r1_call',
         until_ph(3), *hp(P1, 10), 'mark r2_fight', until_ph(7, 3000), 'mark cont', 'wait 300', 'press 1 START 5',
         'mark start_pressed', 'wait 400', 'press 1 A 5', 'mark a_pressed', until_ph(3, 6000), cpu(P2, 0), *hp(P2, 200),
         f'poke8 0x{CLK:08X} 3', 'mark time_ahead', until_ph(4), until_ph(3, 3000), *hp(P1, 150),
         f'poke8 0x{CLK:08X} 3', 'mark time_behind', until_ph(4)]
    fi.fc(q, 60)
    fi.wait_idle(frames / 60 * 4 + 600)
    time.sleep(2)
    return collect(fi, name, frames)


def run_ladder(fi, p1, idx, name, frames=40000):
    import reflog
    reflog.boot(fi, p1, 'kraken')
    q = [f'lua {hook(name)}', f'capseg {name} {frames} {segs()}', cpu(P1, 1), f'poke8 0x0C7F2E46 {idx}']
    for k in range(7):   # 3 fights x 2 rounds (+1 spare): every opponent round at 20 health
        q += [until_ph(3, 9000), *hp(P2, 20), f'mark r{k}_fight', until_ph(4, 9000), f'mark r{k}_call']
    fi.fc(q, 60)
    fi.wait_idle(frames / 60 * 4 + 600)
    time.sleep(2)
    return collect(fi, name, frames)


if __name__ == '__main__':
    from fcinst import Inst
    a = sys.argv[1:]
    os.makedirs(OUT, exist_ok=True)
    if a[0] == 'decode':
        write(a[1])
    else:
        fi = Inst(a[1])
        try:
            if a[0] == 'round': rows = run_round(fi, a[2], a[3], a[4])
            elif a[0] == 'screens': rows = run_screens(fi, a[2])
            elif a[0] == 'cont': rows = run_cont(fi, a[2])
            elif a[0] == 'spots': rows = run_spots(fi, a[2], a[3], a[4])
            elif a[0] == 'ladder': rows = run_ladder(fi, a[2], int(a[3]), a[4])
            print(a[-1], len(rows), 'frames', flush=True)
            open(OUT + a[-1] + '.flycast.log', 'w').write(fi.log())
        finally:
            fi.stop()
