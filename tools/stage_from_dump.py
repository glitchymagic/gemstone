#!/usr/bin/env python3
"""Everything a stage needs from ONE RAM dump taken during a real fight on it, plus the Flycast screenshot taken in the
same frame (pass 3): export_stage.py (geometry, props, layout, bounds), the spawn x/z (both fighters, player +0x148/+0x150),
the camera yaw preset (eye - target from the view matrix at 0x0C7F2A24), and a side-by-side proof rendered in Godot
from the game's own camera. Usage: stage_from_dump.py STGn0 dump.bin shot.png ["Stage name"] [--keep-spawn]"""
import json, struct, subprocess, sys
import numpy as np
R = './'
PY = sys.executable
stg, dump, shot = sys.argv[1].upper(), sys.argv[2], sys.argv[3]
name = sys.argv[4] if len(sys.argv) > 4 and not sys.argv[4].startswith('--') else stg
lo = stg.lower()
subprocess.run([PY, R + 'tools/export_stage.py', stg, dump], check=True)
b = open(dump, 'rb').read()
M = np.array(struct.unpack_from('<16f', b, 0x7F2A24)).reshape(4, 4)
Rm, T = M[:3, :3], M[3, :3]
eye = -T @ Rm.T
fwd = -Rm[:, 2]
p1 = np.array(struct.unpack_from('<3f', b, 0x7E40C4 + 0x148)); p2 = np.array(struct.unpack_from('<3f', b, 0x7EB394 + 0x148))
mid = (p1 + p2) / 2
dist = float(np.dot(mid - eye, fwd))
tgt = eye + fwd * dist
d = eye - tgt
yaw = float(np.degrees(np.arctan2(d[0], d[2])))
info_p = R + f'game/assets/ripped/{lo}_info.json'
info = json.load(open(info_p))
info['cam_yaw_deg'] = round(yaw, 1)
if '--keep-spawn' not in sys.argv or 'spawn_cm' not in info:
    info['spawn_cm'] = [[round(float(p1[0])), round(float(p1[2]))], [round(float(p2[0])), round(float(p2[2]))]]
json.dump(info, open(info_p, 'w'), indent=1)
print(stg, 'camera yaw', round(yaw, 1), 'eye', eye.round(0), 'spawn', info['spawn_cm'])
subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot', '--headless', '--path', R + 'game', '--import'],
               capture_output=True, timeout=600)   # new GLBs must be imported before Godot can load them
g = '/tmp/%s_cam.png' % lo
subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot', '--path', R + 'game', '--resolution', '1280x960', '-s',
                'res://tests/shot.gd', '--', 'stage', g, '60', 'x'] + ['%.3f' % v for v in (*(eye / 100), *(tgt / 100))] + ['41.1'],
               env={'PS_STAGE': lo, 'PATH': '/usr/bin:/bin', 'HOME': os.path.expanduser('~')}, capture_output=True, timeout=180)
subprocess.run([PY, R + 'tools/sidebyside.py', shot, g, R + f'docs/rip-proof/{lo}_sidebyside.png',
                f"Flycast (the owner's disc): arcade fight on {name}", f'Godot remaster: {stg} from the disc, same camera (from RAM)'],
               check=True)
