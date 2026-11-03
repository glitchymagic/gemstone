#!/usr/bin/env python3
"""Probe samples (tools/area_probe.py) -> game/assets/fidelity/STAGE_area.json: the playable area the original enforces,
for the reference fighter's centre (Falcon). Evidence = every placed point (inside if a fighter put there settled
without being moved; outside if the game pushed it out, held it, or it fell into nothing) + every pushed fighter's
resting place (exactly on the edge; P2's shifted by its radius difference) -> nearest-evidence 10 cm raster, the part
connected to the start points, small solid holes filled -> signed distance (cm, + inside), edge contours, the floor
levels per 50 cm cell, every spot the probe stood on, the round's start feet.
  stage_area.py build STAGE [--png]     samples in $AREA_OUT (default dumps/area/)
  stage_area.py patch STAGE CHECK.json surf|floor   from tests/area_check.gd (see patch())
  stage_area.py radius                   -> game/assets/fidelity/fighter_radius.json"""

import base64, glob, json, math, os, sys
import numpy as np
from scipy.spatial import cKDTree
from scipy.ndimage import distance_transform_edt
from skimage import measure

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'   # this checkout
OUT = os.environ.get('AREA_OUT', './dumps/area/')   # area_probe.py's samples
FID = R + 'game/assets/fidelity/'
CELL = 10
LCELL = 50
FCELL = 25   # floor-height raster (the 25 cm lattice the probes sit on)
NLEV = 4
# running into a ledge (D-pad runs in Flycast, docs/fx-oom.md): 50 / 53 / 55 / 60 / 65 cm are stepped up in the run state
# (held 3-4 frames at the edge, then y snaps up); 91 (Dawnvolta) / 100 (ship) / 120 (Ayame) stop the run; the dojo's
# 100 cm ledge is climbed by a 6-frame hop (state 17)
STEP_UP_CM = 65
JUMP_APEX_CM = 330   # standing jump: vy 35.5, gravity 2 cm/f^2 (o_move_basic)
JUMP_REACH_CM = 370  # moving jump: 9.75 cm/f for 38 frames
PASSES = ('A', 'B', 'C', 'RA', 'RB', 'RC', 'FA', 'FB', 'FC')


def moved(s):
    return math.hypot(s['last']['x'] - s['p'][0], s['last']['z'] - s['p'][2])


def settled(s):
    return s['last']['st'] in (0, 6) and abs(s['last']['vy']) < 0.01


def frozen(s):
    """held at the placement height (inside a collision volume on Londo): no floor (stageprobe.py frozen)"""
    return moved(s) < 3 and settled(s) and abs(s['last']['y'] - s['p'][1]) < 0.5


def stayed(s):
    return moved(s) < 3 and settled(s) and not frozen(s)


def stayed_ref(s, rel):
    """Stayed for the reference fighter: a bigger probe (rel cm more radius than Falcon) pushed back by no more than
    that difference would have left Falcon where he was put."""
    return stayed(s) or (settled(s) and not frozen(s) and rel[s['k']] > 0 and moved(s) <= rel[s['k']] + 2)


def radius_delta(d):
    """r(P2) - r(P1) in cm from the calibration (same placed points, both fighters pushed sideways onto the same floor
    by a wall: the difference of where they stop, along the push)."""
    ds = []
    for c in d.get('cal', []):
        p, f1, f2 = c['p'], c['f1'], c['f2']
        if f1['st'] not in (0, 6) or f2['st'] not in (0, 6) or abs(f1['y'] - f2['y']) > 2: continue
        n = np.array([p[0] - f1['x'], p[2] - f1['z']]); L = np.linalg.norm(n)
        L2 = math.hypot(p[0] - f2['x'], p[2] - f2['z'])
        if L < 3 or L2 < 3: continue
        n /= L
        ds.append(float(np.dot([f1['x'] - f2['x'], f1['z'] - f2['z']], n)))
    return (float(np.median(ds)) if ds else 0.0), ds


def build(stage):
    d = json.load(open(OUT + f'{stage}_probe.json'))
    S = [s for s in d['samples'] if s['pas'] in PASSES and not frozen(s)]
    d21, ds = radius_delta(d)
    # radius of each probe relative to the reference (Falcon)
    if d['p1'] == 'falcon': rel = {1: 0.0, 2: d21}
    elif d['p2'] == 'falcon': rel = {1: -d21, 2: 0.0}
    else: rel = {1: 0.0, 2: d21}
    by = {}
    for s in d['samples']:   # frozen samples count as evidence of no floor (outside unless another sample stayed)
        if s['pas'] in PASSES: by.setdefault((round(s['p'][0], 1), round(s['p'][2], 1)), []).append(s)
    ins_pts, out_pts = [], []
    for k, ss in by.items():
        (ins_pts if any(stayed_ref(s, rel) for s in ss) else out_pts).append(k)
    out_set = set(out_pts)
    edge_in, edge_out, walls = [], [], []
    for s in S:
        if not settled(s) or stayed(s): continue
        f = np.array([s['last']['x'], s['last']['z']]); p = np.array([s['p'][0], s['p'][2]])
        n = p - f; L = np.linalg.norm(n)
        if L < 3: continue
        n /= L
        fr = f + rel[s['k']] * n    # the reference fighter's centre stops here
        edge_in.append(fr)
        k = (round(s['p'][0], 1), round(s['p'][2], 1))
        if (k in out_set and L < 120) or (rel[s['k']] > 0 and L <= rel[s['k']] + 2):   # a wall push
            edge_out.append(fr + 4.0 * n); walls.append((fr, n))
    P = np.array([list(k) for k in ins_pts] + [list(e) for e in edge_in] + [list(k) for k in out_pts] + [list(e) for e in edge_out])
    lab = np.array([1] * (len(ins_pts) + len(edge_in)) + [0] * (len(out_pts) + len(edge_out)))
    tree = cKDTree(P)
    x0 = math.floor((P[:, 0].min() - 60) / CELL) * CELL; z0 = math.floor((P[:, 1].min() - 60) / CELL) * CELL
    x1 = math.ceil((P[:, 0].max() + 60) / CELL) * CELL; z1 = math.ceil((P[:, 1].max() + 60) / CELL) * CELL
    W, H = int((x1 - x0) / CELL) + 1, int((z1 - z0) / CELL) + 1
    gx, gz = np.meshgrid(x0 + np.arange(W) * CELL, z0 + np.arange(H) * CELL)
    q = np.stack([gx.ravel(), gz.ravel()], 1)
    dist, idx = tree.query(q)
    m = (lab[idx] == 1) & (dist < 45)
    # a wall push is exact: nothing past the wall's plane through the nearest pushed fighter's resting place
    # (not where a floor the game settles fighters on lies just past it: the edge of a raised floor, e.g. the ring round
    # Londo's fountain base that the game pushes a placed fighter off but a running one steps up onto)
    ipts = np.array([list(k) for k in ins_pts]); itree = cKDTree(ipts)
    keepw = []
    for fr, n in walls:
        near = itree.query_ball_point(fr + 30 * n, 32)
        if not any(5 < np.dot(ipts[i] - fr, n) < 60 for i in near): keepw.append((fr, n))
    walls = keepw
    m_nocut = m.copy()

    def cut(ws):
        mm = m_nocut.copy()
        if ws:
            wp = np.array([w[0] for w in ws]); wn = np.array([w[1] for w in ws])
            wd, wi = cKDTree(wp).query(q)
            mm &= ~((wd < 35) & (np.einsum('ij,ij->i', q - wp[wi], wn[wi]) > 2.0))
        return mm.reshape(H, W)

    def spawn_labels(lb):
        keep = set()
        for sp in d['spawn']:
            i, j = int(round((sp[2] - z0) / CELL)), int(round((sp[0] - x0) / CELL))
            if 0 <= i < H and 0 <= j < W and lb[i, j]: keep.add(lb[i, j])
        return keep
    mask = cut(walls)
    lb = measure.label(mask, connectivity=2)
    keep = spawn_labels(lb)
    # raised floors (fx-proof 10-27): the wall pushes round a block's sides cut its top off from the start floor, and the
    # "connected to the start points" rule then dropped floors the original stands fighters on: Galuda's / Rouge's
    # 60-65 cm floors that a run climbs (run tests), Ayame's 120 cm and the ship's 100 cm decks a jump reaches. An
    # island is the original's when settled fighters rest on it, its floor is at most a standing jump's apex (330 cm)
    # over the start floor and it lies within a moving jump's reach (9.75 cm/f x 38 f = 3.7 m) of the start floor's
    # part; then the wall pushes facing into it are its sides (not walls), and it joins the area.
    y0 = float(d['spawn'][0][1])
    rest = [s for s in S if settled(s) and moved(s) < 3]
    reach = distance_transform_edt(~np.isin(lb, list(keep))) * CELL
    good = set()
    for L in range(1, lb.max() + 1):
        if L in keep: continue
        ys = []
        for s_ in rest:
            i, j = int(round((s_['last']['z'] - z0) / CELL)), int(round((s_['last']['x'] - x0) / CELL))
            if 0 <= i < H and 0 <= j < W and lb[i, j] == L: ys.append(s_['last']['y'])
        if len(ys) < 4: continue
        if float(np.median(ys)) - y0 <= JUMP_APEX_CM and float(reach[lb == L].min()) <= JUMP_REACH_CM: good.add(L)
    islands = []
    if good:
        isl = np.isin(lb, list(good))
        from scipy.ndimage import binary_dilation
        isl_d = binary_dilation(isl, iterations=6)
        def into(w):
            p_ = w[0] + 30 * w[1]
            i, j = int(round((p_[1] - z0) / CELL)), int(round((p_[0] - x0) / CELL))
            return 0 <= i < H and 0 <= j < W and isl_d[i, j]
        walls = [w for w in walls if not into(w)]
        mask = cut(walls)
        lb = measure.label(mask, connectivity=2)
        keep = spawn_labels(lb)
        for L in range(1, lb.max() + 1):
            if (isl & (lb == L)).any(): keep.add(L)
        islands = [int(L) for L in good]
    mask = np.isin(lb, list(keep))
    # small solid holes inside the area (a fountain column, a planter's sides, step edges where the game nudges a
    # fighter off): the stage's own collision handles those; holes with void under them or >= 4 m2 stay holes
    void = [k for k, ss in by.items() if not any(settled(s) for s in ss)]
    holes = measure.label(~mask, connectivity=1)
    border = set(holes[0, :]) | set(holes[-1, :]) | set(holes[:, 0]) | set(holes[:, -1])
    vcell = {}
    for vx, vz in void:
        i, j = int(round((vz - z0) / CELL)), int(round((vx - x0) / CELL))
        if 0 <= i < H and 0 <= j < W: vcell[holes[i, j]] = True
    filled = 0
    for h in range(1, holes.max() + 1):
        if h in border or vcell.get(h): continue
        n = int((holes == h).sum())
        if n * CELL * CELL < 40000:
            mask[holes == h] = True; filled += 1
    # a start point outside the mask is a fighter's body, not the stage: Final Valgas never walks and the probe fighter
    # can't be put inside him, so his spot came out as a 4-5 m hole; the remaster's fighters push each other
    for sp in d['spawn']:
        i, j = int(round((sp[2] - z0) / CELL)), int(round((sp[0] - x0) / CELL))
        if not (0 <= i < H and 0 <= j < W) or mask[i, j]: continue
        dn = float(distance_transform_edt(~mask)[i, j]) * CELL
        rr = min(1.6 * dn, 400.0)
        ii, jj = np.ogrid[:H, :W]
        mask |= ((ii - i) ** 2 + (jj - j) ** 2) * CELL * CELL <= rr * rr
        filled += 1
    sdf = distance_transform_edt(mask) * CELL - distance_transform_edt(~mask) * CELL
    sdf = np.where(mask, sdf - CELL / 2, sdf + CELL / 2)   # zero between the last inside and first outside cell
    # floor levels per 50 cm cell from every settled sample's resting place
    lev = {}
    for s in S:
        if not settled(s): continue
        i, j = int(math.floor((s['last']['z'] - z0) / LCELL)), int(math.floor((s['last']['x'] - x0) / LCELL))
        lev.setdefault((i, j), []).append(s['last']['y'])
    levels = {}
    for (i, j), ys in lev.items():
        ys = sorted(ys); cl = []
        for y in ys:
            if cl and y - cl[-1][-1] < 15: cl[-1].append(y)
            else: cl.append([y])
        levels[f'{i},{j}'] = [round(float(np.median(c)), 1) for c in cl]
    # the floor heights the game settles a fighter on, per 25 cm cell (up to NLEV levels, ascending; -32768 = none):
    # every settled sample's resting place, clustered within 5 cm; inside cells without one take a neighbour's
    fx0 = math.floor(x0 / FCELL) * FCELL; fz0 = math.floor(z0 / FCELL) * FCELL
    FW = int((x1 - fx0) / FCELL) + 1; FH = int((z1 - fz0) / FCELL) + 1
    fl = {}
    for s in S:
        if not settled(s): continue
        i, j = int(round((s['last']['z'] - fz0) / FCELL)), int(round((s['last']['x'] - fx0) / FCELL))
        fl.setdefault((i, j), []).append(s['last']['y'])
    flo = np.full((FH, FW, NLEV), -32768, np.int16)
    for (i, j), ys in fl.items():
        if not (0 <= i < FH and 0 <= j < FW): continue
        ys = sorted(ys); cl = []
        for y in ys:
            if cl and y - cl[-1][-1] < 5: cl[-1].append(y)
            else: cl.append([y])
        v = [int(round(float(np.median(c)))) for c in cl][-NLEV:]
        flo[i, j, :len(v)] = v
    def in_area(i, j):
        mi, mj = int(round((fz0 + i * FCELL - z0) / CELL)), int(round((fx0 + j * FCELL - x0) / CELL))
        return 0 <= mi < H and 0 <= mj < W and sdf[mi, mj] > -15
    for it in range(3):
        empty = [(i, j) for i in range(FH) for j in range(FW) if flo[i, j, 0] == -32768 and in_area(i, j)]
        for i, j in empty:
            for di, dj in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                a, b = i + di, j + dj
                if 0 <= a < FH and 0 <= b < FW and flo[a, b, 0] != -32768 and (a, b) not in empty:
                    flo[i, j] = flo[a, b]; break
    floor = dict(x0=fx0, z0=fz0, cell=FCELL, w=FW, h=FH, n=NLEV, i16=base64.b64encode(flo.astype('<i2').tobytes()).decode(),
                 note='cell (i, j) is centred on x0 + j*cell, z0 + i*cell; n levels per cell, ascending, -32768 = none')
    # boundary contours (cm) of the inside mask at sdf 0
    cs = measure.find_contours(sdf, 0.0)
    contours = []
    for c in cs:
        pts = np.stack([x0 + c[:, 1] * CELL, z0 + c[:, 0] * CELL], 1)
        pts = measure.approximate_polygon(pts, tolerance=3.0)
        if len(pts) >= 2: contours.append([[round(float(a), 1), round(float(b), 1)] for a, b in pts])
    # every spot the original let the probe stand on (settled final positions, reference fighter's centre), 5 cm dedupe
    stand = {}
    for s in S:
        if not settled(s): continue
        f = np.array([s['last']['x'], s['last']['z']])
        if not stayed(s):
            p = np.array([s['p'][0], s['p'][2]]); n = p - f; L = np.linalg.norm(n)
            if L > 1e-6: f = f + rel[s['k']] * n / L
        mi, mj = int(round((f[1] - z0) / CELL)), int(round((f[0] - x0) / CELL))
        if not (0 <= mi < H and 0 <= mj < W and sdf[mi, mj] > -8): continue   # only spots in the area kept
        k = (int(round(f[0] / 5)), int(round(f[1] / 5)), int(round(s['last']['y'] / 5)))
        stand[k] = [round(float(f[0]), 1), round(float(f[1]), 1), round(s['last']['y'], 1)]
    allys = [y for v in levels.values() for y in v]
    raw = np.clip(np.round(sdf), -32768, 32767).astype('<i2').tobytes()
    out = dict(stage=stage, ref='falcon', note='where the reference fighter\'s centre (Falcon) can be in the original '
               '(Flycast probes: a fighter placed on a 50 cm lattice flood-filled from the round start points, refined to '
               '25 cm at every edge, settles or is pushed out by the game\'s own collision); sdf in cm, + inside',
               probes=dict(samples=len(S), placed_points=len(by), inside_points=len(ins_pts), edge_points=len(edge_in),
                           rounds=d.get('rounds'), refine=d.get('refine_n'), void_points=len(void), holes_filled=filled,
                           raised_floors_joined=len(islands)),
               radius_delta_cm={d['p2'] if d['p1'] == 'falcon' else d['p1']: round(d21 if d['p1'] == 'falcon' else -d21, 1)},
               radius_cal=[round(x, 1) for x in ds], spawn=d['spawn'],
               sdf=dict(x0=x0, z0=z0, cell=CELL, w=W, h=H, i16=base64.b64encode(raw).decode()),
               levels=dict(x0=x0, z0=z0, cell=LCELL, cells=levels), floor=floor, floor_min=min(allys), floor_max=max(allys),
               contours=contours, stand=sorted(stand.values()), step_up_cm=STEP_UP_CM, step_up_note='largest ledge measured stepped up while running (65 cm, Rouge stage); 91 cm and up stop a run (a 100 cm dojo ledge is hopped, state 17)', area_m2=round(float(mask.sum()) * CELL * CELL / 1e4, 2))
    old = FID + f'{stage}_area.json'
    if os.path.exists(old) and '--keep' in sys.argv:   # keep the patches / left-out surfaces across rebuilds
        prev = json.load(open(old))
        for k in ('patches', 'patch_note', 'no_collide_world', 'no_collide_parts', 'no_collide_note'):
            if k in prev: out[k] = prev[k]
    json.dump(out, open(old, 'w'), separators=(',', ':'))
    return out, mask, sdf, (x0, z0, W, H), P, lab


def picture(stage, out, mask, P, lab, extra=None):
    from PIL import Image, ImageDraw
    x0, z0 = out['sdf']['x0'], out['sdf']['z0']; W, H = out['sdf']['w'], out['sdf']['h']
    im = np.zeros((H, W, 3), np.uint8) + 255
    lv = out['levels']; fmin, fmax = out['floor_min'], out['floor_max']
    im[mask] = (150, 210, 150)
    for k, ys in lv['cells'].items():
        i, j = map(int, k.split(','))
        y = max(ys); t = (y - fmin) / max(1.0, fmax - fmin)
        col = (int(60 + 180 * t), int(170 - 60 * t), int(60 + 40 * (1 - t)))
        r0, c0 = int(i * LCELL / CELL), int(j * LCELL / CELL)
        sub = mask[r0:r0 + 5, c0:c0 + 5]
        blk = im[r0:r0 + 5, c0:c0 + 5]; blk[sub] = col
    img = Image.fromarray(im[::-1] if False else im)
    s = 800 / max(W, H)
    img = img.resize((max(1, int(W * s)), max(1, int(H * s))), Image.NEAREST)
    dr = ImageDraw.Draw(img)
    for c in out['contours']:
        dr.line([((a - x0) / CELL * s, (b - z0) / CELL * s) for a, b in c], fill=(200, 0, 0), width=2)
    for sp in out['spawn']:
        u, v = (sp[0] - x0) / CELL * s, (sp[2] - z0) / CELL * s
        dr.ellipse([u - 5, v - 5, u + 5, v + 5], fill=(255, 255, 0), outline=(0, 0, 0))
    if extra:
        for (a, b, col) in extra:
            u, v = (a - x0) / CELL * s, (b - z0) / CELL * s
            dr.rectangle([u - 1, v - 1, u + 1, v + 1], fill=col)
    img.save(OUT + f'{stage}_area.png')   # a picture for docs/fx-oom.md (z down)
    return img.size


def patch(stage, chk_path, mode):
    """From tests/area_check.gd: mode 'surf' = leave out the collision of disc surfaces / placed parts the remaster
    stands fighters on where the original's floor is clearly lower and never agrees (a water plane, an awning), mode
    'floor' = floor patches: every spot the original stands a fighter on where the remaster's collision has no floor
    within 12 cm (or only a lower one) -> one 50 cm box per spot, top at the original's floor."""
    path = FID + f'{stage}_area.json'
    out = json.load(open(path))
    c = json.load(open(chk_path))
    if mode == 'surf':
        w, pp = set(out.get('no_collide_world', [])), set(out.get('no_collide_parts', []))
        for k, (agree, high, low) in c['surf'].items():
            if high >= 10 and agree <= 0.1 * high:
                if k.startswith('part00:') or ':' in k: w.add(k)
                elif k.startswith('part') and k[4:].isdigit(): pp.add(int(k[4:]))
        # placed parts the original lets fighters stand inside: >= half their footprint (25 cm cells) has stand spots
        # under the part's top and the part blocks >= 10 of them in the remaster
        blk = {}
        for b in c['blocked']:
            if len(b) > 3 and str(b[3]).isdigit(): blk[int(b[3])] = blk.get(int(b[3]), 0) + 1
        for k, (cells, n) in c.get('parts_cover', {}).items():
            if cells > 0 and n / cells >= 0.5 and blk.get(int(k), 0) >= 10: pp.add(int(k))
        out['no_collide_world'] = sorted(w); out['no_collide_parts'] = sorted(pp)
        out['no_collide_note'] = ('remaster collision left out: disc surfaces (world GLB mesh:surface) / placed parts '
                                  'that are above the original\'s floor wherever a probe stood and agree < 10%, and placed '
                                  'parts the original lets a fighter stand inside (>= half the footprint)')
        json.dump(out, open(path, 'w'), separators=(',', ':'))
        return sorted(w), sorted(pp)
    old = out.get('patches', [])
    seen = {(round(p[0] / 25), round(p[1] / 25), round(p[2] / 5)) for p in old}
    new = list(old)
    st = np.array(out['stand'])
    for m in c['missing']:
        k = (round(m[0] / 25), round(m[1] / 25), round(m[2] / 5))
        if k in seen: continue
        # as big as fits: 50 cm, less where the original stands fighters at another height close by
        other = st[np.abs(st[:, 2] - m[2]) > 12]
        dmin = np.min(np.max(np.abs(other[:, :2] - np.array(m[:2])), 1)) if len(other) else 99.0
        if dmin < 50: continue   # an edge of a floor (the original's and the disc's edges differ by < 25 cm): left alone
        seen.add(k); new.append([m[0], m[1], m[2], 50.0])
    for h in c.get('holes', []):   # nothing at all under the original's floor: a gap in the disc mesh
        k = (round(h[0] / 25), round(h[1] / 25), round(h[2] / 5))
        if k in seen: continue
        seen.add(k); new.append([h[0], h[1], h[2], 27.0])
    out['patches'] = new
    out['patch_note'] = ('50 cm boxes (x, z, top y, size cm; only >= 50 cm from where the original stands fighters at another height) + 27 cm boxes over every 25 cm floor cell with nothing at all under it where the original stands a fighter and the disc mesh the '
                         'remaster collides with has no floor (tests/area_check.gd)')
    json.dump(out, open(path, 'w'), separators=(',', ':'))
    return len(old), len(new)


def radius():
    """game/assets/fidelity/fighter_radius.json: each fighter's stage-collision radius (player struct +0x258, read in
    every probe boot: P1 Falcon / Ryoma, P2 the stage owner) and how much further in than Falcon it stops (delta_cm),
    checked against the calibration pushes (the same wall pushes for the owner and for Falcon)."""
    import struct
    out = {'ref': 'falcon', 'radius_cm': {}, 'delta_cm': {}, 'calibration_cm': {}, 'calibration_samples': {}}
    for f in sorted(glob.glob(OUT + 'stg*_probe.json')):
        d = json.load(open(f))
        sb = f.replace('_probe.json', '_structs.bin')
        if os.path.exists(sb):
            b = open(sb, 'rb').read()
            for k, nm in ((1, d['p1']), (2, d['p2'])):
                out['radius_cm'][nm] = round(struct.unpack_from('<f', b, (k - 1) * 0x72D0 + 0x258)[0], 2)
        d21, ds = radius_delta(d)
        if ds:
            other = d['p2'] if d['p1'] == 'falcon' else d['p1']
            out['calibration_cm'][other] = round(d21 if d['p1'] == 'falcon' else -d21, 1)
            out['calibration_samples'][other] = [round(x, 1) for x in ds]
    rf = out['radius_cm'].get('falcon', 30.0)
    out['delta_cm'] = {k: round(v - rf, 2) for k, v in out['radius_cm'].items()}
    out['note'] = ('stage-collision radius per fighter (player struct +0x258, cm): the original stops a fighter\'s centre '
                   'this far from its walls; the area files are for Falcon\'s centre, so a fighter stops delta_cm further in '
                   '(negative = further out). calibration_cm = the same delta measured from wall pushes (both fighters put '
                   'at the same spots past a wall), the check that +0x258 is the radius the game uses')
    json.dump(out, open(FID + 'fighter_radius.json', 'w'), indent=1)
    return out


if __name__ == '__main__':
    os.makedirs(FID, exist_ok=True)
    cmd = sys.argv[1]
    if cmd == 'build':
        st = sys.argv[2]
        out, mask, sdf, g, P, lab = build(st)
        print(st, 'area m2', out['area_m2'], 'probes', out['probes'], 'delta', out['radius_delta_cm'], 'floors',
              out['floor_min'], out['floor_max'], 'contours', len(out['contours']), 'stand', len(out['stand']))
        if '--png' in sys.argv: picture(st, out, mask, P, lab)
    elif cmd == 'patch':
        print(sys.argv[2], sys.argv[4], patch(sys.argv[2], sys.argv[3], sys.argv[4]))
    elif cmd == 'radius':
        print(json.dumps(radius()['delta_cm']))
