#!/usr/bin/env python3
"""One stage from the owner's disc into the game (pass 3): STGn0.MDL + STGn0_MODEL.BIN -> game/assets/ripped/stgN0_world.glb
(world-space geometry), stgN0_propK.glb (each placed object part, local space), stgN0_layout.json (every placed object's
world matrix: from the disc, tools/stage_layout_disc.py, or from RAM during a real fight, tools/stage_layout.py) and
stgN0_info.json (bounds, throwables).
World parts = textured parts below index 10 that have no placed-object record (Londo 0/1/3, dojo 0/3/5/9, mansion
0/1/2/5/6/7/9); everything else that is never placed (breakage pieces, effects) is left out.
Usage: export_stage.py STG20 disc            (placement read from 1ST_READ.BIN, importer/stage_spec.json)
       export_stage.py STG20 ram_during_fight.bin"""
import json, os, subprocess, sys
import numpy as np
R = './'
PY = sys.executable
sys.path.insert(0, R + 'tools')
import psmdl
stg, ram = sys.argv[1].upper(), sys.argv[2]
lo = stg.lower()
out = R + 'game/assets/ripped/'
mdl = R + f'rip/fs/{stg}.MDL'; mb = R + f'rip/fs/{stg}_MODEL.BIN'; tex = R + f'rip/up/{stg}'
os.makedirs(out, exist_ok=True)
if ram == 'disc':
    subprocess.run([PY, R + 'tools/stage_layout_disc.py', stg, out + f'{lo}_layout.json'], check=True, capture_output=True)
else:
    subprocess.run([PY, R + 'tools/stage_layout.py', ram, mdl, out + f'{lo}_layout.json'], check=True, capture_output=True)
lay = json.load(open(out + f'{lo}_layout.json'))
parts, _, _ = psmdl.parse(open(mdl, 'rb').read())
placed = sorted(set(d['part'] for d in lay))
world = [k for k, p in enumerate(parts) if p['mats'] and k < 10 and k not in placed]
subprocess.run([PY, R + 'tools/export_glb.py', mdl, mb, out + f'{lo}_world.glb', '--parts', ','.join(map(str, world)),
                '--texdir', tex], check=True, capture_output=True)
for k in placed:
    subprocess.run([PY, R + 'tools/export_glb.py', mdl, mb, out + f'{lo}_prop{k}.glb', '--parts', str(k), '--texdir', tex],
                   check=True, capture_output=True)
# walkable bounds: the xz extent of the world geometry's lowest broad surfaces (vertices within 60 cm of the floor level)
V = []
for k in world:
    for m in parts[k]['mats']:
        for _flags, verts in m['strips']:
            V += [v[:3] for v in verts if isinstance(v, tuple) and len(v) >= 3]
V = np.array(V) if V else np.zeros((1, 3))
floor = np.percentile(V[:, 1], 10)
low = V[V[:, 1] < floor + 60]
info = {'world': world, 'placed': placed, 'floor_y': round(float(floor), 1),
        'bounds_cm': [round(float(low[:, 0].min()), 1), round(float(low[:, 2].min()), 1),
                      round(float(low[:, 0].max()), 1), round(float(low[:, 2].max()), 1)]}
if ram == 'disc':   # which props the game lets you pick up (part numbers, importer/stage_spec.json)
    sspec = json.load(open(R + 'importer/stage_spec.json'))[lo]
    info['throwable'] = sspec.get('throwable', [])
    if sspec.get('indoor'): info['indoor'] = True
    # the PowerVR background plane colours: 1ST_READ 0x0C14AB90 + stage*12, ARGB at screen (0,0), (640,0), (0,480)
    import struct
    from stage_layout_disc import STAGES, B
    exe = open(R + 'rip/fs/1ST_READ.BIN', 'rb').read()
    bg = struct.unpack_from('<3I', exe, 0x0C14AB90 + 12 * STAGES.index(stg) - B)
    info['bg_argb'] = ['%08X' % c for c in bg]
    info['bg_rgb'] = [[(c >> 16) & 255, (c >> 8) & 255, c & 255] for c in bg]
if os.path.exists(out + f'{lo}_info.json'):   # keep spawns / camera yaw measured earlier
    old = json.load(open(out + f'{lo}_info.json')); old.update(info); info = old
json.dump(info, open(out + f'{lo}_info.json', 'w'), indent=1)
print(stg, info)
