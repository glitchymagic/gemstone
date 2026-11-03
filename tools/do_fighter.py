#!/usr/bin/env python3
"""One fighter, end to end, from the owner's disc + the game's own motion player (pass 3). Mechanical steps only; the
logged arcade fight (tools/arcade.py moves) and the PER clip map entries stay a human/agent decision.
  do_fighter.py N PREFIX boot      restart Flycast -> Motion Check player N; RAM dumps of both forms;
                                   segs + RAM skeletons -> rip/mocap/segs_pN{0,1}_f0.json, rip/skel/pN{0,1}.json
  do_fighter.py N PREFIX capture   every kind 0/1/3 motion of the normal form + the 22 shared kind-2 ids,
                                   and the Power Change idle (for remap constants and the root scale)
  do_fighter.py N PREFIX build     solve parents, cut clips, PC clips (shared or remapped), export both GLBs, clip maps
PREFIX: 2 letters, e.g. w0 (Wang-Tang). Files: Pn0 = normal form, Pn1 = Power Change (PA has no PC form)."""
import json, os, subprocess, sys, time
import numpy as np
MAIN = './'
R = os.environ.get('PS_ROOT', MAIN)          # a worktree: builds write ITS game/assets/ripped (rip/ may be a symlink)
PY = 'python3'
FLY = MAIN + 'tools/flycast/build/Flycast.app/Contents/MacOS/Flycast'
GDI = MAIN + '_disc/Power Stone (USA).gdi'
sys.path.insert(0, R + 'tools')
# PS_FC_INST=NAME: drive an isolated tools/fcinst.py instance (own HOME, command/dump folder, started/stopped by its own
# PID) instead of the default Flycast (restart() would otherwise kill every Flycast by name)
INST = os.environ.get('PS_FC_INST')
if INST:
    from fcinst import Inst
    FI = Inst(INST)
    os.environ['PS_FC_ROOT'] = FI.root
CAP = FI.root + 'cap/' if INST else R + 'dumps/cap/'
LOG = FI.dir + 'flycast.log' if INST else '/tmp/flycast.log'
MOCAP = os.environ.get('PS_MOCAP', R + 'rip/mocap/')   # clip folders + segs (copy them to keep rip/ untouched)
TMP = os.environ.get('PS_TMP', '/tmp')


def sh(*a, **k):
    return subprocess.run(list(a), check=True, text=True, capture_output=True, **k).stdout


def fc(cmds, wait=900):
    return sh(PY, R + 'tools/fc.py', '-w', str(wait), *cmds)


def restart():
    if INST:
        FI.start(); return
    subprocess.run(['pkill', '-9', '-f', 'Flycast.app/Contents/MacOS/Flycast'])
    time.sleep(1)
    open(R + 'dumps/cmd/.seq', 'w').write('1')
    if os.path.exists(R + 'dumps/status.txt'): os.remove(R + 'dumps/status.txt')
    subprocess.Popen([FLY, GDI], stdout=open('/tmp/flycast.log', 'w'), stderr=subprocess.STDOUT, start_new_session=True)
    time.sleep(4)


def peek_player():
    fc(['peek32 0x0C49492C 1'], 30)
    line = [l for l in open(LOG, errors='replace') if 'peek 0C49492C' in l][-1]
    return int(line.split(':')[-1].split()[0], 16)


def pn(n, form):
    return 'P%X%d' % (n, form)


def boot(n, prefix):
    import arcade
    restart()
    fc(arcade.motion_check(n) + [f'shot mc{n:x}_0.png', f'dump mc{n:x}_0.bin 0x0C000000 0x1000000'])
    v = peek_player()
    assert v & 0xFF == n, f'player field {v:08x} != {n}'
    forms = [0, 1] if os.path.exists(R + f'rip/fs/{pn(n, 1)}.MDL') else [0]
    if 1 in forms:
        fc(['poke8 0x0C49492F 1', 'wait 5', 'press 1 RIGHT 3', 'wait 240', f'shot mc{n:x}_1.png',
            f'dump mc{n:x}_1.bin 0x0C000000 0x1000000', 'poke8 0x0C49492F 1', 'wait 5', 'press 1 LEFT 3', 'wait 240'])
    for f in forms:
        ram = R + f'dumps/mc{n:x}_{f}.bin'
        segs = sh(PY, R + 'tools/mocap.py', 'segs', ram, R + f'rip/fs/{pn(n, f)}.MDL')
        open(R + f'rip/mocap/segs_{pn(n, f).lower()}_f0.json', 'w').write(segs)
        print(sh(PY, R + 'tools/skel_from_ram.py', ram, R + f'rip/fs/{pn(n, f)}.MDL',
                 R + f'rip/skel/{pn(n, f).lower()}_ramslots.json').strip().split('\n')[0])
    print('boot ok', hex(peek_player()))


def capture(n, prefix):
    import mc_capture
    p0 = pn(n, 0).lower()
    for kinds in ([0, 1], [2, 3]):
        fc(mc_capture.commands(prefix, pn(n, 0), R + f'rip/mocap/segs_{p0}_f0.json', kinds), 590)
        print('captured kinds', kinds)
    if os.path.exists(R + f'rip/fs/{pn(n, 1)}.MDL'):
        seg = json.load(open(R + f'rip/mocap/segs_{pn(n, 1).lower()}_f0.json'))['seg']
        pc = prefix[0] + '1'
        fc(['poke8 0x0C49492F 1', 'wait 5', 'press 1 RIGHT 3', 'wait 240', 'poke8 0x0C49492E 0', 'poke8 0x0C49492F 3',
            'wait 5', 'poke32 0x0C49493C 0xFFFFFFFF', f'capseg {pc}k0_000 240 {seg}', 'press 1 RIGHT 2', 'wait 240',
            'poke8 0x0C49492E 1', 'poke32 0x0C49493C 15', f'capseg {pc}k1_016 160 {seg}', 'press 1 RIGHT 2', 'wait 160'])
        print('captured PC idle + k1/16')


def variants(n, prefix):
    """Probe the game's own face / R hand / L hand selectors (fighter bytes 0x0C7EB1CE/CF/D0, the Motion Check fields)
    for each form: set one selector to 0..3, record which parts get a non-zero matrix. -> rip/skel/pN{f}_variants.json"""
    import arcade, mocap
    restart()
    fc(arcade.motion_check(n))
    assert peek_player() & 0xFF == n
    forms = [0, 1] if os.path.exists(R + f'rip/fs/{pn(n, 1)}.MDL') else [0]
    for f in forms:
        if f == 1:
            fc(['poke8 0x0C49492F 1', 'wait 5', 'press 1 RIGHT 3', 'wait 240'])
        segs = R + f'rip/mocap/segs_{pn(n, f).lower()}_f0.json'
        seg = json.load(open(segs))['seg']
        res = {}
        for gi, addr in enumerate((0x0C7EB1CE, 0x0C7EB1CF, 0x0C7EB1D0)):
            for v in range(4):
                name = f'var_{prefix}{f}_{gi}{v}'
                fc([f'freeze8 0x{addr:08X} {v}', 'wait 6', f'capseg {name} 2 {seg}', 'wait 4', f'unfreeze 0x{addr:08X}',
                    f'poke8 0x{addr:08X} 0', 'wait 4'], 60)
                d = mocap.decode(R + f'dumps/cap/{name}.bin', segs)
                det = np.abs(np.linalg.det(d['W'][-1, :, :3, :3].astype(np.float64))) > 1e-3
                res[f'{gi}{v}'] = [int(k) for k in np.nonzero(det)[0]]
        base = set(res['00'])
        groups = []
        for gi in range(3):
            g = []
            for v in range(4):
                shown = sorted(set(res[f'{gi}{v}']) - (base - set(res[f'{gi}0']) if v else set()))
                new = sorted(set(res[f'{gi}{v}']) - set(res[f'{gi}0'])) if v else []
                gone = sorted(set(res[f'{gi}0']) - set(res[f'{gi}{v}'])) if v else []
                g.append({'v': v, 'shown': new, 'hidden': gone})
            groups.append(g)
        out = {'visible_default': sorted(base), 'probe': groups}
        json.dump(out, open(R + f'rip/skel/{pn(n, f).lower()}_variants.json', 'w'), indent=1)
        print(pn(n, f), json.dumps(groups))


def body_equal(a, b, nb):
    return a['parent'][:nb] == b['parent'][:nb]


def build(n, prefix):
    import glob
    p0, p1 = pn(n, 0).lower(), pn(n, 1).lower()
    caps = sorted(glob.glob(R + f'dumps/cap/{prefix}k*.bin'))
    pick = [c for c in caps if any(c.endswith(x) for x in ('k0_000.bin', 'k1_016.bin', 'k1_053.bin', 'k3_008.bin'))]
    print(sh(PY, R + 'tools/solve_parents.py', R + f'rip/mocap/segs_{p0}_f0.json', R + f'rip/skel/{p0}_ramslots.json',
             R + f'rip/skel/{p0}.json', *pick).strip().split('\n')[-2][:200])
    cd = R + f'rip/mocap/clips_{p0[:2]}'
    subprocess.run(['rm', '-rf', cd])
    sh(PY, R + 'tools/clips.py', R + f'rip/skel/{p0}.json', R + f'rip/mocap/segs_{p0}_f0.json', cd, *caps)
    idx = json.load(open(cd + '/index.json'))
    print(len(idx), 'clips; free parts', sorted(set(k for v in idx.values() for k in v['free'])))
    sk0 = json.load(open(R + f'rip/skel/{p0}.json'))
    jobs = [(p0, cd, sk0, 1.0)]
    if os.path.exists(R + f'rip/fs/{p1.upper()}.MDL'):
        pc = prefix[0] + '1'
        pcc = [R + f'dumps/cap/{pc}k0_000.bin', R + f'dumps/cap/{pc}k1_016.bin']
        print(sh(PY, R + 'tools/solve_parents.py', R + f'rip/mocap/segs_{p1}_f0.json', R + f'rip/skel/{p1}_ramslots.json',
                 R + f'rip/skel/{p1}.json', *pcc).strip().split('\n')[-2][:200])
        sk1 = json.load(open(R + f'rip/skel/{p1}.json'))
        subprocess.run(['rm', '-rf', '/tmp/pcidle'])
        sh(PY, R + 'tools/clips.py', R + f'rip/skel/{p1}.json', R + f'rip/mocap/segs_{p1}_f0.json', '/tmp/pcidle', pcc[0])
        a = np.load(cd + f'/{prefix}k0_000.npz'); b = np.load(f'/tmp/pcidle/{pc}k0_000.npz')
        m = min(len(a['t']), len(b['t']))
        scale = round(float(b['t'][:m, 1].mean() / a['t'][:m, 1].mean()), 3)
        qd = float(np.abs(a['q'][:m, :19] - b['q'][:m, :19]).max())
        same = len(sk0['parent']) == len(sk1['parent']) and sk0['parent'] == sk1['parent']
        print(f'PC: parts {len(sk0["parent"])} -> {len(sk1["parent"])}, same skeleton {same}, root scale {scale}, body q diff {qd:.4f}')
        if same:
            jobs.append((p1, cd, sk1, scale))
        else:
            cdp = cd + 'pc'
            subprocess.run(['rm', '-rf', cdp])
            print(sh(PY, R + 'tools/remap_clips.py', R + f'rip/skel/{p1}.json', R + f'rip/mocap/segs_{p1}_f0.json', pcc[0],
                     cd, cdp, '19').strip())
            jobs.append((p1, cdp, sk1, scale))
    for name, cdir, sk, scale in jobs:
        nparts = len(sk['parent'])
        loose = [k for k in range(1, nparts) if sk['parent'][k] < 0]   # parentless effect pieces: the game places them itself
        split = sorted(set(list(range(nparts - 10, nparts)) + sk.get('hidden', []) + sk.get('missing', []) + loose))
        args = [PY, R + 'tools/export_rig.py', R + f'rip/fs/{name.upper()}.MDL', R + f'rip/fs/{name.upper()}_MODEL.BIN',
                R + f'rip/skel/{name}.json', cdir, R + f'game/assets/ripped/{name}.glb', '--texdir', R + f'rip/up/{name.upper()}',
                '--split', ','.join(map(str, split))]
        if scale != 1.0: args += ['--root-scale', str(scale)]
        print(sh(*args).strip().split('\n')[-1])
        print(sh(PY, R + 'tools/make_clipmap.py', prefix, cdir, R + f'rip/skel/{name}.json',
                 R + f'game/assets/ripped/{name}_clips.json').strip())


if __name__ == '__main__':
    n, prefix, stage = int(sys.argv[1], 16), sys.argv[2], sys.argv[3]
    {'boot': boot, 'capture': capture, 'build': build, 'variants': variants}[stage](n, prefix)
