#!/usr/bin/env python3
"""BUG-36: the original's sound cues from tools/sndlog.py runs (key-ons + reflog rows, tools/sndmap.py) ->
game/assets/fidelity/sfx_map.json, and the samples it names cut from the disc banks -> game/assets/audio/se/ (untracked).

Every key-on of the disc is explained by one of (key-ons are visible on the SAME vblank as the state / motion change):
  motion  a fighter's motion (kind, id) reaching motion frame F (+0x71A4/5, +0x719E): voices, swings, jumps, steps.
          Key = (fighter, 'kK_MMM', F); P-prefixed keys for the Power Change form (+0x71F3).
  hit     the frame a fighter's health drops: the impact sample, keyed on the ATTACKER's fighter + motion.
  other   no fighter cue on that frame (stage / item / announcer timing): listed, not mapped.
A motion cue is kept when the sample keys on at >= MIN_P of that motion frame's entries in the logs (an entry = the first
frame a fighter shows that (kind, id, frame)); a cue with several samples over its entries = a random pick (weights kept).
Sample banks: fighter banks (FOKER ... VAR_2) belong to that fighter; COMMON / NA are shared; STG0N.BIN is stage stgN0's
own bank (landing / steps / falls on its ground). Stage banks do NOT share an index layout (Londo's body fall STG00 #5 is
STG01 #6; Ryoma's stage lands on #0 / #1, Londo on #0), so a stage sample only plays on the stage it was logged on:
cues keep per-stage entry counts ('ns') and the stage's samples are weighed against those.
  sndcues.py build RUN,RUN,...   (default: every run in $SND_OUT)"""
import collections, glob, json, os, struct, sys, wave
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import sndmap as S
import dtpk
import tapes

WT = S.WT
OUT = S.OUT
SE = WT + 'game/assets/audio/se/'
MAP = WT + 'game/assets/fidelity/sfx_map.json'
BANK_OF = {'falcon': 'FOKER', 'ryoma': 'RYOUM', 'wangtang': 'WANG', 'jack': 'JACK', 'gunrock': 'GANRO', 'galuda': 'GARUD',
           'ayame': 'AYAME', 'rouge': 'RUJYU', 'kraken': 'KRAKN', 'valgas': 'VAR_1', 'finalvalgas': 'VAR_2'}
FIGHTER_OF = {v: k for k, v in BANK_OF.items()}
MIN_P = 0.5
IDS = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas', 'finalvalgas']


def db_of(tl, dl):
    """AICA attenuation -> dB: TL ~0.375 dB a step, direct send level DISDL 15 = 0 dB, -3 dB a step"""
    return round(-tl * 0.375 - (15 - dl) * 3.0, 1)


def sid(bank, s):
    return f'{bank}_{s:03d}' if isinstance(s, int) else f'{bank}_{s}'


def mkey(p):
    return f"{'P' if p.get('pc') else ''}k{p['kind']}_{p['mot']:03d}"


def fkey(who, p):
    """cue owner: kind 2 is the shared motion bank (hits, knockdowns, pick-ups): one cue set '_k2' for every fighter"""
    return '_k2' if p['kind'] == 2 else who


SHARED_K1 = {78, 84, 150, 151, 152, 153, 154}   # object throw, grab, pole swing, object move: one id for every fighter


def pooled(p):
    """kinds 0 / 3 (basic moves, transform / revert / poses) and the shared kind-1 ids keep one more cue set '_all' over
    every fighter, shared / stage samples only: the fallback for a fighter the logs never showed doing it. A pooled cue
    must still pass the 50% rule over all fighters, so an id that meant different moves would drop out on its own."""
    return p['kind'] in (0, 3) or (p['kind'] == 1 and p['mot'] in SHARED_K1)


BROKEN = {'cpu_falcon_finalvalgas'}   # poked straight to Final Valgas: models are his, sound RAM kept Ayame's banks


def runs():
    done = [os.path.basename(p)[:-5] for p in glob.glob(OUT + '*.keys') if os.path.exists(p[:-5] + '.meta.json')]   # finished
    return sorted(x for x in done if x not in BROKEN)


def load_run(run):
    banks, ev, rows = S.load(run)
    meta = json.load(open(OUT + run + '.meta.json'))
    tp = WT + f"game/tests/tapes/{run.split('@')[0]}.tape"
    tm = tapes.meta(tp) if os.path.exists(tp) else {'p1': meta.get('p1', '?'), 'p2': '?'}
    p2 = meta.get('p2', '?')   # ladder.who names the MDT: P00 .. PA0 = fighter 0 .. 10
    p2 = IDS[int(p2[1], 16)] if len(p2) == 3 and p2[0] == 'P' else tm.get('p2', '?')
    who = [tm.get('p1', '?'), p2]
    stg = meta.get('stage', '?')
    sb = next((b for b in banks if b.startswith('STG0')), 'STG0' + stg[3:4].upper())
    return dict(name=run, banks=banks, ev=ev, rows=rows, who=who, stage=stg, sbank=sb)


def gem_drops(R):
    """{(run name, frame)} where a gem count went down, and the shared samples keyed there on >= half of them (the gem
    spill sound: COMMON #28): those key-ons belong to the gem_drop event, never to a motion cue or an impact"""
    fr, c, n = set(), collections.Counter(), 0
    for r in R:
        rows = r['rows']
        byf = collections.defaultdict(list)
        for e in r['ev']: byf[e['f']].append(e)
        for k in range(1, len(rows)):
            for v in (0, 1):
                if rows[k]['p'][v]['gems'] < rows[k - 1]['p'][v]['gems']:
                    n += 1; fr |= {(r['name'], k), (r['name'], k + 1)}
                    c.update({sid(e['bank'], e['s']) for d in (0, 1) for e in byf.get(k + d, []) if e['bank'] == 'COMMON'})
    return fr, {x for x, v in c.items() if v >= 0.5 * max(1, n)}


def analyse(names):
    R = [load_run(n) for n in names]
    GD, GDS = gem_drops(R)
    entries = collections.Counter()           # (fighter, key, frame) -> entries
    entries_st = collections.Counter()        # (fighter, key, frame, stage bank) -> entries
    co = collections.defaultdict(collections.Counter)   # (fighter, key, frame) -> sample -> key-ons on an entry frame
    lv = collections.defaultdict(list)        # sample -> [(db, pan, hz)]
    for r in R:
        rows = r['rows']
        for k in range(1, len(rows)):
            for p in (0, 1):
                a, b = rows[k]['p'][p], rows[k - 1]['p'][p]
                if (a['kind'], a['mot'], a['fr']) != (b['kind'], b['mot'], b['fr']):
                    entries[(fkey(r['who'][p], a), mkey(a), a['fr'])] += 1
                    entries_st[(fkey(r['who'][p], a), mkey(a), a['fr'], r['sbank'])] += 1
                    if pooled(a):
                        entries[('_all', mkey(a), a['fr'])] += 1
                        entries_st[('_all', mkey(a), a['fr'], r['sbank'])] += 1
    explained = []
    for r in R:
        rows = r['rows']
        drop = {k for k in range(1, len(rows)) for v in (0, 1) if rows[k]['p'][v]['hp'] < rows[k - 1]['p'][v]['hp']}
        for e in r['ev']:
            k = e['f']
            if k < 1 or k >= len(rows): explained.append((r, e, 'other', None)); continue
            s = sid(e['bank'], e['s'])
            lv[s].append((db_of(e['tl'], e['dl']), e['pan'], e['hz'], e['pcms'], e['lea']))
            if e['bank'] == 'NA': continue   # the announcer: fight.gd's round flow already says each line
            # shared samples on a health-drop frame are the impact (by attack record, below), never a motion cue: the
            # tapes land each hit on the same motion frame, which would make whiffs sound like hits
            if e['bank'] == 'COMMON' and (k in drop or k - 1 in drop): continue
            if (r['name'], k) in GD and s in GDS: continue   # the gem spill (event gem_drop)
            # a fighter's own voice 0-4 frames after HIS health dropped = the hurt voice (by record, '_hurt_by_rec4')
            vdrop = [p for p in (0, 1) if e['bank'] == BANK_OF.get(r['who'][p]) and any(
                0 < k - d < len(rows) and rows[k - d]['p'][p]['hp'] < rows[k - d - 1]['p'][p]['hp'] for d in range(5))]
            if vdrop: continue
            cands = [p for p in (0, 1) if e['bank'] not in FIGHTER_OF or FIGHTER_OF[e['bank']] == r['who'][p]]
            for p in cands:
                a, b = rows[k]['p'][p], rows[k - 1]['p'][p]
                if (a['kind'], a['mot'], a['fr']) != (b['kind'], b['mot'], b['fr']):
                    ss = s
                    if a['kind'] == 2 and e['bank'] in FIGHTER_OF: ss = 'SELF_%03d' % e['s'] if isinstance(e['s'], int) else s
                    co[(fkey(r['who'][p], a), mkey(a), a['fr'])][ss] += 1
                    if pooled(a) and e['bank'] not in FIGHTER_OF: co[('_all', mkey(a), a['fr'])][ss] += 1
    return R, entries, co, lv, entries_st, GD, GDS


def build(names):
    R, entries, co, lv, entries_st, GD, GDS = analyse(names)
    cues = {}
    # a sample seen once on a motion frame is kept only if it is that fighter's own bank (voices) or the same sample is a
    # repeated cue somewhere else: world sounds (items, stage) land on whatever frame an idle fighter's counter shows
    rep = {s for cnt in co.values() for s, c in cnt.items() if c >= 2}
    for key, cnt in co.items():
        n = entries[key]
        if key[1].endswith('k0_000'): cnt = collections.Counter({s: c for s, c in cnt.items() if c >= 2})
        cnt = collections.Counter({s: c for s, c in cnt.items() if c >= 2 or s.rsplit('_', 1)[0] in FIGHTER_OF or s in rep})
        cnt = collections.Counter({s: c for s, c in cnt.items() if s.rsplit('_', 1)[0] not in FIGHTER_OF or key[0] != '_k2'})
        ns = {sb: entries_st[key + (sb,)] for sb in {x.split('_')[0] for x in cnt if x.startswith('STG')}}
        grp = collections.Counter()   # covered share per group: shared / fighter samples vs n, each stage's vs its n
        for x, c in cnt.items():
            g = x.split('_')[0] if x.startswith('STG') else ''
            grp[g] += c / max(1, ns.get(g, n) if g else n)
        if n == 0 or not cnt or max(grp.values()) < MIN_P: continue
        fighter, mk, fr = key
        cues.setdefault(fighter, {}).setdefault(mk, {})[str(fr)] = {'n': n, 'pick': {s: c for s, c in cnt.most_common()}}
        if ns: cues[fighter][mk][str(fr)]['ns'] = ns
    # hits: health drops -> the sample keyed on that frame that no motion cue explains, by attacker fighter + motion
    hits = collections.defaultdict(collections.Counter)
    hitn = collections.Counter()
    expl = collections.Counter(); unexpl = collections.Counter(); per = collections.Counter()
    for r in R:
        rows = r['rows']
        byf = collections.defaultdict(list)
        for e in r['ev']: byf[e['f']].append(e)
        for k in range(1, len(rows)):
            for v in (0, 1):
                if rows[k]['p'][v]['hp'] < rows[k - 1]['p'][v]['hp']:
                    att = rows[k]['p'][1 - v]
                    hk = (r['who'][1 - v], mkey(att))
                    hitn[hk] += 1
                    for e in byf.get(k, []):
                        s = sid(e['bank'], e['s'])
                        if e['bank'] in ('COMMON',) and not _motion_ok(cues, r, rows, k, e): hits[hk][s] += 1
    # impacts by the attack record's sound byte rec[0x12] (REACT.md: 0x0C0DAB92(rec[0x13]...) family; 99 = none) and the
    # victim's voice by rec[4], from the attacker's hit id (+0x100) -> its 20-byte record (react_code.json, 1ST_READ)
    rx = json.load(open(WT + 'game/assets/fidelity/react_code.json'))['records']
    imp = collections.defaultdict(collections.Counter); impn = collections.Counter()
    hurt = collections.defaultdict(collections.Counter); hurtn = collections.Counter(); hurtd = collections.Counter()
    for r in R:
        rows = r['rows']
        byf = collections.defaultdict(list)
        for e in r['ev']: byf[e['f']].append(e)
        for k in range(4, len(rows)):
            for v in (0, 1):
                if rows[k]['p'][v]['hp'] >= rows[k - 1]['p'][v]['hp']: continue
                a = 1 - v
                hid = next((rows[k - d]['p'][a]['hid'] for d in range(4) if rows[k - d]['p'][a]['hid'] > 0), 0)
                recs = rx.get(r['who'][a], [])
                rec = bytes.fromhex(recs[hid]) if 0 < hid < len(recs) and len(recs[hid]) == 40 else None
                ik = str(rec[0x12]) if rec else '?'
                impn[ik] += 1
                for d in (0, 1):
                    for e in byf.get(k + d, []):
                        if e['bank'] == 'COMMON' and not _motion_ok(cues, r, rows, k + d, e) and not \
                                ((r['name'], k + d) in GD and sid(e['bank'], e['s']) in GDS): imp[ik][sid(e['bank'], e['s'])] += 1
                vb = BANK_OF.get(r['who'][v])
                hk = str(rec[4]) if rec else '?'
                hurtn[hk] += 1
                for d in range(5):
                    for e in byf.get(k + d, []):
                        if e['bank'] == vb and isinstance(e['s'], int): hurt[hk][str(e['s'])] += 1; hurtd[d] += 1
    # events on a fighter's own fields: gem count up (pick-up) / down (knocked out of him), the KO call (round phase
    # 3 -> 4 with his health <= 0: the shared samples on that frame, then his own voice KO_LAG frames later)
    evc = collections.defaultdict(collections.Counter); evn = collections.Counter()
    KO_LAG = 90
    for r in R:
        rows = r['rows']
        byf = collections.defaultdict(list)
        for e in r['ev']: byf[e['f']].append(e)
        for k in range(1, len(rows)):
            for v in (0, 1):
                a, b = rows[k]['p'][v], rows[k - 1]['p'][v]
                kinds = []
                if a['gems'] > b['gems'] and r['name'].startswith('cpu_'): kinds.append('gem')   # tapes set gems by @gems
                if a['gems'] < b['gems']: kinds.append('gem_drop')
                if rows[k]['phase'] == 4 and rows[k - 1]['phase'] == 3 and a['hp'] <= 0: kinds.append('ko')   # the KO call
                for kd in kinds:
                    evn[kd] += 1
                    for d in (0, 1):
                        for e in byf.get(k + d, []):
                            if e['bank'] == 'COMMON' and not _motion_ok(cues, r, rows, k + d, e): evc[kd][sid(e['bank'], e['s'])] += 1
                            if e['bank'] == 'NA' and kd == 'gem_drop': evc[kd][sid(e['bank'], e['s'])] += 1   # "Oh no!" 
                    if kd == 'ko':
                        for d in range(KO_LAG - 3, KO_LAG + 4):
                            for e in byf.get(k + d, []):
                                for who, tag in ((v, 'ko_voice'),):
                                    if e['bank'] == BANK_OF.get(r['who'][who]) and isinstance(e['s'], int):
                                        evc[tag]['SELF_%03d' % e['s']] += 1
    evn['ko_voice'] = evn['ko']
    # a shared sample on under a quarter of a record's hits = something else on that frame (a swing, a step)
    impact = {k: {'n': impn[k], 'pick': {x: v for x, v in c.most_common() if v >= 0.25 * impn[k]}} for k, c in imp.items() if k != '?'}
    hv = {k: {'n': hurtn[k], 'pick': dict(c.most_common())} for k, c in hurt.items() if k != '?'}
    allh = collections.Counter()
    for c in hurt.values(): allh.update(c)
    hv['_any'] = {'n': sum(hurtn.values()), 'pick': dict(allh.most_common())}
    hv['_delay'] = hurtd.most_common(1)[0][0] if hurtd else 2
    hit_map = {}
    anyc = collections.Counter()
    for hk, cnt in hits.items():
        hit_map.setdefault(hk[0], {})[hk[1]] = {'n': hitn[hk], 'pick': dict(cnt.most_common())}
        anyc.update(cnt)
    if anyc:   # an attack the logs never landed: the impact the disc plays most (sfx_map.gd falls back to it)
        s0, c0 = anyc.most_common(1)[0]
        hit_map['_any'] = {'n': c0, 'pick': {s0: c0}}
    used = set()
    for f in cues.values():
        for m in f.values():
            for c in m.values(): used |= set(c['pick'])
    for fk, f in hit_map.items():
        for c in ([f] if fk == '_any' else f.values()): used |= set(c['pick'])
    for c in impact.values(): used |= set(c['pick'])
    for r in R:   # the metric: every effect key-on explained by a cue (motion), an impact / hurt voice or an event
        rows = r['rows']
        for e in r['ev']:
            s = sid(e['bank'], e['s'])
            k = e['f']
            if e['bank'] == 'NA': continue
            ok = 0 < k < len(rows) and _motion_ok(cues, r, rows, k, e)
            if not ok and 0 < k < len(rows):   # events: gem spill, gem pick-up, the KO call (+ the KO'd voice 90 f later)
                if (r['name'], k) in GD and s in GDS: ok = 'event'
                elif any(rows[k - d]['p'][v]['gems'] > rows[k - d - 1]['p'][v]['gems'] for v in (0, 1) for d in (0, 1) if k - d >= 1) \
                        and s in evc.get('gem', {}): ok = 'event'
                elif any(rows[j]['phase'] == 4 and rows[j - 1]['phase'] == 3 for j in list(range(max(1, k - 1), k + 1)) +
                         list(range(max(1, k - 93), max(1, k - 86)))) and (s in evc.get('ko', {}) or e['bank'] in FIGHTER_OF): ok = 'event'
            if not ok and e['bank'] in FIGHTER_OF and any(e['bank'] == BANK_OF.get(r['who'][p]) and 0 < k - d < len(rows) and
                                                         rows[k - d]['p'][p]['hp'] < rows[k - d - 1]['p'][p]['hp'] for p in (0, 1) for d in range(5)):
                ok = 'hurt'
            if not ok and 0 < k < len(rows) and e['bank'] == 'COMMON' and \
                    any(rows[k - d]['p'][v]['hp'] < rows[k - d - 1]['p'][v]['hp'] for v in (0, 1) for d in (0, 1)):
                ok = 'hit'
            (expl if ok else unexpl)[s] += 1
            per[(r['name'], bool(ok))] += 1
    events = {k: {'n': evn[k], 'pick': {x: c for x, c in evc[k].most_common() if c >= 2}} for k in evn if evc[k]}
    for k in ('ko_voice',):
        if k in events: events[k]['delay'] = KO_LAG
    for c in events.values(): used |= {x for x in c['pick'] if not x.startswith('SELF_')}
    smp = {}
    for s in sorted(used):
        l = lv[s] if not s.startswith('SELF_') else [x for b in FIGHTER_OF for x in lv.get(b + s[4:], [])]
        dbs = sorted(x[0] for x in l); hzs = collections.Counter(x[2] for x in l)
        smp[s] = {'db': dbs[len(dbs) // 2], 'hz': hzs.most_common(1)[0][0], 'pan': collections.Counter(x[1] for x in l).most_common(1)[0][0],
                  'n': len(l), 'pcms': collections.Counter(x[3] for x in l).most_common(1)[0][0],
                  'lea': collections.Counter(x[4] for x in l).most_common(1)[0][0]}
    out = {'_doc': 'BUG-36 (docs/SOUND.md): the original\'s sound cues, logged off the AICA in Flycast (tools/sndlog.py, '
                   'tools/sndcues.py). motion[fighter][kK_MMM][motion frame] = {n: entries logged, pick: sample -> '
                   'key-ons}; hit[attacker fighter][attacker kK_MMM] = impact samples on the health-drop frame; '
                   'samples[id] = median dB (TL / DISDL), most common rate Hz, pan. STG0N_nnn = stage stgN0\'s own bank (plays only there; ns = entries per stage).',
           'runs': names, 'samples': smp, 'motion': cues, 'hit': hit_map, 'impact': impact, 'hurt': hv, 'event': events,
           'unexplained': dict(unexpl.most_common()), 'explained': dict(expl.most_common())}
    os.makedirs(os.path.dirname(MAP), exist_ok=True)
    json.dump(out, open(MAP, 'w'), indent=1, sort_keys=True)
    te, tu = sum(expl.values()), sum(unexpl.values())
    print(f'{len(names)} runs, {te + tu} key-ons: {te} explained ({100 * te / max(1, te + tu):.1f}%), {tu} not')
    print('unexplained', unexpl.most_common(15))
    print('impact keys', dict(impn))
    return out


def _motion_ok(cues, r, rows, k, e):
    s = sid(e['bank'], e['s'])
    for p in (0, 1):
        if e['bank'] in FIGHTER_OF and FIGHTER_OF[e['bank']] != r['who'][p]: continue
        a = rows[k]['p'][p]
        c = cues.get(fkey(r['who'][p], a), {}).get(mkey(a), {}).get(str(a['fr']))
        ss = 'SELF_%03d' % e['s'] if a['kind'] == 2 and e['bank'] in FIGHTER_OF and isinstance(e['s'], int) else s
        if c and ss in c['pick']: return True
    return False


def cut(stages=None):
    """every sample sfx_map.json names -> game/assets/audio/se/ID.wav (16-bit mono at the rate the game plays it)."""
    m = json.load(open(MAP))
    os.makedirs(SE, exist_ok=True)
    stg = stages or [f'STG0{n}' for n in '0123456789A']   # stage stgN0's sound bank is STG0N.BIN (stg10 -> STG01)
    for s, info in m['samples'].items():
        bank, idx = s.rsplit('_', 1)
        targets = [(bank, s)]
        for b, name in targets:
            d = S.bank_files().get(b)
            if d is None: continue
            if idx.startswith('+'):   # not in the bank's sample table: start = the key-on's SA, length = its LEA
                ofs, n = int(idx[1:], 16), int(info['lea'])
                size = {0: 2 * n, 1: n}.get(int(info['pcms']), (n + 1) // 2)
                raw = d[ofs:ofs + size]
                pcm = {0: lambda: np.frombuffer(raw[:len(raw) // 2 * 2], '<i2'),
                       1: lambda: np.frombuffer(raw, np.int8).astype(np.int16) << 8}.get(int(info['pcms']), lambda: dtpk.aica(raw))()
            else:
                sm = [x for x in S.samples(b) if x[0] == int(idx)]
                if not sm: continue
                i, ofs, fmt, n, size = sm[0]
                raw = d[ofs:ofs + size]
                if n >= size * 1.9: pcm = dtpk.aica(raw)
                elif n >= size * 0.9: pcm = (np.frombuffer(raw, np.int8).astype(np.int16) << 8)
                else: pcm = np.frombuffer(raw[:len(raw) // 2 * 2], '<i2')
            with wave.open(SE + name + '.wav', 'wb') as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(int(info['hz'])); w.writeframes(pcm.astype('<i2').tobytes())
    idx = {int(x[5:]) for f in m['motion'].values() for mo in f.values() for c in mo.values() for x in c['pick'] if x.startswith('SELF_')}
    idx |= {int(i) for k, c in m.get('hurt', {}).items() if isinstance(c, dict) for i in c['pick']}
    idx |= {int(x[5:]) for c in m.get('event', {}).values() for x in c['pick'] if x.startswith('SELF_')}
    for b in BANK_OF.values():   # the victim's own bank, same index on every fighter's bank (docs/SOUND.md)
        for i, ofs, fmt, n, size in S.samples(b):
            if i not in idx: continue
            raw = S.bank_files()[b][ofs:ofs + size]
            pcm = dtpk.aica(raw) if n >= size * 1.9 else (np.frombuffer(raw, np.int8).astype(np.int16) << 8) if n >= size * 0.9 \
                else np.frombuffer(raw[:len(raw) // 2 * 2], '<i2')
            with wave.open(SE + f'{b}_{i:03d}.wav', 'wb') as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050); w.writeframes(pcm.astype('<i2').tobytes())
    print('cut', len(m['samples']), 'samples ->', SE)


ACTIONS = [('jump (standing / moving)', ['k0_005', 'k0_006', 'k0_010']), ('landing', ['k0_009']), ('run steps', ['k0_025']),
           ('stop', ['k0_026']), ('wall kick', ['k2_206', 'k0_013']), ('pole catch / swing', ['k2_211', 'k1_150', 'k1_151', 'k1_152']),
           ('punch chain (swing + voice)', ['k1_016', 'k1_017', 'k1_018', 'k1_019']), ('kick', ['k1_024', 'k1_025']),
           ('grab', ['k1_084']), ('object throw', ['k1_078']), ('pick-up / carry', ['k2_219', 'k2_220']),
           ('knocked down (fall, voice)', ['k2_152', 'k2_099', 'k2_115']), ('get-up', ['k2_146']),
           ('Power Change / revert', ['k3_008', 'k3_009', 'Pk3_009']), ('intro / win poses', ['k3_000', 'k3_001', 'k3_002', 'k3_003'])]


def table():
    """markdown coverage rows for docs/SOUND.md: action -> samples (key-ons / entries) per cue owner"""
    m = json.load(open(MAP))
    mo = m['motion']
    out = ['| action | motion@frame: samples (key-ons / entries) | fighters with a logged cue |', '|---|---|---|']
    for name, keys in ACTIONS:
        cells, who = [], set()
        for owner in ['_all', '_k2'] + sorted(k for k in mo if not k.startswith('_')):
            for k in keys:
                for fr, c in sorted(mo.get(owner, {}).get(k, {}).items(), key=lambda x: int(x[0])):
                    if owner.startswith('_'):
                        cells.append(f"{k}@{fr}: " + ', '.join(f'{x} {v}/{c.get("ns", {}).get(x[:5], c["n"]) if x.startswith("STG") else c["n"]}' for x, v in list(c['pick'].items())[:3]))
                    else: who.add(owner)
        out.append(f"| {name} | {'; '.join(cells[:6]) or '(per fighter only)'} | {len(who)}: {', '.join(sorted(who))} |")
    imp = m['impact']
    out.append('| hit impact by attack record rec[0x12] | ' + '; '.join(f"{k}: {', '.join(f'{x} {v}/{c[chr(110)]}' for x, v in list(c['pick'].items())[:2])}" for k, c in sorted(imp.items(), key=lambda x: int(x[0]))) + ' | all (records) |')
    h = m['hurt']
    out.append('| hurt voice (own bank, +%d f) | ' % h.get('_delay', 2) + '; '.join(f"rec[4]={k}: {c['pick']} of {c['n']}" for k, c in h.items() if isinstance(c, dict)) + ' | all (same index) |')
    for k, c in m.get('event', {}).items():
        out.append(f"| event {k} | {', '.join(f'{x} {v}/{c[chr(110)]}' for x, v in list(c['pick'].items())[:4])}{' (+%d f)' % c['delay'] if c.get('delay') else ''} | all |")
    return '\n'.join(out)


if __name__ == '__main__':
    if sys.argv[1] == 'build':
        build(sys.argv[2].split(',') if len(sys.argv) > 2 else runs())
    elif sys.argv[1] == 'cut':
        cut()
    elif sys.argv[1] == 'table':
        print(table())
