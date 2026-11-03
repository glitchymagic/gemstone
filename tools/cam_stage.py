#!/usr/bin/env python3
"""The original's fight camera on one stage, measured from a tools/stagelog.py log (camera object + both fighters every
frame, CPU vs CPU) -> game/assets/fidelity/STG_cam.json (TRACKED; scripts/fight_cam.gd reads it), and how well that
model reproduces the original's own camera when it is fed the original's fighter positions (the fidelity number).

The rule, read off the logs of all 11 stages (2026-10-26, docs/fx-cam.md):
  target T     = midpoint of the fighters' FEET (+0x020) + 100 cm up (exact: median |error| 0.0 cm)
  smoothed S   = S.xz += (T.xz - S.xz) / 8 per frame; S.y += trunc((T.y - S.y) / 8) (integer steps: S.y rests up to
                 7 cm off T.y). The camera looks at S.
  yaw          = one of three presets 20 deg apart per stage (Londo -155/-135/-115), picked by where S is on the stage
                 (zone grid below), eased 10% of the gap per frame (BAMS integer, ends 0.05 deg short)
  distance     = horizontal eye-to-S distance hd follows R = max(dmin, a + sqrt((b*lat)^2 + (c*dep)^2 + (e*dy)^2))
                 (lat / dep = the fighters' feet separation across / along the view, dy = their height difference):
                 up at k_out of the gap per frame when R > hd, down at k_in when R < hd - band (dead band)
  eye height   = desired eye y H = min(cap 500 cm, S.y + h_k * hd) (camera object +0x448), eye y eased 5%/frame to H
  The eye-height cap is an ABSOLUTE world height on every stage (Kraken's upper deck: the eye sits 170 cm over S).
  stage area   = 50 cm cells where the original's fighters stood (feet), for audits that skip frames a remaster
                 fighter spends outside the original's playable area (an out-of-map bug, not a camera one).

  cam_stage.py STG             fit + write (logs dumps/cap/cl<NN>.bin + cm<NN>.bin)
  cam_stage.py all             every stage with a log
  cam_stage.py boss stga0 cfa0 Final Valgas's arena: the original's other camera (aim = the boss)
  cam_stage.py fit-dist        refit the distance law on every log at once (prints the parameters)"""
import json, os, re, sys
import numpy as np

R = './'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'game', 'assets', 'fidelity')
FS = 188
CELL = 100          # zone grid cell (cm)
ACELL = 50          # area grid cell (cm)
# distance law, fitted on Kraken's Ship + Dawnvolta + Valgas's lair (37,074 fight frames, simulate-and-compare, mean
# |error| 27.7 cm): a, b, c, dmin, k_out, k_in, band, e
DIST = dict(a=353.1, b=0.927, c=1.132, e=1.069, dmin=593.1, k_out=0.103, k_in=0.117, band=0.89)
H_K = 0.279
EYE_CAP = 500.0
EYE_EASE = 0.05
YAW_EASE = 0.10
S_EASE = 0.125


def load(path):
    raw = open(path, 'rb').read(); n = len(raw) // FS
    a = np.frombuffer(raw[:n * FS], np.uint8).reshape(n, FS)
    f = lambda o, k=3: np.frombuffer(a[:, o:o + 4 * k].tobytes(), '<f4').reshape(n, k).astype(np.float64)
    d = dict(E=f(48), T=f(60), S=f(72), H1=f(84), H2=f(96), F1=f(116), F2=f(128), X448=f(172, 4)[:, 2])
    d['s1'] = a[:, 110].astype(int); d['s2'] = a[:, 114].astype(int); d['n'] = n
    return d


def fight_mask(d):
    """Real fight frames: before the match end (the first state-21 run longer than 10 s: the logs keep running into
    the game's next screen), neither fighter in the round intro / round end / Power Change (21, 22, 23)."""
    s1, s2 = d['s1'], d['s2']
    end = d['n']
    r = np.where(s1 == 21)[0]
    if len(r):
        br = np.where(np.diff(r) > 1)[0]
        for a, b in zip(np.r_[r[0], r[br + 1]], np.r_[r[br], r[-1]]):
            if b - a > 600: end = a; break
    m = np.zeros(d['n'], bool); m[:end] = True
    m &= ~np.isin(s1, [21, 22, 23]) & ~np.isin(s2, [21, 22, 23]) & (np.abs(d['E']).sum(1) > 0)
    return m


def blocks(m, minlen=120):
    idx = np.where(m)[0]
    if not len(idx): return []
    br = np.where(np.diff(idx) > 1)[0]
    return [(a, b + 1) for a, b in zip(np.r_[idx[0], idx[br + 1]], np.r_[idx[br], idx[-1]]) if b + 1 - a >= minlen]


def yaw_of(E, S):
    return np.degrees(np.arctan2((E - S)[:, 0], (E - S)[:, 2]))


def wrap(a): return (a + 180) % 360 - 180


def presets(yaw, m):
    dy = np.abs(wrap(np.r_[0, np.diff(yaw)]))
    rest = (np.convolve((dy < 0.01) & m, np.ones(20), 'same') >= 20)
    v = np.round(yaw[rest] / 5) * 5
    u, c = np.unique(v, return_counts=True)
    top = sorted(u[np.argsort(-c)[:3]].tolist())
    return top, rest


def zone_grid(P, lab, ok, cell=CELL, pure=0.0):
    """Most-seen preset per cell of P.xz (frames with a label), unseen cells = the nearest seen one; cells where no
    preset has a PURE share = -1 (keep the current preset: the original's switch lines have hysteresis)."""
    m = ok & (lab >= 0)
    xs = np.floor(P[m, 0] / cell).astype(int); zs = np.floor(P[m, 2] / cell).astype(int)
    x0, x1, z0, z1 = xs.min() - 1, xs.max() + 1, zs.min() - 1, zs.max() + 1
    cnt = np.zeros((z1 - z0 + 1, x1 - x0 + 1, 3))
    np.add.at(cnt, (zs - z0, xs - x0, lab[m]), 1)
    seen = cnt.sum(2) > 0
    grid = np.argmax(cnt, 2)
    share = cnt.max(2) / np.maximum(cnt.sum(2), 1)
    sy, sx = np.nonzero(seen)
    for r in range(grid.shape[0]):
        for c in range(grid.shape[1]):
            if not seen[r, c]:
                k = np.argmin((sy - r) ** 2 + (sx - c) ** 2); grid[r, c] = grid[sy[k], sx[k]]
    if pure > 0: grid[seen & (share < pure)] = -1
    return dict(x0_cm=int(x0 * cell), z0_cm=int(z0 * cell), cell_cm=cell, cols=int(grid.shape[1]),
                rows=int(grid.shape[0]), grid=grid.tolist())


def zone_at(z, x, y):
    c = int(np.clip(np.floor((x - z['x0_cm']) / z['cell_cm']), 0, z['cols'] - 1))
    r = int(np.clip(np.floor((y - z['z0_cm']) / z['cell_cm']), 0, z['rows'] - 1))
    return z['grid'][r][c]


def sim(d, a, b, cam, hold=0):
    """The model, fed the original's fighter feet, from the original's camera state at frame a. Returns yaw, hd, eye y,
    S per frame."""
    F1, F2 = d['F1'][a:b], d['F2'][a:b]
    E0, S0 = d['E'][a], d['S'][a].copy()
    pres = cam['yaws_deg']; Z = cam['zones']; D = cam['dist']
    S = S0.copy(); yaw = float(np.degrees(np.arctan2(E0[0] - S0[0], E0[2] - S0[2])))
    hd = float(np.hypot(E0[0] - S0[0], E0[2] - S0[2])); ey = float(E0[1])
    want = None; cand = None; held = 0
    out = np.zeros((b - a, 6))
    for i in range(b - a):
        T = (F1[i] + F2[i]) * 0.5 + [0, 100, 0]
        if i > 0:
            S[0] += (T[0] - S[0]) * S_EASE; S[2] += (T[2] - S[2]) * S_EASE
            S[1] += np.trunc((T[1] - S[1]) * S_EASE)
            zp = T if str(Z.get('of', 'S')).startswith(('T', 'target T')) else S
            zi = zone_at(Z, zp[0], zp[2])
            if want is None: want = zi if zi >= 0 else int(np.argmin(np.abs(wrap(np.array(pres) - yaw))))
            if zi < 0: zi = want
            if zi != want:
                held = held + 1 if zi == cand else 1; cand = zi
                if held > hold: want = zi; held = 0
            else: held = 0
            yaw += wrap(pres[want] - yaw) * YAW_EASE
            br = np.radians(yaw); bk = np.array([np.sin(br), np.cos(br)]); rt = np.array([bk[1], -bk[0]])
            dv = (F1[i] - F2[i])[[0, 2]]
            lat, dep, dy = abs(dv @ rt), abs(dv @ bk), abs(F1[i, 1] - F2[i, 1])
            Rq = max(D['dmin'], D['a'] + np.sqrt((D['b'] * lat) ** 2 + (D['c'] * dep) ** 2 + (D['e'] * dy) ** 2))
            if Rq > hd: hd += D['k_out'] * (Rq - hd)
            elif Rq < hd - D['band']: hd += D['k_in'] * (Rq + D['band'] - hd)
            H = min(cam['eye_cap_cm'], S[1] + cam['eye_k'] * hd)
            ey += (H - ey) * EYE_EASE
        out[i] = (yaw, hd, ey, S[0], S[1], S[2])
    return out


def fidelity(d, ok, cam):
    """Median |error| of the model vs the original's camera on every fight block: yaw (deg), horizontal distance (cm),
    eye height over the target (cm), aim point (cm)."""
    E, S = d['E'], d['S']
    ey_, eh, ed, ea, n = [], [], [], [], 0
    for a, b in blocks(ok):
        o = sim(d, a, b, cam, cam.get('hold', 0))
        yw = yaw_of(E[a:b], S[a:b]); hd = np.hypot(*(E[a:b] - S[a:b])[:, [0, 2]].T)
        ey_.append(np.abs(wrap(o[:, 0] - yw))); ed.append(np.abs(o[:, 1] - hd))
        eh.append(np.abs((o[:, 2] - o[:, 4]) - (E[a:b, 1] - S[a:b, 1]))); ea.append(np.linalg.norm(o[:, 3:6] - S[a:b], axis=1))
        n += b - a
    c = lambda x: np.concatenate(x)
    yw, dd, hh, aa = c(ey_), c(ed), c(eh), c(ea)
    return dict(frames=int(n), yaw_med_deg=round(float(np.median(yw)), 2), yaw_within_2deg=round(float((yw < 2).mean()), 3),
                dist_med_cm=round(float(np.median(dd)), 1), dist_p90_cm=round(float(np.percentile(dd, 90)), 1),
                height_med_cm=round(float(np.median(hh)), 1), aim_med_cm=round(float(np.median(aa)), 1))


def load_all(stg):
    """Every log of the stage (cl<NN> = 2 rounds, cm<NN> = 10 min with the round timer held), concatenated; a log
    boundary is never inside a fight block. Returns (data, fight mask, per-frame log index)."""
    tags = [t for t in ('cl' + stg[3:], 'cm' + stg[3:]) if os.path.exists(R + f'dumps/cap/{t}.bin')]
    ds = [load(R + f'dumps/cap/{t}.bin') for t in tags]
    oks = [fight_mask(d) for d in ds]
    for o in oks: o[0] = False
    d = {k: np.concatenate([x[k] for x in ds]) for k in ds[0] if k != 'n'}
    d['n'] = sum(x['n'] for x in ds)
    src = np.concatenate([np.full(x['n'], i) for i, x in enumerate(ds)])
    return d, np.concatenate(oks), src, tags


def fit(stg):
    d, ok, src, tags = load_all(stg)
    E, S, T, F1, F2 = d['E'], d['S'], d['T'], d['F1'], d['F2']
    tgt_err = np.linalg.norm(T - ((F1 + F2) * 0.5 + [0, 100, 0]), axis=1)[ok]
    yaw = yaw_of(E, S)
    pres, rest = presets(yaw, ok)
    lab = np.full(d['n'], -1)
    for i, p in enumerate(pres): lab[(np.abs(wrap(yaw - p)) < 0.1) & rest] = i
    hd = np.hypot(*(E - S)[:, [0, 2]].T)
    H = d['X448']
    mh = ok & (H < EYE_CAP - 1) & (hd > 100)
    hk = float(np.median((H[mh] - S[mh, 1]) / hd[mh]))
    hit = float((np.abs(np.minimum(EYE_CAP, S[:, 1] + hk * hd) - H)[ok] < 1).mean())
    cam = dict(yaws_deg=pres, dist=DIST, eye_k=round(hk, 4), eye_cap_cm=EYE_CAP, eye_ease=EYE_EASE,
               yaw_ease=YAW_EASE, target_up_cm=100.0, target_ease=S_EASE)
    # zone settings chosen held-out: grid from one log, scored on the other (one log: first / second half)
    if len(tags) > 1: parts = [src == 0, src == 1]
    else:
        bl = blocks(ok); half = np.zeros(d['n'], bool); half[:bl[0][0] + (bl[-1][1] - bl[0][0]) // 2] = True
        parts = [half, ~half]
    best = None
    for P, nm in ((S, 'S'), (T, 'T')):
        for cell in (100, 200):
            for hold in (0, 6, 15):
                for pure in (0.0, 0.7, 0.85):
                    fds = [fidelity(d, ok & parts[1 - k], dict(cam, zones=dict(zone_grid(P, lab, ok & parts[k], cell, pure), of=nm), hold=hold))
                           for k in (0, 1)]
                    w = [f['frames'] for f in fds]
                    yw = sum(f['yaw_within_2deg'] * n for f, n in zip(fds, w)) / sum(w)
                    ym = sum(f['yaw_med_deg'] * n for f, n in zip(fds, w)) / sum(w)
                    sc = ym + (1 - yw) * 5
                    if best is None or sc < best[0]: best = (sc, nm, cell, hold, pure, dict(yaw_within_2deg=round(yw, 3), yaw_med_deg=round(ym, 2)))
    _, nm, cell, hold, pure, held = best
    z = zone_grid(S if nm == 'S' else T, lab, ok, cell, pure)
    fd = fidelity(d, ok, dict(cam, zones=dict(z, of=nm), hold=hold))
    fd['zones_held_out'] = held
    cam['zones'] = dict(z, of='smoothed target S (the point the camera looks at)' if nm == 'S' else 'target T',
                        hold_frames=hold, keep_share=pure)
    # the original's playable area: where its fighters' feet were
    P = np.r_[F1[ok], F2[ok]]
    xs = np.floor(P[:, 0] / ACELL).astype(int); zs = np.floor(P[:, 2] / ACELL).astype(int)
    ax0, az0 = xs.min(), zs.min()
    occ = np.zeros((zs.max() - az0 + 1, xs.max() - ax0 + 1), np.uint8)
    occ[zs - az0, xs - ax0] = 1
    grounded = np.r_[np.isin(d['s1'][ok], [0, 2, 31, 32]), np.isin(d['s2'][ok], [0, 2, 31, 32])]
    fy, fc = np.unique(np.round(P[grounded, 1]), return_counts=True)
    cam['area'] = dict(x0_cm=int(ax0 * ACELL), z0_cm=int(az0 * ACELL), cell_cm=ACELL, cols=int(occ.shape[1]),
                       rows=int(occ.shape[0]), rows_bits=[''.join('1' if v else '0' for v in row) for row in occ],
                       feet_y_cm=[float(np.min(P[:, 1])), float(np.max(P[:, 1]))],
                       grounded_floor_y_cm=[float(v) for v in fy[np.argsort(-fc)][:8]])
    cam['measured'] = dict(logs=[f'dumps/cap/{t}.bin' for t in tags], tool='tools/stagelog.py (CPU vs CPU, healths held) + tools/cam_stage.py',
                           frames=int(d['n']), fight_frames=int(ok.sum()),
                           target_err_med_cm=round(float(np.median(tgt_err)), 2),
                           target_err_p90_cm=round(float(np.percentile(tgt_err, 90)), 2),
                           yaw_share={str(p): round(float((lab == i).sum() / max((lab >= 0).sum(), 1)), 3) for i, p in enumerate(pres)},
                           eye_rule_hit_1cm=round(hit, 3), eye_max_cm=round(float(E[ok, 1].max()), 1),
                           model_vs_original=fd)
    os.makedirs(OUT, exist_ok=True)
    txt = json.dumps(cam, indent=1)
    txt = re.sub(r'\[\s*([-\d.,\s]+?)\s*\]', lambda m: '[' + re.sub(r'\s+', '', m.group(1)).replace(',', ', ') + ']', txt)
    open(os.path.join(OUT, f'{stg}_cam.json'), 'w').write(txt + '\n')
    print(f'{stg}: logs {tags} presets {pres} zones {nm} {cell} cm hold {hold} keep<{pure}, eye_k {hk:.4f} (rule hit '
          f'{hit:.2f}), target err {np.median(tgt_err):.1f} cm, model vs original {fd}', flush=True)
    return cam


def sim_boss(d, a, b, cam):
    """Final Valgas's arena (the original's other camera): aim = the boss's feet + 2 m, eased; the eye on the far side of
    the player along the boss -> player line, distance a + b x their separation, eye height from the player's feet height
    over the boss's (the boss always stands at y 0 in the original: the same numbers, but a remaster fighter below the
    original's floor can't drag the eye under it). Player = P1, boss = P2 (the arcade's last fight)."""
    F1, F2 = d['F1'][a:b], d['F2'][a:b]
    E0, S0 = d['E'][a], d['S'][a]
    B = cam['boss']
    S = S0.copy(); yaw = float(np.degrees(np.arctan2(E0[0] - S0[0], E0[2] - S0[2])))
    hd = float(np.hypot(E0[0] - S0[0], E0[2] - S0[2])); ey = float(E0[1])
    out = np.zeros((b - a, 6))
    for i in range(b - a):
        if i > 0:
            T = np.array([F2[i, 0], F2[i, 1] + B['aim_y_cm'], F2[i, 2]])   # the boss stands at y 0 in the original
            S += (T - S) * B['aim_ease']
            dv = F1[i] - F2[i]
            yaw += wrap(float(np.degrees(np.arctan2(dv[0], dv[2]))) - yaw) * B['yaw_ease']
            hd += (B['dist_a'] + B['dist_b'] * float(np.hypot(dv[0], dv[2])) - hd) * B['dist_ease']
            ey += (F2[i, 1] + B['eye_a'] + B['eye_b'] * (F1[i, 1] - F2[i, 1]) - ey) * B['eye_ease']
        out[i] = (yaw, hd, ey, S[0], S[1], S[2])
    return out


def fit_boss(stg, tag):
    from scipy.optimize import minimize
    d = load(R + f'dumps/cap/{tag}.bin'); ok = fight_mask(d)
    E, S, T, F1, F2 = d['E'], d['S'], d['T'], d['F1'], d['F2']
    bl = blocks(ok)
    yw = yaw_of(E, S); hd = np.hypot(*(E - S)[:, [0, 2]].T)
    base = dict(aim_y_cm=200.0, aim_ease=0.1, eye_ease=0.1, eye_a=238.0, eye_b=2.53, yaw_ease=0.056, dist_a=735.0,
                dist_b=1.126, dist_ease=0.03)

    def score(B, part=None):
        ey, ed, eh = [], [], []
        for a, b in bl:
            o = sim_boss(d, a, b, dict(boss=B))
            ey.append(np.abs(wrap(o[:, 0] - yw[a:b]))); ed.append(np.abs(o[:, 1] - hd[a:b]))
            eh.append(np.abs(o[:, 2] - E[a:b, 1]))
        return [np.concatenate(x) for x in (ey, ed, eh)]
    # the two rates the logs don't pin down directly (yaw, distance) by simulate-and-compare
    def cost(p):
        if not (0 < p[0] < 1 and 0 < p[1] < 1): return 1e9
        e = score(dict(base, yaw_ease=p[0], dist_ease=p[1]))
        return np.median(e[0]) * 20 + np.median(e[1])
    r = minimize(cost, [base['yaw_ease'], base['dist_ease']], method='Nelder-Mead', options=dict(maxiter=60))
    B = dict(base, yaw_ease=round(float(r.x[0]), 4), dist_ease=round(float(r.x[1]), 4))
    e = score(B)
    tgt = np.c_[F2[:, 0], F2[:, 1] + 200.0, F2[:, 2]]
    fd = dict(frames=int(ok.sum()), yaw_med_deg=round(float(np.median(e[0])), 2), yaw_within_2deg=round(float((e[0] < 2).mean()), 3),
              dist_med_cm=round(float(np.median(e[1])), 1), dist_p90_cm=round(float(np.percentile(e[1], 90)), 1),
              height_med_cm=round(float(np.median(e[2])), 1))
    cam = dict(mode='boss', boss=B, note='Final Valgas arena: the original uses another camera here (aim = the boss, '
               'eye behind the player on the boss -> player line). Player = the non-boss fighter.',
               measured=dict(logs=[f'dumps/cap/{tag}.bin'], tool='tools/stagelog.py (boot_boss) + tools/cam_stage.py fit_boss',
                             fight_frames=int(ok.sum()), aim_err_med_cm=round(float(np.median(np.linalg.norm((T - tgt)[ok], axis=1))), 2),
                             model_vs_original=fd))
    open(os.path.join(OUT, f'{stg}_cam.json'), 'w').write(json.dumps(cam, indent=1) + '\n')
    print(stg, 'boss camera', B, fd, flush=True)


def fit_dist():
    from scipy.optimize import minimize
    segs = []
    for f in sorted(os.listdir(R + 'dumps/cap')):
        if not (f[:2] in ('cl', 'cm') and f.endswith('.bin') and len(f) == 8): continue
        d = load(R + 'dumps/cap/' + f); ok = fight_mask(d)
        E, S, F1, F2 = d['E'], d['S'], d['F1'], d['F2']
        hd = np.hypot(*(E - S)[:, [0, 2]].T)
        bk = (E - S)[:, [0, 2]] / np.maximum(hd, 1)[:, None]; rt = np.c_[bk[:, 1], -bk[:, 0]]
        dv = (F1 - F2)[:, [0, 2]]
        lat = np.abs((dv * rt).sum(1)); dep = np.abs((dv * bk).sum(1)); dy = np.abs(F1[:, 1] - F2[:, 1])
        for a, b in blocks(ok): segs.append((lat[a:b], dep[a:b], dy[a:b], hd[a:b]))
    print('frames', sum(len(s[3]) for s in segs))

    def run(p, s):
        a, b, c, dmin, ko, ki, band, e = p
        lat, dep, dy, hd = s
        Rq = np.maximum(dmin, a + np.sqrt((b * lat) ** 2 + (c * dep) ** 2 + (e * dy) ** 2))
        h = hd[0]; o = np.empty(len(hd))
        for i in range(len(hd)):
            o[i] = h
            if Rq[i] > h: h += ko * (Rq[i] - h)
            elif Rq[i] < h - band: h += ki * (Rq[i] + band - h)
        return o

    def cost(p):
        if not (0 < p[4] <= 1 and 0 < p[5] <= 1 and p[6] >= 0): return 1e9
        return np.mean(np.concatenate([np.abs(run(p, s) - s[3]) for s in segs]))
    p0 = [DIST[k] for k in ('a', 'b', 'c', 'dmin', 'k_out', 'k_in', 'band', 'e')]
    r = minimize(cost, p0, method='Nelder-Mead', options=dict(maxiter=3000))
    e = np.concatenate([np.abs(run(r.x, s) - s[3]) for s in segs])
    print(dict(zip(('a', 'b', 'c', 'dmin', 'k_out', 'k_in', 'band', 'e'), np.round(r.x, 4))), 'mean', round(r.fun, 2),
          'median', round(float(np.median(e)), 1), 'p90', round(float(np.percentile(e, 90)), 1))


if __name__ == '__main__':
    if sys.argv[1] == 'all':
        for s in ['stg00', 'stg10', 'stg20', 'stg30', 'stg40', 'stg50', 'stg60', 'stg70', 'stg80', 'stg90']:
            if os.path.exists(R + f'dumps/cap/cl{s[3:]}.bin') or os.path.exists(R + f'dumps/cap/cm{s[3:]}.bin'): fit(s)
    elif sys.argv[1] == 'boss':
        fit_boss(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'fit-dist':
        fit_dist()
    else:
        fit(sys.argv[1])
