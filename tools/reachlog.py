#!/usr/bin/env python3
"""fx-reach: where the disc draws the body and where it hits, per frame, in a same-input tape run (both fighters human).
The reference log of tools/reflog.py plus, per player, the game's own sphere centres as its hit test uses them:
  +0x148 4 attack spheres (f32 x, y, z, r: world cm; r = 0 = not live), +0x188 12 body spheres (entry 0 = push),
  +0x330 part 0 (hip joint) world translation (the fighter object's part-0 world matrix row 3, record - 0x40 + 0x30).
  reachlog.py orig INST OUTDIR TAPE...   Flycast instance INST -> OUTDIR/o_TAPE.jsonl (+ .bin / .meta.json)
  reachlog.py decode OUTDIR NAME          the .bin again (aset / bset = +0x101 / +0x102)
Rows = reflog's schema + p[i].att [[x,y,z,r] x4], p[i].body [[x,y,z,r] x12], p[i].hip [x,y,z]."""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reflog

EXTRA = [(0x148, 64), (0x188, 192), (0x330, 12)]
reflog.PFIELDS = reflog.PFIELDS + EXTRA
_base_player = reflog._player


def _player(d):
    p = _base_player(d)
    p['att'] = [[round(v, 2) for v in struct.unpack_from('<4f', d[0x148], 16 * i)] for i in range(4)]
    p['body'] = [[round(v, 2) for v in struct.unpack_from('<4f', d[0x188], 16 * i)] for i in range(12)]
    p['hip'] = [round(v, 2) for v in struct.unpack('<3f', d[0x330])]
    p['aset'], p['bset'] = d[0x100][1], d[0x100][2]
    return p


reflog._player = _player


def orig(inst, outdir, names):
    from fcinst import Inst
    import fidelity_run
    reflog.OUT = outdir.rstrip('/') + '/'
    os.makedirs(reflog.OUT, exist_ok=True)
    fi = Inst(inst)
    try:
        for t in names:
            out, m = fidelity_run.built(t)
            reflog.boot(fi, m['p1'], m['p2'])
            rows = reflog.play(fi, out, 'o_' + t)
            print(f'orig {t}: {len(rows)} frames', flush=True)
    finally:
        fi.stop()


if __name__ == '__main__':
    if sys.argv[1] == 'decode':   # reachlog.py decode DIR NAME: .bin -> .jsonl again
        reflog.write_jsonl(reflog.decode(sys.argv[2] + f'/{sys.argv[3]}.bin'), sys.argv[2] + f'/{sys.argv[3]}.jsonl')
    elif sys.argv[1] == 'orig':
        orig(sys.argv[2], sys.argv[3], sys.argv[4:])
