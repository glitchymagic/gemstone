#!/usr/bin/env python3
"""Clips for a Power Change form whose part list differs from the normal form (Ryoma P11: 56 parts vs 47).
Body bones 0..nbody-1 replay the normal-form clip (the game plays the same MDT on both forms; verified bit-equal);
every extra part keeps the constant local rotation measured from a capture of the changed form.
Also used for the shared kind-2 bank (hit reactions, object handling): the same rotations drive every fighter,
root motion scaled (Ryoma ~1.12 x Falcon).
Usage: remap_clips.py skel.json segs.json cap.bin in_dir out_dir [nbody] [--only a,b] [--root-scale k] [--rename from:to]"""
import glob, json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap, clips
import argparse
ap = argparse.ArgumentParser(); ap.add_argument('skel'); ap.add_argument('segs'); ap.add_argument('cap'); ap.add_argument('ind'); ap.add_argument('outd')
ap.add_argument('nbody', nargs='?', type=int, default=19); ap.add_argument('--only', default=''); ap.add_argument('--root-scale', type=float, default=1.0)
ap.add_argument('--rename', default='')
A = ap.parse_args()
skp, segp, capp, ind, outd, nbody = A.skel, A.segs, A.cap, A.ind, A.outd, A.nbody
only = set(x for x in A.only.split(',') if x)
ren = A.rename.split(':') if A.rename else None
sk = json.load(open(skp))
d = mocap.decode(capp, segp); s, L, _, _ = clips.segment(d)
qc = clips.to_clip(d, sk, s, 1, clips.mchar())[0]
os.makedirs(outd, exist_ok=True)
idx = json.load(open(os.path.join(ind, 'index.json')))
oidx = json.load(open(os.path.join(outd, 'index.json'))) if os.path.exists(os.path.join(outd, 'index.json')) else {}
for cp in sorted(glob.glob(os.path.join(ind, '*.npz'))):
    nm = os.path.splitext(os.path.basename(cp))[0]
    if only and nm not in only: continue
    c = np.load(cp)
    F = c['q'].shape[0]
    q = np.repeat(qc[:1], F, 0)
    q[:, :nbody] = c['q'][:, :nbody]
    on = nm.replace(ren[0], ren[1]) if ren else nm
    np.savez_compressed(os.path.join(outd, on + '.npz'), q=q.astype(np.float32), t=(c['t'] * A.root_scale).astype(np.float32), loop=c['loop'])
    oidx[on] = dict(idx[nm], src=nm)
json.dump(oidx, open(os.path.join(outd, 'index.json'), 'w'), indent=1)
print('remapped', len(oidx), 'clips to', qc.shape[1], 'parts')
