#!/usr/bin/env python3
"""BUG-14: score the disc's health-recovery rule (docs/HEALTH.md) on every logged frame and hit.

The rule (1ST_READ, see HEALTH.md): per player s16 health +0x71D4, s16 recoverable ceiling +0x71D6, u8 counter +0x720F.
  every frame 0x0C055566: cnt = (cnt - 1) & 0xFF; if cnt == 0 and hp < ceil: hp += 1, cnt = 40
  a hit (0x0C08E16C..0x0C08E2DE, d = the hit's damage):
    attacker combo (+0x720E) == 1 and hp != ceil  ->  ceil = hp            (a new combo forfeits what is still pending)
    record b4 == 0 and option byte 0x0C7F4767 == 0  ->  hp -= d; ceil -= trunc(d * 0.19999999f); ceil = max(ceil, hp)
    otherwise (throws 2, PC 3/4, objects 5, 7 ...)  ->  hp -= d; ceil = hp            (nothing comes back)
    cnt = 40
The logs (.bin) carry +0x71D4..7 (hp, ceil) and +0x720C..F (combo, counter) per frame, so both halves are checked
directly: the tick on every quiet frame, the ceiling after every hit (and the remaster's provisional floor(d * 7/8)).

  health_check.py [LOG.bin ...]      default: dumps/fidelity/o_*.bin + dumps/fidelity/cpu/cpu_*.bin
  health_check.py --json OUT.json    also write every hit (who, motion, hid, record type, d, ceil before/after)"""
import glob, json, os, struct, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import reflog as RL
R = './'
F02 = np.float32(np.frombuffer(bytes.fromhex('cccc4c3e'), '<f4')[0])   # 0x3e4ccccc
IDS = RL.IDS


def layout(path):
    """field list per player + global list + extra per-player AI block for a log .bin"""
    if '/cpu/' in path:
        import cpu_stats as CS
        return CS.PF, CS.AF, CS.GF
    return RL.PFIELDS, [], RL.GFIELDS


def decode(path):
    PF, AF, GF = layout(path)
    fs = 2 * (sum(n for _, n in PF) + sum(n for _, n in AF)) + sum(n for _, n in GF)
    raw = open(path, 'rb').read()
    js = path[:-4] + '.jsonl'
    if os.path.exists(js):   # older CPU logs lack the last global (0x0C7F2E44): 308 bytes a frame, not 312
        n = sum(1 for _ in open(js))
        if n and len(raw) % n == 0 and len(raw) // n != fs:
            GF = GF[:-1] if len(raw) // n == fs - GF[-1][1] else GF
            fs = len(raw) // n
    rows = []
    for f in range(len(raw) // fs):
        fr = raw[f * fs:(f + 1) * fs]
        pos, ps = 0, []
        for _ in range(2):
            d = {}
            for o, n in PF:
                d[o] = fr[pos:pos + n]; pos += n
            pos += sum(n for _, n in AF)
            p = RL._player(d)
            p['ceil'] = struct.unpack('<h', d[0x71D4][2:4])[0]
            p['cnt'] = d[0x720C][3]
            ps.append(p)
        g = {}
        for a, n in GF:
            g[a] = fr[pos:pos + n]; pos += n
        rows.append(dict(f=f, p=ps, phase=g[0x0C7F302C][0]))
    return rows


def chars(path):
    b = os.path.basename(path)[:-4]
    if '/cpu/' in path:
        m = json.load(open(path[:-4] + '.meta.json'))
        return m['p1'], m['p2']
    t = R + f'game/tests/tapes/{b[2:]}.tape'
    if os.path.exists(t):
        import tapes
        m = tapes.meta(t)
        return m.get('p1'), m.get('p2')
    return None, None


_HITS = {}
def rec_type(ch, hid):
    if ch not in IDS or ch == 'finalvalgas': return None
    n = IDS.index(ch)
    if n not in _HITS:
        p = R + f'game/assets/ripped/p{n}0_hit.json'
        _HITS[n] = json.load(open(p))['hits'] if os.path.exists(p) else {}
    h = _HITS[n].get(str(hid))
    return None if h is None else h.get('type')


def rec_amount(d):
    """the disc: d - trunc(d * 0.19999999f) comes back (d = the int damage; trunc(0.2 x) == trunc(0.2 trunc(x)))"""
    return int(d) - int(np.float32(d) * F02)


def check(path, hits_out):
    rows = decode(path)
    c1, c2 = chars(path)
    st = dict(tick=0, tick_ok=0, tick_bad=[], hits=0, rec_ok=0, rec_fit=0, rec_78=0, nrec=0, nrec_ok=0, cancel=0,
              cancel_ok=0, other=[], cnt_set=0, frozen={}, rec_range=0, prov_same=0, prov_more=0, prov_less=0)
    for t in range(1, len(rows)):
        a, b = rows[t - 1], rows[t]
        for i in range(2):
            p0, p1 = a['p'][i], b['p'][i]
            o0, o1 = a['p'][1 - i], b['p'][1 - i]
            if p1['hp'] < p0['hp'] and p0['hp'] >= 0:   # a hit (or a KO)
                d = p0['hp'] - p1['hp']
                st['hits'] += 1
                pre = p0['ceil']
                cancel = o1['combo'] == 1 and p0['hp'] != p0['ceil']
                if cancel: pre = p0['hp']
                ko = p1['hp'] <= 0
                rec_c = max(p1['hp'], pre - int(np.float32(d) * F02))
                kind = 'rec' if p1['ceil'] > p1['hp'] else 'nrec'
                ty = rec_type((c1, c2)[1 - i], o1['hid'])
                h = dict(log=os.path.basename(path), f=b['f'], victim=(c1, c2)[i], attacker=(c1, c2)[1 - i], d=d,
                         hp0=p0['hp'], hp1=p1['hp'], ceil0=p0['ceil'], ceil1=p1['ceil'], cnt1=p1['cnt'],
                         combo=o1['combo'], cancel=cancel, att=[o1['st'], o1['kind'], o1['mot'], o1['hid'], o1['pc']],
                         vic=[p1['st'], p1['kind'], p1['mot'], p1['pc']], rtype=ty, cls=kind, ko=ko)
                if p1['cnt'] == 40: st['cnt_set'] += 1
                if not ko:
                    # the remaster's provisional rule (fighter.gd receive_hit: rec_left = floor(d x 7/8) of this hit only,
                    # 0 when the attacker is in Power Change or grabbing) against what the disc leaves pending
                    prov = 0 if (o1['pc'] or o1['st'] in (28, 37)) else d * 7 // 8
                    disc = max(0, p1['ceil'] - p1['hp'])
                    st['prov_same' if prov == disc else ('prov_more' if prov > disc else 'prov_less')] += 1
                    if kind == 'rec':
                        st['rec_ok'] += p1['ceil'] == rec_c
                        # the damage is a float (gem / Power Change / CPU level factors) truncated: trunc(0.2 x) is
                        # either that of the int damage or one more; a recovery tick may come first in the same frame
                        lo, hi = int(np.float32(d) * F02), int(np.float32(d + 0.999) * F02)
                        st['rec_range'] += any(pre - k - p1['ceil'] in (0,) for k in range(lo, hi + 1)) or \
                            any(pre + 1 - k - p1['ceil'] == 0 for k in range(int(np.float32(d + 1) * F02), int(np.float32(d + 1.999) * F02) + 1))
                        st['rec_fit'] += 1
                        st['rec_78'] += (p1['ceil'] - p1['hp']) == (p0['ceil'] - p0['hp'] if not cancel else 0) + d * 7 // 8
                    else:
                        st['nrec'] += 1
                        st['nrec_ok'] += p1['ceil'] == p1['hp']
                    if cancel:
                        st['cancel'] += 1
                        st['cancel_ok'] += p1['ceil'] in (rec_c, p1['hp'])
                h['pred_ok'] = (p1['ceil'] == rec_c) if kind == 'rec' else (p1['ceil'] == p1['hp'])
                hits_out.append(h)
                continue
            if p1['hp'] > p0['hp'] + 1 or p1['ceil'] > p0['ceil']:   # a heal (food) or a round reset
                st['other'].append((b['f'], i, p0['hp'], p1['hp'], p0['ceil'], p1['ceil'])); continue
            # a quiet frame: the tick
            cnt = (p0['cnt'] - 1) & 0xFF; hp = p0['hp']
            if cnt == 0 and p0['hp'] < p0['ceil'] and p0['hp'] >= 0: hp += 1; cnt = 40
            if b['phase'] != 3: continue   # the recovery runs in the fight phase only (it stands still in 0-2, 4-9)
            st['tick'] += 1
            if (hp, cnt) == (p1['hp'], p1['cnt']): st['tick_ok'] += 1
            elif (p0['hp'], p0['cnt']) == (p1['hp'], p1['cnt']):   # not called this frame: a world freeze?
                why = 'transform' if 23 in (p1['st'], o1['st'], p0['st'], o0['st']) else \
                    'pc_attack' if 11 in (p1['st'], o1['st']) else 'other'
                st['frozen'][why] = st['frozen'].get(why, 0) + 1
                if why == 'other': st['tick_bad'].append(dict(f=b['f'], i=i, phase=b['phase'], hp=(p0['hp'], p1['hp']), cnt=(p0['cnt'], p1['cnt']),
                                             ceil=p0['ceil'], st=(p1['st'], o1['st']), fr=(p0['fr'], p1['fr'], o0['fr'], o1['fr'])))
            else: st['tick_bad'].append(dict(f=b['f'], i=i, phase=b['phase'], hp=(p0['hp'], p1['hp']), cnt=(p0['cnt'], p1['cnt']),
                                             ceil=p0['ceil'], st=(p1['st'], o1['st']), fr=(p0['fr'], p1['fr'], o0['fr'], o1['fr'])))
    return st


def main(args):
    jout = None
    if args and args[0] == '--json': jout, args = args[1], args[2:]
    logs = args or sorted(glob.glob(R + 'dumps/fidelity/o_*.bin')) + sorted(glob.glob(R + 'dumps/fidelity/cpu/cpu_*.bin'))
    hits = []
    tot = dict(tick=0, tick_ok=0, hits=0, rec_ok=0, rec_fit=0, rec_78=0, nrec=0, nrec_ok=0, cancel=0, cancel_ok=0,
               cnt_set=0, rec_range=0, prov_same=0, prov_more=0, prov_less=0)
    bad = []; frozen = {}
    for p in logs:
        s = check(p, hits)
        for k in tot: tot[k] += s[k]
        for x in s['tick_bad']: x['log'] = os.path.basename(p); bad.append(x)
        for k, v in s['frozen'].items(): frozen[k] = frozen.get(k, 0) + v
    print(f"{len(logs)} logs")
    print(f"quiet fight-phase frames: {tot['tick']}, the tick rule exact on {tot['tick_ok']} ({100 * tot['tick_ok'] / max(1, tot['tick']):.3f}%);"
          f" not ticked (health + counter held) {frozen}, other mismatches {len(bad) - frozen.get('other', 0)}")
    print(f"hits: {tot['hits']}, counter set to 40 on {tot['cnt_set']}")
    print(f"  recoverable (ceiling above health after the hit): {tot['rec_fit']}, the disc's ceiling rule exact on "
          f"{tot['rec_ok']} with the int damage, {tot['rec_range']} with the float damage's range; floor(d*7/8) on {tot['rec_78']}")
    print(f"  the remaster's provisional rule leaves the disc's pending amount after {tot['prov_same']} hits, more after "
          f"{tot['prov_more']}, less after {tot['prov_less']}")
    print(f"  nothing back: {tot['nrec']}, ceiling = health on {tot['nrec_ok']}")
    print(f"  first hit of a new combo with health still pending: {tot['cancel']}, consistent {tot['cancel_ok']}")
    from collections import Counter
    if bad:
        print('tick mismatches by phase / (hp changed, cnt changed):',
              Counter((x['phase'], x['hp'][0] != x['hp'][1], x['cnt'][0] != x['cnt'][1]) for x in bad).most_common(12))
    ty = Counter((h['cls'], h['rtype'], h['att'][4] > 0) for h in hits if not h['ko'])
    print('hits by (class, attack record b4 of the attacker hid, attacker in PC):')
    for k, v in sorted(ty.items(), key=lambda kv: -kv[1]): print('  ', k, v)
    if jout:
        json.dump(dict(totals=tot, tick_bad=bad[:2000], hits=hits), open(jout, 'w'), indent=0)
        print('->', jout)


if __name__ == '__main__':
    main(sys.argv[1:])
