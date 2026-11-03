#!/usr/bin/env python3
"""Add newly captured Motion Check motions to a fighter that is already built (pass 3): decode only the new captures
(clips.py), merge them into the existing clip folder + index, redo the PC remap, re-export both forms' rigs and clip
maps exactly like do_fighter.py build (skeletons are not re-solved).
  add_clips.py capture N PREFIX k2_206,k2_211   (Flycast free: boots Motion Check for player N, captures form 0)
  add_clips.py build N PREFIX k2_206,k2_211
ids may carry a capture length: k2_000:60 (frames, default 240). Env (see do_fighter.py): PS_FC_INST=r1 (an isolated
fcinst instance, never the default Flycast), PS_ROOT=worktree (the build writes its game/assets/ripped), PS_MOCAP=dir
(clip folders + segs; a copy keeps rip/mocap untouched), PS_TMP=scratch dir."""
import json, os, shutil, subprocess, sys
import numpy as np
R = os.environ.get('PS_ROOT', './')
PY = sys.executable
sys.path.insert(0, R + 'tools')
import do_fighter as d
MOCAP, CAP, TMP = d.MOCAP, d.CAP, d.TMP
CAPS = [CAP] + [c.rstrip('/') + '/' for c in os.environ.get('PS_CAPS', '').split(':') if c]   # more capture folders


def split_ids(ids):
    out = []
    for i in ids:
        a, _, f = i.partition(':')
        out.append((a, int(f) if f else 240))
    return out


def capture(n, prefix, ids):
    import arcade
    d.restart()
    d.fc(arcade.motion_check(n))
    v = d.peek_player()
    assert v & 0xFF == n, f'player field {v:08x} != {n}'
    seg = json.load(open(MOCAP + f'segs_{d.pn(n, 0).lower()}_f0.json'))['seg']
    ids = split_ids(ids)
    for kind in sorted(set(int(i[1]) for i, _ in ids)):
        c, tot = [f'poke8 0x0C49492E {kind}', 'poke8 0x0C49492F 3', 'wait 10'], 0
        for i, fr in ids:
            if int(i[1]) != kind: continue
            m = int(i[3:])
            c += [f'poke32 0x0C49493C {(m - 1) & 0xFFFFFFFF if m else 0xFFFFFFFF}', f'capseg {prefix}{i} {fr} {seg}',
                  'press 1 RIGHT 2', f'wait {fr}']
            tot += fr
        d.fc(c, 300 + tot // 5)      # capseg slows Flycast to ~14 fps: budget 1/5 s per frame
    print('captured', prefix, ids, flush=True)


def glb_root_y(path, clip):
    import struct
    b = open(path, 'rb').read()
    n = struct.unpack_from('<I', b, 12)[0]
    J = json.loads(b[20:20 + n]); bl = struct.unpack_from('<I', b, 20 + n)[0]; B = b[28 + n:28 + n + bl]
    an = next(a for a in J['animations'] if a['name'] == clip)
    ch = next(c for c in an['channels'] if c['target']['path'] == 'translation' and J['nodes'][c['target']['node']]['name'] == 'b00')
    a = J['accessors'][an['samplers'][ch['sampler']]['output']]; v = J['bufferViews'][a['bufferView']]
    return float(np.frombuffer(B, '<f4', a['count'] * 3, v.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, 3)[:, 1].mean())


def build(n, prefix, ids, pre=None):
    """pre = a folder of clips already cut (tools/fight_clips.py: <prefix><id>.npz + index.json): merged instead of
    cutting Motion Check captures with clips.py"""
    p0, p1 = d.pn(n, 0).lower(), d.pn(n, 1).lower()
    ids = [i for i, _ in split_ids(ids)]
    cd = MOCAP + f'clips_{p0[:2]}'
    tmp = pre or f'{TMP}/addclips_{prefix}'
    if pre is None:
        shutil.rmtree(tmp, ignore_errors=True)
        caps = [next(c + f'{prefix}{i}.bin' for c in CAPS if os.path.exists(c + f'{prefix}{i}.bin')) for i in ids
                if any(os.path.exists(c + f'{prefix}{i}.bin') for c in CAPS)]
    new = {}
    if pre is not None:
        new = {k: v for k, v in json.load(open(tmp + '/index.json')).items() if k in [prefix + i for i in ids]}
    elif caps:     # no captures (ids 'none'): re-export what the clip folder already holds
        d.sh(PY, R + 'tools/clips.py', R + f'rip/skel/{p0}.json', MOCAP + f'segs_{p0}_f0.json', tmp, *caps)
        new = json.load(open(tmp + '/index.json'))
    idx = json.load(open(cd + '/index.json'))
    for k, v in new.items():
        shutil.copy(f'{tmp}/{k}.npz', f'{cd}/{k}.npz'); idx[k] = v
    json.dump(idx, open(cd + '/index.json', 'w'), indent=1)
    print(prefix, 'merged', sorted(new), '->', len(idx), 'clips', flush=True)
    sk0 = json.load(open(R + f'rip/skel/{p0}.json'))
    jobs = [(p0, cd, sk0, 1.0)]
    pc = prefix[0] + '1'
    if os.path.exists(R + f'rip/fs/{p1.upper()}.MDL') and not os.path.exists(d.MAIN + f'dumps/cap/{pc}k0_000.bin'):
        # Falcon / Ryoma (built in pass 2, no PC idle capture under this name): the PC root scale is read back from the
        # existing GLBs; Ryoma's extra PC parts keep the constant rotations his remapped clips already hold
        sk1 = json.load(open(R + f'rip/skel/{p1}.json'))
        scale = round(glb_root_y(R + f'game/assets/ripped/{p1}.glb', f'{prefix}k0_000') /
                      glb_root_y(R + f'game/assets/ripped/{p0}.glb', f'{prefix}k0_000'), 3)
        cdp = cd + 'pc'
        if os.path.isdir(cdp):
            const = np.load(f'{cdp}/{prefix}k0_000.npz')['q'][:1]
            pidx = json.load(open(cdp + '/index.json'))
            for k in new:
                c = np.load(f'{cd}/{k}.npz')
                q = np.repeat(const, c['q'].shape[0], 0); q[:, :19] = c['q'][:, :19]
                np.savez_compressed(f'{cdp}/{k}.npz', q=q.astype(np.float32), t=c['t'].astype(np.float32), loop=c['loop'])
                pidx[k] = dict(idx[k], src=k)
            json.dump(pidx, open(cdp + '/index.json', 'w'), indent=1)
            jobs.append((p1, cdp, sk1, scale))
        else:
            jobs.append((p1, cd, sk1, scale))
        print(prefix, 'PC root scale (from the existing GLBs)', scale, flush=True)
    elif os.path.exists(R + f'rip/fs/{p1.upper()}.MDL'):
        pcc = [d.MAIN + f'dumps/cap/{pc}k0_000.bin', d.MAIN + f'dumps/cap/{pc}k1_016.bin']
        sk1 = json.load(open(R + f'rip/skel/{p1}.json'))
        shutil.rmtree(f'{TMP}/pcidle', ignore_errors=True)
        d.sh(PY, R + 'tools/clips.py', R + f'rip/skel/{p1}.json', MOCAP + f'segs_{p1}_f0.json', f'{TMP}/pcidle', pcc[0])
        a = np.load(cd + f'/{prefix}k0_000.npz'); b = np.load(f'{TMP}/pcidle/{pc}k0_000.npz')
        m = min(len(a['t']), len(b['t']))
        scale = round(float(b['t'][:m, 1].mean() / a['t'][:m, 1].mean()), 3)
        if len(sk0['parent']) == len(sk1['parent']) and sk0['parent'] == sk1['parent']:
            jobs.append((p1, cd, sk1, scale))
        else:
            cdp = cd + 'pc'
            shutil.rmtree(cdp, ignore_errors=True)
            print(d.sh(PY, R + 'tools/remap_clips.py', R + f'rip/skel/{p1}.json', MOCAP + f'segs_{p1}_f0.json', pcc[0],
                       cd, cdp, '19').strip()[-200:])
            jobs.append((p1, cdp, sk1, scale))
    for name, cdir, sk, scale in jobs:
        nparts = len(sk['parent'])
        loose = [k for k in range(1, nparts) if sk['parent'][k] < 0]
        split = sorted(set(list(range(nparts - 10, nparts)) + sk.get('hidden', []) + sk.get('missing', []) + loose))
        args = [PY, R + 'tools/export_rig.py', R + f'rip/fs/{name.upper()}.MDL', R + f'rip/fs/{name.upper()}_MODEL.BIN',
                R + f'rip/skel/{name}.json', cdir, R + f'game/assets/ripped/{name}.glb', '--texdir', R + f'rip/up/{name.upper()}',
                '--split', ','.join(map(str, split))]
        if scale != 1.0: args += ['--root-scale', str(scale)]
        print(d.sh(*args).strip().split('\n')[-1], flush=True)
        print(d.sh(PY, R + 'tools/make_clipmap.py', prefix, cdir, R + f'rip/skel/{name}.json',
                   R + f'game/assets/ripped/{name}_clips.json').strip(), flush=True)


if __name__ == '__main__':
    {'capture': capture, 'build': build}[sys.argv[1]](int(sys.argv[2], 16), sys.argv[3], sys.argv[4].split(','))
