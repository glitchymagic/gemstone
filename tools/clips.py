#!/usr/bin/env python3
"""RAM motion capture -> animation clips. Each capture (tools/mocap.py decode) holds the game's own world matrices
for every bone, recorded every vblank while Motion Check plays one motion. Local bone rotations are recovered
exactly as L = W_bone * inverse(W_parent) (row vectors); the root is taken relative to the fighter's base
transform (Motion Check: P1 stands at x = -70 facing +X, ANGLE 0x4000).
The playhead (Motion Check u16 at 0x0C494938) marks frame 0; a motion ends where the playhead stops (one-shot,
the game holds the last pose) or where the pose returns to frame 0 (loop).
Usage: clips.py skel.json out_dir cap1.bin [cap2.bin ...]   (segs JSON = rip/mocap/segs_<form>.json via --segs)"""
import argparse, json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap


def mchar(angle=0x4000, pos=(-70.0, 0.0, 0.0)):
    a = angle / 65536.0 * 2 * np.pi
    M = np.eye(4)
    M[:3, :3] = [[np.cos(a), 0, -np.sin(a)], [0, 1, 0], [np.sin(a), 0, np.cos(a)]]
    M[3, :3] = pos
    return M


def quat(R):
    """column-vector rotation matrix -> xyzw"""
    U, _, Vt = np.linalg.svd(R); R = U @ Vt
    t = np.trace(R)
    if t > 0:
        s = np.sqrt(t + 1) * 2; w = s / 4; x = (R[2, 1] - R[1, 2]) / s; y = (R[0, 2] - R[2, 0]) / s; z = (R[1, 0] - R[0, 1]) / s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = np.sqrt(1 + R[0, 0] - R[1, 1] - R[2, 2]) * 2; w = (R[2, 1] - R[1, 2]) / s; x = s / 4; y = (R[0, 1] + R[1, 0]) / s; z = (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = np.sqrt(1 + R[1, 1] - R[0, 0] - R[2, 2]) * 2; w = (R[0, 2] - R[2, 0]) / s; x = (R[0, 1] + R[1, 0]) / s; y = s / 4; z = (R[1, 2] + R[2, 1]) / s
    else:
        s = np.sqrt(1 + R[2, 2] - R[0, 0] - R[1, 1]) * 2; w = (R[1, 0] - R[0, 1]) / s; x = (R[0, 2] + R[2, 0]) / s; y = (R[1, 2] + R[2, 1]) / s; z = s / 4
    return np.array([x, y, z, w])


def segment(d):
    var = d['var'].astype(np.int64)
    ph = var[:, 0x18] | (var[:, 0x19] << 8)
    rot = d['rot'].reshape(len(ph), -1).astype(np.int64)
    m0 = ph[:12].min()
    s = max(i for i in range(12) if ph[i] == m0)        # last frame still at the reset value
    tail = ph[s:]
    inc = np.nonzero(np.diff(tail) == 0)[0]
    if len(inc) and np.all(np.diff(tail[inc[0]:]) == 0):
        e = s + int(inc[0])
        return s, e - s + 1, False, ph
    # loop: exact period p in the settled second half, then the earliest frame k where it already repeats
    F = len(ph)
    def wrapd(x): return np.abs(((x) + 32768) % 65536 - 32768)
    for p in range(8, (F - s) // 2):
        t = np.arange(max(s, F - 2 * p), F - p)
        if wrapd(rot[t + p] - rot[t]).max() <= 40:
            k = next(k for k in range(s, F - p) if wrapd(rot[k + p] - rot[k]).max() <= 40)
            return k, p, True, ph
    return s, F - s, True, ph


def to_clip(d, skel, s, length, M):
    par = skel['parent']
    W = d['W'].astype(np.float64)
    n = W.shape[1]
    Minv = np.linalg.inv(M)
    q = np.zeros((length, n, 4)); q[..., 3] = 1; t = np.zeros((length, 3)); err = 0.0
    tl = np.tile(np.asarray(skel['offset'], dtype=np.float64), (length, 1, 1))   # local translations (pass 3)
    vis = np.abs(np.linalg.det(W[s:s + length, :, :3, :3])).min(0) > 1e-3   # hidden parts: zero-scale matrix
    for f in range(length):
        Wf = W[s + f]
        for k in range(n):
            if not vis[k] or (par[k] >= 0 and not vis[par[k]]): continue
            L = Wf[k] @ (np.linalg.inv(Wf[par[k]]) if par[k] >= 0 else Minv)
            q[f, k] = quat(L[:3, :3].T)
            if par[k] < 0:
                if k == 0: t[f] = L[3, :3]   # only the real root; other parentless parts (effects) must not overwrite it
            else: tl[f, k] = L[3, :3]
    for f in range(1, length):          # hemisphere continuity for linear interpolation
        flip = np.sum(q[f] * q[f - 1], axis=1) < 0
        q[f, flip] *= -1
    dev = np.abs(tl - np.asarray(skel['offset'])[None]).max(axis=(0, 2))
    dev[[k for k in range(n) if par[k] < 0]] = 0
    free = [int(k) for k in np.nonzero(dev > 0.5)[0]]   # parts that leave their bone (thrown weapons, projectiles)
    err = float(dev.max()) if len(dev) else 0.0
    return q, t, err, tl, free


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('skel'); ap.add_argument('segs'); ap.add_argument('out'); ap.add_argument('caps', nargs='+')
    ap.add_argument('--angle', type=lambda x: int(x, 0), default=0x4000); ap.add_argument('--x', type=float, default=-70.0)
    ap.add_argument('--names', help='json {motion number: name}')
    a = ap.parse_args()
    skel = json.load(open(a.skel)); os.makedirs(a.out, exist_ok=True)
    names = json.load(open(a.names)) if a.names else {}
    M = mchar(a.angle, (a.x, 0, 0))
    index = {}
    for cp in a.caps:
        d = mocap.decode(cp, a.segs)
        s, length, loop, ph = segment(d)
        q, t, err, tl, free = to_clip(d, skel, s, length, M)
        mid = os.path.splitext(os.path.basename(cp))[0]
        num = mid.split('_')[-1]
        nm = names.get(str(int(num)), mid)
        np.savez_compressed(os.path.join(a.out, nm + '.npz'), q=q.astype(np.float32), t=t.astype(np.float32), loop=loop,
                            tl=tl[:, free].astype(np.float32), free=np.array(free, dtype=np.int32))
        index[nm] = {'src': mid, 'start': s, 'frames': length, 'loop': loop, 'offset_err': round(err, 3), 'free': free,
                     'ph0': int(ph[s]), 'root_y': [round(float(t[:, 1].min()), 1), round(float(t[:, 1].max()), 1)]}
        print(nm, index[nm])
    json.dump(index, open(os.path.join(a.out, 'index.json'), 'w'), indent=1)
