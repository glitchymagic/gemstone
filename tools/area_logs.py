#!/usr/bin/env python3
"""The disc's own fights as area evidence (lane pstrailer2, wave 3): every place the original put a fighter in a logged
fight is a place the original lets a fighter be. The probe build (tools/stage_area.py) places fighters on a lattice and
lets them settle; spots it never stood a fighter on stay "outside" even when the game runs fighters across them (Londo's
240 cm raised floor: the disc's runner in o_ledge_londo stays at y 240 for 80 cm past the probe's edge, then drops to the
120 cm floor; the remaster's core held him at the probe edge, the BUG-41 "Falcon held 3,796 frames at Londo
(250, 250, 700)").
Sources: dumps/fidelity/cpu/cpu_*.jsonl (the disc's CPU-vs-CPU fights, P2's home stage) + dumps/fidelity/o_*.jsonl (the
tape logs, stage in .meta.json). Per stage:
  - inside: the 10 cm sdf cell under every logged centre (fight phases 2-5; not the thrown victim, state 29, whom the
    thrower's motion carries), for fighters at least as big as the reference (Falcon 30 cm; a smaller fighter's centre
    only counts where the area already is). Grounded centres (a standing state, y flat over 3 frames, not on a pole)
    widen the area itself; airborne ones only `sdf_air` (the remaster's area for a fighter off the ground: walls come
    from this area alone in the fighter core, so a launch's line over a fence must not open the fence for walkers).
    New cells are closed with a 20 cm disc (fills the strips between paths, the outer edge stays at the logged extremes),
    then the signed distance is rebuilt the way stage_area.py builds it;
  - floors: every grounded frame (vy 0, y unchanged since the last frame) adds its y to its 25 cm cell's levels (merged
    within 5 cm, up to 4 levels) and to the 50 cm level cells;
  - contours are rebuilt from the new sdf.
  area_logs.py [STAGE ...]     (default: every stage with an area file)  -> game/assets/fidelity/STAGE_area.json
  area_logs.py --dry STAGE     print what would change"""
import base64, glob, json, math, os, sys
import numpy as np
from scipy.ndimage import distance_transform_edt, binary_closing
from skimage import measure

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
FID = R + 'game/assets/fidelity/'
HOME = {'falcon': 'stg00', 'ryoma': 'stg10', 'wangtang': 'stg20', 'jack': 'stg30', 'gunrock': 'stg40', 'galuda': 'stg50',
        'ayame': 'stg60', 'rouge': 'stg70', 'kraken': 'stg80', 'valgas': 'stg90', 'finalvalgas': 'stga0'}
CLOSE_CM = 20
GROW_CM = 150   # rasters grown to every logged centre + this (cm)


def logs():
    """-> {stage: [(fighter, rows, side)]}"""
    out = {}
    for f in sorted(glob.glob(R + 'dumps/fidelity/cpu/cpu_*.jsonl')):
        mf = f[:-6] + '.meta.json'
        if not os.path.exists(mf): continue
        m = json.load(open(mf))
        out.setdefault(HOME[m['p2']], []).append((f, (m['p1'], m['p2'])))
    for f in sorted(glob.glob(R + 'dumps/fidelity/o_*.jsonl')):
        mf = f[:-6] + '.meta.json'
        if not os.path.exists(mf): continue
        m = json.load(open(mf))
        tp = R + 'game/tests/tapes/' + os.path.basename(f)[2:-6] + '.tape'
        if not os.path.exists(tp) or not m.get('stage'): continue
        hdr = open(tp).readline()
        kv = dict(w.split('=') for w in hdr[2:].split() if '=' in w) if hdr.startswith('#!') else {}
        out.setdefault(m['stage'], []).append((f, (kv.get('p1'), kv.get('p2', m.get('p2')))))
    return out


def log_extent(stage):
    """(xmin, xmax, zmin, zmax) cm of every logged centre on this stage (fight phases 2-5), None without logs."""
    xs, zs = [], []
    for fn, who in logs().get(stage, []):
        for l in open(fn):
            r = json.loads(l)
            if r.get('phase', 3) < 2: continue
            for p in r['p'][:2]:
                if abs(p['x']) < 1e5 and abs(p['z']) < 1e5: xs.append(p['x']); zs.append(p['z'])
    return (min(xs), max(xs), min(zs), max(zs)) if xs else None


# standing locomotion + attacks only: the reaction / lying / get-up / pose states put the position on the hip bone
# (REACT.md launch step 0), past the walls the centre respects (fx-cov BUG-49: Londo's splat 17.6 cm out with them)
GROUND_ST = {0, 2, 6, 10, 11, 31, 32, 35}
POLE_MOT = {150, 151, 152}
GROUND_SET = {0, 2, 6, 31, 32}   # the states that put a fighter's feet on a floor: idle, walk-start, landing, run, stop


def closed_near(base, add, C):
    """base | add, the new part closed with a CLOSE_CM disc, only within CLOSE_CM of the new cells."""
    rr = int(round(CLOSE_CM / C))
    ii, jj = np.ogrid[-rr:rr + 1, -rr:rr + 1]
    st = (ii * ii + jj * jj) <= rr * rr
    new = add & ~base
    if not new.any(): return base.copy()
    union = base | add
    closed = binary_closing(np.pad(union, rr + 1), structure=st)[rr + 1:-rr - 1, rr + 1:-rr - 1] | union
    near_new = distance_transform_edt(~new) * C <= CLOSE_CM
    return base | (closed & near_new)


def to_sdf(mask, C):
    # zero ON the last inside cell's centre (stage_area.py put it half a cell further out: fx-cov BUG-49, every wall
    # stop 4.6 cm past the disc's, e.g. atk_ground's splat at x 704.6 vs 700.0)
    sdf = distance_transform_edt(mask) * C - distance_transform_edt(~mask) * C
    sdf = np.where(mask, sdf - C, sdf)
    return base64.b64encode(np.clip(np.round(sdf), -32768, 32767).astype('<i2').tobytes()).decode(), sdf


def run(stage, dry=False):
    path = FID + f'{stage}_area.json'
    a = json.load(open(path))
    rad = json.load(open(FID + 'fighter_radius.json'))['radius_cm']
    g = a['sdf']; x0, z0, C, W, H = g['x0'], g['z0'], g['cell'], g['w'], g['h']
    base = a.get('sdf_probe', g['i16'])   # the probe build's own sdf: re-runs start from it, they don't compound
    probe0 = np.frombuffer(base64.b64decode(base), dtype='<i2').reshape(H, W)
    f = a['floor']; fx0, fz0, FC, FW, FH, NL = f['x0'], f['z0'], f['cell'], f['w'], f['h'], f['n']
    FL = np.frombuffer(base64.b64decode(a.get('floor_probe', f['i16'])), dtype='<i2').reshape(FH, FW, NL).copy()
    # the probe's rasters end 60 cm past its last placement; the disc's fighters go further on some stages (Rouge's
    # 1.2 / 1.85 m walkways to z 7.5 m, the raster ends at 2.6; the ship's decks; Galuda's west / north floors): grow
    # the rasters (same grid) to every logged centre + GROW_CM, the new cells outside / no floor until evidence says so
    ext = log_extent(stage)
    if ext is not None:
        ex0, ex1, ez0, ez1 = ext[0] - GROW_CM, ext[1] + GROW_CM, ext[2] - GROW_CM, ext[3] + GROW_CM
        X1, Z1 = x0 + (W - 1) * C, z0 + (H - 1) * C
        nx0 = x0 - max(0, math.ceil((x0 - ex0) / C)) * C; nz0 = z0 - max(0, math.ceil((z0 - ez0) / C)) * C
        nW = int(round((max(X1, x0 + math.ceil((ex1 - x0) / C) * C) - nx0) / C)) + 1
        nH = int(round((max(Z1, z0 + math.ceil((ez1 - z0) / C) * C) - nz0) / C)) + 1
        if (nx0, nz0, nW, nH) != (x0, z0, W, H):
            oj, oi = int(round((x0 - nx0) / C)), int(round((z0 - nz0) / C))
            big = np.full((nH, nW), -32768 // 2, dtype='<i2'); big[oi:oi + H, oj:oj + W] = probe0
            probe0, x0, z0, W, H = big, nx0, nz0, nW, nH
            g['x0'], g['z0'], g['w'], g['h'] = x0, z0, W, H
            a['sdf_probe'] = base64.b64encode(probe0.astype('<i2').tobytes()).decode()
        FX1, FZ1 = fx0 + (FW - 1) * FC, fz0 + (FH - 1) * FC
        nfx0 = fx0 - max(0, math.ceil((fx0 - ex0) / FC)) * FC; nfz0 = fz0 - max(0, math.ceil((fz0 - ez0) / FC)) * FC
        nFW = int(round((max(FX1, fx0 + math.ceil((ex1 - fx0) / FC) * FC) - nfx0) / FC)) + 1
        nFH = int(round((max(FZ1, fz0 + math.ceil((ez1 - fz0) / FC) * FC) - nfz0) / FC)) + 1
        if (nfx0, nfz0, nFW, nFH) != (fx0, fz0, FW, FH):
            oj, oi = int(round((fx0 - nfx0) / FC)), int(round((fz0 - nfz0) / FC))
            big = np.full((nFH, nFW, NL), -32768, dtype='<i2'); big[oi:oi + FH, oj:oj + FW] = FL
            FL, fx0, fz0, FW, FH = big, nfx0, nfz0, nFW, nFH
            f['x0'], f['z0'], f['w'], f['h'] = fx0, fz0, FW, FH
            a['floor_probe'] = base64.b64encode(FL.astype('<i2').tobytes()).decode()
    mask0 = probe0 > 0
    FL0 = FL.copy()
    lv = a['levels']; lx0, lz0, LC = lv['x0'], lv['z0'], lv['cell']
    cells = {k: list(v) for k, v in a.get('levels_probe', lv['cells']).items()}
    gadd = np.zeros_like(mask0); aadd = np.zeros_like(mask0)
    n_g = n_a = n_floor = n_rows = n_iso = n_lifted = n_under = 0
    ev = []   # standing evidence: (sdf i, j, floor fi, fj, y cm, levels key)
    for fn, who in logs().get(stage, []):
        rows = [json.loads(l) for l in open(fn)]
        n_rows += len(rows)
        for k in range(2):
            ch = who[k]
            small = ch is None or rad.get(ch, 30.0) < rad.get('falcon', 30.0)
            settle = 0
            on_ground = False
            for t in range(1, len(rows) - 1):
                r = rows[t]
                if r.get('phase', 3) < 2: on_ground = False; continue
                p = r['p'][k]
                q0 = rows[t - 1]['p'][k]
                if math.hypot(p['x'] - q0['x'], p['z'] - q0['z']) > 40: settle = 5   # a teleport (tape @place, round
                if settle > 0: settle -= 1; on_ground = False; continue            # reset): the game settles it first
                q, nx = rows[t - 1]['p'][k], rows[t + 1]['p'][k]
                flat = abs(p['vy']) < 1e-3 and abs(p['y'] - q['y']) < 1e-3 and abs(nx['y'] - p['y']) < 1e-3
                # on the ground = a ground state reached with the feet flat (idle, walk-start, run, stop, landing);
                # attacks (10 / 11) and the rest of GROUND_ST only count while that holds. An air attack's hit-stop
                # holds the attacker still in mid-air (vy 0, y flat for 8 frames in state 10): that is no floor
                # (lead 10-27: stg10 (-60, -330) got a 287 cm level from Ryoma's air punch k1/10, the remaster's
                # fighters then landed and stood on it; the disc falls through to 0)
                if not flat or p['st'] not in GROUND_ST or (p['kind'] == 1 and p['mot'] in POLE_MOT): on_ground = False
                elif p['st'] in GROUND_SET: on_ground = True
                if p['st'] == 29: continue   # the thrown victim: the thrower's motion carries him
                i, j = int(round((p['z'] - z0) / C)), int(round((p['x'] - x0) / C))
                if not (0 <= i < H and 0 <= j < W) or (small and not mask0[i, j]): continue
                grounded = on_ground and flat and p['st'] in GROUND_ST
                if not grounded:
                    if flat and p['st'] in GROUND_ST and not (p['kind'] == 1 and p['mot'] in POLE_MOT): n_lifted += 1
                    # air evidence only from falls off an edge (a run-off, state 31 / 14, moving down): launches and
                    # jumps cross over walls at height, and a 2D area can't tell (fx-cov: jumpers next to walls drifted
                    # into launch lines, fell under the floor and snapped back)
                    if p['st'] in (31, 14) and p['vy'] <= 0: n_a += 1; aadd[i, j] = True
                    continue
                y = int(round(p['y']))
                fi, fj = int(round((p['z'] - fz0) / FC)), int(round((p['x'] - fx0) / FC))
                key = f'{int(math.floor((p["z"] - lz0) / LC))},{int(math.floor((p["x"] - lx0) / LC))}'
                ev.append((i, j, fi, fj, y, key))
    # a level no neighbouring 25 cm cell has (within 15 cm, probe or logs) is no floor: a body is 55-120 cm across,
    # every real floor spans cells (a one-cell level = a fighter held in the air)
    lv_at = {}
    for e in ev:
        lv_at.setdefault((e[2], e[3]), set()).add(e[4])
    def has_level(ii, jj, y):
        if any(abs(y - x) <= 15 for x in lv_at.get((ii, jj), ())): return True
        if 0 <= ii < FH and 0 <= jj < FW: return any(x != -32768 and abs(y - int(x)) <= 15 for x in FL[ii, jj])
        return False
    for (i, j, fi, fj, y, key) in ev:
        if not any(has_level(fi + di, fj + dj, y) for di in (-1, 0, 1) for dj in (-1, 0, 1) if (di, dj) != (0, 0)):
            n_iso += 1; continue
        n_g += 1; gadd[i, j] = True
        if 0 <= fi < FH and 0 <= fj < FW:
            # under the probe's floor at this lattice point: the probe placed a fighter on the cell's centre 30 cm over
            # the start floor (and dropped one from 7 m where that failed) and the game settled it on the probe's
            # lowest level there, so nothing lower is under the centre: the logged centre was off-centre, at the foot
            # of a block's face (Ayame's 120 cm blocks: runners at 0 / -33 along the face put those levels into
            # cells the probe lifts onto 120, and the remaster's fighters then stood 1.2 m inside the block)
            pv = [int(x) for x in FL0[fi, fj] if x != -32768]
            if pv and y < min(pv) - 15:
                n_under += 1
                continue
            v = [int(x) for x in FL[fi, fj] if x != -32768]
            if not any(abs(y - x) <= 5 for x in v) and len(v) < NL:
                v = sorted(v + [y]); FL[fi, fj, :] = -32768; FL[fi, fj, :len(v)] = v; n_floor += 1
        c = cells.setdefault(key, [])
        if not any(abs(y - x) <= 15 for x in c): c.append(float(y)); c.sort()
    mask = closed_near(mask0, gadd, C)            # standing evidence: where a fighter's centre can be on the ground
    # 25 cm floor cells the closing put inside the area without a logged floor of their own (the strip between two
    # logged paths): the levels of their logged neighbours (8-neighbourhood, two passes), never into the probe's area
    n_fill = 0
    for _pass in range(2):
        newf = {}
        for fi in range(FH):
            for fj in range(FW):
                if (FL[fi, fj] != -32768).any(): continue
                mi, mj = int(round((fz0 + fi * FC - z0) / C)), int(round((fx0 + fj * FC - x0) / C))
                if not (0 <= mi < H and 0 <= mj < W) or not mask[mi, mj] or mask0[mi, mj]: continue
                v = set()
                for di in (-1, 0, 1):
                    for dj in (-1, 0, 1):
                        ii, jj = fi + di, fj + dj
                        if 0 <= ii < FH and 0 <= jj < FW and (FL[ii, jj] != FL0[ii, jj]).any():
                            v |= {int(x) for x in FL[ii, jj] if x != -32768}
                if v:
                    m = []
                    for y in sorted(v):
                        if not m or y - m[-1] > 5: m.append(y)
                    newf[(fi, fj)] = m[:NL]
        for (fi, fj), m in newf.items():
            FL[fi, fj, :] = -32768; FL[fi, fj, :len(m)] = m; n_fill += 1
    air = closed_near(mask, aadd, C)              # flight evidence: only for fighters off the ground (arena.sdf_air_at)
    gg, ga = int((mask & ~mask0).sum()), int((air & ~mask).sum())
    print(f'{stage}: {n_rows} log rows, {n_g} grounded / {n_a} airborne centres, +{gg * C * C / 1e4:.2f} m2 ground '
          f'(on {mask0.sum() * C * C / 1e4:.2f}), +{ga * C * C / 1e4:.2f} m2 air only, {n_floor} floor levels added, '
          f'{n_fill} cells filled from neighbours, raster {W}x{H} at ({x0}, {z0}); not standing: {n_lifted} flat rows off '
          f'the ground (air attacks\' hit-stop), {n_iso} one-cell levels, {n_under} under the probe\'s floor')
    if '--png' in sys.argv:
        from PIL import Image
        im = np.zeros((H, W, 3), np.uint8); im[mask0] = (90, 90, 90); im[mask & ~mask0] = (255, 60, 0)
        im[air & ~mask] = (0, 200, 255)
        Image.fromarray(im[::-1]).save(os.environ.get('TMPDIR', '/tmp/') + f'area_logs_{stage}.png')
    if dry: return
    a.setdefault('sdf_probe', base); a.setdefault('floor_probe', base64.b64encode(FL0.astype('<i2').tobytes()).decode())
    a.setdefault('levels_probe', lv['cells'])
    a['sdf']['i16'], sdf = to_sdf(mask, C)
    a['sdf_air'] = to_sdf(air, C)[0] if ga else a['sdf']['i16']
    a['floor']['i16'] = base64.b64encode(FL.astype('<i2').tobytes()).decode()
    a['levels']['cells'] = cells
    cs = measure.find_contours(sdf, 0.0)
    contours = []
    for c in cs:
        pts = np.stack([x0 + c[:, 1] * C, z0 + c[:, 0] * C], 1)
        pts = measure.approximate_polygon(pts, tolerance=3.0)
        if len(pts) >= 2: contours.append([[round(float(u), 1), round(float(v), 1)] for u, v in pts])
    a['contours'] = contours
    ys = [y for v in cells.values() for y in v]
    a['floor_min'], a['floor_max'] = min(ys), max(ys)
    a['area_m2'] = round(float(mask.sum()) * C * C / 1e4, 2)
    a['logs'] = dict(rows=n_rows, grounded=n_g, airborne=n_a, flat_off_ground=n_lifted, one_cell_levels=n_iso, under_probe_floor=n_under, ground_m2_gained=round(gg * C * C / 1e4, 2),
                     air_only_m2=round(ga * C * C / 1e4, 2), floor_levels_added=n_floor, close_cm=CLOSE_CM,
                     note="tools/area_logs.py: the disc's CPU fights + tape logs as inside / floor evidence; sdf_probe / "
                          "floor_probe / levels_probe = the probe build's own (re-runs start from them); sdf_air = sdf "
                          "plus the cells fighters crossed in the air (falls off ledges, launches)")
    json.dump(a, open(path, 'w'), separators=(',', ':'))


if __name__ == '__main__':
    dry = '--dry' in sys.argv
    sts = [s for s in sys.argv[1:] if not s.startswith('--')] or sorted(
        os.path.basename(p)[:5] for p in glob.glob(FID + 'stg*_area.json'))
    for s in sts: run(s, dry)
