#!/usr/bin/env python3
"""BUG-36: turn a tools/sndlog.py run (AICA channel changes + reflog rows + sound RAM) into key-on events with the
sample each one starts and what both fighters were doing.
- Banks: every DTPK file on the disc (rip/fs) is placed in the run's sound RAM dump by matching file bytes (several
  64-byte chunks from the sample area must agree on one base). The header is patched by the driver, so the header is
  not used for the match.
- Key-on = a channel whose KYONB (+0x00 bit 14) goes 0 -> 1, or whose start address changes while KYONB stays set.
  SA = (+0x00 & 0x7F) << 16 | +0x04; PCMS = +0x00 bits 8-7 (0 PCM16, 1 PCM8, 2 ADPCM); pitch = 44100 * 2^OCT *
  (1 + FNS / 1024) (OCT = +0x18 bits 14-11 signed, FNS bits 9-0); TL = +0x28 bits 15-8 (attenuation, ~0.375 dB / step);
  DISDL = +0x24 bits 11-8 (direct level, 15 = 0 dB, -3 dB / step), DIPAN = bits 4-0.
- Sample = (bank, index) when SA is a listed sample's start, else (bank, '+0xOFFSET') inside the bank.
  sndmap.py banks RUN | keys RUN   (RUN = a name in $SND_OUT)"""
import functools, json, os, struct, sys
import numpy as np

WT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
FS = WT + 'rip/fs/'
OUT = os.environ.get('SND_OUT', '/tmp/ps-fx-snd/disc/')


@functools.lru_cache(None)
def bank_files():
    out = {}
    for f in sorted(os.listdir(FS)):
        if f.endswith('.BIN'):
            with open(FS + f, 'rb') as h:
                if h.read(4) == b'DTPK': out[f[:-4]] = open(FS + f, 'rb').read()
    return out


@functools.lru_cache(None)
def samples(bank):
    """[(index, offset in file, fmt byte, sample count, bytes)] from the DTPK sample table (tools/dtpk.py layout)"""
    d = bank_files()[bank]
    tab = struct.unpack_from('<I', d, 0x3C)[0]
    n = struct.unpack_from('<I', d, tab)[0]
    out = []
    for i in range(n):
        e = tab + 4 + i * 16
        ofs = struct.unpack_from('<I', d, e)[0] & 0xFFFFFF
        a, b = struct.unpack_from('<HH', d, e + 4)
        size = struct.unpack_from('<I', d, e + 12)[0]
        out.append((i, ofs, d[e + 3], b, size))
    return out


def place(ram):
    """{bank: base address in sound RAM (byte offset from 0x00800000)} for every bank whose sample bytes are there."""
    res = {}
    for name, d in bank_files().items():
        if len(d) > len(ram): continue
        sm = samples(name)
        if not sm: continue
        lo = min(s[1] for s in sm)
        probes = [lo + (len(d) - lo) * k // 8 for k in range(8)]
        probes = [p for p in probes if p + 64 <= len(d)]
        bases = {}
        for p in probes:
            chunk = d[p:p + 64]
            if len(set(chunk)) < 8: continue   # silence: matches anywhere
            i = ram.find(chunk)
            while i >= 0:
                bases[i - p] = bases.get(i - p, 0) + 1
                i = ram.find(chunk, i + 1)
        good = []
        r = np.frombuffer(ram, np.uint8); dd = np.frombuffer(d, np.uint8)
        for b, c in bases.items():   # the whole sample area must be there (stage banks share samples: partial matches)
            if c < max(3, len(probes) // 2) or b < 0 or b + len(d) > len(ram): continue
            if (r[b + lo:b + len(d)] == dd[lo:]).mean() >= 0.97: good.append(b)
        if good: res[name] = sorted(good)
    return res


def read_keys(path):
    rows = []
    for ln in open(path):
        w = ln.split()
        rows.append((int(w[0]), int(w[1]), *[int(x, 16) for x in w[2:]]))
    return rows


def keyons(keys):
    """[(frame, ch, sa, pcms, lsa, lea, oct, fns, disdl, dipan, tl)] for every key-on (see module doc)."""
    st = {}
    out = []
    for k, ch, r0, r4, r8, rc, r18, r24, r28 in keys:
        on = bool(r0 & 0x4000)
        sa = ((r0 & 0x7F) << 16) | r4
        prev = st.get(ch)
        st[ch] = (on, sa)
        if k == 0 or not on: continue   # frame 0 = the baseline of every channel
        if prev is None or not prev[0] or prev[1] != sa:
            o = (r18 >> 11) & 0xF
            o = o - 16 if o >= 8 else o
            out.append((k, ch, sa, (r0 >> 7) & 3, r8, rc, o, r18 & 0x3FF, (r24 >> 8) & 0xF, r24 & 0x1F, (r28 >> 8) & 0xFF))
    return out


def resolver(ram, banks):
    """sa -> (bank, index | '+0xOFS') using the placement (a bank loaded twice: either copy)."""
    spans = []
    for b, bases in banks.items():
        for base in bases:
            spans.append((base, base + len(bank_files()[b]), b))
    starts = {}
    for b0, b1, b in spans:
        for i, ofs, fmt, n, size in samples(b):
            starts[b0 + ofs] = (b, i)

    def res(sa):
        if sa in starts: return starts[sa]
        for b0, b1, b in spans:
            if b0 <= sa < b1: return (b, '+0x%X' % (sa - b0))
        return ('?', '0x%X' % sa)
    return res


def hz(o, fns):
    return round(44100 * 2.0 ** o * (1 + fns / 1024.0))


def load(run):
    ram = open(OUT + run + '_sndram.bin', 'rb').read()
    banks = place(ram)
    res = resolver(ram, banks)
    ks = keyons(read_keys(OUT + run + '.keys'))
    rows = [json.loads(l) for l in open(OUT + run + '.jsonl')]
    ev = []
    for k, ch, sa, pcms, lsa, lea, o, fns, dl, pan, tl in ks:
        b, i = res(sa)
        ev.append(dict(f=k, ch=ch, bank=b, s=i, sa=sa, pcms=pcms, hz=hz(o, fns), oct=o, fns=fns, dl=dl, pan=pan, tl=tl,
                       lea=lea))
    return banks, ev, rows


if __name__ == '__main__':
    run = sys.argv[2]
    banks, ev, rows = load(run)
    if sys.argv[1] == 'banks':
        for b, v in sorted(banks.items(), key=lambda x: x[1]): print(b, [hex(x) for x in v], len(bank_files()[b]))
    else:
        for e in ev:
            r = rows[e['f']] if e['f'] < len(rows) else None
            ps = ' | '.join(f"st{p['st']:>2} k{p['kind']}/{p['mot']:<3} f{p['fr']:<3} hp{p['hp']}" for p in r['p']) if r else ''
            print(f"{e['f']:5d} ch{e['ch']:<2} {e['bank']:>7} {str(e['s']):>9} {e['hz']:6d}Hz tl{e['tl']:<3} dl{e['dl']:<2} "
                  f"pan{e['pan']:<2} | {ps}")
