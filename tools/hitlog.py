#!/usr/bin/env python3
"""Log real hits in Flycast (pass 4): both fighters' hit fields every frame, then check them against the game's own
hit data (tools/hitdata.py).
  hitlog.py segs                 -> the capseg segment string (both players + the CPU level byte)
  hitlog.py hits NAME            -> every health drop: attacker move, hit id, base damage, combo count, gems, the
                                    damage tools/hitdata.damage() predicts, and the victim's reaction motion
  hitlog.py frames NAME P K/M    -> per-frame hit id / attack set / sphere radii for one move of player P
Player fields (offsets from the struct, P1 0x0C7E40C4, P2 0x0C7EB394):
  +0x0F4 attack record ptr  +0x100 hit id, +0x101 attack sphere set, +0x102 body sphere set
  +0x148 4 attack spheres (x,y,z,r)   +0x188 12 body spheres   +0x020 root x,y,z
  +0x71A0 u16 hit index, +0x71A2 step, +0x71A3 frames left, +0x71A4 kind, +0x71A5 motion   +0x71BA state
  +0x71D4 s16 health   +0x71ED CPU flag?   +0x71F3 Power Change   +0x71F4 s16 gauge   +0x720E combo count
  +0x7230 gems"""
import struct, sys
import numpy as np
sys.path.insert(0, './tools')
import hitdata as H
CAP = './dumps/cap/'
BASES = [0x0C7E40C4, 0x0C7EB394]
FIELDS = [(0x000, 8), (0x0F4, 4), (0x100, 4), (0x148, 64), (0x188, 192), (0x020, 16), (0x71A0, 8), (0x71B8, 4), (0x71D4, 8),
          (0x71EC, 12), (0x720C, 8), (0x7230, 4)]
GLOBALS = [(0x0C7F305C, 4), (0x0C7F2F10, 4)]
# lite capture (no sphere positions: ~4x faster in Flycast); load() reads dumps/cap/NAME.fields when present
LITE = [(0x000, 8), (0x0F4, 4), (0x100, 4), (0x020, 16), (0x71A0, 8), (0x71B8, 4), (0x71D4, 8), (0x71EC, 12),
        (0x720C, 8), (0x7230, 4)]


def segs(fields=None):
    out = [f'0x{b + o:08X}:{n}' for b in BASES for o, n in (fields or FIELDS)]
    return ','.join(out + [f'0x{a:08X}:{n}' for a, n in GLOBALS])


def frame_size(fields=None):
    return 2 * sum(n for _, n in (fields or FIELDS)) + sum(n for _, n in GLOBALS)


def load(name):
    global FIELDS
    import json, os
    fp = CAP + name + '.fields'
    if os.path.exists(fp): FIELDS = [tuple(x) for x in json.load(open(fp))]
    raw = open(CAP + name + '.bin', 'rb').read()
    fs = frame_size()
    nfr = len(raw) // fs
    out = []
    for f in range(nfr):
        fr = raw[f * fs:(f + 1) * fs]
        pos, ps = 0, []
        for b in BASES:
            d = {}
            for o, n in FIELDS:
                d[o] = fr[pos:pos + n]; pos += n
            ps.append(d)
        g = fr[pos:]
        out.append((ps, g))
    return out


def player(d):
    hid, aset, bset, b103 = d[0x100]
    hidx, step, left, kind, mot = struct.unpack('<HBBBB', d[0x71A0][:6])
    st = d[0x71B8][2]
    hp = struct.unpack('<h', d[0x71D4][:2])[0]
    cpu = d[0x71EC][1]
    pc = d[0x71EC][7]
    gauge = struct.unpack('<h', d[0x71EC][8:10])[0]
    combo = d[0x720C][2]
    gems = d[0x7230][0]
    rec = struct.unpack('<I', d[0x0F4])[0]
    att = [struct.unpack('<4f', d[0x148][16 * i:16 * i + 16]) for i in range(4)] if 0x148 in d else []
    body = [struct.unpack('<4f', d[0x188][16 * i:16 * i + 16]) for i in range(12)] if 0x188 in d else []
    root = struct.unpack('<3f', d[0x020][:12])
    ch = d[0x000][4]
    return dict(ch=ch, hid=hid, aset=aset, bset=bset, kind=kind, mot=mot, step=step, state=st, hp=hp, cpu=cpu, pc=pc,
                gauge=gauge, combo=combo, gems=gems, rec=rec, att=att, body=body, root=root)


def hits(name):
    fr = load(name)
    rows = []
    for i in range(1, len(fr)):
        for v in (0, 1):
            a = 1 - v
            pv0, pv1 = player(fr[i - 1][0][v]), player(fr[i][0][v])
            if pv1['hp'] < pv0['hp'] and pv0['hp'] > 0:
                pa = player(fr[i - 1][0][a]); pa1 = player(fr[i][0][a])
                lvl = fr[i][1][0]
                atk_char = pa['ch']
                # the record pointer the victim copied (+0xF8) isn't logged; use the attacker's live record
                rptr = pa['rec'] or pa1['rec']
                base = H.u32(H.ATTACK_PTRS + 4 * atk_char)
                hid = (rptr - base) // 20 if rptr else -1
                rec = H.attack(atk_char, hid) if 0 <= hid < 128 else None
                d = pv0['hp'] - pv1['hp']
                pred = None
                if rec:
                    pred = H.damage(rec['dmg'], pv0['ch'], combo_hits=pa1['combo'], attacker_gems=pa['gems'],
                                    attacker_pc=bool(pa['pc']), victim_pc=bool(pv0['pc']), cpu_level=lvl,
                                    attacker_cpu=bool(pa['cpu']), victim_cpu=bool(pv0['cpu']), rtype=rec['type'])
                if pa['state'] == 28 or pa['kind'] == 4:   # a throw: the throw code applies type-2 records 48-62
                    for th in range(48, 63):
                        tr = H.attack(atk_char, th)
                        if tr['type'] == 2 and H.damage(tr['dmg'], pv0['ch'], combo_hits=pa1['combo'], attacker_gems=pa['gems'],
                                                        attacker_pc=bool(pa['pc']), victim_pc=bool(pv0['pc']), cpu_level=lvl,
                                                        attacker_cpu=bool(pa['cpu']), victim_cpu=bool(pv0['cpu']), rtype=2) == d:
                            hid, rec, pred = th, tr, d
                            break
                # victim reaction: first motion after the hit
                react = None
                for j in range(i, min(i + 6, len(fr))):
                    q = player(fr[j][0][v])
                    if (q['kind'], q['mot']) != (pv0['kind'], pv0['mot']):
                        react = (q['kind'], q['mot']); break
                rows.append(dict(frame=i, att=a, ach=pa['ch'], vch=pv0['ch'], move=(pa['kind'], pa['mot']), hid=hid, base=rec['dmg'] if rec else None,
                                 dmg=d, pred=pred, combo=pa1['combo'], gems=pa['gems'], apc=pa['pc'], vpc=pv0['pc'],
                                 lvl=lvl, react=react, rtype=rec['type'] if rec else None, b0=rec['b0'] if rec else None,
                                 hp=pv1['hp']))
    return rows


if __name__ == '__main__':
    if sys.argv[1] == 'segs':
        print(segs())
    elif sys.argv[1] == 'hits':
        for r in hits(sys.argv[2]):
            ok = 'OK' if r['pred'] == r['dmg'] else '--'
            print(f"{r['frame']:6d} P{r['att'] + 1} c{r['ach']}>c{r['vch']} k{r['move'][0]}/{r['move'][1]} hit {r['hid']} base {r['base']} "
                  f"combo {r['combo']} gems {r['gems']} pc {r['apc']}/{r['vpc']} lvl {r['lvl']} -> dmg {r['dmg']} "
                  f"pred {r['pred']} {ok} react {r['react']} hp {r['hp']}")
    elif sys.argv[1] == 'frames':
        fr = load(sys.argv[2]); p = int(sys.argv[3]) - 1
        k, m = (int(x) for x in sys.argv[4].split('/'))
        prev = None
        for i, (ps, g) in enumerate(fr):
            q = player(ps[p])
            if (q['kind'], q['mot']) == (k, m):
                if prev != i - 1: print('--- start', i)
                rr = ' '.join(f'{s[3]:.0f}' for s in q['att'])
                print(f"{i:6d} step {q['step']} hid {q['hid']} aset {q['aset']} bset {q['bset']} att r [{rr}]")
                prev = i


def timing(name):
    """Every logged motion with hit steps: predicted (hit, attack set, body set) per motion frame vs the log."""
    import json
    fr = load(name)
    data = {}
    ok = bad = 0
    per = {}
    for p in (0, 1):
        start = None; key = None
        for i in range(len(fr)):
            q = player(fr[i][0][p])
            k = (q['ch'], q['kind'], q['mot'])
            if i == 0 or k != prev or q['step'] < prevstep:
                start, key = i, k
            prev, prevstep = k, q['step']
            if q['ch'] not in data:
                data[q['ch']] = json.load(open(f"./game/assets/ripped/{H.pname(q['ch']).lower()}_hit.json"))
            mv = data[q['ch']]['moves'].get(f"k{q['kind']}_{q['mot']:03d}")
            if not mv: continue
            t = i - start
            hid = 0; pa = pb = None
            for s in mv:
                if s[2]: hid = s[2]
                if s[0] <= t < s[0] + s[1]: pa, pb = s[3], s[4]; break
            if pa is None: hid, pa, pb = 0, 0, 0
            good = (pa == q['aset'] and (pa == 0 or hid == q['hid']))
            ok += good; bad += not good
            e = per.setdefault(f"c{q['ch']} k{q['kind']}/{q['mot']}", [0, 0]); e[0 if good else 1] += 1
    return ok, bad, per


def derive(names, out):
    """From logged fights: body sets of motions without hit steps (counted once per motion occurrence, so long idles
    between demo fights don't swamp it) and hit ids the game's code arms during live attack sets."""
    import json
    from collections import Counter, defaultdict
    code, bdef, data = defaultdict(Counter), defaultdict(Counter), {}
    for name in names:
        fr = load(name)
        for p in (0, 1):
            prev = None
            for i in range(len(fr)):
                q = player(fr[i][0][p]); ch = q['ch']
                if ch > 10: continue
                if ch not in data:
                    data[ch] = json.load(open(f"./game/assets/ripped/{H.pname(ch).lower()}_hit.json"))
                key = f"k{q['kind']}_{q['mot']:03d}"
                mv = data[ch]['moves'].get(key)
                if q['aset'] and q['hid'] and not (mv and any(s[2] for s in mv)): code[(ch, key)][q['hid']] += 1
                if not mv and (ch, key) != prev: bdef[(ch, key)][q['bset']] += 1
                prev = (ch, key)
    by = defaultdict(dict)
    for (ch, key), c in sorted(bdef.items()): by[ch][key] = c.most_common(1)[0][0]
    # projectile / effect hits: the move arms a type-3/4 record but its flying object carries another one. Invert the
    # formula on every logged hit of that move; keep the base only when one integer explains all of them.
    samples = defaultdict(list)
    for name in names:
        for r in hits(name):
            if r['dmg'] >= 200 or r['hid'] < 0 or r['rtype'] not in (3, 4): continue
            key = f"k{r['move'][0]}_{r['move'][1]:03d}"
            armed = {s[2] for s in data.get(r['ach'], {}).get('moves', {}).get(key, []) if s[2]}
            if r['hid'] in armed and r['pred'] != r['dmg']: samples[(r['ach'], key)].append(r)
    proj = {}
    for (ch, key), rs in samples.items():
        fits = [b for b in range(1, 121) if all(H.damage(b, r['vch'], combo_hits=r['combo'], attacker_gems=r['gems'],
                attacker_pc=bool(r['apc']), victim_pc=bool(r['vpc']), cpu_level=r['lvl'], attacker_cpu=True,
                victim_cpu=True, rtype=r['rtype']) == r['dmg'] for r in rs)]
        if fits and len(rs) >= 2: proj[f'{ch}/{key}'] = fits[0]
    json.dump({'source': 'tools/hitlog.py derive ' + ' '.join(names),
               'code_hits': {f'{ch}/{key}': v.most_common(1)[0][0] for (ch, key), v in code.items()},
               'proj_base': proj,
               'body_default': {str(ch): by[ch] for ch in by}}, open(out, 'w'), indent=0)
    return len(code), sum(len(v) for v in by.values()), proj


if __name__ == '__main__' and sys.argv[1] == 'derive':
    print(derive(sys.argv[3:], sys.argv[2]))
