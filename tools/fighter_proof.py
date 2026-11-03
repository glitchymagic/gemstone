#!/usr/bin/env python3
"""Side-by-side rip proof for one fighter: left = the Flycast Motion Check frames of both forms (dumps/shots/mcN_0/1.png,
written by do_fighter.py boot), right = Godot rendering the ripped rigs playing the RAM-captured idle.
Usage: fighter_proof.py N id "Name"      -> docs/rip-proof/<id>_sidebyside.png"""
import os, subprocess, sys
from PIL import Image
R = './'
n, cid, name = int(sys.argv[1], 16), sys.argv[2], sys.argv[3]
subprocess.run(['/Applications/Godot.app/Contents/MacOS/Godot', '--path', R + 'game', '--resolution', '1280x720', '-s',
                'res://tests/model_shot.gd', '--', f'/tmp/{cid}_godot.png', 'idle', cid], capture_output=True, timeout=180)
shots = [R + f'dumps/shots/mc{n:x}_{f}.png' for f in (0, 1) if os.path.exists(R + f'dumps/shots/mc{n:x}_{f}.png')]
ims = [Image.open(s).convert('RGB') for s in shots]
w, h = ims[0].size
L = Image.new('RGB', (w // 2 * len(ims), h))
for i, im in enumerate(ims): L.paste(im.crop((0, 0, w // 2, h)), (w // 2 * i, 0))
L.save(f'/tmp/{cid}_flycast.png')
out = R + f'docs/rip-proof/{cid}_sidebyside.png'
subprocess.run([sys.executable, R + 'tools/sidebyside.py', f'/tmp/{cid}_flycast.png', f'/tmp/{cid}_godot.png', out,
                f"Flycast (the owner's disc): Motion Check, {name}" + (' normal + Power Change' if len(ims) > 1 else ''),
                'Godot remaster: ripped rig, RAM-captured idle'], check=True)
print(out)
