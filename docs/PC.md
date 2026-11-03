# The original's Power Change machine (decoded spec)

fx-react, 2026-10-27. Code from the 1ST_READ disassembly (tools/ghidra/sh4dis.py), numbers checked on every Power
Change in the original's logs: the 31 reference tapes (dumps/fidelity/o_*.jsonl, incl. o_gems_pc and the moves_* PC
parts) and the 16 CPU-vs-CPU logs (fx-cpu logs/cpu_*.jsonl): 115 transforms, 80 reverts, 1,010 PC attack starts, 74k PC frames.
Checker: `tools/pc_check.py` (summary), `tools/pc_check.py events`, `tools/pc_check.py export
game/assets/fidelity/pc_code.json` (per fighter: transform / revert chains, gauge at the transform's end, the gauge cost
of every PC attack). The stage camera logs (dumps/cap/cl*, cm*) have no PC fields.

Fields: +0x7230 gems held, +0x7231 gem bit mask, +0x71F1 PC model loaded, +0x71F3 PC flag (the HUD / damage x1.2 /
x0.5 use it), +0x71F4 s16 gauge, +0x71BA state (23 = transform / revert), +10 sub-step, +0xEC / +0xEE counters.

## Gems and the trigger
- **Pick-up** 0x0C09CB20 (item kind 5 within reach, 0x0C09CA88(p, 5)): only when the fighter is not char 10
  (Final Valgas), not in PC (+0x71F1 == 0, +0x71F3 == 0), **gauge == 0**, state != 23, **gems < 3**, the gem not
  already taken: +0x7230++, mask bit (gem colour, item +0xE), voice 0x16 / 0x2C (P1 / P2) while gems < 3. The same
  function eats health items (kinds 15 / 16 / 17: +95 / +47 / +23, cap 240).
- **Transform start**: the logs show no wait: in every CPU fight the transform starts the frame the third gem is
  counted, from any of states 0, 31, 32 (running into the gem), 5 (air), 6, 10 (attack), 15, 16 (lying / getting up);
  the only 3-gem frames without it are a win pose (state 21, 205 f) and 6 frames after a tape `@gems` poke. The code
  that calls the state-23 init for the transform was not found in this pass (the only `0x0C0A2E26(p, 23, ..)` call
  is the revert's); the init is 0x0C0A13EC, the per-frame handler **0x0C095BE0** (state table 0x0C3390D4[state]).
- **Aura**: per frame (player tick, 0x0C093580) a fighter not in PC with gems >= 2 (and the bits at tick+0x50 & 7
  clear) gets effect 0x0C044E38 (the PC-ready glow).
- Gems drop on hits (0x0C08E980 in the hit init, docs/REACT.md) and are set to 0 when the form changes
  (0x0C095A5E: +0x7230 = +0x7231 = 0); a KO in PC clears them too (REACT.md, launch step 0).

## Transform (state 23, k3/8)
- **130 frames** on the ground (90 of 102 ground starts; the other 11 are Wang-Tang's 122, 1 Falcon cut to 73),
  motion **k3/8 x130** for 8 fighters; Wang-Tang k3/8 91 > k3/11 31 (= 122 frames), Jack k3/8 73 > k3/11 57 (130).
- Mid-air (old state 5, 13 logged): **k3/11** (air version), 73-130 frames (Falcon 73 / 83 + 47 k3/12, Gunrock 95,
  Kraken 130); mid-attack (state 10): the attack is cut, k3/11 73 (Falcon). Mid-lying (15 / 16): cut, normal k3/8.
- **State-23 init 0x0C0A13EC** (reached through 0x0C0A2E26 -> 0x0C0A1162's per-state inits): clears the
  velocities, face/hands 0, then **+0x71F1 == 0 -> transform, else -> revert (0x0C0A161A)**. Transform: 0x0C09B7A4(p,
  12), effect 0x0C04B1F0, sound 0x0C0D8E6E(21, player, 112), voice 0x0C0A3796(player, 19), +0x30 = the camera's yaw,
  then per fighter (+4): **k3/8 on the ground, k3/11 when airborne (+0x71BC == 2)** and the morph counter **+0xEE**:
  Ryoma 34 (air 30), Rouge 41 (air 39), Jack 49, Galuda 61 (air 58), Ayame 61, Falcon / Kraken / Valgas 60, Wang-Tang /
  Gunrock 70 (the gauge at the state's end confirms every one: 2400 - (130 - morph) - 2); **+0xEC = 130** (0x82),
  +0x720C = 60, +0x7232 = 1, global 0x0C7F3194 set, 0x0C05FBEE.
- Morph (0x0C0954CA, sub-step 0): +0xEE counts down; for its last 14 frames the model flickers between the forms
  (+0x71F1 = +0xEE & 1, 0x0C099A24 swaps the model); at 0: **0x0C0A165E: +0x71F1 = 1, gauge = 2400 (0x960)**,
  +0x71F3 = 1. The gauge then ticks inside state 23: gauge at the state's end = 2302 (Ryoma), 2309 (Rouge), 2317
  (Jack), 2328 (Falcon, Galuda, Kraken, Valgas), 2329 (Ayame), 2338 (Gunrock), 2346 (Wang-Tang), i.e. the PC form
  appears 32-58 frames into the 130 (per-fighter +0xEE). Lower values = the round clock / KO pause stopped the state.
- +0xEC counts the state down; at 0: global 0x0C7F3194 = 0, 0x0C05FC00, then 0x0C0A2080 (back to the free state).

## Gauge (+0x71F4)
- Full = **2400**; **-1 per frame** (0x0C093528: only while the global byte 0x0C7F4766 is 0): 59,497 PC frames tick
  by 1; the 14,241 that don't are all round phases 4/5 (KO / TIME call, win poses) or after the match. Nothing else
  refills it; picking up gems is impossible while it is > 0.
- **Drives cost per move**, charged on the drive motion's first frame (`pc_code.json` attack_cost; the logged drop
  is cost + the 1-frame tick, or the rest of the gauge when it is lower): **240** most drives (Falcon 96/98/99, Jack
  96-99/102, Rouge 96/99-104, Valgas 96/98/101/103, Wang-Tang 96/97/103/104, Gunrock 101/104/105, Galuda 99, Ryoma
  96/103/111, Ayame 97), **360** (Ryoma 99, Valgas 99, Wang-Tang 98/99, Galuda 96/97, Rouge 105), **288** (Ayame
  99/101, Kraken 100/101), **120** (Kraken 96/99), **480** (Galuda 107, Gunrock 100/144), 450 (Galuda 110, 1 log).
  So RIP.md's flat "Drive -240" is wrong for 13 moves.
- **Fusions take the whole remaining gauge** (drop = gauge, e.g. Ryoma k1/101 2174 / 2251, Wang-Tang k1/106 1154,
  Ayame k1/105 2018, Galuda k1/113 2175, Kraken k1/108 616 / 1158 and k1/111 934).

## Drives and Fusions (what the logs show)
- A drive press first shows **k1/16 for 1 frame**, then the drive motion (e.g. Ayame k1/16 x1 > k1/99 x71; air:
  k1/16 x1 > k1/101). State 10 (11 for some). Chains per fighter are in pc_check.py's summary (e.g. Falcon k1/96 92 >
  k1/97 19; Jack k1/96 95; Kraken k1/96 41 > 97 25 > 98 26; Rouge k1/99 48 > k0/8 39 > k0/9 9 (lands)).
- **Fusions are fixed motion chains that end by themselves**: Ryoma k1/101 87 > 102 22 > 103 17 > 104 65 (191 f);
  Wang-Tang k1/106 52 > 108 57 > 109 99 > 110 183 (391 f); Kraken k1/111 48 > 112 17 > 113 113 > 114 19 (197 f);
  Galuda k1/113 55 > k1/102 64 (119 f); Ayame k1/105 64; Kraken k1/108 41. Landing a hit does not extend them (H-13:
  the remaster's "a fusion that keeps hitting never ends" has no counterpart). The gauge is 0 when they end, so the
  revert follows at once. The fusion input was not decoded here.
- The per-character move code is table **0x0C339070[char]** (Falcon 0x0C067870, Ryoma 0x0C069A98, Wang-Tang
  0x0C06DFF0, Jack 0x0C072818, Gunrock 0x0C077428, Galuda 0x0C07AC0C, Ayame 0x0C07E774, Rouge 0x0C080FF4, Kraken
  0x0C084168, Valgas / Final Valgas 0x0C087C34), called every frame from the player tick (0x0C093640); its +0x71F4
  writes (0x0C065F00-0x0C088D6E, 80 sites) are the drive / fusion costs. **Projectiles / effect objects** that these
  spawn hit through 0x0C08DEEC (docs/REACT.md "object hit"): victim +0xF8 = record (table 0x0C338A98[object +4 =
  owner's char] + hit id * 20), +10 = 2 (short reaction init, no gem drop / sound / hit-stop); not decoded per move.

## Revert (state 23 again)
- Trigger (player tick 0x0C0934DC): PC (+0x71F1), **gauge <= 0**, +9 == 0 (no sub-machine running), **state not 10,
  11 or 23** (an attack / drive / fusion finishes first) -> 0x0C0A2E26(p, 23, 0).
- Chain: **k3/9 then the landing k0/9**, the state ends when k0/9 ends (not a fixed 90): Falcon / Jack / Kraken /
  Wang-Tang k3/9 91 > k0/9 8 (99; Jack's k0/9 4 = 95, Kraken's 1 = 92), Galuda 85 + 8 = 93, Ayame 90 + 9 = 99, **Rouge
  70 + 9 = 79, Valgas 75 + 8 = 83**; only Ryoma and Gunrock have a second motion: k3/9 39 > k3/10 51 = 90. In the air
  the k3/9 part lasts until the landing (100-114). So H-7: a revert clip shorter than "the state" is not stretched or
  held; the original plays k0/9 and leaves state 23 when it ends (Rouge 79, Valgas 83 frames).
- A hit interrupts the revert (k3/9 x5-69 > state 27); gems are already 0.
- KO in PC: 0x0C0A167C (revert without the animation) from the launch's step 0 (REACT.md).

## What the remaster must change (requests for fighter.gd)
1. Transform 130 frames (k3/8; k3/11 in the air), PC form + gauge 2400 at the per-fighter morph frame (gauge at the
   end of state 23 in pc_code.json gives it: morph frame = 130 - (2400 - gauge_end)), gems -> 0.
2. Gauge -1/frame in round phase 3 only; drive cost per move from pc_code.json attack_cost (not a flat 240); fusion =
   all of it; no gem pick-up while the gauge is > 0.
3. Revert only when the gauge is 0 and the fighter is not in states 10/11/23: k3/9 (+ k3/10 for Ryoma/Gunrock) then
   k0/9; state length = the motions' lengths (no fixed 2.0/2.2 s, H-6).
4. Fusions = their logged motion chains, ending by themselves (H-13).

## Open
The code that starts the transform at 3 gems (it calls the state-23 init 0x0C0A13EC another way); the revert's init
0x0C0A161A and per-frame 0x0C095856 (k3/9 / k3/10 / k0/9 choice) read only from the logs; drive / fusion inputs and per-move projectile objects (0x0C339070[char] code);
Final Valgas (his "PC" in the CPU log is not him for most of it).

## Port (fx-pc, 2026-10-27; status: steps 1-2 committed, numbers below)
How it runs now: `game/scripts/core_pc.gd` (CorePC, tables) + fighter.gd "Power Change (fx-pc)" section (pc_g, _pc_frame,
_pc_begin, _pc_row, _pc_end, _pc_trigger, _pc_attack, can_take_gem, pick_gem, _set_powered). The data is the
original's own per-frame rows, `game/assets/fidelity/pc_moves.json`, built by `tools/pc_table.py` from every reference
log (dumps/fidelity/o_*.jsonl incl. the new pc_<fighter> tapes + the fx-cpu CPU logs): per fighter the transform /
revert rows (ground + air) and every Drive (X / Y, air AX / AY) and Fusion (FX = A+X, FY = A+Y) as rows [kind, mot,
motion frame, fwd cm, side cm, up cm, PC flag] + its gauge-cost row + the state it leaves into. Representative sample
per move = ended by itself with the attacker untouched, then the chain logged most often, then the fx-pc tapes first.
- Per frame (Fighter.tick, first): revert check (PC, gauge 0, round phase 3, not state 10 / 11 / 23, no reaction /
  throw running) BEFORE the gauge's -1 (logged: the gauge shows 0 for one free frame before state 23), then -1 in
  round phase 3 only, then the transform trigger (3 gems, not in PC, states 0/31/32/5/6/10/15/16), then A+X / A+Y.
- The form swap happens on the row where the original's PC flag flips (transform morph row: gauge = 2400 that row;
  revert swap row: gems -> 0, form back, the remaster's gem scatter). Motions show from their first row with no
  cross-fade (the original never blends); held motion frames (same fr twice) hold the pose.
- Drives / Fusions: hits use the existing hit code (_game_hit_update, else Rules.ATTACKS reach) and hold the timeline
  for the hit-stop like the core's attacks.
- New tapes `game/tests/tapes/pc_<fighter>.tape` (all 10): 3 gems, Drive X, Drive Y, air X, air Y, Fusion A+X,
  3 gems + Fusion A+Y, 3 gems + 2700 idle frames (the gauge runs out, revert). P2 stands 680 cm off (Londo; Falcon's
  tape on Ryoma's stage, 240 cm). Original logs: dumps/fidelity/o_pc_<fighter>.jsonl (Flycast pc1 / pc2).
- Match vs the disc (same-input tapes, P1 = the Power Change fighter, only the frames where the original is in PC,
  in state 23 or holds 3 gems; exact values; gauge in the game's units):

| tape | before (437b5da): st / motion / PC / gauge / gems % | after (fx-pc) | frames |
|---|---|---|---|
| pc_ryoma | 69.4 / 69.4 / 7.9 / 17.6 / 94.3 | 100.0 / 99.9 / 100.0 / 50.5 / 100.0 | 4653 |
| pc_falcon | 35.8 / 35.7 / 9.0 / 40.1 / 96.0 | 89.1 / 89.0 / 89.2 / 100.0 / 91.4 | 2425 |
| pc_wangtang | 71.9 / 71.9 / 11.1 / 17.2 / 93.5 | 99.7 / 99.6 / 100.0 / 48.4 / 100.0 | 4550 |
| pc_jack | 69.3 / 69.3 / 9.2 / 18.0 / 93.9 | 99.7 / 99.6 / 100.0 / 50.0 / 100.0 | 4641 |
| pc_gunrock | 68.3 / 68.2 / 10.8 / 18.3 / 94.0 | 99.7 / 99.8 / 100.0 / 100.0 / 100.0 | 4426 |
| pc_galuda | 73.9 / 73.9 / 11.0 / 15.6 / 93.4 | 100.0 / 100.0 / 100.0 / 100.0 / 100.0 | 4180 |
| pc_ayame | 68.1 / 68.1 / 12.6 / 21.9 / 91.2 | 90.0 / 89.8 / 95.0 / 51.6 / 95.0 | 4813 |
| pc_rouge | 72.2 / 72.2 / 8.0 / 14.0 / 94.7 | 99.5 / 99.5 / 100.0 / 48.0 / 100.0 | 4442 |
| pc_kraken | 37.0 / 36.9 / 8.7 / 42.9 / 96.2 | 76.8 / 76.1 / 81.4 / 100.0 / 83.2 | 2425 |
| pc_valgas | 69.5 / 69.5 / 9.4 / 16.1 / 94.6 | 99.9 / 98.0 / 100.0 / 100.0 / 100.0 | 4541 |
| gems_pc | 31.7 / 31.7 / 13.8 / 39.6 / 90.0 | 98.4 / 95.3 / 99.2 / 92.6 / 98.4 | 1781 |
| moves_ryoma | 35.5 / 35.4 / 2.0 / 40.6 / 100.0 | 77.6 / 77.5 / 88.4 / 88.8 / 90.4 | 1694 |
| moves_falcon | 36.1 / 36.0 / 3.6 / 38.1 / 100.0 | 76.9 / 76.8 / 80.5 / 92.8 / 84.1 | 1649 |
| moves_wangtang | 37.9 / 37.8 / 4.2 / 41.9 / 100.0 | 77.0 / 75.3 / 82.3 / 91.7 / 86.4 | 1679 |
| moves_jack | 32.5 / 32.4 / 8.8 / 45.1 / 95.7 | 83.5 / 83.4 / 82.1 / 100.0 / 82.1 | 2194 |
| moves_gunrock | 26.6 / 26.5 / 11.7 / 25.0 / 95.6 | 79.7 / 78.5 / 85.1 / 63.8 / 85.4 | 2008 |
| moves_galuda | 41.2 / 41.2 / 20.7 / 33.8 / 87.5 | 94.5 / 93.8 / 94.5 / 89.8 / 94.5 | 1475 |
| moves_ayame | 38.5 / 38.5 / 31.4 / 39.9 / 85.3 | 78.2 / 77.5 / 90.9 / 90.9 / 100.0 | 1589 |
| moves_rouge | 35.0 / 34.9 / 7.7 / 41.5 / 96.3 | 79.5 / 75.5 / 78.9 / 100.0 / 78.9 | 2082 |
| moves_kraken | 37.6 / 37.5 / 3.6 / 41.2 / 100.0 | 63.3 / 58.8 / 72.2 / 92.9 / 75.8 | 1647 |
| moves_valgas | 31.8 / 31.9 / 13.7 / 26.0 / 94.4 | 78.7 / 77.6 / 99.3 / 70.2 / 98.6 | 1472 |
| TOTAL | 56.2 / 56.1 / 10.1 / 25.8 / 94.3 | 91.6 / 90.8 / 94.0 / 77.2 / 94.8 |  |

  Gauge within 1 unit: before 25.8%, after 96.7% (all 21 tapes), 100% on the 10 pc_ tapes.

  The gauge's 50% rows (pc_ryoma, wangtang, jack, rouge, ayame) are off by exactly 1 after the third transform: the
  original's log has one frame where the whole game did not advance (its frame counter `timer` repeats; row 2828 in 7
  of the 10 pc_ logs, gems_pc 1402), right after a transform: a lag frame of the emulated machine, not game logic.
  Falcon's pc_ tape (Ryoma's stage) starts on a remaster floor 33 cm higher than the disc's (y 33 vs 0 at -297,-89:
  stage floor, not PC), so its air Drives land late. moves_<fighter> (P2 at 120 cm, real hits): the non-PC part
  before the gems differs (attacks / reactions: other lanes), so their PC part starts out of step.
- Known limits of the port: moves whose length depends on the situation play the most-logged length (Kraken Drive Y
  k1/96 41 / 71 / 85 f near / CPU / far; Ryoma Fusion Y k1/101 75 / 87 f); Fusions that grab (Ayame FY, Kraken FX
  leave into state 28) end into idle here; Galuda / Gunrock Fusion A+X were never logged (their gauge ran out before
  the press in every tape: Drives cost them 360 / 480) and fall back to the remaster's old fusion.

### Next steps (if this session ends, the next wave continues here)
1. DONE: 10 o_pc_* logs (Flycast pc1 / pc2), table rebuilt, before/after above (scratch tools: /tmp/ps-
   pstrailer2/fx-pc/{rem.py OUTDIR TAPE.., pcdiff.py ORIG REM P, table.py TAPES DIR..}; baseline clone base/, rb/).
2. DONE: gems_pc's late Drive Y was the extra hit-stop on PC moves (removed: the logs never hold a thrower).
3. Base suite: 155/164 in both looks before the test updates (1 = the old Power Change unit check, 8 = cine_tests
   expecting the cinematic on the 3rd gem's frame); both tests now follow the disc's order: 164/164 in both looks
   (remaster + classic, 04:09).
4. Lead requests (fighter.gd outside the PC parts): (a) _gset / _gplay: every standing jump shows k0/5 one frame
   too long (state 5 starts with k0/6 on the disc; travel's cross-fade: force-start like flow_pose / _pc_show);
   (b) Drive / Fusion projectiles (object hits 0x0C08DEEC) are what reach P2 at 680 cm in the original;
   (c) _core_tick state 5 landing: a fall that reaches the floor mid-step (pc_ayame 549: y 7 -> 0 with vy -32) stays
   state 5 on that frame in the original and lands (state 6) the next one; the core lands the same frame (1 frame early,
   seen after Ayame's Drive Y k1/97 and the air Drives that leave into state 5).
5. Open, not this brief: Drive / Fusion projectiles reach P2 680 cm away in the original (its object hits), the
   remaster's don't (P2 st 86% in pc_ryoma); the gauge drain on a PC victim's hits is not dmg x 7.5 in the logs
   (e.g. 14 dmg -> 339): left as pass 4's rule.
