"""CPU vs CPU on a stage with the stage objects logged per frame (fx-obj). usage: objlog.py INST P1 P2 FRAMES NAME OBJS(hex,comma)"""
import sys, time, os, json, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fcinst import Inst
import reflog as RL
inst, p1, p2, frames, name = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
objs = [int(x, 16) for x in sys.argv[6].split(',')] if len(sys.argv) > 6 and sys.argv[6] else []
P1, P2 = RL.P1, RL.P2
PX = [(0x2C, 8), (0x71BC, 4), (0x71C8, 4), (0x721C, 8), (0x2D8, 4), (0x2E4, 4)]
OX = [(0x00, 8), (0x20, 12), (0x30C, 8)]
def segs():
    s = RL.segs().split(',')
    for b in (P1, P2): s += [f'0x{b + o:08X}:{n}' for o, n in PX]
    for a in objs: s += [f'0x{a + o:08X}:{n}' for o, n in OX]
    return ','.join(s)
fi = Inst(inst)
OUT = os.environ.get('OBJLOG_OUT', '/tmp/ps-fx-obj/logs/')
try:
    t0 = time.time()
    RL.boot(fi, p1, p2)
    lines = [f'freeze8 0x{P1 + 0x71ED:08X} 1', f'freeze8 0x{P2 + 0x71ED:08X} 1', 'freeze8 0x0C7F305C 19', 'freeze8 0x0C7F305D 152',
             f'dump {name}_ram0.bin 0x0C7D0000 0x10000', f'capseg {name} {frames} {segs()}']
    fi.fc(lines, 60)
    fi.wait_idle(frames / 60 * 8 + 600, 5)
    time.sleep(1)
    os.replace(fi.root + f'cap/{name}.bin', OUT + name + '.bin')
    os.replace(fi.root + f'{name}_ram0.bin', OUT + name + '_ram0.bin')
    json.dump(dict(p1=p1, p2=p2, frames=frames, objs=[hex(a) for a in objs], px=PX, ox=OX, fsize=RL.frame_size() + 2 * sum(n for _, n in PX) + len(objs) * sum(n for _, n in OX),
                   wall_s=round(time.time() - t0)), open(OUT + name + '.meta.json', 'w'))
    print('done', name, round(time.time() - t0), flush=True)
finally:
    fi.stop()
