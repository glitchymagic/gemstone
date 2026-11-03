#!/usr/bin/env python3
"""Drive a real arcade fight in Flycast and log every move (pass 3). Builds fc.py command lists.
  arcade.py start N            title -> ARCADE -> pick select-screen slot N (0 = Falcon) -> fight; P1 health frozen
  arcade.py mc N               boot -> debug TEST MENU -> GAME CHECK > MOTION CHECK, P1 player field stepped to N
  arcade.py moves NAME         log P1 normal moves + a forced Power Change (3 gems poked) with both Drives,
                               air Drives and both Fusions, waiting on the state byte between inputs
Then: fightlog.py show NAME"""
import subprocess, sys
PY = 'python3'
FC = './tools/fc.py'
P1 = 0x0C7E40C4
ST, PCF, GEM, HP = P1 + 0x71BA, P1 + 0x71F3, P1 + 0x7230, P1 + 0x71D4
IDLE = f'until8 0x{ST:08X} 0 900'


def freeze():
    return [f'freeze16 0x{HP + 2 * i:08X} 240' for i in range(3)]


def start(n):
    c = ['press 1 START 5', 'wait 120', 'press 1 START 5', 'wait 150', 'press 1 A 5', 'wait 270']
    c += ['press 1 RIGHT 4', 'wait 10'] * n
    return c + ['press 1 A 5'] + freeze() + ['wait 900']


def motion_check(n):
    c = ['wait 1200', 'poke32 0x0C061B38 0x0C0D7108', 'wait 30', 'press 1 START 5', 'wait 120']
    c += ['press 1 DOWN 4', 'wait 8'] * 8 + ['press 1 A 4', 'wait 60', 'press 1 A 4', 'wait 200', 'poke8 0x0C49492F 0', 'wait 5']
    return c + ['press 1 RIGHT 3', 'wait 120'] * n + ['wait 100']


def power_change():
    return [f'poke8 0x{GEM:08X} 3', f'poke8 0x{GEM + 1:08X} 7', f'until8 0x{PCF:08X} 1 900', IDLE, 'wait 5']


def moves(name):
    segs = subprocess.check_output([PY, FC.replace('fc.py', 'fightlog.py'), 'segs'], text=True).strip()
    # inputs are locked while FIGHT! shows; the CPU is pinned in its lying state (P2 state byte frozen at 15) so it
    # can't interrupt the log
    c = [f'capseg {name} 6000 {segs}', IDLE, 'wait 240', 'freeze8 0x0C7F254E 15', 'wait 30']
    for m in (['X 4', 'wait 8', 'X 4', 'wait 8', 'X 4'], ['Y 4', 'wait 8', 'Y 4'], ['B 4']):
        c += [x if x.startswith('wait') else f'press 1 {x}' for x in m] + [IDLE, 'wait 20']
    for d, b in (('RIGHT', 'X'), ('LEFT', 'Y')):            # dash attacks: run, then attack
        c += [f'hold 1 {d} 45', 'wait 35', f'press 1 {b} 4', IDLE, 'wait 20']
    for b in ('X', 'Y'):                                     # air attacks
        c += ['press 1 A 3', 'wait 12', f'press 1 {b} 4', IDLE, 'wait 20']
    c += power_change() + ['mark pc_drives']
    for b in ('X', 'Y'):
        c += [f'press 1 {b} 4', IDLE, 'wait 10']
    for b in ('X', 'Y'):
        c += ['press 1 A 3', 'wait 12', f'press 1 {b} 4', IDLE, 'wait 10']
    c += [f'until8 0x{PCF:08X} 0 900', IDLE]
    for b in ('X+A', 'Y+A'):
        c += power_change() + [f'mark fusion_{b}', f'press 1 {b} 6', f'until8 0x{PCF:08X} 0 1200', IDLE, 'wait 30']
    return c + ['unfreeze 0x0C7F254E']


if __name__ == '__main__':
    cmd = {'start': lambda: start(int(sys.argv[2])), 'mc': lambda: motion_check(int(sys.argv[2])),
           'moves': lambda: moves(sys.argv[2])}[sys.argv[1]]()
    print('\n'.join(cmd))
