#!/usr/bin/env python3
"""Which stage objects the game lets fighters pick up and throw (pass 3 rule, now a tool): an object record whose world
position changed between RAM dumps of real fights on that stage was moved by the game's own fighters; parts with the
same mesh bytes as a moved one (the other stools, crates, barrels) are the same kind of object.
  throwables.py STGn0 dump.bin [dump.bin ...] [--fresh]   -> prints moved parts (>= 8 cm) + siblings, merges them into
                                    game/assets/ripped/stgn0_info.json "throwable" (union; --fresh replaces the list)"""
import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap, psmdl
R = './'
B = 0x0C000000
MIN_MOVE = 8.0   # cm: smaller shifts are objects settling onto the floor at round start (seen: 4 cm, never again)


def layout(ram, mdl_path):
    """Same records as tools/stage_layout.py: 0xA4-byte object records, world matrix at part-pointer - 0x4C."""
    parts, base, _ = mocap.find_records(ram, mdl_path, 0)
    p2 = {base + p['ofs']: k for k, p in enumerate(parts)}
    a = np.frombuffer(ram[:len(ram) // 4 * 4], dtype='<u4')
    out = {}
    for i in np.nonzero(np.isin(a, np.array(list(p2), dtype=np.uint32)))[0]:
        o = int(i) * 4
        M = np.array(struct.unpack_from('<16f', ram, o - 0x4C)).reshape(4, 4)
        if abs(M[3, 3] - 1) > 1e-3 or abs(abs(np.linalg.det(M[:3, :3])) - 1) > 0.05: continue
        out[B + o] = (p2[int(a[i])], M[3, :3].copy())
    return out


def mesh_key(mdl, p):
    return mdl[p['ofs']:p['end']] if p.get('end') else None


def main(stg, dumps):
    mdl_path = R + f'rip/fs/{stg.upper()}.MDL'
    mdl = open(mdl_path, 'rb').read()
    parts, _, _ = psmdl.parse(mdl)
    lays = [layout(open(d, 'rb').read(), mdl_path) for d in dumps]
    moved = set()
    for addr, (part, pos) in lays[0].items():
        for L in lays[1:]:
            if addr in L and L[addr][0] == part and np.abs(L[addr][1] - pos).max() > MIN_MOVE:
                moved.add(part)
    keys = {k: mesh_key(mdl, p) for k, p in enumerate(parts)}
    sib = {k for k in keys for m in moved if keys[k] and keys[k] == keys[m] and parts[k]['mats']}
    placed = sorted({part for L in lays for part, _ in L.values()})
    found = sorted((moved | sib) & set(placed))
    print(f'{stg}: {len(dumps)} dumps, {len(lays[0])} objects; moved parts {sorted(moved)}; with siblings {found}')
    ip = R + f'game/assets/ripped/{stg.lower()}_info.json'
    info = json.load(open(ip))
    old = [] if '--fresh' in sys.argv else info.get('throwable', [])
    info['throwable'] = sorted(set(old) | set(found))
    info['throwable_note'] = ('moved between real fight dumps of this stage (picked up / thrown by the game) + '
                              'identical-mesh siblings (tools/throwables.py)')
    json.dump(info, open(ip, 'w'), indent=1)
    print(f'  {ip}: throwable {old} -> {info["throwable"]}')


if __name__ == '__main__':
    main(sys.argv[1], [a for a in sys.argv[2:] if not a.startswith('--')])
