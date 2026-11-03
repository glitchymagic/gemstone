#!/usr/bin/env python3
"""The look of the Power Drive / Fusion shots (w8, docs/SHOTS.md "Look"): which effect-model part each shot draws and
where, every frame, from the disc's own draw nodes; plus the parts as .glb files.

On the disc a shot object (pool slot, 0x31C bytes) carries its draw nodes: +0x2DC = node count, +0x2E0.. = node
pointers (0xA4-byte nodes: N - 0x54 = the world matrix, 4 rows of 4 floats, row vectors X / Y / Z axes + translation in
cm, scale included; N - 8 = the model part pointer (into the attacker's EFn0.MDL or the common bank in 1ST_READ at
0x171088, textures EFKY_MODEL.BIN: air Drive X flipbook 68-71, Fusion X sparks 16 / 17), 0 = a transform-only node; N + 0 = flags 0xF0001; N + 4 / + 0x10 /
+ 0x1C = local position / rotation / scale). The parts live in the attacker's EFn0.MDL, loaded whole in RAM (part
pointer table before it; Ryoma's at 0x0C600620 when he is P1). Logged with `SHOT_NODES=1 SHOT_TAG=_nd pc_shots.py log
INST <f>` (the node region 0x0C36C000 + 0x8000 every frame -> o_shot_<f>_nd.nodes.bin, the same tape as the shot
table's logs: the run is deterministic, its shots match part A one for one).

Out: game/assets/fidelity/pc_shot_look.json (tracked): fighters -> move -> one entry per pc_shots.json shot (same
order): rows = per frame [[part, X(3), Y(3), Z(3), T(3)], ...] in the attacker's frame of that shot ([fwd, side, up]
like the table's positions; T = cm from the shot's own position that row, so a shot at a random spot keeps its look), part < 1000 = EFn0.MDL part, 1000 + i = common bank part i; [] = nothing drawn. glbs: game/assets/ripped/effects/efN0_pPP.glb
(untracked disc data, tools/export_glb.py).
  shot_look.py build [fighters]     the table (needs the _nd logs)
  shot_look.py glb [fighters]       export the parts the table uses"""
import json, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('COV_SLOTS', '64')
import pc_shots, psmdl

R = './'
D = pc_shots.D
OUT = R + 'game/assets/fidelity/pc_shot_look.json'
GLB = R + 'game/assets/ripped/effects/'
END = 0x0C374000   # the logged node region ends here; its start follows the log's size (pc_shots.py SHOT_NODES)
TAG = '_nd'
BANK, EFKY_TAB, EFKY_N = 0x171088, 0x1C7414, 41   # the common model bank in 1ST_READ + its texture table (item_mesh.py)
COMMON = 1000
ITEM_TAB, ITEM_N, ITEM_PARTS = 0x1C76B4, 2, (142, 176)   # item_mesh.py: the 35 item parts use ITEM_MODEL.BIN's textures
_bank = None


def bank():
    global _bank
    if _bank is None:
        exe = open(R + 'rip/fs/1ST_READ.BIN', 'rb').read()
        parts, _, _ = psmdl.parse(exe[BANK:])
        _bank = (exe, parts, {0x0C010000 + BANK + p['ofs']: COMMON + i for i, p in enumerate(parts)})
    return _bank


def ef_index(f):
    return pc_shots.FIGHTERS.index(f)


def ef_parts(f):
    """(RAM base of the attacker's EFn0.MDL in the logged run, part offsets) from the run's ready RAM."""
    n = ef_index(f)
    mdl = open(R + f'rip/fs/EF{n:X}0.MDL', 'rb').read()
    ram = open(D + f'o_shot_{f}{TAG}_ready_ram.bin', 'rb').read()
    i = ram.find(mdl[64:112])
    if i < 0: raise SystemExit(f'{f}: EF{n:X}0.MDL not found in RAM')
    parts, _, _ = psmdl.parse(mdl)
    return 0x0C000000 + i - 64, {p['ofs']: k for k, p in enumerate(parts)}


# parts the disc colours per frame in a way not decoded yet (checked against the disc's own screenshots, SHOT_PICS):
# Valgas' 6 m Drive X sphere (opaque list, tex 12) is a white / pink blast on the disc, a solid teal ball plain
HIDE = {('valgas', 0)}


def node_rows(f, k, nm, nodes, fs):
    """Per pool file of a press: {slot: [(part, matrix 16 floats), ...]} for the slot's mesh nodes."""
    base, ofs = ef_parts(f)
    NB, NLEN = END - fs, fs
    d = D + f'pool/{f}{TAG}/{k}_{nm}/'
    out = []
    for i, fn in enumerate(sorted(os.listdir(d))):
        B = open(d + fn, 'rb').read()
        r = k + 1 + i
        reg = nodes[r * fs:(r + 1) * fs]
        row = {}
        for s in range(pc_shots.NSLOT):
            o = s * pc_shots.STRIDE
            if B[o + 2] != 1 or B[o + 3] != 0: continue
            n = struct.unpack_from('<I', B, o + 0x2DC)[0]
            ms = []
            for j in range(min(n, 16)):
                a = struct.unpack_from('<I', B, o + 0x2E0 + 4 * j)[0]
                if not NB + 0x54 <= a < NB + NLEN - 0x20: continue
                pp = struct.unpack_from('<I', reg, a - 8 - NB)[0]
                if not pp: continue
                part = ofs.get(pp - base, bank()[2].get(pp))
                m = struct.unpack_from('<16f', reg, a - 0x54 - NB)
                if part is None or not any(m[:12]) or (f, part) in HIDE: continue   # another bank / a zero matrix / HIDE
                ms.append((part, m))
            row[s] = ms
        out.append(row)
    return out


def _vec(u, fw):
    return [u[0] * fw[0] + u[2] * fw[1], u[0] * fw[1] - u[2] * fw[0], u[1]]


def build(names):
    tab = json.load(open(OUT)) if os.path.exists(OUT) else {}
    tab['about'] = __doc__.split('\n\n')[0] + ' See tools/shot_look.py.'
    shots_tab = json.load(open(pc_shots.OUT))['fighters']
    for f in names:
        nodes = open(D + f'o_shot_{f}{TAG}.nodes.bin', 'rb').read()
        nlen = len(nodes) // json.load(open(D + f'o_shot_{f}{TAG}.meta.json'))['frames']
        dv = pc_shots.drives(f + TAG)
        by = {}
        for d in dv: by.setdefault(d['name'], []).append(d)
        mv = {}
        for nm, ds in by.items():
            looks = []
            for d in ds:
                nr = node_rows(f, d['press'], nm, nodes, nlen)
                lk = []
                for s in d['shots']:
                    org, fw = d['org'], s['fw']
                    rows = []
                    for r in range(s['t'] + d['t0'], s['t'] + d['t0'] + len(s['rows'])):
                        i = r - d['press'] - 1
                        ms = nr[i].get(s['slot'], []) if 0 <= i < len(nr) else []
                        sp = s['rows'][r - s['t'] - d['t0']][0]   # the shot's own position that row (attacker frame)
                        rows.append([[p] + [round(v, 3) for ax in range(3) for v in _vec(m[4 * ax:4 * ax + 3], fw)] +
                                     [round(v - sp[i], 1) for i, v in enumerate(pc_shots._rel(m[12], m[13], m[14], org, fw))]
                                     for p, m in ms])
                    lk.append(dict(t=s['t'], kind=s['kind'], p0=s['rows'][0][0], rows=rows))
                looks.append(lk)
            # one entry per table shot: part A's shot of the same spawn row / kind / start, extended from part B
            out = []
            for sh in (shots_tab.get(f, {}).get(nm, {}).get('shots', [])):
                p0 = sh['rows'][0][0]
                k = sum(1 for o in out if (o['t'], o['kind']) == (sh['t'], sh['kind']))   # n-th shot of its row / kind
                def find(lk):   # same start (fixed paths), else the n-th of its row and kind (random spots: Valgas FY)
                    same = [x for x in lk if (x['t'], x['kind']) == (sh['t'], sh['kind'])]
                    return next((x for x in same if max(abs(x['p0'][i] - p0[i]) for i in range(3)) < 25),
                                same[k] if k < len(same) else None)
                a = find(looks[0]) if looks else None
                rows = list(a['rows']) if a else []
                for lk in looks[1:]:
                    if len(rows) >= len(sh['rows']): break
                    b = find(lk)
                    if b and len(b['rows']) > len(rows): rows += b['rows'][len(rows):]
                out.append(dict(t=sh['t'], kind=sh['kind'], rows=rows[:len(sh['rows'])]))
            mv[nm] = out
        tab.setdefault('fighters', {})[f] = dict(ef=f'ef{ef_index(f):x}0', moves=mv)
        used = sorted({n[0] for m in mv.values() for s in m for r in s['rows'] for n in r})
        print(f, 'parts', used, {k: (len(v), sum(1 for s in v if any(s['rows']))) for k, v in mv.items()})
    json.dump(tab, open(OUT + '.tmp', 'w'), separators=(',', ':'))
    os.replace(OUT + '.tmp', OUT)


def glb(names):
    import export_glb
    tab = json.load(open(OUT))
    os.makedirs(GLB, exist_ok=True)
    for f in names:
        e = tab['fighters'][f]
        used = sorted({n[0] for m in e['moves'].values() for s in m for r in s['rows'] for n in r})
        n = ef_index(f)
        for p in [q for q in used if q >= COMMON]:
            exe, parts, _ = bank()
            tmp = GLB + '_bank.mdl'
            item = ITEM_PARTS[0] <= p - COMMON <= ITEM_PARTS[1]   # the item meshes (Kraken's bomb = part 151): item textures
            ttab, tn, mb = (ITEM_TAB, ITEM_N, 'ITEM_MODEL.BIN') if item else (EFKY_TAB, EFKY_N, 'EFKY_MODEL.BIN')
            open(tmp, 'wb').write(exe[BANK:BANK + parts[-1]['end']] + exe[ttab:ttab + 16 * tn] + b'\0' * 16)
            export_glb.build(tmp, R + 'rip/fs/' + mb, GLB + f'common_p{p - COMMON:03d}.glb', None, {p - COMMON},
                             None, f'common_p{p - COMMON:03d}')
            os.replace(tmp, os.environ.get('TMPDIR', '/tmp').rstrip('/') + '/_bank.mdl')
        for p in [q for q in used if q < COMMON]:
            export_glb.build(R + f'rip/fs/EF{n:X}0.MDL', R + f'rip/fs/EF{n:X}0_MODEL.BIN', GLB + f'{e["ef"]}_p{p:02d}.glb',
                             None, {p}, None, f'{e["ef"]}_p{p:02d}')


if __name__ == '__main__':
    names = sys.argv[2:] or [f for f in pc_shots.FIGHTERS if os.path.exists(D + f'o_shot_{f}{TAG}.nodes.bin')]
    {'build': build, 'glb': glb}[sys.argv[1]](names)
