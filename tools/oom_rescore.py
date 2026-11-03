#!/usr/bin/env python3
"""Re-score any PS_AUDIT log (tests/match_movie.gd) for out-of-map frames with THIS checkout's area files, the same
rule for a before and an after run: a fighter's feet outside the original's area (sdf < -5 cm - its reach), or
standing / lying (idle, run, down, get-up at one height 10 frames, fight phase, no cinematic) with no floor of the
original within 35 cm (centre and 25 cm round it).
  oom_rescore.py LOG.jsonl STAGE   -> 'frames N out_xz A out_floor B (any C)'"""
import base64, json, sys, os
import numpy as np
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'


def main():
    log, st = sys.argv[1], sys.argv[2]
    a = json.load(open(R + f'game/assets/fidelity/{st}_area.json'))
    g = a['sdf']; S = np.frombuffer(base64.b64decode(g['i16']), dtype='<i2').reshape(g['h'], g['w'])
    f = a['floor']; F = np.frombuffer(base64.b64decode(f['i16']), dtype='<i2').reshape(f['h'], f['w'], f['n'])
    def sdf(x, z):
        j = (x - g['x0']) / g['cell']; i = (z - g['z0']) / g['cell']
        i, j = int(round(i)), int(round(j))
        return float(S[i, j]) if 0 <= i < g['h'] and 0 <= j < g['w'] else -1e4
    def near(x, y, z):
        anyv = False
        for ox, oz in ((0, 0), (25, 0), (-25, 0), (0, 25), (0, -25)):
            j = int(round((x + ox - f['x0']) / 25)); i = int(round((z + oz - f['z0']) / 25))
            if not (0 <= i < f['h'] and 0 <= j < f['w']): continue
            for v in F[i, j]:
                if v == -32768: continue
                anyv = True
                if abs(v - y) <= 35: return True
        return not anyv
    n = oxz = ofl = oany = 0
    hist = {}
    for l in open(log):
        r = json.loads(l); n += 1
        bxz = bfl = False
        for k, p in enumerate(r['p']):
            x, y, z = (v * 100 for v in p['pos'])
            h = hist.setdefault(k, []); h.append(y); del h[:-10]
            if sdf(x, z) < -15: bxz = True
            # standing / running / lying / getting up (remaster states 0 1 7 8) at one height for 10 frames (longer
            # than the 8-frame hit-stop), in the fight (no cinematic, no replay): resting on something
            elif r['ph'] == 1 and r.get('cine', '') == '' and p['st'] in (0, 1, 7, 8) and len(h) == 10 \
                    and max(h) - min(h) < 0.5 and not near(x, y, z): bfl = True
        oxz += bxz; ofl += bfl; oany += (bxz or bfl)
    print(f'frames {n} out_xz {oxz} out_floor {ofl} any {oany}')


if __name__ == '__main__':
    main()
