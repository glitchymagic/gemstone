#!/usr/bin/env python3
"""The game's own hit data, read from the owner's disc (docs/RIP.md "Hit data").

Pn0_HIT.BIN: u16 BE index[5 kinds][256 motions] (0 = none), then 8-byte steps from 0xA00:
  b0 -> player+0x102, b1 -> player+0x101, b2 = hit id (0 keep, 0xFF end) -> player+0x100, b3 = the step's LAST
  motion frame (absolute): the motion routine 0x0C09A910 counts frames in u16 player+0x719E (+1 per frame from 0 at
  set_motion) and moves to the next step once that count passes b3 (0x0C09AC3A). 254 = until the motion ends.
  set_motion (0x0C09A808) copies index[kind][motion] to player+0x71A0; 0x0C09AEBC loads step player+0x71A2.
1ST_READ.BIN 0x0C338A98: u32 per character -> 20-byte attack records, hit id = record number.
  b1 = base damage (health is 240), see damage() for the multipliers (0x0C059718 + 0x0C08DFA4).

Sphere sets (PL block, 1ST_READ 0x0C11D7B0 + char * 0x3200, same bytes as PLnn_DATA.BIN; pointers 0x0C336660):
  +0x0000 attack sets, 4 x (joint u8, flag u8, sphere u16) per set, chosen by player+0x101 -> 4 spheres at +0x148
  +0x0640 body sets, 12 x (joint, flag, sphere) per set, chosen by player+0x102 -> 12 spheres at +0x188
  +0x1900 spheres, 8 bytes: s16 x, y, z offset in the joint's frame (cm), s16 radius; joint 255 = the fighter's root
  (sphere builder 0x0C020680, set lookup 0x0C022952, counts per object type 0x0C320034).
Usage: hitdata.py N [kind/motion ...]     N = fighter number 0..10 (P00..PA0)
       hitdata.py N --all                 every motion that has hit steps
       hitdata.py export [OUT_DIR]        game/assets/ripped/pN0_hit.json for every fighter"""
import json, struct, sys

ROOT = './'
FS = ROOT + 'rip/fs/'
BASE = 0x0C010000
B = open(FS + '1ST_READ.BIN', 'rb').read()
ATTACK_PTRS = 0x0C338A98
# victim's defence by character (0x0C32E078), combo scaling by hits in a row (0x0C32E0A4)
DEFENCE = list(struct.unpack_from('<11f', B, 0x0C32E078 - BASE))
COMBO = list(struct.unpack_from('<16f', B, 0x0C32E0A4 - BASE))
CPU_ATK = list(struct.unpack_from('<32f', B, 0x0C32DF78 - BASE))   # CPU attacker, by CPU level 0x0C7F305C
CPU_DEF = list(struct.unpack_from('<32f', B, 0x0C32DFF8 - BASE))   # CPU victim (divides)
MAX_HP = 240


def u32(a): return struct.unpack_from('<I', B, (a & 0x1FFFFFFF) - BASE)[0]


def pname(n): return 'P%X0' % n


def steps_table(n):
    h = open(FS + pname(n) + '_HIT.BIN', 'rb').read()
    idx = struct.unpack_from('>1280H', h, 0)
    return h, idx


def steps(n, kind, motion):
    h, idx = steps_table(n)
    i = idx[kind * 256 + motion]
    if not i: return []
    out, frame = [], 0
    while True:
        b0, b1, hid, last = h[0xA00 + i * 8: 0xA00 + i * 8 + 4]
        if hid == 0xFF: break
        if last >= frame:   # a step whose end is already passed is skipped by the game's catch-up loop
            out.append({'f0': frame, 'frames': last - frame + 1, 'hit': hid, 'b0': b0, 'b1': b1})
            frame = last + 1
        i += 1
        if len(out) > 64: break
    return out


def attack(n, hid):
    a = u32(ATTACK_PTRS + 4 * n) + 20 * hid
    r = B[a - BASE: a - BASE + 20]
    return {'raw': r.hex(), 'dmg': r[1], 'b0': r[0], 'b3': r[3], 'type': r[4], 'b5': r[5],
            'scale': r[8], 'react': r[14], 'b12': r[12], 'b13': r[13], 'b16': r[16], 'snd': r[18]}


PL_BASE = 0x0C11D7B0


def pl(n):
    a = PL_BASE + n * 0x3200 - BASE
    return B[a:a + 0x3200]


def sets(n, off, per, count):
    d = pl(n)
    out = {}
    for s in range(count):
        e = [struct.unpack_from('<BBH', d, off + s * per * 4 + 4 * k) for k in range(per)]
        if any(any(x) for x in e): out[s] = [(j, sp) for j, f, sp in e]
    return out


def sphere(n, i):
    return list(struct.unpack_from('<4h', pl(n), 0x1900 + 8 * i))


def export(n):
    h, idx = steps_table(n)
    moves, hids = {}, set()
    for k in range(5):
        for m in range(256):
            if not idx[k * 256 + m]: continue
            st = steps(n, k, m)
            if not st: continue
            moves[f'k{k}_{m:03d}'] = [[s['f0'], s['frames'], s['hit'], s['b1'], s['b0']] for s in st]
            hids |= {s['hit'] for s in st if s['hit']}
    aset, bset = sets(n, 0, 4, 100), sets(n, 0x640, 12, 100)
    used = {sp for v in list(aset.values()) + list(bset.values()) for j, sp in v}
    hits = {}
    for hid in sorted(hids):
        a = attack(n, hid); r = bytes.fromhex(a['raw'])
        hits[str(hid)] = {'dmg': r[1], 'class': r[0], 'type': r[4], 'level': r[6], 'react': r[14], 'raw': a['raw']}
    # from logged real fights (tools/hitlog.py, work/*_derived.json): body sets of motions without hit steps (the
    # set numbers are the same for every fighter: majority over all fighters, then this fighter's own), and hit ids
    # the game's code sets itself (Falcon's Power Rocket flight k1/100 = hit 117)
    body_default, code_hits, proj_base = {}, {}, {}
    import glob, collections
    votes = collections.defaultdict(collections.Counter)
    for f in sorted(glob.glob(ROOT + 'work/*_derived.json')):
        dj = json.load(open(f))
        for ch, mp in dj.get('body_default', {}).items():
            for key, bs in mp.items():
                votes[key][bs] += 1
        for k, hid in dj.get('code_hits', {}).items():
            ch, key = k.split('/')
            if int(ch) == n: code_hits[key] = hid
        for k, b in dj.get('proj_base', {}).items():
            ch, key = k.split('/')
            if int(ch) == n: proj_base[key] = b
    body_default = {key: c.most_common(1)[0][0] for key, c in votes.items()}
    for f in sorted(glob.glob(ROOT + 'work/*_derived.json')):
        body_default.update(json.load(open(f)).get('body_default', {}).get(str(n), {}))
    # throw records (type 2: no defence, combo cut or bonus): 48-62; the throw code applies them itself (logged:
    # Falcon's throw 49 + 49 + 48 = 12 + 12 + 24, his and Wang-Tang's other throw 50 = 48)
    for hid in list(code_hits.values()) + list(range(48, 63)):
        a = attack(n, hid); r = bytes.fromhex(a['raw'])
        hits[str(hid)] = {'dmg': r[1], 'class': r[0], 'type': r[4], 'level': r[6], 'react': r[14], 'raw': a['raw']}
    return {'char': n, 'defence': round(DEFENCE[n], 4), 'max_hp': MAX_HP, 'combo': [round(c, 6) for c in COMBO],
            'body_default': body_default, 'code_hits': code_hits, 'proj_base': proj_base,
            'spheres': {str(i): sphere(n, i) for i in sorted(used)},
            'atk_sets': {str(k): v for k, v in aset.items()}, 'body_sets': {str(k): v for k, v in bset.items()},
            'moves': moves, 'hits': hits}


def damage(base, victim, combo_hits=0, attacker_gems=0, attacker_pc=False, victim_pc=False,
           cpu_level=None, attacker_cpu=False, victim_cpu=False, rtype=0):
    """0x0C059718 then 0x0C08DFA4 with the arcade options (0x0C7F476B/C = 1, damage level 1)."""
    d = float(base)
    if attacker_cpu and cpu_level is not None: d *= CPU_ATK[cpu_level]
    if rtype != 2:
        d *= DEFENCE[victim] * COMBO[min(combo_hits, 15)]
    if victim_cpu and cpu_level is not None: d /= CPU_DEF[cpu_level]
    d = max(d, 1.0)
    if rtype not in (2, 7):
        m = 1.0
        if rtype in (3, 4) or attacker_pc: m = 1.2
        if attacker_gems == 2: m = 1.1
        elif attacker_gems == 1: m = 1.05
        d *= m
    d = max(d, 1.0)
    if victim_pc: d *= 0.5
    if d and d < 1.0: d = 1.0
    return int(d)


if __name__ == '__main__' and sys.argv[1] == 'export':
    out = sys.argv[2] if len(sys.argv) > 2 else ROOT + 'game/assets/ripped/'
    for n in range(11):
        j = export(n)
        json.dump(j, open(out + pname(n).lower() + '_hit.json', 'w'), separators=(',', ':'))
        print(pname(n), len(j['moves']), 'moves', len(j['hits']), 'hit records', len(j['atk_sets']), 'attack sets')
elif __name__ == '__main__':
    n = int(sys.argv[1], 16)
    h, idx = steps_table(n)
    want = []
    if len(sys.argv) > 2 and sys.argv[2] == '--all':
        want = [(k, m) for k in range(5) for m in range(256) if idx[k * 256 + m]]
    else:
        want = [tuple(int(x) for x in a.split('/')) for a in sys.argv[2:]]
    for k, m in want:
        st = steps(n, k, m)
        hits = [s for s in st if s['hit']]
        if not hits and len(sys.argv) > 2 and sys.argv[2] == '--all': continue
        line = ' '.join(f"[{s['f0']}+{s['frames']} h{s['hit']} {s['b0']}/{s['b1']}]" for s in st)
        print(f'k{k}/{m}: {line}')
        for hid in sorted({s['hit'] for s in hits}):
            a = attack(n, hid)
            print(f"    hit {hid}: dmg {a['dmg']} type {a['type']} react {a['react']} raw {a['raw']}")
