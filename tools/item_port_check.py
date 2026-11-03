#!/usr/bin/env python3
"""Chests and items: the disc's object log vs the remaster's (fx-item2, BUG-46).
  item_port_check.py [FID_OUT dir] TAPE...
Disc: dumps/fidelity/o_TAPE.obj.jsonl (per row the object pool: [slot, type, owner, kind, b5, x, y, z, +0x30C, +0x30D];
chest = type 2 kind 7, item = type 3 kind 6). Remaster: r_TAPE.objs.jsonl "items" ([7 chest | 6 item, id, x, y, z, sub],
tests/tape_run.gd). Events per chest: the row it appears, its spot (x / z), its item, the row the item appears, the row it
is ready (sub 0), the row the chest is gone. Prints one line per chest and a score (exact rows, +-1 row)."""
import json, os, sys

D = './dumps/fidelity/'


def disc(t):
    rows = [json.loads(l) for l in open(D + f'o_{t}.obj.jsonl')]
    ch, its, open_c, open_i = [], [], {}, {}
    for f, r in enumerate(rows):
        seen_c, seen_i = set(), set()
        for o in r:
            if o[1] == 2 and o[3] == 7:
                if o[0] not in open_c:
                    open_c[o[0]] = {'row': f, 'x': round(o[5]), 'z': round(o[7]), 'id': o[8]}; ch.append(open_c[o[0]])
                open_c[o[0]]['last'] = f; seen_c.add(o[0])
            if o[1] == 3 and o[3] == 6:
                if o[0] not in open_i and o[9] == 16:
                    open_i[o[0]] = {'row': f, 'id': o[8], 'x': round(o[5]), 'z': round(o[7]), 'ready': None}; its.append(open_i[o[0]])
                if o[0] in open_i:
                    seen_i.add(o[0])
                    if o[9] == 0 and open_i[o[0]]['ready'] is None: open_i[o[0]]['ready'] = f
        for k in [k for k in open_c if k not in seen_c]: open_c.pop(k)
        for k in [k for k in open_i if k not in seen_i]: open_i.pop(k)
    return _join(ch, its)


def rem(t, out):
    rows = [json.loads(l) for l in open(out + f'/r_{t}.objs.jsonl')]
    ch, its = [], []
    open_c, open_i = {}, {}
    for r in rows:
        f = r['f']
        seen_c = set()
        for o in r.get('items', []):
            k = (round(o[2]), round(o[4]))
            if o[0] == 7:
                kk = (round(o[2]) // 10, round(o[4]) // 10)
                if kk not in open_c:
                    open_c[kk] = {'row': f, 'x': round(o[2]), 'z': round(o[4]), 'id': o[1]}; ch.append(open_c[kk])
                open_c[kk]['last'] = f; seen_c.add(kk)
            else:
                kk = (o[1], round(o[2]) // 10, round(o[4]) // 10)
                if o[5] == 16 and kk not in open_i:
                    open_i[kk] = {'row': f, 'id': o[1], 'x': round(o[2]), 'z': round(o[4]), 'ready': None}; its.append(open_i[kk])
                if kk in open_i and o[5] == 0 and open_i[kk]['ready'] is None: open_i[kk]['ready'] = f
        for kk in list(open_c):
            if kk not in seen_c: open_c.pop(kk)
    return _join(ch, its)


def _join(ch, its):
    out = []
    for c in ch:
        m = [i for i in its if abs(i['x'] - c['x']) <= 10 and abs(i['z'] - c['z']) <= 10 and c['row'] <= i['row'] <= c.get('last', c['row']) + 2]
        i = m[0] if m else None
        out.append({'row': c['row'], 'x': c['x'], 'z': c['z'], 'id': c['id'], 'gone': c.get('last', c['row']) + 1,
                    'item_row': i['row'] if i else None, 'ready': i['ready'] if i else None})
    return out


def main(out, tapes):
    tot = {'n': 0, 'exact': 0, 'near': 0, 'spot': 0, 'id': 0}
    fx = {'n': 0, 'exact': 0, 'near': 0, 'spot': 0, 'id': 0, 'chests': 0}   # chests 1 and 2: the drop clock's fixed rows
    for t in tapes:
        if not os.path.exists(D + f'o_{t}.obj.jsonl') or not os.path.exists(out + f'/r_{t}.objs.jsonl'):
            print(t, 'missing a side'); continue
        a, b = disc(t), rem(t, out)
        print(f'== {t}: disc {len(a)} chests, remaster {len(b)}')
        for k in range(max(len(a), len(b))):
            x = a[k] if k < len(a) else None
            y = b[k] if k < len(b) else None
            print('  disc', x, '\n  rem ', y)
            if x and y:
                for f in ('row', 'item_row', 'ready', 'gone'):
                    if x[f] is None or y[f] is None: continue
                    tot['n'] += 1
                    tot['exact'] += x[f] == y[f]; tot['near'] += abs(x[f] - y[f]) <= 1
                    if k < 2:
                        fx['n'] += 1; fx['exact'] += x[f] == y[f]; fx['near'] += abs(x[f] - y[f]) <= 1
                if k < 2:
                    fx['chests'] += 1
                    fx['spot'] += abs(x['x'] - y['x']) <= 5 and x['z'] == y['z']
                    fx['id'] += x['id'] == y['id']
                tot['spot'] += (x['x'], x['z']) == (y['x'], y['z']) or abs(x['x'] - y['x']) <= 5 and x['z'] == y['z']
                tot['id'] += x['id'] == y['id']
    print('chests 1-2 (fixed clock): rows exact %d/%d, within 1 row %d/%d, spot %d/%d, item %d/%d' % (
        fx['exact'], fx['n'], fx['near'], fx['n'], fx['spot'], fx['chests'], fx['id'], fx['chests']))
    print('all chests: rows exact %d/%d, within 1 row %d/%d, chest spots %d, items %d' % (tot['exact'], tot['n'], tot['near'], tot['n'], tot['spot'], tot['id']))


if __name__ == '__main__':
    a = sys.argv[1:]
    out = a.pop(0) if a and os.path.isdir(a[0]) else os.environ.get('FID_OUT', D)
    main(out.rstrip('/'), a)
