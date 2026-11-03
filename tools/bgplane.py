#!/usr/bin/env python3
"""The game's background plane colour per stage, read out of Flycast's video memory during real fights (pass 4).
The PowerVR draws ISP_BACKGND_T's polygon wherever nothing else covers the screen; Power Stone keeps it at the start of
the parameter buffer (ISP_BACKGND_T = 0x01000000: tag 0, skip 1), i.e. 32-bit VRAM PARAM_BASE + 0: ISP, TSP, TCW words,
then 3 vertices (x, y, z, packed ARGB). tools/stagefight.py peeks both buffers (0xA5000000 / 0xA5400000) + PARAM_BASE.
  bgplane.py LOG STAGEMAP [LOG STAGEMAP ...]    STAGEMAP = TAGPREFIX=STGn0,... (which dump tag was on which stage)
     -> per stage the vertex colours seen (all reads), written to game/assets/ripped/stgn0_info.json "bg_argb"
  e.g. bgplane.py work/flycast_sfR.log sfR0=STG00,sfR1=STG60 work/bgplane_peeks.txt -"""
import collections, json, re, sys
R = './'


def reads(log):
    """[(tag, PARAM_BASE, [16 words at the buffer PARAM_BASE points to])] in log order."""
    out, tag, pb, words = [], None, None, {}
    for line in open(log):
        m = re.search(r'mark (\S+)', line)
        if m: tag, pb, words = m.group(1), None, {}; continue
        m = re.search(r'peek ([0-9A-F]{8}): (.*)$', line.strip())
        if not m: continue
        a, vals = int(m.group(1), 16), [int(x, 16) for x in m.group(2).split()]
        if a == 0xA05F8020: pb = vals[0]
        elif a in (0xA5000000, 0xA5400000): words[a] = vals
        if tag and pb is not None and len(words) == 2:
            out.append((tag, pb, words.get(0xA5000000 + (pb & 0xF00000), words[0xA5000000])))
            words = {}
    return out


def vertex_colours(w):
    return [w[3 + 4 * k + 3] for k in range(3)] if len(w) >= 15 else []


def main(args):
    seen = collections.defaultdict(collections.Counter)
    i = 0
    while i < len(args):
        log, smap = args[i], args[i + 1]; i += 2
        if smap == '-':   # pre-labelled lines: "STGn0 TAG [drive] ... peek A5000000: words"
            for line in open(log):
                if line.startswith('STG') and 'peek' in line:
                    stg = line.split()[0]
                    w = [int(x, 16) for x in line.split('peek A5000000:')[1].split()]
                    seen[stg][' '.join(f'{c:08X}' for c in vertex_colours(w))] += 1
            continue
        pre = dict(kv.split('=') for kv in smap.split(','))
        for tag, pb, w in reads(log):
            stg = next((v for k, v in sorted(pre.items(), key=lambda kv: -len(kv[0])) if tag.startswith(k)), None)
            if stg:
                seen[stg][' '.join(f'{c:08X}' for c in vertex_colours(w))] += 1
    for stg, c in sorted(seen.items()):
        tri, n = c.most_common(1)[0]
        print(stg, dict(c))
        ip = R + f'game/assets/ripped/{stg.lower()}_info.json'
        try:
            info = json.load(open(ip))
        except OSError:   # Londo is laid out by hand in arena.gd: its info file holds only the background
            info = {}
        vs = [int(x, 16) for x in tri.split()]
        info['bg_argb'] = tri.split()
        info['bg_note'] = ('the game\'s PowerVR background plane (ISP_BACKGND_T polygon read from Flycast VRAM in a real '
                           'fight, tools/bgplane.py): ARGB at screen (0,0), (640,0), (0,480), shaded as a plane over the '
                           'whole screen; its TSP word 0x20880440 is an opaque copy (src ONE, dst ZERO), so the alpha byte '
                           'is ignored and the RGB shows (Final Valgas: 000E3C5D = deep blue)')
        info['bg_rgb'] = [[(v >> 16) & 255, (v >> 8) & 255, v & 255] for v in vs]
        json.dump(info, open(ip, 'w'), indent=1)


if __name__ == '__main__':
    main(sys.argv[1:])
