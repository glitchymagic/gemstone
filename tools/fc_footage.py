#!/usr/bin/env python3
"""Trailer footage of the ORIGINAL game (the real disc in our Flycast, never the remaster): arcade as P1, fight 1 = P2
on P2's home stage (tools/reflog.py boot), then from P1's ready state a screenshot EVERY vblank (Lua shotseq) for N frames, both sides the game's AI (P1 +0x71ED), healths not held
(the round runs as the disc runs it). Runs in its own Flycast instance (tools/fcinst.py), stopped by its PID.
  LANE_TMP=... fc_footage.py TAG [P1 P2 (ryoma falcon = Londo)] [FRAMES=2400]   -> INST/dumps/shots/TAG/NNNNN.png (640x480)
  ffmpeg -framerate 60 -i .../TAG/%05d.png ..."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fcinst import Inst
import ladder as L
P1, P2 = 0x0C7E40C4, 0x0C7EB394
ST1 = P1 + 0x71BA


def run(tag, p1='ryoma', p2='falcon', frames=2400):
    import reflog
    i = Inst('tr')
    try:
        reflog.boot(i, p1, p2)   # arcade as P1, fight 1 = P2 on P2's home stage, at P1's ready state (22)
        i.fc(['dump who.bin 0x0C000000 0x1000000'], 120)
        print('fight:', L.who(i.root + 'who.bin'), flush=True)
        os.remove(i.root + 'who.bin')
        i.fc([f'freeze8 0x{P1 + 0x71ED:08X} 1', f'shotseq {tag} {frames}'], frames / 10 + 600)
        print(f'{tag}: {frames} frames in {i.root}shots/{tag}/', flush=True)
    finally:
        i.stop()


if __name__ == '__main__':
    a = sys.argv[1:]
    run(a[0], *(a[1:3] if len(a) > 2 else ['ryoma', 'falcon']), int(a[3]) if len(a) > 3 else 2400)
