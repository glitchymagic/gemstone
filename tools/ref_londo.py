#!/usr/bin/env python3
"""Reference footage of the original: a CPU-vs-CPU fight on Londo (arcade as Falcon, ladder row 6 poked so fight 2 is
Falcon's home stage; both sides the game's AI, healths held), then the KO + win sequence (P2's health dropped).
Frames every STEP vblanks into dumps/shots/TAG_NNNN.png; tools/ref_londo.py TAG [SECONDS] [STEP] then
ffmpeg -framerate 60/STEP -i dumps/shots/TAG_%04d.png ... Flycast is started here and stopped by its own PID only.
  ref_londo.py TAG 45 3"""
import os, signal, subprocess, sys, time
sys.path.insert(0, './tools')
import do_fighter as D
import ladder as L
import arcade
R = './'
P1, P2 = 0x0C7E40C4, 0x0C7EB394
ST1 = P1 + 0x71BA


def start_flycast():
    open(R + 'dumps/cmd/.seq', 'w').write('1')
    if os.path.exists(R + 'dumps/status.txt'): os.remove(R + 'dumps/status.txt')
    p = subprocess.Popen([D.FLY, D.GDI], stdout=open('/tmp/flycast.log', 'w'), stderr=subprocess.STDOUT,
                         start_new_session=True)
    open('/tmp/psa/flycast.pid', 'w').write(str(p.pid))
    time.sleep(4)
    return p


def boot():
    """Flycast up, arcade as Falcon, fight 1 won, fight 2 (Falcon on Londo) at its round intro. Returns the process."""
    p = start_flycast()
    L.fc(['wait 1200'], 120)
    L.fc(arcade.start(0), 300)
    first = L.p2_mdt()
    L.fc(['poke8 0x0C7F2E45 6', 'poke8 0x0C7F2E46 0'], 30)   # row 6, index 0 -> fight 2 = row6[1] = Falcon, Londo
    hp0 = [f'poke16 0x{P2 + 0x71D4 + 2 * i:08X} 0' for i in range(3)]
    mash = (hp0 + ['press 1 X 4', 'wait 8', 'press 1 A 4', 'wait 8']) * 8
    for _ in range(200):
        L.fc(mash, 120)
        if L.p2_mdt() != first: break
    L.fc(['press 1 A 4', 'wait 60'] * 4 + [f'until8 0x{ST1:08X} 22 3000'], 300)
    return p


def run(tag, secs=45, step=3):
    p = boot()
    try:
        cmds = [f'unfreeze 0x{P1 + 0x71D4 + 2 * k:08X}' for k in range(3)]
        n = 0
        for _ in range(int(60 * 4 / step)):   # round intro (state 22 -> 0)
            cmds += [f'shot {tag}_{n:04d}.png', f'wait {step}']; n += 1
        cmds += [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
        cmds += [f'freeze8 0x{P1 + 0x71ED:08X} 1']
        for _ in range(int(60 * secs / step)):
            cmds += [f'shot {tag}_{n:04d}.png', f'wait {step}']; n += 1
        cmds += [f'unfreeze 0x{P2 + 0x71D4 + 2 * k:08X}' for k in range(3)]
        cmds += [f'poke16 0x{P2 + 0x71D4 + 2 * k:08X} 4' for k in range(3)]   # one hit from a KO: the KO + win poses
        for _ in range(int(60 * 25 / step)):
            cmds += [f'shot {tag}_{n:04d}.png', f'wait {step}']; n += 1
        L.fc(cmds, (secs + 40) * 4 + 600)
        print(f'{tag}: {n} frames', flush=True)
    finally:
        os.kill(p.pid, signal.SIGKILL)


CAM = 0x0C7F2664
CAM_SEGS = [(CAM + 0x3C0, 48), (CAM + 0x450, 12), (CAM + 0x474, 12), (CAM + 0x480, 12), (P1 + 0x148, 12),
            (P2 + 0x148, 12), (P1 + 0x71B8, 4), (P2 + 0x71B8, 4)]


def run_cam(tag, frames=10800):
    """dumps/cap/TAG.bin: per frame view matrix (12 f32), eye, target, smoothed target, P1 xyz, P2 xyz (f32 x3 each),
    P1 / P2 state words; a shot every 120 frames (dumps/shots/TAG_NNN.png). Both sides the game's AI, healths held."""
    p = boot()
    try:
        segs = ','.join(f'0x{a:08X}:{n}' for a, n in CAM_SEGS)
        cmds = [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
        cmds += [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'capseg {tag} {frames} {segs}']
        for k in range(frames // 120):
            cmds += ['wait 120', f'shot {tag}_{k:03d}.png']
        L.fc(cmds, frames / 60 * 3 + 600)
        t0 = time.time()
        while time.time() - t0 < frames / 60 * 3 + 600:
            time.sleep(10)
            st = open(R + 'dumps/status.txt').read()
            if 'caps=0' in st and 'queue=0' in st: break
        print(f'{tag}: done', flush=True)
    finally:
        os.kill(p.pid, signal.SIGKILL)


AICA = 0x00700000


def run_snd(tag, frames=5400):
    """Which samples the game plays when: the sound chip's 64 channel registers (+0x00 key-on / format / start address
    high bits, +0x04 start address low) every frame, with both fighters' health / state / hit fields, CPU vs CPU on
    Londo; then sound RAM (2 MB at 0x00800000) once, to place each bank's samples. dumps/cap/TAG.bin + dumps/TAG_sndram.bin"""
    p = boot()
    try:
        segs = [f'0x{AICA + ch * 0x80:08X}:8' for ch in range(64)]
        if os.environ.get('SND_PITCH'): segs += [f'0x{AICA + ch * 0x80 + 0x0C:08X}:4' for ch in range(64)] + \
                [f'0x{AICA + ch * 0x80 + 0x18:08X}:4' for ch in range(64)]   # loop end (samples), octave / pitch
        segs += [f'0x{b + o:08X}:{n}' for b in (P1, P2) for o, n in ((0x71B8, 4), (0x71D4, 8), (0x0F4, 4), (0x100, 4))]
        cmds = [f'peek32 0x{AICA:08X} 4', f'freeze8 0x{P1 + 0x71ED:08X} 1', f'capseg {tag} {frames} {",".join(segs)}']
        cmds += [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
        cmds += [f'wait {frames + 30}', f'dump {tag}_sndram.bin 0x00800000 0x200000']
        L.fc(cmds, frames / 60 * 3 + 600)
        t0 = time.time()
        while time.time() - t0 < frames / 60 * 3 + 600:
            time.sleep(10)
            st = open(R + 'dumps/status.txt').read()
            if 'caps=0' in st and 'queue=0' in st and os.path.exists(R + f'dumps/{tag}_sndram.bin'): break
        print(f'{tag}: done', flush=True)
    finally:
        os.kill(p.pid, signal.SIGKILL)


if __name__ == '__main__':
    if sys.argv[1] == 'snd':
        run_snd(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 5400)
    elif sys.argv[1] == 'cam':   # the original's camera on Londo: eye / target / view matrix + both fighters, per frame
        run_cam(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 10800)
    else:
        run(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 45, int(sys.argv[3]) if len(sys.argv) > 3 else 3)
