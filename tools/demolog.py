#!/usr/bin/env python3
"""Pass 4: log the attract demo (CPU vs CPU, the game's own fights) for hit data checks, stage dumps and the
PowerVR background registers. Restarts Flycast, never touches anything but the Mac's offscreen Flycast.
  demolog.py TAG FRAMES [DUMP_EVERY]   -> dumps/cap/TAG.bin (tools/hitlog.py fields), dumps/TAG_NN.bin + shots/TAG_NN.png
                                          every DUMP_EVERY frames (default 1200), PVR registers via peek32 in /tmp/flycast.log"""
import sys, time
sys.path.insert(0, './tools')
import do_fighter as D
import hitlog

# PARAM_BASE, ISP_BACKGND_D, ISP_BACKGND_T, VO_BORDER_COL, FOG_COL_RAM, FOG_COL_VERT, FOG_DENSITY, FOG_CLAMP_MAX/MIN
PVR_REGS = [0xA05F8020, 0xA05F8088, 0xA05F808C, 0xA05F8040, 0xA05F80B0, 0xA05F80B4, 0xA05F80B8, 0xA05F80BC,
            0xA05F80C0]


def run(tag, frames, every=1200):
    D.restart()
    cmds = [f'capseg {tag} {frames} {hitlog.segs()}']
    for k in range(frames // every):
        cmds += [f'wait {every}', f'mark {tag}_{k:02d}', f'dump {tag}_{k:02d}.bin 0x0C000000 0x1000000',
                 f'shot {tag}_{k:02d}.png'] + [f'peek32 0x{r:08X} 1' for r in PVR_REGS]
    D.fc(cmds, 30)
    t0 = time.time()
    while time.time() - t0 < frames / 60 * 3 + 600:
        time.sleep(20)
        st = open('./dumps/status.txt').read()
        if 'caps=0' in st and 'queue=0' in st: break
    print(open('./dumps/status.txt').read())


if __name__ == '__main__':
    run(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 1200)
