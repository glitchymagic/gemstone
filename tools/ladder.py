#!/usr/bin/env python3
"""Walk the real arcade ladder in Flycast and record who you fight where, in order (pass 3, step 5).
P1's health is frozen; each round the CPU's health is poked to 0 and P1 throws a punch so the game runs its own KO.
After every fight start, a RAM dump identifies the opponent (which Pn0_MOT.MDT sits in P2's slot 0x0C7C58A0) and the
stage (which STGn0.MDL is loaded); the P2 motion log of the whole run is kept (dumps/cap/ladder_*.bin).
Usage: ladder.py SLOT [MAX_FIGHTS]     (SLOT = character-select position; Flycast must be at the title screen)
Env: LADDER_TAG (name prefix), STOP_AT=STGn0 (stop after that stage's dump), LOG_FROM=N (from fight N on, let the CPU
fight ~6000 frames with both healths held and log both players' motions: fightlog.py show TAG_cpuN 2)"""
import glob, json, os, subprocess, sys, time
R = './'
PY = 'python3'
sys.path.insert(0, R + 'tools')
import arcade
P2 = 0x0C7EB394
SEGS = subprocess.check_output([PY, R + 'tools/fightlog.py', 'segs'], text=True).strip()
TAG = os.environ.get('LADDER_TAG', 'ladder')   # dump/shot name prefix (one per run)
MDTS = {os.path.basename(f)[:3]: open(f, 'rb').read()[:0x200] for f in glob.glob(R + 'rip/fs/P*0_MOT.MDT')}
STGS = {}
for f in glob.glob(R + 'rip/fs/STG*0.MDL'):
    m = open(f, 'rb').read()   # several probes: the game edits some stage vertices in place after loading
    STGS[os.path.basename(f)[:5]] = [m[o:o + 0x40] for o in (0x200, 0x1000, 0x4000, len(m) // 2, len(m) - 0x400)]


def fc(cmds, wait=600):
    return subprocess.run([PY, R + 'tools/fc.py', '-w', str(wait), *cmds], check=True, text=True, capture_output=True).stdout


def who(dump):
    b = open(dump, 'rb').read()
    opp = [k for k, v in MDTS.items() if b[0x7C58A0:0x7C58A0 + 0x200] == v]
    stg = [k for k, v in STGS.items() if sum(b.find(c) >= 0 for c in v) >= 2]
    return (opp[0] if opp else '?'), (stg[0] if stg else '?')


def p2_mdt():
    fc(['dump p2mdt.bin 0x0C7C58A0 0x200'], 60)
    b = open(R + 'dumps/p2mdt.bin', 'rb').read()
    return next((k for k, v in MDTS.items() if b == v), '?')


def main(slot, maxf):
    """P2's three health fields are held at 0 while P1 alternates punch and jump: the first hit (or the round timer)
    wins the round, the game runs its own KO / time-over and moves on. A new fight = P2's motion table changes."""
    fc(arcade.start(slot), 300)
    hp0 = [f'poke16 0x{P2 + 0x71D4 + 2 * i:08X} 0' for i in range(3)]
    mash = (hp0 + ['press 1 X 4', 'wait 8', 'press 1 A 4', 'wait 8']) * 100
    out = []
    for i in range(maxf):
        dump = f'{TAG}_{i:02d}.bin'
        # story screens come before some fights (Final Valgas): wait for the round intro (P1 state 22), then idle
        ready = [] if i == 0 else ['press 1 A 4', 'wait 60'] * 4 + ['until8 0x0C7EB27E 22 3000', 'until8 0x0C7EB27E 0 3000']
        fc(ready + ['until8 0x0C7EB27E 0 3000', 'wait 240', f'dump {dump} 0x0C000000 0x1000000',
                    f'shot {TAG}_{i:02d}.png'], 200)
        opp, stg = who(R + 'dumps/' + dump)
        print(f'fight {i + 1}: {opp} on {stg}', flush=True)
        out.append({'fight': i + 1, 'opponent': opp, 'stage': stg})
        json.dump(out, open(R + f'work/{TAG}.json', 'w'), indent=1)
        if stg == os.environ.get('STOP_AT'):   # e.g. STOP_AT=STG60: only that stage's fight dump is wanted
            break
        if i + 1 >= int(os.environ.get('LOG_FROM', 99)):   # let the CPU fight (both healths held) and log its motions
            hold = [f'freeze16 0x{P2 + 0x71D4 + 2 * k:08X} 240' for k in range(3)]
            poke = ['press 1 X 4', 'wait 50', 'hold 1 RIGHT 30', 'wait 40', 'press 1 Y 4', 'wait 60', 'press 1 A 3',
                    'wait 12', 'press 1 X 4', 'wait 80', 'hold 1 LEFT 30', 'wait 60']
            fc([f'capseg {TAG}_cpu{i + 1} 6000 {SEGS}'] + hold + poke * 18, 900)
            fc([f'unfreeze 0x{P2 + 0x71D4 + 2 * k:08X}' for k in range(3)], 60)
            print(f'  logged CPU motions: dumps/cap/{TAG}_cpu{i + 1}.bin', flush=True)
        for chunk in range(16):
            fc(mash, 400)
            now = p2_mdt()
            if now != opp:
                print(f'  next: {now} after {chunk + 1} chunks', flush=True)
                break
        else:
            print('  no new opponent after 16 chunks (ladder over or stuck)', flush=True)
            fc([f'shot ladder_end_{i:02d}.png'], 60)
            break
    print(json.dumps(out))


if __name__ == '__main__':
    main(int(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else 12)
