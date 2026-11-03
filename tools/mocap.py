#!/usr/bin/env python3
"""RAM motion capture helpers (the game's own motion player, recorded from Flycast).
  mocap.py segs ram.bin X.MDL [which]   -> JSON {parts: [record addr per part], seg: "A:L,..."} for capseg
                                           (which = 0 first loaded copy / 1 second; records found via the
                                           +0x50 mesh pointer, flag 1 at +0x00)
  mocap.py decode cap.bin segs.json     -> npz: W (frames, parts, 4, 4) world row-vector matrices,
                                           rot (frames, parts, 3) s32, off (frames, parts, 3), flag, ptr, var
Each part's segment = record-0x40 .. record+0xB0 (world 4x4 then the 0xB0 node record)."""
import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl

B = 0x0C000000
SEG = 0xF0
VARS = (0x0C494920, 0x60)   # Motion Check menu/player variables


def find_records(ram, mdl_path, which=0):
    mdl = open(mdl_path, 'rb').read()
    parts, _, _ = psmdl.parse(mdl)
    bases = []
    for co in (0x100, 0x40, 0x2000):            # the game edits some vertex floats in place after load
        i = 0
        while True:
            i = ram.find(mdl[co:co + 0x40], i)
            if i < 0: break
            if B + i - co not in bases: bases.append(B + i - co)
            i += 1
        if bases: break
    base = bases[which]
    p2 = {base + p['ofs']: k for k, p in enumerate(parts)}
    recs = {}
    for o in range(0x50, len(ram) - 0x60, 4):
        v = struct.unpack_from('<I', ram, o)[0]
        if v in p2 and struct.unpack_from('<H', ram, o - 0x50)[0] & 0xFF == 1:   # 0x0101 = second list (braids)
            r = o - 0x50 + B
            recs.setdefault(p2[v], []).append(r)
    return parts, base, recs


def segs(ram_path, mdl_path, which=0, fighter=0):
    ram = open(ram_path, 'rb').read()
    parts, base, recs = find_records(ram, mdl_path, which)
    # records of fighter n: sort each part's candidates, take the one whose group (part-0 array) is nth
    roots = sorted(recs[0])
    root = roots[fighter] if fighter < len(roots) else roots[0]
    pick = []
    for k in range(len(parts)):
        c = sorted(recs.get(k, []), key=lambda r: abs(r - root))
        pick.append(c[0] if c and abs(c[0] - root) < 0x8000 else None)
    seg = ','.join('0x%08X:%d' % (r - 0x40, SEG) for r in pick if r is not None)
    seg += ',0x%08X:%d' % VARS
    return {'mdl': os.path.basename(mdl_path), 'base': hex(base), 'parts': [hex(r) if r else None for r in pick], 'seg': seg}


def decode(cap_path, segs_path):
    sj = json.load(open(segs_path))
    present = [k for k, r in enumerate(sj['parts']) if r]
    n = len(sj['parts'])
    raw = open(cap_path, 'rb').read()
    fsz = len(present) * SEG + VARS[1]
    F = len(raw) // fsz
    W = np.zeros((F, n, 4, 4), np.float32); rot = np.zeros((F, n, 3), np.int32)
    off = np.zeros((F, n, 3), np.float32); off2 = np.zeros((F, n, 3), np.float32)
    flag = np.zeros((F, n), np.uint32); ptr = np.zeros((F, n), np.uint32)
    var = np.zeros((F, VARS[1]), np.uint8)
    for f in range(F):
        o = f * fsz
        for j, k in enumerate(present):
            s = o + j * SEG
            W[f, k] = np.array(struct.unpack_from('<16f', raw, s)).reshape(4, 4)
            r = s + 0x40
            flag[f, k] = struct.unpack_from('<I', raw, r)[0]
            rot[f, k] = struct.unpack_from('<3i', raw, r + 0x14)
            ptr[f, k] = struct.unpack_from('<I', raw, r + 0x50)[0]
            off[f, k] = struct.unpack_from('<3f', raw, r + 0x58)
            off2[f, k] = struct.unpack_from('<3f', raw, r + 0x64)
        var[f] = np.frombuffer(raw, np.uint8, VARS[1], o + len(present) * SEG)
    return dict(W=W, rot=rot, off=off, off2=off2, flag=flag, ptr=ptr, var=var)


if __name__ == '__main__':
    if sys.argv[1] == 'segs':
        which = int(sys.argv[4]) if len(sys.argv) > 4 else 0
        fighter = int(sys.argv[5]) if len(sys.argv) > 5 else 0
        print(json.dumps(segs(sys.argv[2], sys.argv[3], which, fighter)))
    elif sys.argv[1] == 'decode':
        d = decode(sys.argv[2], sys.argv[3])
        np.savez_compressed(sys.argv[4], **d)
        print('frames', d['W'].shape[0])
