#!/usr/bin/env python3
"""The ORIGINAL's CPU (AI) data, straight out of 1ST_READ.BIN (docs/CPU.md explains the machine).
The AI is a per-character script interpreter: situations (interrupt classes) pick a script from per-character tables by
CPU level band and rand(); scripts are u16 bytecode (88 opcodes, handler table 0x0C32D7F8, lengths 0x0C32D958) that OR
virtual pad bits into the player's input word +0x2DC, exactly where a human's (remapped) pad goes.

  cpu_ai.py export            -> game/assets/fidelity/cpu_ai.json (every table + every script, for a port)
  cpu_ai.py dis CHAR [SET]    disassemble one fighter's scripts (CHAR = 0..9 or a name; SET = n | oppPC | PC)
  cpu_ai.py ops               opcode table (name, length, handler, uses)
  cpu_ai.py check LOG...      every script selection in CPU-vs-CPU logs (tools/cpu_stats.py) against the tables:
                              (Mode, IntLv) -> situation.sub, level band, PC set -> the logged Table must be a listed
                              script or a library script it calls (2026-10-26: 1182 / 1182)"""
import json, os, struct, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
B = open('./rip/fs/1ST_READ.BIN', 'rb').read()
BASE = 0x0C010000
OUT = os.path.join(os.path.dirname(HERE), 'game/assets/fidelity/cpu_ai.json')
NAMES = ['falcon', 'ryoma', 'wangtang', 'jack', 'gunrock', 'galuda', 'ayame', 'rouge', 'kraken', 'valgas']


def _o(a): return ((a & 0x1FFFFFFF) | 0x0C000000) - BASE
def u32(a): return struct.unpack_from('<I', B, _o(a))[0]
def u16(a): return struct.unpack_from('<H', B, _o(a))[0]
def s16(a): return struct.unpack_from('<h', B, _o(a))[0]
def u8(a): return B[_o(a)]
def isptr(v): return (v >> 24) in (0x0C, 0x8C)


# ---- addresses (all 1ST_READ, loaded at 0x0C010000) ----
OPS_TBL, OPLEN_TBL, NOPS = 0x0C32D7F8, 0x0C32D958, 88
SEL = {'n': 0x0C32D64C, 'oppPC': 0x0C32D6A4, 'PC': 0x0C32D678}     # [char] -> [situation] -> [sub] -> band lists
SCR = {'n': 0x0C32D5C8, 'oppPC': 0x0C32D620, 'PC': 0x0C32D5F4}     # [char] -> [situation] -> [script index] -> code
DIR_TBL = 0x0C32D7E8        # u16[8] pad direction bits per camera-relative 45-degree sector
EVADE_PCT = 0x0C32D768      # u16[32] by CPU level: chance (of 255) to take the 0x800 evade interrupt
THROWN_PCT = 0x0C32D7A8     # u16[32] by CPU level: chance (of 255) for the 0x800 interrupt while being thrown (st 29)
RESP_TBL = 0x0C32D6D0       # u32[char] -> u8[256]: opponent hit id -> sub-table of situation 5
RADIUS_TBL = 0x0C32D6FC     # s16[kind]: subtracted from target distances (0x0C0500CA)
WAYPTS = 0x0C32DB90         # u32[stage] -> xyz f32 points (op 85)

# name, short meaning (REG = AI work +0x26, CNT = +0x18, target = +0x6C/+0x60..+0x68). Exact for the simple ones; the
# movement / search ops are summarised (docs/CPU.md).
OPS = {
    0: ('END', 'stop: work+0x38=0, IntLv=1, Mask=1 (default script next frame), yield'),
    1: ('KEEP_DIST', 'steer to keep d+-20 cm from the target (aim with 10-frame lead past 300 cm)'),
    2: ('PRESS', 'wait for an empty previous pad (+0x2E0), hold BTN 1 frame, next op the frame after'),
    3: ('JUMP', 'hold jump(4) + direction to the opponent (n>0) / away (n<0) for |n| frames'),
    4: ('RUN_TO', 'run toward the target until within d cm (+-20 / +-10 steering)'),
    5: ('OP5', 'unused'),
    6: ('END0', 'unused (same handler as END, length 0)'),
    7: ('ENDIF', 'end of an IF / ELSE block'),
    8: ('ELSE', 'skip to the matching ENDIF'),
    9: ('GOTO', 'tail jump to library script n (situation 0 list)'),
    10: ('CALL', 'call library script n (push ip/target/pos/Mask/IntLv, RET+1)'),
    11: ('RET', 'return from CALL (pop)'),
    12: ('OP12', 'unused'), 13: ('REG_OPP_PC', 'unused: REG = opponent Power Change flag'),
    14: ('REG_HP', 'unused: REG = own health'), 15: ('REG_GEMS', 'unused: REG = own gems'),
    16: ('REG_DIST_T', 'unused: REG = distance to the target'), 17: ('OP17', 'unused'), 18: ('OP18', 'unused'),
    19: ('REG_DIST', 'REG = horizontal distance to the opponent (cm, int)'),
    20: ('REG_OPP_DY', 'REG = opponent.y - own.y (cm)'),
    21: ('REG_OWN_DY', 'REG = own.y - opponent.y (cm)'),
    22: ('REG_FIGHT', 'REG = the arcade fight index (0x0C7F2E46 + 120*player)'),
    23: ('OP23', 'unused'), 24: ('OP24', 'unused'),
    25: ('RAND', 'REG = (u32)(rand()/32768*255) % n'),
    26: ('OP26', 'unused'), 27: ('OP27', 'unused'), 28: ('OP28', 'unused'),
    29: ('IF_GT', 'if REG > n'), 30: ('IF_LT', 'if REG < n'), 31: ('IF_EQ', 'if REG == n'),
    32: ('IF_NZ', 'if REG != 0'), 33: ('IF_Z', 'if REG == 0'),
    34: ('OP34', 'unused'), 35: ('OP35', 'unused'), 36: ('OP36', 'unused'), 37: ('OP37', 'unused'),
    38: ('OP38', 'unused'), 39: ('OP39', 'unused'), 40: ('OP40', 'unused'), 41: ('OP41', 'unused'),
    42: ('WAIT_IDLE', 'yield until own state == 0'),
    43: ('WAIT_LAND', 'yield while own.y > target.y and falling (+0x3C)'),
    44: ('FIND_ITEM', 'target = best item (objects kind 1/18, list *0x0C7E4078, filter 0x0C0AC55C) by '
                      '2*dist(me) - dist(opponent); REG = found'),
    45: ('TARGET_OPP', 'target = the opponent (pointer + position)'),
    46: ('WAIT_FREE', 'yield until own state in {0, 2, 31, 5}'),
    47: ('OP47', 'unused'), 48: ('OP48', 'unused'), 49: ('OP49', 'unused'),
    50: ('MOVE50', 'phased approach move (1 use, rand + target)'),
    51: ('WALK', 'hold the direction to (n>0) / away from (n<0) the aimed target |n| frames, then go on'),
    52: ('OP52', 'unused'),
    53: ('TARGET_ORIGIN', 'target position = (0, 0, 0)'),
    54: ('OP54', 'unused'),
    55: ('APPROACH', 'steer toward the target position (n = distance)'),
    56: ('SIDESTEP', 'strafe +-90 degrees (rand side) for n frames'),
    57: ('REG_OPP_ST', 'REG = opponent state (+0x71BA)'),
    58: ('REG_CARRY', 'REG = own +0x7236 (carrying)'),
    59: ('IF_NE', 'if REG != n'),
    60: ('WAIT', 'yield n frames'),
    61: ('OP61', 'unused'),
    62: ('FIND_POLE', 'target = best object kind 5 (list *0x0C7E407C, height window); REG = found'),
    63: ('MASK_ON', 'Mask |= n'), 64: ('MASK_OFF', 'Mask &= ~n'),
    65: ('OP65', 'unused'), 66: ('OP66', 'unused'),
    67: ('DASH', 'double tap (empty, tap, empty) then hold to / away from the aimed target |n| frames'),
    68: ('OP68', 'unused'), 69: ('OP69', 'unused'),
    70: ('FIND_KIND6', 'target = best object kind 6 (list *0x0C7E407C); REG = found'),
    71: ('FIND_KIND7', 'target = best object kind 7 (list *0x0C7E4078); REG = found'),
    72: ('TARGET_RANDOM', 'target position = (-500 + 10*(rand%100), 0, -500 + 10*(rand%100)) cm'),
    73: ('TARGET_STAGE', 'y<400: x > -z-100 ? (x,0,300) : (-550,0,z); y>=400: x > -z-100 ? (x,0,-100) : (50,0,z)'),
    74: ('REG_OWN_ST', 'REG = own state'),
    75: ('TIMER', 'work+0x14 (script timer, 600 = default) = n'),
    76: ('MOVE_UNTIL_Y', 'steer toward the target until own.y >= n'),
    77: ('CNT_SET', 'CNT = n'), 78: ('REG_CNT', 'REG = CNT'), 79: ('CNT_CLR', 'CNT = 0'),
    80: ('WAIT_GROUND', 'yield until own state in {0, 2, 31}'),
    81: ('WAIT_OPP_FREE', 'yield while opponent state in {27, 24, 15, 16}'),
    82: ('WAIT_7206', 'yield until own +0x7206 (attack presses taken by 0x0C09468C) > +0x7234'),
    83: ('PRESS_DIR', 'like PRESS, then BTN + direction to the target the next frame'),
    84: ('REG_HELD', 'REG = kind of the held object (+0x71C8 -> +0x30C), 0 = none'),
    85: ('TARGET_WAYPT', 'target position = random stage waypoint (0x0C32DB90[stage 0x0C7F3051])'),
    86: ('GRAB', 'hold direction to the target 2 frames, then press punch+kick (0x600)'),
    87: ('WAIT_OPP_71BC', 'yield while opponent +0x71BC == 2'),
}


def oplen():
    return [u8(OPLEN_TBL + i) for i in range(NOPS)]


def handlers():
    return [u32(OPS_TBL + 4 * i) for i in range(NOPS)]


def script(p, maxw=800):
    """[(addr, op, [args])] until the 0xFFFF terminator."""
    L = oplen()
    out, a = [], p
    for _ in range(maxw):
        op = u16(a)
        if op == 0xFFFF:
            break
        if op >= NOPS:
            raise ValueError(f'bad op {op} at {a:08x}')
        n = max(L[op], 1)
        out.append((a, op, [s16(a + 2 * i) for i in range(1, n)]))
        a += 2 * n
    return out


def band_list(p):
    """Selection list: n thresholds (CPU level < t picks that band), then n lists (len, script indices)."""
    n = u8(p)
    th = [u8(p + 1 + i) for i in range(n)]
    q, bands = p + 1 + n, []
    for _ in range(n):
        k = u8(q)
        bands.append([u8(q + 1 + i) for i in range(k)])
        q += 1 + k
    return th, bands


def _ends():
    e = set()
    for t in list(SEL.values()) + list(SCR.values()):
        for c in range(10):
            base = u32(t + 4 * c); e.add(base)
            for s in range(15): e.add(u32(base + 4 * s))
    return sorted(e)


def tables():
    ends = _ends()
    nxt = lambda a: min(x for x in ends if x > a)
    sel, scr, code = {}, {}, {}
    for k in SEL:
        for c in range(10):
            sb, cb = u32(SEL[k] + 4 * c), u32(SCR[k] + 4 * c)
            for s in range(15):
                sp, cp = u32(sb + 4 * s), u32(cb + 4 * s)
                subs = [u32(sp + 4 * i) for i in range((nxt(sp) - sp) // 4)]
                sel[f'{k}/{c}/{s}'] = [band_list(b) for b in subs if isptr(b)]
                ptrs = [u32(cp + 4 * i) for i in range((nxt(cp) - cp) // 4)]
                ptrs = [p for p in ptrs if isptr(p) and u16(p) < NOPS]
                scr[f'{k}/{c}/{s}'] = [f'{p:08x}' for p in ptrs]
                for p in ptrs:
                    if f'{p:08x}' not in code:
                        code[f'{p:08x}'] = [[op] + args for _, op, args in script(p)]
    return sel, scr, code


def export():
    sel, scr, code = tables()
    L, H = oplen(), handlers()
    uses = Counter(c[0] for s in code.values() for c in s)
    resp = {}
    for c in range(10):
        p = u32(RESP_TBL + 4 * c)
        resp[NAMES[c]] = {str(i): u8(p + i) for i in range(256) if u8(p + i)}
    way = {}
    for st in range(10):
        p = u32(WAYPTS + 4 * st)
        way[f'stg{st}0'] = [list(struct.unpack_from('<3f', B, _o(p + 12 * i))) for i in range(4)]
    d = {
        'source': '1ST_READ.BIN (Power Stone USA), tools/cpu_ai.py export; docs/CPU.md',
        'work': {'base': '0x0C366F40', 'stride': 0x254},
        'pad': {'on': '+0x2DC', 'prev': '+0x2E0', 'press': '+0x2E4', 'release': '+0x2E8',
                'bits': {'punch': 0x400, 'kick': 0x200, 'jump': 0x4, 'action': 0x600, 'up': 0x10, 'down': 0x20,
                         'left': 0x40, 'right': 0x80}},
        'ops': [{'op': i, 'name': OPS[i][0], 'len': L[i], 'handler': f'{H[i]:08x}', 'uses': uses.get(i, 0),
                 'meaning': OPS[i][1]} for i in range(NOPS)],
        'dir_bits': [u16(DIR_TBL + 2 * i) for i in range(8)],
        'evade_pct_by_level': [u16(EVADE_PCT + 2 * i) for i in range(32)],
        'thrown_pct_by_level': [u16(THROWN_PCT + 2 * i) for i in range(32)],
        'radius_by_kind': [s16(RADIUS_TBL + 2 * i) for i in range(12)],
        'response_sub_by_hit_id': resp,
        'waypoints': way,
        'chars': NAMES,
        'select': sel,       # "set/char/situation" -> [[thresholds, [band script lists]] per sub]
        'scripts': scr,      # "set/char/situation" -> [script address per index] (situation 0 = CALL/GOTO library)
        'code': code,        # address -> [[op, args...], ...]
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(d, open(OUT, 'w'), separators=(',', ':'))
    print(OUT, len(code), 'scripts', sum(len(c) for c in code.values()), 'instructions')


# (Mode, IntLv) the dispatcher writes -> (situation, sub); sub None = the response table (situation 5)
MODE_SIT = {(0x30, 0x1000): (13, 0), (0x80, 0x1000): (8, 0), (0x10, 0x800): (11, 0), (0x00, 0x400): (10, 0),
            (0x01, 0x400): (10, 1), (0x90, 0x200): (12, 0), (0x91, 0x200): (12, 1), (0x90, 0x100): (9, 0),
            (0x70, 0x80): (7, 0), (0x60, 0x40): (6, 0), (0x40, 0x20): (14, 0), (0x50, 0x10): (5, None),
            (0x40, 8): (4, 0), (0x41, 4): (4, 1), (0x31, 2): (3, 1), (0x30, 2): (3, 0), (0x32, 2): (3, 2),
            (0x10, 1): (1, 0)}


def check(paths):
    sel, scr, _ = tables()
    calls = lambda p: {args[0] for _, op, args in script(int(p, 16)) if op in (9, 10)}
    ok, bad = 0, []
    for path in paths:
        rows = [json.loads(l) for l in open(path)]
        for k in (0, 1):
            prev = None
            for fi, r in enumerate(rows):
                p = r['p'][k]
                if r['phase'] != 3:
                    prev = None; continue
                key = (p['mode'], p['intlv'])
                if prev is not None and key != prev and key in MODE_SIT:
                    sit, sub = MODE_SIT[key]
                    st = 'PC' if p['pc'] else ('oppPC' if r['p'][1 - k]['pc'] else 'n')
                    lst, lib, cands = scr[f'{st}/{p["ch"]}/{sit}'], scr[f'{st}/{p["ch"]}/0'], set()
                    for si, (th, bands) in enumerate(sel[f'{st}/{p["ch"]}/{sit}']):
                        if sub is not None and si != sub: continue
                        b = next((i for i, t in enumerate(th) if r['lvl'] < t), None)
                        for idx in (bands[b] if b is not None else []):
                            cands.add(idx)
                            todo, seen = list(calls(lst[idx])) if idx < len(lst) else [], set()
                            while todo:
                                c = todo.pop()
                                if c in seen: continue
                                seen.add(c); cands.add(c)
                                if c < len(lib): todo += list(calls(lib[c]))
                    # an END leaves (0x10, IntLv 1) one frame before the default script is picked: allow the next frame
                    nxt = rows[fi + 1]['p'][k]['tbl'] if fi + 1 < len(rows) else None
                    if p['tbl'] in cands or (key == (0x10, 1) and nxt in cands): ok += 1
                    else: bad.append((os.path.basename(path), r['f'], k, hex(key[0]), key[1], st, sit, sub, p['tbl']))
                prev = key
    print('selections consistent', ok, 'of', ok + len(bad))
    for b in bad[:20]: print('  ', b)


def dis(c, k='n'):
    sel, scr, code = tables()
    c = NAMES.index(c) if not str(c).isdigit() else int(c)
    for s in range(15):
        key = f'{k}/{c}/{s}'
        print(f'== situation {s}: select {sel[key]}')
        for i, p in enumerate(scr[key]):
            print(f'  -- script {s}.{i} @ {p}')
            depth = 0
            for a, op, args in script(int(p, 16)):
                if op in (7, 8): depth = max(0, depth - 1)
                print(f'     {a:08x} ' + '  ' * depth + OPS[op][0] + ('' if not args else ' ' + ' '.join(map(str, args))))
                if op in (29, 30, 31, 32, 33, 59, 8): depth += 1


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'export'
    if cmd == 'export':
        export()
    elif cmd == 'dis':
        dis(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'n')
    elif cmd == 'check':
        check(sys.argv[2:])
    elif cmd == 'ops':
        _, _, code = tables()
        uses = Counter(c[0] for s in code.values() for c in s)
        L, H = oplen(), handlers()
        for i in range(NOPS):
            print(f'{i:3d} {OPS[i][0]:14s} len {L[i]} {H[i]:08x} uses {uses.get(i, 0):5d}  {OPS[i][1]}')
