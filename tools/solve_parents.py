#!/usr/bin/env python3
"""Solve each part's parent from captured world matrices: the true parent p is the one for which
W_k * inverse(W_p) has translation == the part's own bone offset (+0x58) in every frame. Needed for parts whose
record header uses a second parent encoding (Ryoma's sword / scabbard pieces), where the slot map is wrong.
Usage: solve_parents.py segs.json skel_in.json skel_out.json cap1.bin [cap2.bin ...]"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap

segs, sin, sout = sys.argv[1:4]
skel = json.load(open(sin))
W = []; OFF = None
for cp in sys.argv[4:]:
    d = mocap.decode(cp, segs)
    W.append(d['W'][::7]); OFF = d['off'][0]
W = np.concatenate(W).astype(np.float64)
n = W.shape[1]
par = list(skel['parent'])
vis = np.abs(np.linalg.det(W[:, :, :3, :3])).min(0) > 1e-3     # hidden parts carry a zero-scale matrix
skel['hidden'] = [k for k in range(n) if not vis[k]]
changed = []
for k in range(1, n):
    if not vis[k]: continue
    best, bp = None, None
    for p in range(n):
        if p == k or not vis[p]: continue
        e = 0.0
        for f in range(W.shape[0]):
            L = W[f, k] @ np.linalg.inv(W[f, p])
            e = max(e, float(np.abs(L[3, :3] - OFF[k]).max()))
            if e > 0.05: break
        if best is None or e < best: best, bp = e, p
    if best is not None and best <= 0.05 and bp != par[k]:
        # prefer the existing parent if it also fits (identical world matrices on co-located parts)
        e0 = max(float(np.abs((W[f, k] @ np.linalg.inv(W[f, par[k]]))[3, :3] - OFF[k]).max()) for f in range(W.shape[0])) if par[k] >= 0 and vis[par[k]] else 1e9
        if e0 > 0.05:
            changed.append((k, par[k], bp, round(best, 4))); par[k] = bp
    elif best is None or best > 0.05:
        changed.append((k, par[k], 'NOFIT', round(best or -1, 3)))
skel['parent'] = par
skel['offset'] = [[round(float(x), 4) for x in OFF[k]] for k in range(n)]
json.dump(skel, open(sout, 'w'), indent=1)
print('changed', changed, 'hidden', skel['hidden'])
print('parent', par)
