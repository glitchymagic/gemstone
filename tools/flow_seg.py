#!/usr/bin/env python3
"""fx-flow: tools/flowlog.py capture (.bin) -> one line per run of (phase, MV_OK, both players state/kind/motion) with its
start frame and length: flow_seg.py LOG.bin > LOG.seg"""
import sys, json
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import flowlog
rows = flowlog.decode(sys.argv[1])
key = lambda r: (r['phase'], r['mvok'], tuple((p['st'], p['kind'], p['mot']) for p in r['p']))
prev = None; start = 0
for r in rows:
    k = key(r)
    if k != prev:
        if prev is not None:
            print(f"{start:6d} +{r['f']-start:5d} ph{prev[0]} mv{prev[1]} P1 st{prev[2][0][0]:2d} k{prev[2][0][1]}/{prev[2][0][2]:<3d} P2 st{prev[2][1][0]:2d} k{prev[2][1][1]}/{prev[2][1][2]:<3d} clk{last['clock']} hp{last['p'][0]['hp']}/{last['p'][1]['hp']}")
        prev = k; start = r['f']
    last = r
print(f"{start:6d} +{rows[-1]['f']-start+1:5d} (end) ph{prev[0]}")
