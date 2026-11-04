#!/usr/bin/env python3
"""Importer step 'fighters': every fighter form's rig, textures and motions straight from the player's disc.
  fighters_import.py [FORM ...]        all 21 forms (p00 p01 ... p91 pa0) or only the ones named
Per form: hd_tex.py decode -> rip/tex/PNF, upscale.py -> rip/up/PNF, mdt_decode.export_form (Pn0_MOT.MDT + the
1ST_READ form descriptor) -> rip/mocap/clips_pnf, the throw-victim clips (kind 4 ids >= 48 live in the THROWER's file
and play on the victim with the thrower's root scale + bone-0 offset), skeleton json, export_rig.py ->
game/assets/ripped/pnf.glb, make_clipmap.py -> pnf_clips.json. Nothing here was recorded from an emulator.
Not in the disc's motion file (the game computes them every frame, so these parts keep their constant pose):
braids / ribbons / charms (physics chains), parts that leave their bone in a motion (thrown props, Ryoma's sword)."""
import json, os, shutil, subprocess, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import mdt_decode as M
FS = os.path.join(ROOT, 'rip', 'fs')
RIP = os.path.join(ROOT, 'rip')
OUT = os.path.join(ROOT, 'game', 'assets', 'ripped')
PY = sys.executable
ALIASES = [(1, 10), (4, 1)]   # clips the game plays from a table slot that is 0 (= that kind's entry 0)
# Final Valgas's kind 2 is a stub (nothing in its table): the shared hit-reaction ids play its entry 0
FV_ALIASES = [(0, 6)] + [(2, m) for m in (106, 107, 112, 115, 118, 120, 128, 129, 130, 144, 145, 146, 147, 148, 152,
                                          153, 158, 159, 175, 219, 220, 221)]
VICTIM_MIN = 48          # kind-4 ids from 48 up are the victim halves of throws (the thrower's own are below)


def sh(*a):
    r = subprocess.run([str(x) for x in a], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f'{a[1] if len(a) > 1 else a[0]}: ' + (r.stdout[-800:] + r.stderr[-800:]).strip())
    return r.stdout


def forms():
    out = []
    for c in range(11):
        for f in (0, 1):
            if os.path.exists(os.path.join(FS, 'P%X%d.MDL' % (c, f))):
                out.append((c, f))
    return out


def skeleton(exe, c, f):
    sk = M.skeleton_from_disc(exe, c, f)
    par = list(sk['parent'])
    if c == 10:          # Final Valgas: the game hangs bone 18 off the head (4), not the hard-coded 17 (seen in RAM)
        par[18] = 4
    # head / hand variants: the game draws only the selected one (variant 0 by default)
    hidden = set(k for g in sk['groups'][2:] for k in g[1:])
    # extras that ride a non-default variant (Ryoma's spare sword pieces on hand pose 2/3, Jack's on hand pose 1 ...)
    # are not drawn by default either
    for k in sk['groups'][1]:
        a = k
        while a >= 0 and a not in hidden and a in sk['groups'][1]:
            a = par[a]
        if a in hidden:
            hidden.add(k)
    hidden = sorted(hidden)
    return dict(parent=par, offset=sk['offset'], hidden=hidden, missing=[], groups=sk['groups'],
                const_rot={str(k): v for k, v in sk['const_rot'].items()}, source='1ST_READ.BIN descriptor')


def victim_clips(exe, c, f, sk, cd, prefix, index):
    """every thrower's victim motions (kind 4, id >= 48) on this form's skeleton"""
    n = len(sk['parent'])
    cr = {int(k): v for k, v in sk['const_rot'].items()}
    made = 0
    for t in range(10):
        md = M.MDT(os.path.join(FS, 'P%X0_MOT.MDT' % t))
        tsk = M.skeleton_from_disc(exe, t, 0)
        tpre = '%s0' % M.LETTER[t]
        for k, m in md.motions():
            if k != 4 or m < VICTIM_MIN:
                continue
            F, lf = M.clip_span(md, 4, m)
            p = M.play(md, 4, m, F + 1, t, 0)
            q, tr = M.to_clip(p, n, tsk['offset'][0], cr, M.MODEL_SCALE[t][0])
            name = f'{prefix}k4_{m:03d}_{tpre}'
            np.savez_compressed(os.path.join(cd, name + '.npz'), q=q[1:].astype(np.float32),
                                t=tr[1:].astype(np.float32), loop=False, loop_from=-1)
            index[name] = {'kind': 4, 'motion': m, 'frames': F, 'loop': False, 'loop_from': None, 'thrower': tpre,
                           'src': 'P%X0_MOT.MDT' % t}
            made += 1
    return made


def build(c, f, exe):
    name = 'p%x%d' % (c, f)
    P = name.upper()
    prefix = '%s0' % M.LETTER[c]
    tex, up = os.path.join(RIP, 'tex', P), os.path.join(RIP, 'up', P)
    if not os.path.isdir(tex) or not os.listdir(tex):
        sh(PY, os.path.join(HERE, 'hd_tex.py'), 'decode', P, tex)
    sh(PY, os.path.join(HERE, 'upscale.py'), tex, up)            # skips the ones already done
    cd = os.path.join(RIP, 'mocap', 'clips_' + name)
    os.makedirs(cd, exist_ok=True)
    for old in os.listdir(cd):
        if old.endswith('.npz'): os.remove(os.path.join(cd, old))
    index = M.export_form(FS, c, f, cd, prefix=prefix)
    md = M.MDT(os.path.join(FS, 'P%X0_MOT.MDT' % c))
    # slots the game plays that point at entry 0 (table value 0), which md.motions() skips: the air punch k1/10 ...
    extra = [(k, m) for k, m in ALIASES + (FV_ALIASES if c == 10 else [])
             if '%sk%d_%03d' % (prefix, k, m) not in index and md.table[k][m] == 0]
    if extra:
        index.update(M.export_form(FS, c, f, cd + '.x', only=extra, prefix=prefix))
        for nm in os.listdir(cd + '.x'):
            if nm.endswith('.npz'): os.replace(os.path.join(cd + '.x', nm), os.path.join(cd, nm))
        shutil.rmtree(cd + '.x')
    # a loop with a lead-in: the game plays the lead-in once, then repeats from loop_from; Godot repeats the whole
    # clip, so fight loops (air tumble k2/112 ...) keep only the loop. Kind 3 (win / lose poses, played once at the
    # end) keeps lead-in + one loop period: the pose IS the lead-in.
    for nm, e in index.items():
        if e['loop'] and e['loop_from'] and e['kind'] != 3:
            p = os.path.join(cd, nm + '.npz')
            z = dict(np.load(p))
            for k in ('q', 't', 'rot', 'body_rot'):
                if k in z: z[k] = z[k][e['loop_from']:]
            np.savez_compressed(p, **z)
            e['lead_in_cut'] = e['loop_from']; e['frames'] -= e['loop_from']
    sk = skeleton(exe, c, f)
    nv = victim_clips(exe, c, f, sk, cd, prefix, index) if c < 10 else 0
    json.dump(index, open(os.path.join(cd, 'index.json'), 'w'), indent=1)
    os.makedirs(os.path.join(RIP, 'skel'), exist_ok=True)
    skp = os.path.join(RIP, 'skel', name + '.json')
    json.dump(sk, open(skp, 'w'), indent=1)
    n = len(sk['parent'])
    split = sorted(set(list(range(n - 10, n)) + sk['hidden']))
    os.makedirs(OUT, exist_ok=True)
    glb = os.path.join(OUT, name + '.glb')
    sh(PY, os.path.join(HERE, 'export_rig.py'), os.path.join(FS, P + '.MDL'), os.path.join(FS, P + '_MODEL.BIN'),
       skp, cd, glb, '--texdir', up, '--split', ','.join(map(str, split)))
    msg = sh(PY, os.path.join(HERE, 'make_clipmap.py'), prefix, cd, skp, os.path.join(OUT, name + '_clips.json')).strip()
    return dict(form=name, clips=len(index), victim_clips=nv, glb_bytes=os.path.getsize(glb), clipmap=msg.split(' ', 1)[1])


def main():
    exe = open(os.path.join(FS, '1ST_READ.BIN'), 'rb').read()
    M.load_tables(exe)
    want = set(a.lower() for a in sys.argv[1:])
    res = []
    for c, f in forms():
        if want and 'p%x%d' % (c, f) not in want:
            continue
        r = build(c, f, exe)
        print(json.dumps(r), flush=True)
        res.append(r)
    clip_frames()
    return res


NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']


def clip_frames():
    """game/assets/fidelity/clip_frames.json: every clip's last frame (= frames - 1) per fighter, normal forms (the
    game times round intros and other motion ends with it)"""
    out = {}
    for c in range(11):
        ix = os.path.join(RIP, 'mocap', 'clips_p%x0' % c, 'index.json')
        if os.path.exists(ix):
            out[NAMES[c]] = {k: int(np.load(os.path.join(os.path.dirname(ix), k + '.npz'))['q'].shape[0]) - 1
                             for k in sorted(json.load(open(ix)))}
    os.makedirs(os.path.join(ROOT, 'game', 'assets', 'fidelity'), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, 'game', 'assets', 'fidelity', 'clip_frames.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
