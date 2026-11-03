#!/usr/bin/env python3
"""Power Stone (DC) Pn0_MOT.MDT static decoder: disc file in -> per-frame bone rotations + root translation.

File layout (all big-endian, see NOTES.md):
  0x000  u16 table[5 kinds][256 motions]  = first key-entry index of the motion inside that kind's entry list
  0xA00  rows: s16[66] per key = 22 triplets: [0] world displacement (unused by the pose), [1] body rotation,
         [2] body translation (1/16 cm), [3..21] rotations of bones ORDER[0..18]  (s16, 32768 = 360 deg)
         rows of kind 0, then kind 1 .. kind 4, back to back
  then   key entries, 8 bytes: u32 word offset of the row inside its kind's rows, u8 flags, u8 frames, u16 0
         flags 0x40 = last key of the motion, 0x80 = loop marker (offset low byte = key index to loop to)
         entries of kind 0 .. kind 4 back to back; each kind's list starts with offset 0.
The game's player (0x0C09A910 step, 0x0C09AC70 load key, 0x0C09B0F8 pose) is reproduced bit-exactly in
float32 below.

Usage:
  mdt_decode.py list P00_MOT.MDT                       motions, clip lengths, loops
  mdt_decode.py dump P00_MOT.MDT KIND MOTION [--char N --form F]   per-frame s32 angles / translations
  mdt_decode.py export rip/fs CHAR FORM OUTDIR
        -> OUTDIR/*.npz in tools/clips.py form (q (F,parts,4) xyzw, t (F,3), loop) + raw s32 rot, index.json,
           skel.json (parent/offset from the 1ST_READ descriptor) for tools/export_rig.py
"""
import argparse, json, os, struct, sys
import numpy as np

NBONE = 19

F32 = np.float32
# Three small tables the motion player reads, loaded from YOUR 1ST_READ.BIN by load_tables() (export does it itself):
ORDER = []        # u8[19] at 0x0C150D50: the bone each rotation triplet drives
TRANS_Y = []      # f32[11][2] at 0x0C150CD8: root-translation Y factor per [char][form]
MODEL_SCALE = []  # f32[11][2] at 0x0C150C60: whole-model scale per [char][form]


def load_tables(exe):
    o = lambda a: a - 0x0C010000
    ORDER[:] = list(exe[o(0x0C150D50):o(0x0C150D50) + NBONE])
    ty = struct.unpack_from('<22f', exe, o(0x0C150CD8)); ms = struct.unpack_from('<22f', exe, o(0x0C150C60))
    TRANS_Y[:] = [(round(ty[2 * i], 6), round(ty[2 * i + 1], 6)) for i in range(11)]
    MODEL_SCALE[:] = [(round(ms[2 * i], 6), round(ms[2 * i + 1], 6)) for i in range(11)]


def _tables_near(path):
    if not ORDER:
        load_tables(open(os.path.join(os.path.dirname(os.path.abspath(path)), '1ST_READ.BIN'), 'rb').read())


class MDT:
    def __init__(self, path_or_bytes):
        m = path_or_bytes if isinstance(path_or_bytes, (bytes, bytearray)) else open(path_or_bytes, 'rb').read()
        self.raw = m
        self.table = np.frombuffer(m[:0xA00], '>u2').reshape(5, 256).astype(int)
        e = len(m) - 8                          # entries run to the end of the file; walk back while they parse
        while e >= 0xA00:
            off, fl, du, z = struct.unpack_from('>IBBH', m, e)
            if z != 0 or fl not in (0, 0x40, 0x80) or off > 0x400000: break
            e -= 8
        es = e + 8
        ent = np.frombuffer(m[es:es + (len(m) - es) // 8 * 8],
                            dtype=[('off', '>u4'), ('fl', 'u1'), ('du', 'u1'), ('z', '>u2')])
        starts = [i for i in range(len(ent)) if ent['off'][i] == 0 and ent['fl'][i] != 0x80]
        assert len(starts) == 5, (path_or_bytes, starts)
        rows = np.frombuffer(m[0xA00:es], '>i2').astype(np.int32)
        self.ents, self.rows = [], []
        w = 0
        for k in range(5):
            a, b = starts[k], (starts[k + 1] if k < 4 else len(ent))
            ek = ent[a:b]
            nw = int(ek['off'].max()) + 66
            self.ents.append([(int(o), int(f), int(d)) for o, f, d in zip(ek['off'], ek['fl'], ek['du'])])
            self.rows.append(rows[w:w + nw])
            w += nw
        assert w == len(rows), 'row words do not add up'

    def exists(self, kind, motion):
        return motion == 0 or self.table[kind][motion] != 0

    def motions(self):
        return [(k, n) for k in range(5) for n in range(256) if self.table[k][n] or n == 0]

    def keys(self, kind, motion):
        """[(row s16[66], frames, flags)] up to the last key, and the loop target key index (None = one-shot)"""
        ents = self.ents[kind]
        i = self.table[kind][motion]
        out = []
        while True:
            o, f, d = ents[i]
            out.append((self.rows[kind][o:o + 66], d, f))
            if f & 0x40: break
            i += 1
        nxt = ents[i + 1] if i + 1 < len(ents) else (0, 0, 0)
        loop = (nxt[0] & 0xFF) if nxt[1] & 0x80 else None
        return out, loop


def ang(v):
    """s16 key value -> s32 node angle (0x0C09B540: float(v) * 65536 / 91.019 / 360, truncated)"""
    x = F32(v) * F32(65536.0)
    x = x / F32(91.01899719238281)
    x = x / F32(360.0)
    return np.trunc(x).astype(np.int32)


def _diff16(cur, prev):
    d = (cur & 0xFFFF).astype(np.int64) - (prev & 0xFFFF).astype(np.int64)
    d = np.where((d >= 0) & ((d & 0x8000) != 0), d - 0x10000, d)
    d = np.where((d < 0) & ((d & 0x8000) == 0), d + 0x10000, d)
    return d


def interp_ang(prev, cur, t):
    """0x0C09B64C + 0x0C0622C6: prev + trunc(float(diff16(cur, prev)) * t)"""
    return (prev.astype(np.int64) + np.trunc(_diff16(cur, prev).astype(F32) * F32(t)).astype(np.int64)).astype(np.int64)


def row_pose(row, ty):
    """one key row -> (bone angles s32 (19,3), body angles (3,), body translation f32 (3,))"""
    r = np.asarray(row, np.int32).reshape(22, 3)
    tr = r[2].astype(F32) / F32(16.0)
    tr[1] = tr[1] * F32(ty)
    return ang(r[3:]), ang(r[1]), tr


def play(mdt, kind, motion, frames, char=0, form=0, prev_row=None):
    """Simulate set_motion + `frames` vblanks of the game's motion player.
    Returns dict: rot (F,19,3) s32 node angles in PART order, body_rot (F,3) s32, body_t (F,3) f32, ph (F,) playhead,
    ended (F,) bool.  Frame f = playhead f after set_motion (frame 0 = the set_motion frame).
    prev_row: the key row the previous motion stood on (only used if the first key lasts > 1 frame)."""
    keys, loop = mdt.keys(kind, motion)
    ty = TRANS_Y[char][form]
    ents, rows = mdt.ents[kind], mdt.rows[kind]
    first = int(mdt.table[kind][motion])
    st = dict(k=0, cd=1, tot=1, cur=None, prev=None, ph=0, ended=False, fl=0)

    def load(i):                                        # 0x0C09AC70: entry first+i becomes the current key
        o, fl, d = ents[first + i]
        st['prev'] = st['cur']
        st['cur'] = rows[o:o + 66]
        st['cd'] = st['tot'] = d
        st['fl'] = fl

    st['cur'] = prev_row if prev_row is not None else rows[ents[first][0]:ents[first][0] + 66]
    load(0); st['k'] = 1
    R = np.zeros((frames, NBONE, 3), np.int64); BR = np.zeros((frames, 3), np.int64)
    BT = np.zeros((frames, 3), F32); PH = np.zeros(frames, np.int32); EN = np.zeros(frames, bool)
    DS = np.zeros((frames, 3), F32); pos = np.zeros(3, F32)
    for f in range(frames):
        if f > 0:                                       # 0x0C09A910
            st['ph'] += 1; st['cd'] -= 1
            if st['cd'] == 0:
                k = st['k']
                o, fl, d = ents[first + k] if first + k < len(ents) else (0, 0, 0)
                if fl & 0x80:                           # loop marker: jump to key (offset & 0xFF), playhead = frames before it
                    j = o & 0xFF
                    load(j); st['k'] = j + 1
                    st['ph'] = sum(ents[first + i][2] for i in range(j))
                elif st['fl'] & 0x40:                   # 0x0C09AD94: past the last key -> reload it (hold)
                    load(k - 1); st['ph'] -= 1; st['ended'] = True
                else:
                    load(k); st['k'] = k + 1
        tot, cd = st['tot'], st['cd']
        if f > 0:                                       # triplet 0: displacement over the segment, spread evenly (also on the hold frame)
            v = np.asarray(st['cur'][:3], np.int32).astype(F32) / F32(16.0)
            pos = (pos + v / F32(tot)).astype(F32)
        DS[f] = pos
        t = F32(F32(tot - cd + 1) / F32(tot)) if tot > 0 else F32(1.0)
        a1, b1, t1 = row_pose(st['cur'], ty)
        a0, b0, t0 = row_pose(st['prev'], ty)
        bones = interp_ang(a0, a1, t)
        R[f, ORDER] = bones
        BR[f] = interp_ang(b0, b1, t)
        BT[f] = t0 + (t1 - t0) * t
        PH[f] = st['ph']; EN[f] = st['ended']
    return dict(rot=R, body_rot=BR, body_t=BT, disp=DS, ph=PH, ended=EN, loop=loop, keys=len(keys))


def motion_length(mdt, kind, motion):
    keys, loop = mdt.keys(kind, motion)
    return sum(d for _, d, _ in keys), loop



# ---------- skeleton from 1ST_READ.BIN (per-form model descriptors) ----------
EXE_BASE = 0x0C010000
DESC_TABLE = 0x0C34BBA0          # descriptor(char, form) = DESC_TABLE + char*0x120 + form*0x48 (0x48 more = 2P copy)
BODY_PARENT = [-1, 0, 0, 1, 3, 1, 5, 6, 7, 1, 9, 10, 11, 2, 13, 14, 2, 16, 17]   # fixed tree (hard-coded in the game)
GROUP_PARENT = {2: 4, 3: 8, 4: 12}   # head variants hang off bone 4, right hand variants off 8, left off 12


def skeleton_from_disc(exe, char, form):
    """-> dict(parent, offset, const_rot (part -> s32 xyz), groups, mdl_part_offsets, parent_list_slot)
    Descriptor words: [0..4] -> u32 MDL part offsets per group (body, extras, heads, R hands, L hands),
    [5..9] -> u32 part sizes per group, [10] -> f32[3] body bone offsets, [11] -> f32[3] extra offsets,
    [12] -> s32[3] extra rotations (65536 = 360 deg), [13] extra count, [14] -> u8 (list, slot) parent of each
    extra (list 0 body, 1 extras, 2 heads, 3 R hands, 4 L hands), [15] MDL bytes before the texture table,
    [16] texture table bytes, [17] texture count."""
    if isinstance(exe, str): exe = open(exe, 'rb').read()
    rd = lambda fmt, a: struct.unpack_from(fmt, exe, a - EXE_BASE)
    d = rd('<18I', DESC_TABLE + char * 0x120 + form * 0x48)
    nx = d[13]
    sizes = [NBONE, nx, (d[7] - d[2]) // 4, (d[8] - d[3]) // 4, (d[9] - d[4]) // 4]
    groups, k = [], 0
    for n in sizes:
        groups.append(list(range(k, k + n))); k += n
    npart = k
    off = [list(rd('<3f', d[10] + 12 * i)) for i in range(NBONE)]
    off += [list(rd('<3f', d[11] + 12 * i)) for i in range(nx)]
    off += [[0.0, 0.0, 0.0]] * (npart - NBONE - nx)
    par = list(BODY_PARENT)
    pairs = rd('<%dB' % (2 * nx), d[14]) if nx else ()
    raw_pairs = []
    for i in range(nx):
        lst, slot = pairs[2 * i], pairs[2 * i + 1]
        raw_pairs.append((lst, slot))
        par.append(groups[lst][slot])
    for g in (2, 3, 4):
        par += [GROUP_PARENT[g]] * sizes[g]
    const_rot = {NBONE + i: list(rd('<3i', d[12] + 12 * i)) for i in range(nx)}
    mdl_ofs = []
    for g in range(5):
        if sizes[g]: mdl_ofs += list(rd('<%dI' % sizes[g], d[g]))
    return dict(parent=par, offset=[[round(float(x), 6) for x in o] for o in off], const_rot=const_rot,
                groups=groups, extra_parent_list_slot=raw_pairs, mdl_part_offsets=mdl_ofs,
                mdl_bytes=d[15], tex_bytes=d[16], tex_count=d[17])


# ---------- rotations -> the clip form used by tools/clips.py / export_rig.py ----------
TAU = 2 * np.pi / 65536.0


def euler_rowmat(a):
    """s32 angles (...,3) -> row-vector rotation matrices R = Rx(x) Ry(y) Rz(z) (v' = v R)"""
    a = np.asarray(a, np.float64) * TAU
    cx, sx = np.cos(a[..., 0]), np.sin(a[..., 0]); cy, sy = np.cos(a[..., 1]), np.sin(a[..., 1])
    cz, sz = np.cos(a[..., 2]), np.sin(a[..., 2])
    sh = a.shape[:-1]
    Rx = np.zeros(sh + (3, 3)); Rx[..., 0, 0] = 1; Rx[..., 1, 1] = cx; Rx[..., 1, 2] = sx; Rx[..., 2, 1] = -sx; Rx[..., 2, 2] = cx
    Ry = np.zeros(sh + (3, 3)); Ry[..., 1, 1] = 1; Ry[..., 0, 0] = cy; Ry[..., 0, 2] = -sy; Ry[..., 2, 0] = sy; Ry[..., 2, 2] = cy
    Rz = np.zeros(sh + (3, 3)); Rz[..., 2, 2] = 1; Rz[..., 0, 0] = cz; Rz[..., 0, 1] = sz; Rz[..., 1, 0] = -sz; Rz[..., 1, 1] = cz
    return Rx @ Ry @ Rz


def mat2quat(Rc):
    """column-vector rotation matrices (...,3,3) -> xyzw (same branch order as tools/clips.quat)"""
    Rc = np.asarray(Rc, np.float64)
    out = np.zeros(Rc.shape[:-2] + (4,))
    flat = Rc.reshape(-1, 3, 3); o = out.reshape(-1, 4)
    for i, R in enumerate(flat):
        t = np.trace(R)
        if t > 0:
            s = np.sqrt(t + 1) * 2; o[i] = [(R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s, s / 4]
        elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
            s = np.sqrt(1 + R[0, 0] - R[1, 1] - R[2, 2]) * 2; o[i] = [s / 4, (R[0, 1] + R[1, 0]) / s, (R[0, 2] + R[2, 0]) / s, (R[2, 1] - R[1, 2]) / s]
        elif R[1, 1] > R[2, 2]:
            s = np.sqrt(1 + R[1, 1] - R[0, 0] - R[2, 2]) * 2; o[i] = [(R[0, 1] + R[1, 0]) / s, s / 4, (R[1, 2] + R[2, 1]) / s, (R[0, 2] - R[2, 0]) / s]
        else:
            s = np.sqrt(1 + R[2, 2] - R[0, 0] - R[1, 1]) * 2; o[i] = [(R[0, 2] + R[2, 0]) / s, (R[1, 2] + R[2, 1]) / s, s / 4, (R[1, 0] - R[0, 1]) / s]
    return out


def to_clip(p, nparts, root_offset, const_rot=None, model_scale=1.0, with_disp=True):
    """player output -> q (F, nparts, 4) local xyzw quats (column-vector convention), t (F, 3) root translation.
    Root local = R(bone 0) R(body) (row vectors), root translation = (offset0 R(body) + body_t) * model_scale."""
    F = p['rot'].shape[0]
    Rb = euler_rowmat(p['rot'])                       # (F,19,3,3)
    Rbody = euler_rowmat(p['body_rot'])               # (F,3,3)
    q = np.zeros((F, nparts, 4)); q[..., 3] = 1
    if const_rot is not None:
        for k, a in const_rot.items():
            if k < nparts: q[:, k] = mat2quat(euler_rowmat(np.array(a))[None].transpose(0, 2, 1))[0]
    L = Rb.copy(); L[:, 0] = Rb[:, 0] @ Rbody
    q[:, :NBONE] = mat2quat(np.swapaxes(L, -1, -2))
    t = (np.einsum('j,fjk->fk', np.asarray(root_offset, np.float64), Rbody) + p['body_t'].astype(np.float64)) * model_scale
    if with_disp: t = t + p['disp'].astype(np.float64)
    for f in range(1, F):                             # hemisphere continuity, as tools/clips.py
        flip = np.sum(q[f] * q[f - 1], axis=1) < 0
        q[f, flip] *= -1
    return q, t


LETTER = 'frwjglaokvz'       # tools/clips.py naming: f0k1_016 = Falcon, kind 1, motion 16


def clip_span(mdt, kind, motion, limit=4000):
    """frames of the clip (clip frame 0 = playhead 1, as tools/clips.py cuts the captures) and where the loop
    region starts (None = one-shot: the last frame is the held last key).  Found by running the player: a one-shot
    ends on its first hold frame; a loop ends on the frame its 0x80 marker reloads key j (= the pose of the frame
    where key j was first reached, which is loop_from)."""
    ents = mdt.ents[kind]; first = int(mdt.table[kind][motion])
    k, cd, t, reach = 1, ents[first][2], 0, {0: 0}
    fl = ents[first][1]
    while t < limit:
        t += 1; cd -= 1
        if cd == 0:
            o, f2, d = ents[first + k] if first + k < len(ents) else (0, 0, 0)
            if f2 & 0x80:
                return t, reach.get(o & 0xFF, 0)
            if fl & 0x40:
                return t, None
            cd, fl = d, f2; reach.setdefault(k, t); k += 1
    return limit, None


def export_form(fs, char, form, out, only=None):
    """every motion of one form -> out/<x><form>k<k>_<mmm>.npz (q, t, loop, loop_from, rot) + index.json + skel.json"""
    os.makedirs(out, exist_ok=True)
    exe = open(os.path.join(fs, '1ST_READ.BIN'), 'rb').read()
    load_tables(exe)
    skel = skeleton_from_disc(exe, char, form)
    md = MDT(os.path.join(fs, 'P%X0_MOT.MDT' % char))
    n = len(skel['parent'])
    index = {}
    for k, m in (only or md.motions()):
        F, lf = clip_span(md, k, m)
        p = play(md, k, m, F + 1, char, form)
        q, t = to_clip(p, n, skel['offset'][0], skel['const_rot'], MODEL_SCALE[char][form])
        name = '%s%dk%d_%03d' % (LETTER[char], form, k, m)
        np.savez_compressed(os.path.join(out, name + '.npz'), q=q[1:].astype(np.float32), t=t[1:].astype(np.float32),
                            loop=lf is not None, loop_from=-1 if lf is None else lf, rot=p['rot'][1:].astype(np.int32),
                            body_rot=p['body_rot'][1:].astype(np.int32))
        index[name] = {'kind': k, 'motion': m, 'frames': F, 'loop': lf is not None, 'loop_from': lf,
                       'entry0': bool(md.table[k][m] == 0), 'src': 'P%X0_MOT.MDT' % char}
    js = dict(parent=skel['parent'], offset=skel['offset'], const_rot={str(k): v for k, v in skel['const_rot'].items()},
              groups=skel['groups'], mdl_part_offsets=skel['mdl_part_offsets'],
              motion_scale=MODEL_SCALE[char][form], trans_y=TRANS_Y[char][form], source='1ST_READ.BIN descriptor')
    json.dump(js, open(os.path.join(out, 'skel.json'), 'w'), indent=1)
    json.dump(index, open(os.path.join(out, 'index.json'), 'w'), indent=1)
    return index


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    a1 = sub.add_parser('list'); a1.add_argument('mdt')
    a2 = sub.add_parser('dump'); a2.add_argument('mdt'); a2.add_argument('kind', type=int); a2.add_argument('motion', type=int)
    a2.add_argument('--char', type=int, default=0); a2.add_argument('--form', type=int, default=0)
    a3 = sub.add_parser('export'); a3.add_argument('fs'); a3.add_argument('char', type=lambda x: int(x, 16))
    a3.add_argument('form', type=int); a3.add_argument('out')
    a = ap.parse_args()
    if a.cmd in ('list', 'dump'):
        _tables_near(a.mdt)
    if a.cmd == 'list':
        md = MDT(a.mdt)
        for k, n in md.motions():
            F, lf = clip_span(md, k, n)
            print(f'k{k}/{n:03d} frames {F:4d} ' + ('loop from %d' % lf if lf is not None else 'one-shot'))
    elif a.cmd == 'dump':
        md = MDT(a.mdt)
        F, lf = clip_span(md, a.kind, a.motion)
        p = play(md, a.kind, a.motion, F + 1, a.char, a.form)
        for f in range(F + 1):
            print(f, p['ph'][f], p['disp'][f], p['body_t'][f], p['body_rot'][f], p['rot'][f].tolist())
    else:
        ix = export_form(a.fs, a.char, a.form, a.out)
        print('wrote', len(ix), 'motions to', a.out)


if __name__ == '__main__':
    main()
