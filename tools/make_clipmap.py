#!/usr/bin/env python3
"""Game action -> captured motion clip map for one fighter form (assets/ripped/<id>_clips.json).
Confirmed in real arcade fights (Falcon, Ryoma) by logging the fighter's kind/motion bytes (0x0C7EB268/9):
idle k0/0, jump k0/5 -> k0/6 -> land k0/9, run k0/25 (stop 26), punch k1/16 -> 17 -> 18, kick k1/24 -> 25,
air punch k1/10, air kick k1/12, grab k1/84, object throw k1/78, and the shared kind-2 bank: hit stagger 112,
heavy 152, knocked down 153 -> lying 144 -> get-up 146, pick-up 219, carry 220, carry-run 221.
Pass 3 (forced Power Change fight, gems poked to 3 at player+0x7230, kind/motion bytes logged per input):
kind 3 = per-fighter system motions: 0 round intro, 1 ready, 2/3 win poses, 5 lose (continue screen), 8 transform,
9 revert; running attacks reuse punch1/kick1 (k1/16, k1/24). Falcon specials: Drive P k1/98, Drive K k1/96 > 97,
air Drive P k1/99, Fusion P+J k1/101, Fusion K+J k1/101 > 100 > 159 (> 100 > 159 ... > k2/205).
Ryoma: Drive P k1/96, Drive K k1/105 > 110 > 111 > 112, air Drive P 99, air Drive K 106 > 107 > 110 > 111 > 112,
Fusion P+J k1/108, Fusion K+J k1/101 > 102 > 103 > 104; revert k3/9 > k3/10.
Attract-demo CPU fights (Falcon): moving jump k0/10, wall kick k2/206 > k0/13, pole catch k2/211 > swing k1/150 >
launch k1/151 > k1/152 (the per-fighter k1 ids follow the same convention; only Falcon's are seen in a log).
Usage: make_clipmap.py prefix clips_dir skel.json out.json"""
import json, os, sys
prefix, cdir, skp, out = sys.argv[1:5]
idx = json.load(open(os.path.join(cdir, 'index.json')))
sk = json.load(open(skp))
WANT = {   # first existing candidate wins; k2 = the shared bank (hit reactions, object handling)
    'idle': ['k0_000'], 'run': ['k0_025'], 'run_stop': ['k0_026'], 'jump': ['k0_006'], 'jump_start': ['k0_005'],
    'land': ['k0_009'], 'jump_move': ['k0_010'], 'walljump': ['k2_206'], 'walljump_air': ['k0_013'],
    'pole_catch': ['k2_211'], 'pole_swing': ['k1_150'], 'pole_launch': ['k1_151'], 'pole_kick': ['k1_152'],
    'pick_up': ['k2_219', 'k0_041'], 'carry': ['k2_220', 'k0_027'], 'carry_run': ['k2_221'],
    'punch1': ['k1_016'], 'punch2': ['k1_017'], 'punch3': ['k1_018'],
    'kick1': ['k1_024'], 'kick2': ['k1_025'], 'air': ['k1_012', 'k1_010'], 'air_punch': ['k1_010'],
    'dash': ['k1_016'], 'grab': ['k1_084'], 'throw': ['k1_078'],
    'hit': ['k2_118', 'k2_106'], 'hit_big': ['k2_120', 'k2_107'], 'air_hit': ['k2_112'], 'down': ['k2_153', 'k1_171'],
    'lying': ['k2_144'], 'getup': ['k2_146', 'k1_149'], 'win': ['k3_002'], 'win2': ['k3_003'],
    'lose': ['k3_005'], 'intro': ['k3_000'], 'ready': ['k3_001'], 'transform': ['k3_008'], 'revert': ['k3_009'],
}   # specials only come from PER (a logged Power Change fight per fighter), never by eye
# per-fighter moves confirmed from a logged Power Change fight (override WANT); CHAINS = the game's motion sequence
PER = {'f0': {'dash': ['k1_016'], 'dash_k': ['k1_024'], 'drive_p': ['k1_098'], 'drive_k': ['k1_096'],
              'drive_k2': ['k1_097'], 'air_drive_p': ['k1_099'], 'fusion1': ['k1_101'], 'fusion2': ['k1_101'],
              'fusion2_b': ['k1_100'], 'fusion2_c': ['k1_159'], 'fusion2_d': ['k1_100'], 'fusion2_e': ['k1_159']},
       'r0': {'dash': ['k1_016'], 'drive_p': ['k1_096'], 'drive_k': ['k1_105'], 'drive_k2': ['k1_110'],
              'drive_k3': ['k1_111'], 'drive_k4': ['k1_112'], 'air_drive_p': ['k1_099'], 'air_drive_k': ['k1_106'],
              'air_drive_k2': ['k1_107'], 'fusion1': ['k1_108'], 'fusion2': ['k1_101'], 'fusion2_b': ['k1_102'],
              'fusion2_c': ['k1_103'], 'fusion2_d': ['k1_104'], 'revert2': ['k3_010']},
       'a0': {'punch3': ['k1_021'], 'kick3': ['k1_029'], 'close_kick': ['k1_059'], 'drive_p': ['k1_099'],
              'drive_k': ['k1_097'], 'air_drive_p': ['k1_101'], 'fusion1': ['k1_103'], 'fusion2': ['k1_105'],
              'fusion2_b': ['k0_026']},
       'w0': {'punch4': ['k1_019'], 'kick3': ['k1_026'], 'transform2': ['k3_011'], 'drive_p': ['k1_096'],
              'drive_k': ['k1_099'], 'drive_k2': ['k1_100'], 'air_drive_p': ['k1_103'], 'air_drive_k': ['k1_099'],
              'fusion1': ['k1_101'], 'fusion1_b': ['k1_102'], 'fusion1_c': ['k1_111'], 'fusion2': ['k1_106']},
       'j0': {'getup': ['k0_051'], 'kick2': ['k1_001'], 'transform2': ['k3_011'], 'drive_p': ['k1_096'],
              'drive_k': ['k1_098'], 'air_drive_p': ['k1_102'], 'air_drive_k': ['k1_103'], 'fusion1': ['k1_106'],
              'fusion1_b': ['k1_107'], 'fusion1_c': ['k1_108'], 'fusion2': ['k1_104']},
       'o0': {'punch3': [], 'dash': ['k1_078'], 'throw': [], 'drive_p': ['k1_096'], 'drive_p2': ['k1_097'],
              'drive_p3': ['k1_098'], 'drive_k': ['k1_100'], 'drive_k2': ['k1_101'], 'air_drive_p': ['k1_099'],
              'air_drive_k': ['k1_102'], 'fusion1': ['k1_105'], 'fusion2': ['k1_103']},
       'g0': {'revert2': ['k3_010'], 'drive_p': ['k1_105'], 'drive_k': ['k1_144'], 'drive_k2': ['k1_100'],
              'drive_k3': ['k1_101'], 'drive_k4': ['k1_103'], 'air_drive_p': ['k1_104'], 'air_drive_k': ['k1_100'],
              'fusion1': ['k1_096'], 'fusion1_b': ['k1_097'], 'fusion2': ['k1_144'], 'fusion2_b': ['k1_100'],
              'fusion2_c': ['k1_099'], 'fusion2_d': ['k1_101'], 'fusion2_e': ['k1_102']},
       'l0': {'punch2': ['k1_018'], 'punch3': [], 'kick2': ['k1_026'], 'drive_p': ['k1_096'], 'drive_k': ['k1_107'],
              'drive_k2': ['k1_108'], 'drive_k3': ['k1_109'], 'air_drive_p': ['k1_097'], 'air_drive_k': ['k1_110'],
              'air_drive_k2': ['k1_111'], 'air_drive_k3': ['k1_112'], 'fusion1': ['k1_098'], 'fusion1_b': ['k1_105'],
              'fusion2': ['k1_101'], 'fusion2_b': ['k1_113'], 'fusion2_c': ['k1_102']},
       # Kraken + Valgas: logged as P1 in arcade fights (select cursor 0x0C7F2E54 poked to 0 / 9: the locked slots)
       'k0': {'punch2': ['k1_019'], 'punch3': ['k1_018'], 'kick2': ['k1_031'], 'drive_p': ['k1_100'],
              'drive_k': ['k1_096'], 'drive_k2': ['k1_098'], 'air_drive_p': ['k1_101'], 'air_drive_k': ['k1_099'],
              'air_drive_k2': ['k1_109'], 'fusion1': ['k1_107'], 'fusion1_b': ['k1_108'], 'fusion1_c': ['k1_106'],
              'fusion2': ['k1_102'], 'fusion2_b': ['k1_103'], 'fusion2_c': ['k1_104'], 'fusion2_d': ['k1_105'],
              'fusion2_e': ['k1_106']},
       'v0': {'punch1': ['k1_018'], 'punch2': ['k1_016'], 'punch3': ['k1_017'], 'kick1': ['k1_005'],
              'kick2': ['k1_024'], 'dash': ['k1_018'], 'dash_k': ['k1_005'], 'drive_p': ['k1_096'],
              'drive_k': ['k1_098'], 'air_drive_p': ['k1_097'], 'air_drive_k': ['k1_101'], 'fusion1': ['k1_102'],
              'fusion1_b': ['k1_103'], 'fusion2': ['k1_106'], 'fusion2_b': ['k1_108']},
       # Final Valgas: logged as the CPU in ladder fight 9 (fightlog.py show fv_cpu2 2). He never walks or jumps; every
       # attack runs in the Power Change attack state 11: 99>100 (x9), 99>100>101 (x2), 99>100>103, k1/2, k1/3, 4>16;
       # his match-end pose is k3/1. The action names are only slots for those sequences.
       'z0': {'punch1': ['k1_002'], 'punch2': [], 'kick1': ['k1_003'], 'drive_p': ['k1_099'], 'drive_p2': ['k1_100'],
              'drive_k': ['k1_099'], 'drive_k2': ['k1_100'], 'drive_k3': ['k1_101'], 'fusion1': ['k1_099'],
              'fusion1_b': ['k1_100'], 'fusion1_c': ['k1_103'], 'fusion2': ['k1_004'], 'fusion2_b': ['k1_016'],
              'win': ['k3_001'], 'win2': [], 'ready': [], 'intro': [], 'dash': [], 'air': [], 'air_punch': []}}
CHAINS = {'f0': {'drive_k': 'drive_k2', 'fusion2': 'fusion2_b', 'fusion2_b': 'fusion2_c', 'fusion2_c': 'fusion2_d',
                 'fusion2_d': 'fusion2_e'},
          'r0': {'drive_k': 'drive_k2', 'drive_k2': 'drive_k3', 'drive_k3': 'drive_k4', 'air_drive_k': 'air_drive_k2',
                 'air_drive_k2': 'drive_k2', 'fusion2': 'fusion2_b', 'fusion2_b': 'fusion2_c', 'fusion2_c': 'fusion2_d', 'revert': 'revert2'},
          'a0': {'fusion2': 'fusion2_b'},
          'w0': {'transform': 'transform2', 'drive_k': 'drive_k2', 'fusion1': 'fusion1_b', 'fusion1_b': 'fusion1_c'},
          'j0': {'transform': 'transform2', 'fusion1': 'fusion1_b', 'fusion1_b': 'fusion1_c'},
          'o0': {'drive_p': 'drive_p2', 'drive_p2': 'drive_p3', 'drive_k': 'drive_k2', 'air_drive_k': 'drive_k2'},
          'g0': {'revert': 'revert2', 'drive_k': 'drive_k2', 'drive_k2': 'drive_k3', 'drive_k3': 'drive_k4',
                 'air_drive_k': 'drive_k3', 'fusion1': 'fusion1_b', 'fusion2': 'fusion2_b', 'fusion2_b': 'fusion2_c',
                 'fusion2_c': 'fusion2_d', 'fusion2_d': 'fusion2_e'},
          'l0': {'drive_k': 'drive_k2', 'drive_k2': 'drive_k3', 'air_drive_k': 'air_drive_k2', 'air_drive_k2': 'air_drive_k3',
                 'fusion1': 'fusion1_b', 'fusion2': 'fusion2_b', 'fusion2_b': 'fusion2_c'},
          'k0': {'drive_k': 'drive_k2', 'air_drive_k': 'air_drive_k2', 'fusion1': 'fusion1_b', 'fusion1_b': 'fusion1_c',
                 'fusion2': 'fusion2_b', 'fusion2_b': 'fusion2_c', 'fusion2_c': 'fusion2_d', 'fusion2_d': 'fusion2_e'},
          'v0': {'fusion1': 'fusion1_b', 'fusion2': 'fusion2_b'},
          'z0': {'drive_p': 'drive_p2', 'drive_k': 'drive_k2', 'drive_k2': 'drive_k3', 'fusion1': 'fusion1_b',
                 'fusion1_b': 'fusion1_c', 'fusion2': 'fusion2_b'}}
WANT.update(PER.get(prefix, {}))
m = {}
for name, cands in WANT.items():
    for c in cands:
        cn = f'{prefix}{c}'
        if cn in idx: m[name] = cn; break
loops = [k for k, v in idx.items() if v['loop']]
# head / right hand / left hand variant parts (index 0 = default) per part layout, and the per-motion selection the
# game makes (fighter object bytes 0x0C7EB1CE/CF/D0, logged per motion in real fights)
n = len(sk['parent'])
# every form ends with 2 head variants (parent bone 4), 4 right-hand (parent 8) and 4 left-hand poses (parent 12)
GROUPS = {}
if [sk['parent'][k] for k in range(n - 10, n)] == [4, 4, 8, 8, 8, 8, 12, 12, 12, 12]:
    GROUPS[n] = [[n - 10, n - 9], list(range(n - 8, n - 4)), list(range(n - 4, n))]
SEL = {'k2_096': [1, 1, 1], 'k2_099': [1, 1, 1], 'k2_112': [1, 1, 1], 'k2_152': [1, 1, 1], 'k2_153': [1, 1, 1],
       'k2_176': [1, 1, 1], 'k2_178': [1, 1, 1]}
for k in (0, 1, 2, 3, 4, 5, 33, 34, 35, 97, 98, 108, 111, 115, 128, 129, 131, 163, 173):   # logged hit/held reactions
    SEL[f'k2_{k:03d}'] = [1, 1, 1]
if prefix == 'f0':   # logged in fights: kick/air kick open the right hand, drives open the left
    SEL.update({'k1_012': [0, 2, 0], 'k1_024': [0, 2, 0], 'k1_098': [0, 0, 2], 'k1_096': [0, 0, 2], 'k1_097': [0, 2, 2],
                'k1_159': [0, 2, 2], 'k3_000': [0, 2, 2], 'k3_009': [0, 2, 2], 'k3_003': [0, 2, 0]})
if prefix == 'a0':   # logged in Ayame's arcade fights (vs Wang-Tang)
    SEL.update({'k1_017': [0, 3, 0], 'k1_021': [0, 2, 0], 'k1_010': [0, 2, 3], 'k1_012': [0, 3, 0], 'k1_024': [0, 1, 1],
                'k1_025': [0, 0, 1], 'k1_029': [0, 3, 3], 'k1_059': [0, 3, 3], 'k1_101': [0, 3, 3], 'k3_009': [0, 2, 0],
                'k1_105': [0, 2, 0], 'k0_005': [0, 0, 2], 'k3_002': [0, 3, 3], 'k3_008': [0, 3, 0]})
if prefix == 'l0':   # logged in Galuda's arcade fight (vs Gunrock)
    SEL.update({k: [0, 1, 1] for k in ('k1_018', 'k1_024', 'k1_026', 'k1_012')})
    SEL.update({'k1_010': [0, 1, 0], 'k1_096': [0, 0, 1], 'k1_097': [0, 0, 1]})
if prefix == 'g0':   # logged in Gunrock's arcade fight (vs Jack)
    SEL.update({k: [0, 1, 1] for k in ('k3_008', 'k1_010', 'k1_105', 'k1_100', 'k1_101', 'k1_104', 'k1_096', 'k1_097',
                                       'k3_009', 'k3_010', 'k1_099')})
    SEL.update({'k1_024': [0, 2, 2], 'k1_012': [0, 2, 2]})
if prefix == 'o0':   # logged in Rouge's arcade fight
    SEL.update({k: [0, 3, 0] for k in ('k1_017', 'k1_024', 'k1_025', 'k1_096', 'k1_097', 'k1_098')})
    SEL.update({k: [0, 3, 3] for k in ('k1_078', 'k1_010', 'k1_100', 'k1_101', 'k1_099', 'k1_102', 'k1_105')})
    SEL['k0_005'] = [0, 2, 2]
if prefix == 'w0':   # logged in Wang-Tang's arcade fights (vs Rouge)
    SEL.update({'k1_010': [0, 0, 2], 'k1_012': [0, 2, 2], 'k3_008': [0, 2, 2]})
if prefix == 'r0':   # logged in Ryoma's Power Change fight
    SEL.update({'k1_012': [0, 0, 1], 'k1_105': [0, 2, 3], 'k1_110': [0, 3, 3], 'k1_111': [0, 3, 3], 'k1_112': [0, 2, 3],
                'k1_099': [0, 0, 3], 'k1_106': [0, 3, 3], 'k1_107': [0, 3, 3], 'k1_108': [0, 2, 3], 'k3_009': [0, 0, 1],
                'k3_010': [0, 0, 1]})
    # logged in an in-fight capture (tools/fight_clips.py, hold_id7: item 7 picked up, held, walked, thrown)
    SEL.update({'k2_229': [0, 2, 0], 'k2_230': [0, 2, 0], 'k2_235': [0, 2, 0]})
if prefix == 'k0':   # logged as P1 (fightlog.py sel 1 kraken kraken2)
    SEL['k1_078'] = [0, 1, 0]
if prefix == 'v0':   # logged as P1 (fightlog.py sel 1 valgas valgas2)
    SEL.update({'k1_005': [0, 2, 0], 'k1_010': [0, 2, 0], 'k1_012': [0, 1, 2], 'k1_016': [0, 0, 2], 'k1_017': [0, 2, 2],
                'k1_018': [0, 2, 0], 'k1_024': [0, 2, 2], 'k1_098': [0, 2, 2], 'k1_101': [0, 2, 0], 'k1_106': [0, 1, 1],
                'k3_001': [0, 1, 1], 'k3_009': [0, 1, 1]})
groups = [[f'part{k:02d}' for k in g] for g in GROUPS.get(n, [])]
variants = {prefix + k: v for k, v in SEL.items() if prefix + k in idx}
# in-fight captures (tools/fight_clips.py) carry the selection the game made while it played them
variants.update({k: v['sel'] for k, v in idx.items() if v.get('sel') and any(v['sel']) and k not in variants})
loose = [k for k in range(1, n) if sk['parent'][k] < 0]   # parentless effect pieces (placed by the game's effect code)
hidden = [f'part{k:02d}' for k in sorted(set(sk.get('hidden', []) + sk.get('missing', []) + loose))]   # missing = no node record
chains = {a: b for a, b in CHAINS.get(prefix, {}).items() if a in m and b in m}
json.dump({'map': m, 'chains': chains, 'loops': loops, 'hidden': hidden, 'variant_groups': groups, 'variants': variants}, open(out, 'w'), indent=1)
print(out, len(m), 'actions,', len(loops), 'loops,', len(hidden), 'hidden; missing', [k for k in WANT if k not in m])
