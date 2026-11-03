#!/usr/bin/env python3
"""Pass 4: a real fight on one opponent's home stage, for that stage's throwables and its PowerVR background plane.
Arcade as Falcon; during fight 1 the ladder row (0x0C7F2E45) is poked to 6 (Galuda, Falcon, Ryoma, Jack, Wang-Tang,
Rouge, Kraken, Valgas, Final Valgas) and the fight index (0x0C7F2E46) to TARGET-1, fight 1 is won (P2 health held at 0
while P1 punches), so fight 2 is row 6[TARGET] on its home stage. There both healths are held at 240 and the CPU fights;
P1's CPU flag (+0x71ED) is set too so the game's AI may drive P1 as well. Every EVERY frames: RAM dump + shot + the
background plane (ISP_BACKGND_T tag at PARAM_BASE in 32-bit VRAM: ISP/TSP/TCW words + 3 vertices x,y,z,ARGB).
  stagefight.py TARGET TAG [DUMPS] [EVERY]     TARGET = 3 Jack, 5 Rouge, 6 Kraken, 7 Valgas, 8 Final Valgas
  stagefight.py ladder ROW TAG N,N,... [LOG]  a whole ladder row, N dumps on each fight (both sides the game's AI);
                                              LOG = frames of per-frame hit fields per fight (hitlog.LITE)"""
import os, sys, time
sys.path.insert(0, './tools')
import do_fighter as D
import ladder as L
import arcade
R = './'
P1, P2 = 0x0C7E40C4, 0x0C7EB394
ST1 = P1 + 0x71BA


def bg_peeks():
    return ['peek32 0xA05F8020 1', 'peek32 0xA05F808C 1', 'peek32 0xA5000000 16', 'peek32 0xA5400000 16']


def run(target, tag, dumps=16, every=300):
    D.restart()
    L.fc(['wait 1200'], 120)
    L.fc(arcade.start(0), 300)
    first = L.p2_mdt()
    L.fc(['poke8 0x0C7F2E45 6', f'poke8 0x0C7F2E46 {target - 1}'], 30)
    hp0 = [f'poke16 0x{P2 + 0x71D4 + 2 * i:08X} 0' for i in range(3)]
    mash = (hp0 + ['press 1 X 4', 'wait 8', 'press 1 A 4', 'wait 8']) * 8   # ~4 s per check: one fight only
    for chunk in range(200):
        L.fc(mash, 120)
        if L.p2_mdt() != first: break
    # story screens come before some fights: press through, wait for the round intro (state 22) and the fight (0)
    L.fc(['press 1 A 4', 'wait 60'] * 4 + [f'until8 0x{ST1:08X} 22 3000', f'until8 0x{ST1:08X} 0 3000', 'wait 60'], 300)
    hold = [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
    cmds = hold + [f'freeze8 0x{P1 + 0x71ED:08X} 1']
    for k in range(dumps):
        cmds += [f'wait {every}', f'mark {tag}_{k:02d}', f'dump {tag}_{k:02d}.bin 0x0C000000 0x1000000',
                 f'shot {tag}_{k:02d}.png'] + bg_peeks()
    L.fc(cmds, dumps * every / 20 + 600)
    opp, stg = L.who(R + f'dumps/{tag}_00.bin')
    print(f'{tag}: opponent {opp} on {stg}', flush=True)
    return opp, stg


def ladder_run(row, tag, plan, every=300, log_frames=0):
    """The whole ladder of one row: before fight 1 the row byte is poked, then on every fight both fighters are the
    game's AI (healths held) for plan[fight] dumps, then P2 is KO'd and the next fight comes. plan = dumps per fight."""
    D.restart()
    L.fc(['wait 1200'], 120)
    c = arcade.start(0)
    pick = max(i for i, x in enumerate(c) if x.startswith('press 1 A'))   # the select-screen pick
    L.fc(c[:pick] + [f'poke8 0x0C7F2E45 {row}'] + c[pick:], 300)
    hp0 = [f'poke16 0x{P2 + 0x71D4 + 2 * i:08X} 0' for i in range(3)]
    mash = (hp0 + ['press 1 X 4', 'wait 8', 'press 1 A 4', 'wait 8']) * 8
    hold = [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
    free = [f'unfreeze 0x{b + 0x71D4 + 2 * k:08X}' for b in (P1, P2) for k in range(3)] + \
           [f'unfreeze 0x{P1 + 0x71ED:08X}', f'poke8 0x{P1 + 0x71ED:08X} 0'] + \
           [f'freeze16 0x{P1 + 0x71D4 + 2 * k:08X} 240' for k in range(3)]
    out = []
    for fi, n in enumerate(plan):
        if fi:
            L.fc(['press 1 A 4', 'wait 60'] * 4 + [f'until8 0x{ST1:08X} 22 3000', f'until8 0x{ST1:08X} 0 3000'], 300)
        L.fc(['wait 60'], 30)
        cmds = hold + [f'freeze8 0x{P1 + 0x71ED:08X} 1']
        if log_frames:   # per-frame hit fields of the AI-vs-AI fight (tools/hitlog.py hits TAGlogN)
            import hitlog, json
            json.dump(hitlog.LITE, open(R + f'dumps/cap/{tag}log{fi}.fields', 'w'))
            cmds += [f'capseg {tag}log{fi} {log_frames} {hitlog.segs(hitlog.LITE)}', f'wait {log_frames}']
            n = max(1, n)
        for k in range(max(1, n)):
            cmds += [f'wait {every}', f'mark {tag}{fi}_{k:02d}', f'dump {tag}{fi}_{k:02d}.bin 0x0C000000 0x1000000',
                     f'shot {tag}{fi}_{k:02d}.png'] + bg_peeks()
        L.fc(cmds, max(1, n) * every / 15 + 600)
        opp, stg = L.who(R + f'dumps/{tag}{fi}_00.bin')
        print(f'fight {fi + 1}: {opp} on {stg} ({n} dumps)', flush=True)
        out.append((fi, opp, stg))
        if fi + 1 == len(plan): break
        L.fc(free, 30)
        first = L.p2_mdt()
        for chunk in range(200):
            L.fc(mash, 120)
            if L.p2_mdt() != first: break
    return out


if __name__ == '__main__' and sys.argv[1] == 'ladder':
    print(ladder_run(int(sys.argv[2]), sys.argv[3], [int(x) for x in sys.argv[4].split(',')],
                     log_frames=int(sys.argv[5]) if len(sys.argv) > 5 else 0))
elif __name__ == '__main__':
    run(int(sys.argv[1]), sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 16,
        int(sys.argv[4]) if len(sys.argv) > 4 else 300)
