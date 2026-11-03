# ITEMS: the original's gems, drop spots, chests and items (fx-item, 10-27)

Decoded from 1ST_READ (SH-4 disassembly `tools/ghidra/sh4dis.py`, Ghidra `all_resolved.c`) and measured on the disc's
object logs (fx-cov: `dumps/fidelity/o_TAPE.obj.jsonl`, 30 tapes, per frame every live object of the pool 0x0C7D0980:
[slot, type, owner, kind, b5, x, y, z, +0x30C, +0x30D]). Rules + tables: `game/assets/fidelity/item_code.json`.
Checker: `tools/item_check.py gems|items` (replays every rule on the logs; the scores below are its output).
Units: cm, cm/frame, frames (60 Hz); headings u16, 0 = +z, 0x4000 = +x. Model of this doc: docs/OBJ.md.

Objects: **type 3 kind 5 = the 3 Power Stones** (gem slots 2 / 3 / 4 = colours 0 / 1 / 2), **type 3 kind 6 = an item**
(+0x30C = item id, +0x30D sub-state), **type 2 kind 7 = the item chest** (+0x30C = the item inside), type 6 = effects
(the round-start sparkles, the light pillar that falls onto a gem spot: not items), type 5 = shots / effects.
The **drop manager** lives in the object at 0x0C7F2664 (+0x8 phase, +0xC chest counter, +0xEC clock, +0x310[3]
spot-occupied flags, +0x313 free spots, +0x314 drop-due, +0x318[] gem pointers, +0x32C gem count, +0x32D / +0x32E[]
queue of gem colours waiting to be dropped).

## 1. DROP SPOTS (shared by gems and chests)
**Table 1ST_READ 0x0C33CA80 + stage * 72 + spot * 24** (vec3 + 3 unused floats), stage = byte 0x0C7F3051 (0 Londo ..
10 Final Valgas; the one logged Final Valgas fight, stg_a0, drops on row 2 = Wang-Tang's spots). Exactly 3 spots per stage; every floor gem and every chest of all 30 logs sits on one of them.
| stage | spot 0 | spot 1 | spot 2 |
|---|---|---|---|
| stg00 | 350, 281, 790 | -190, 161, 720 | 430, 41, 0 |
| stg10 | -317, 41, 97 | -577, 161, -140 | 360, 161, 550 |
| stg20 | -50, 91, -50 | -400, 41, -50 | 0, 141, 400 |
| stg30 | 0, 41, -150 | -500, 41, 300 | 200, 41, 400 |
| stg40 | 400, 21, -530 | 300, 41, 250 | -580, 191, -550 |
| stg50 | 0, 41, 0 | 450, 41, 300 | -100, 341, 560 |
| stg60 | 21, 161, 570 | -290, 41, -220 | 590, 161, -120 |
| stg70 | 280, 41, 60 | -650, 101, 60 | 650, 161, -400 |
| stg80 | 320, 41, -200 | -270, 41, -465 | 480, 261, 515 |
| stg90 | 400, 41, 400 | -300, 41, 200 | 200, 41, -300 |
| stga0 | 500, 41, 500 | -500, 41, 500 | 0, 41, -500 |
**Which spot** (0x0C0CC2A6, by the number of free spots +0x313 = 0x0C0CC212; 1 free 0x0C0CC2CA, 2 free 0x0C0CC314,
3 free 0x0C0CC5A8): **the FREE spot with the largest sum of 3D distances from both fighters' feet (+0x20)**, ties ->
the lowest index. A spot is "occupied" while a gem / chest / item stands on it (each sets manager +0x310[spot] every
frame; the tick clears them).

## 2. THE DROP CLOCK (manager tick 0x0C0CC8E8, phases 0x0C0CC9DE / 9FE / AA8 / AD6 / B12)
- phase 0: the frame the round phase (0x0C7F302C) becomes 3 (FIGHT) -> **drop** (fight frame 0) -> phase 1;
- phase 1: **300 frames** -> push gem colour 2 onto the drop queue and **drop** (= the floor gem at fight frame 299 in
  the logs: 29/29) -> phase 3. If a fighter is **Final Valgas** (char 10, he holds no gem): push colours 1 AND 2 ->
  phase 2 (300 frames -> drop: his second floor gem) -> phase 3;
- phase 3: 300 frames -> **drop** (fight frame 599 = chest 2 in every stage log) -> phase 4;
- phase 4: **whenever at least one spot is free for 300 frames in a row -> drop** (the count restarts after each drop).
- **A drop** = the queue's first gem if the queue is not empty (0x0C0CC832: gem at the spot), else **a chest**
  (0x0C05D338(spot, item)) holding `item_pick(+0xC)` (section 5), +0xC cycling 0..9. Gems always win over chests.
- The queue is fed by: the round start (phase 1), a gem that timed out (section 3), the Power Change start (the 3 gems
  go back, 0x0C095A36 -> 0x0C0CC7FC). Spilled gems are NOT queued: they fly (section 4).

## 3. FLOOR GEM (BUG-43): appear, hop, rest, despawn (handler 0x0C05CD68)
- Spawn 0x0C05CB46 at spot y + 9 (Londo spot 1: 170), velocity 0, vy 20 stored, gravity 1.2.
- **Appear phase**: 121 frames frozen (phase byte +8 = 0, counter +0xEC to > 120); then **one hop**: vy 20, gravity
  1.2 -> +177 cm, 34 frames, back to the rest height (gems_drop f420-454); then still. Rest = 50 cm above the floor
  under it (all logs: floor spots 50, Londo's 120 cm top 170). At rest (motion sub 1, 0x0C05CFF8) only the mesh bobs:
  offset 10 cm * cos(6 deg * t) (consts 0x0C05D138-14C: a 60-frame period); the object's y stays put.
- Takeable from 10 frames after the appear phase (+0xC = 1: 130 frames after the spawn).
- **Despawn**: counter +0xEE +1 per frame while NO fighter's feet are within **300 cm** (0x0C05D1EA, const 0x0C05D250;
  a fighter inside resets it to 0); from 900 it counts 2 per frame and the gem **blinks**; at 1080 it is gone =
  **990 frames unattended** (+ the 121 appear frames for a spot gem: 299 -> 1409 in gems_drop); its colour goes back
  on the drop queue -> it is dropped again at the next drop (>= 300 frames later: 1709).
- Pick-up (0x0C09CB20, PC.md): the gem in the body's contact list (+0x294, 0x0C09CA88(p, 5)) and takeable, not
  touched by the other fighter the same frame, not Final Valgas, not in PC, gauge 0, state != 23, gems < 3: gems++,
  mask |= 1 << colour, voice 0x16 / 0x2C. Logged reach: feet 65 cm from the gem (stg_20 f1209).
| rule | score |
|---|---|
| floor gem on one of the 3 drop spots (x/z exact) | 38/40 (2 = stg_a0 rows mid-flight) |
| first floor gem on fight frame 299 | 34/34 |
| spot = the free spot farthest from both fighters (summed) | 37/40 |
| gone 990 frames after the last frame a fighter was within 300 cm (+-2) | 20/20 |

## 4. GEM SPILL (BUG-44): 0x0C08E980 (hit init, REACT.md) -> 0x0C05CB42
- **Who spills**: health >= 0, not in Power Change (+0x71F3 == 0), **1 <= gems < 3**, and the hit record (+0xF8)
  **byte 16 & 4 -> 1 gem, & 8 -> 2 gems** (else none; the launches k2/96 / k2/112 / k2/173 of the logs all spill 1).
  Which gem: the lowest set bit of the colour mask +0x7231; gems--, mask bit cleared; voice 0x0C0A3F30(23 P1 / 45 P2).
- **Start**: the victim's feet (+0x20) **+100 up**, then **+100 cm along the spill heading** (0x0C05CD48).
- **Heading** = **+0x72A8 + 0x8000** = the hit's push direction reversed = toward the attacker (2-gem hits: the 2nd gem
  + 0x8000 more, i.e. away); if the hitting object (+0x7294) sits exactly on the victim's x/z: opponent +0x30 + 0x8000.
  Throws (victim state 28) and pole-swing hits push along their own direction, so the gem follows that one.
- **Flight**: horizontal **20.0 cm/f** along the heading, **vy 30** (= 0.6 * 1000 / 20, consts 0x0C05CD50 /
  0x0C08E980's 1000.0), **gravity 1.2** per frame (0x0C336338; y += vy, then vy -= 1.2), **wall contact: that
  axis' velocity x -0.5** (0x0C05CEEA: +0x270 -> vx, +0x278 -> vz), **floor contact: stop** (motion sub 1, rest);
  mesh scale grows 0 -> 1 by 0.025 per frame (40 frames). Lands ~52 frames / ~7.6 m away on a flat floor.
- Takeable after **40 frames** (+0xC); the same 990-frame unattended despawn as section 3 (then queued).
| rule | score |
|---|---|
| horizontal speed 20.0 cm/f | 40/43 (3 = a throw spill sliding on a ledge, stg_a0 rows) |
| first rise vy 30.0 | 42/43 |
| gravity 1.2 per airborne frame | 2016/2022 |
| wall bounce: that axis x -0.5 | 37/41 (4 = second bounces in corners / ledge lips) |
| starts at victim feet + 100 along the heading (<= 25 cm) | 38/41 |
| heading toward the attacker within 15 deg | 35/41 (6 = throws / a pole swing / an item hit: they push their own way) |
| rests on the floor | 43/43 |

**Port (arena.gd / gem.gd / fight.gd; units m = cm * 0.01, per frame at 60 Hz):**
1. `Arena.drop_spots` = item_code.json `drop_spots[stage]`; a `DropClock` in arena.gd with the phases of section 2
   (frame counter from the FIGHT call; 300-frame steps; phase 4 = 300 frames with >= 1 free spot); a drop takes the
   queued gem colour if any, else a chest (section 5). Spot = free spot with max (|spot - p1 feet| + |spot - p2 feet|).
2. Replace `scatter_gems` at the round start: each fighter holds 1 (as now), colour 2 is queued, nothing else on the
   floor; vs Final Valgas queue 2 colours.
3. `Gem` state: `spot` (-1 = spilled), `phase` (appear / live), `t` frames, `unattended` frames. Spot gem: at spot
   y + 0.09 m, frozen 121 f, then vy 0.20 m/f, g 0.012 m/f^2 until it rests 0.50 m above the floor. Spilled gem:
   start = victim feet + (0, 1.0, 0) + 1.0 m along the heading, v = 0.20 m/f along it + vy 0.30, g 0.012, wall hit
   = that axis x -0.5, floor contact = stop at floor + 0.5 (scale-in over 40 f).
4. Takeable: spilled after 40 f, spot gems after 130 f; pick-up on body contact (feet ~0.65 m; keep can_take_gem()).
5. Despawn: unattended (no fighter feet within 3.0 m) 900 f normal + 90 f blinking (counting 2 per frame), then
   gone and its colour queued again; any fighter inside 3.0 m resets the count.
6. `spill_gems(victim, n)`: n = 1 for launches (hit record byte 16 & 4; & 8 = 2, the 2nd one the opposite way),
   heading = from the victim toward the attacker (throws / pole swings: their push direction reversed), only when
   1 <= gems < 3 and not in PC. The Power Change start queues all 3 colours (no scatter).

## 5. CHESTS (BUG-46)
- **Drop**: section 2 (chest 1 at fight frame 0, chest 2 at 599, then whenever a spot has been free for 300 frames
  and no gem is queued), on the farthest free spot (section 1). **0x0C05D338(spot, item)**: type 2 kind 7 at the spot
  (y = spot y), +0x30C = the item, handler 0x0C05D4E4, meshes = 1ST_READ bank 0x171088 parts **56, 126, 57, 58, 59,
  127** (index list 0x0C336374 into the RAM bank 0x0C4CFA68 = [51, 52, 80, 81, 82, 126, 127]).
- **Opens by itself**: the item appears **354 frames after the drop**, the chest object is gone at **365-366**
  (97/97 untouched chests); a hit opens it earlier (logged 67 / 75 / 223 / 324 frames).
- **Item pop**: the item (type 3 kind 6, sub 16) starts at spot y + 9, **vy 20, gravity 2 per frame** (+110 cm in 11
  frames, back in 11), **ready (sub 0) 23 frames after it appears = 377 after the drop** (Londo chest 1: 354 / 377).
- **Which item** (0x0C0CC72E(counter +0xC), the counter = chests dropped this round, 0..9 cyclic): category =
  **[2, 0, 1, 0, 1, 2, 2, 0, 1, 0][counter]** (0x0C33CF54, used when byte 0x0C7F4764 != 0 = every logged fight; else
  0x0C33CF5E = [3, 0, 1, 3, 1, 2, 0, 3, 1, 2]); item = `list[rand() % count]` (C rand 0x0C0DF920) from 0x0C33CF14:
  **category 0 = [0, 1, 2], 1 = [3, 4, 5, 6], 2 = [7, 8, 9, 10]**, 3 = rand() % (byte 0x0C7F4750 + 1): 0 -> food
  **15 / 16 / 17** (+95 / +47 / +23 health, eaten on touch by 0x0C09CB20) else [12, 13, 14, 11, 0][r - 1].
  **Kraken in the fight** (char 8): table 0x0C33CF34, category 0 = [0, 1] (no item 2).
| rule (item_check.py items) | score |
|---|---|
| chests 1 / 2 dropped on fight frame 0 / 599 | 69/69 |
| chest on a drop spot (x/z exact) | 122/122 (stg_a0's drops use row 2, Wang-Tang's spots: the logged Final Valgas fight) |
| chest spot = the free spot farthest from both fighters | 118/122 |
| item id in category seq[chest number] | 115/117 (the fxitem_idN chest 2s excluded: poked) |
| untouched chests open at 365-366 frames | 97/97 |
| item pops vy 20, gravity 2 | 92/92 |
| pick-up motion = the family of the id | 17/17 |
| item ready 23 frames after it appears | 91/92 |

## 6. ITEMS: ids, classes, motions, use (logged + tables)
Per-id tables: **object handler 0x0C33618C** (u32 x 18) and **mesh node count 0x0C3361D4** (u32 x 18):
| id | category | handler (class) | nodes | carry family (kind 2: pick-up / idle / walk / jump 4-5-6 / use floor / use air) | use, logged |
|---|---|---|---|---|---|
| 0 | 0 | 0x0C05AD7C shooter | 1 | 237 / 238 / 239 / 240-242 / **243** / 244 | a projectile at ~20 cm/f leaving smoke puffs every 2 frames (39.8 cm apart, y 157-165) from k2/243 frame 20; 2 hits 16 + 33 (impact + blast), tumble k2/112; gone after 2 uses |
| 1 | 0 | 0x0C05C118 held melee | 2 | 237 / 238 / 239 / 240-242 / **245** / 246 | swing k2/245 31 f; 31 per hit, launch k2/96; 3 of 3 uses, kept |
| 2 | 0 | 0x0C05AD7C shooter | 1 | **80** / 81 / 82 / 83-85 / **86** / 88 | one shot per use: muzzle puff on k2/86 frame 11 (70 cm ahead, 157 up), the hit 4 frames later 160 cm away (~40 cm/f); 26, launch k2/96; 4 uses, gone 461 f after the pick-up |
| 3 | 1 | 0x0C05B6DC held melee | 1 | **195** (as 4) | k2/197 45-53 f; 52, tumble k2/112; 4 uses; dropped 600 f after the pick-up |
| 4 | 1 | 0x0C05B6DC held melee | 1 | **195** / 194 / 196 / 198-200 / **197** / 201 (run 202 > 203, stop 204) | k2/197 45-53 f; 42, tumble k2/112; dropped 600 f after the pick-up |
| 5 | 1 | 0x0C05B6DC held melee | 1 | **195** (as 4) | k2/197; 50, tumble k2/112; 4 uses; still held after 653 f |
| 6 | 1 | 0x0C05B6DC held melee | 1 | **247** / 248 / 249 / 250-252 / **253** / 254 | fx-obj lonA-C: 62 floor + 43 air uses |
| 7 | 2 | 0x0C05BA30 thrown | 3 | **229** / 230 / 231 / 232-234 / **235** / 236 | released on k2/235 frame 10, the item flies 25.0 cm/f straight at the opponent's hip (Ryoma's carry-throw speed, OBJ.md 6b), 7 f; 32, tumble k2/112; used up |
| 8 | 2 | 0x0C05BA30 thrown | 3 | **229** (as 7) | as 7: 25 cm/f at the hip, 32, tumble; used up |
| 9 | 2 | 0x0C05BA30 thrown | 3 | the OBJECT carry: k2/219 17 f / 220 / 221, throw k1/60 (air k2/225) | explodes: 40 to BOTH fighters (thrower too), tumble; used up |
| 10 | 2 | 0x0C05C728 thrown | 2 | **229** (as 7) | same flight; 2 hits 24 + 24, reaction k2/176 > 178 > 99; used up |
| 11-14 | 3 (option byte 0x0C7F4750 > 0 only) | 0x0C05D8C4 / DC20 / E118 / AD7C | 1 / 1 / 6 / 2 | never dropped in a normal fight | |
| 15-17 | 3 | 0x0C05EB84 food | 1 | not picked up: eaten on touch, +95 / +47 / +23 | |
- **Pick-up** (0x0C0A19DC on the ACTION input = B, a floor item at rest touching the body, not food): **state 35**
  (init 0x0C0A070E): an item more than 90 deg off the facing -> a **5-frame turn first** (sub 1, +0xEC 5: the logged
  `s35 k0/0 x5`), sound 14 + voice 18, the item -> set_state(obj, 5 = held, player) (owner = the player, position
  = an offset on the hand); then the family's pick-up motion **24 frames** (12/12 logged pick-ups use the family of
  their id: 17/17 with the forced runs); then the family's idle / walk / jump motions replace k0/* while held.
- **Use**: punch or kick while holding = **state 10 kind 15** (+0x721F = 15; state-10 init 0x0C0A1B1A when the held
  class != 1) with the family's floor / air use motion. The hit uses the object/item attack records 0x0C33AB08
  (OBJ.md 6b) through Rules.game_damage; logged damage above (CPU level 9 victim Falcon).
- **Floor lifetime** (not picked up, nobody within 300 cm; from ready to gone): **id 8 277, ids 7 / 9 457, ids 0 / 1 /
  2 / 3 / 4 / 5 / 10 362-363 frames**; a fighter nearby extends it (stg_20 id 10: 913). The spot is free again after.
- **Meshes** (real disc data, ripped with tools/psmdl.py from **1ST_READ.BIN file offset 0x171088**, 324 parts; the RAM
  node pointers point straight into it: object +0x2E0.. nodes, node +0x9C = the part): **gems** colour 0 / 1 / 2 =
  parts **139 / 67 / 140** (+ glow parts 31 / 32 / 33), **chest** 56 / 126 / 57 / 58 / 59 / 127, **items** = the item
  bank (RAM 0x0C664988 {1, 35}, table **0x0C1D6D70**: entry 0-15 -> parts 142-157, then 161, 162, 158, 159, 160, 176,
  174, 175, 163-173); logged in RAM: **item 2 = part 144**, **item 8 = parts 149 + 155 + 157** (Flycast i1, Londo
  f420 / f1020).
- Ids 3 / 5 / 8 / 9 / 10 were logged by forcing them (tapes `fxitem_idN`: the category-0 list 0x0C33CF00..02 poked to
  the id at frame 10, so the round's second chest holds it; then items_weapon's pick-up at 985 and 3 X + 3 Y at P2;
  logs `dumps/fidelity/o_fxitem_idN*`). Item parts 142-157 use material texture 0 and 158-176 texture 1 of the item texture set
  (ITEM_MODEL.BIN, the only item texture file on the disc; decode with pstex.decompress).
- **CPU**: docs/CPU.md (FIND_KIND6 / FIND_KIND7 score items / chests like FIND_ITEM, interrupt 0x02 = a new item,
  0x100 = an item thrown at me, REG_HELD = the held id).

## 7. Port (arena.gd / a new item.gd / fighter.gd; m = cm * 0.01, per frame at 60 Hz)
1. **Drop clock + spots** (section 1-2, item_code.json `drop_spots`, `drop_clock`): one `DropClock` in arena.gd for
   gems AND chests (a drop = the queued gem, else a chest); spot = the free spot with the largest summed distance to
   both fighters; a spot is occupied while a gem / chest / floor item stands on it.
2. **Chest** (type 2 kind 7, meshes bank parts 56 / 126 / 57 / 58 / 59 / 127): at the spot; the item appears at
   drop + 354 (or the frame the chest is hit), the chest goes at drop + 365; the item pops from spot y + 0.09 m with
   vy 0.20 m/f, g 0.02 m/f^2, ready 23 frames later. Item id = `item_pick` (seq [2,0,1,0,1,2,2,0,1,0] by chest
   number in the round, category lists, the game's C rand like Roster.pick_row; Kraken: category 0 = [0, 1]).
3. **Floor item**: stays on its spot `floor_life_logged[id]` frames after ready (nobody within 3 m; a fighter near
   holds it), then gone and the spot is free. Food 15-17: eaten on touch (+95 / +47 / +23, cap 240), never carried.
4. **Pick-up** (fighter.gd, lead): ACTION (B) touching a ready floor item (not food) -> gst 35: more than 90 deg off
   the facing = 5 frames turning first, then the family's pick-up motion 24 f; the item rides the right hand (owner =
   the fighter); while held the family's idle / walk / run / jump motions replace k0/0 / 3 / 25 / 5-6.
5. **Use**: X or Y while holding -> gst 10 kind 15 with the family's floor / air use motion; class by
   `handler_by_id`: shooters (0, 2) spawn shots (0: one per frame of the use = a stream, 2: one per use), melee
   (1, 3-6) hit with the motion, thrown (7-9) send the item itself at the opponent's hip (24.7 cm/f) and it is used
   up; damage through Rules.game_damage on the item's record (logged: 0 16 + 33, 1 31, 2 26, 4 42, 7 32 on Falcon at
   CPU level 9).
6. **Hit while holding**: drop it like a carried object (OBJ.md 4 "Dropped").
7. **CPU** (cpu.gd): FIND_KIND6 / FIND_KIND7 + interrupts 0x02 / 0x100 already in cpu_ai.json (CPU.md): give them real
   targets (floor items / chests) once 1-6 exist.

## 8. Not done yet + fighter.gd requests (lead)
Not done: the shooters' shots themselves (the type-5 kind-1 objects are smoke puffs, handler 0x0C043706, position in
node +0x80; the speeds above come from the puff trail / hit frame, not from the shot's own record); the held-item limit (ids 3 / 4 dropped 600 frames after the
pick-up, id 5 not by 653, the shooters used up after 2 / 4 uses: rule in the item handlers 0x0C05AD7C / 0x0C05B6DC
not decoded); the chest's hit-open rule (handler 0x0C05D4E4); per-id floor life table (measured only); the item
texture mapping in ITEM_MODEL.BIN; meshes of ids other than 2 / 8 (same RAM recipe: a dump with the item out).
fighter.gd requests, by player impact:
1. **Item clips**: none of the item motions are in the clip bank (clip_frames.json has no k2/80-88, 194-204,
   229-254): capture them for all 10 fighters (`tools/add_clips.py capture N PREFIX k2_080,k2_081,k2_082,k2_083,
   k2_084,k2_085,k2_086,k2_088,k2_194,...,k2_204,k2_229,...,k2_254`, then build) before porting section 6.
2. **Items** (section 7.4-7.6): gst 35 for items (5-frame turn, family pick-up 24 f), carry-family motion overrides,
   gst 10 kind 15 uses, drop when hit; evidence 17/17 pick-ups, the fxitem / items_id logs.
3. **Gem spill** (section 4 port 6): `arena.spill_gems(global_position, lost)` (fighter.gd 496 / 1971) spills ALL lost
   gems in a random direction; the disc spills 1 (2 on byte-16 & 8 hits) toward the attacker only when 1 <= gems < 3
   and not in PC, from feet + 100 up + 100 along the heading at 20 cm/f, vy 30, g 1.2.
4. **Power Change start** (fighter.gd 771 `scatter_gems`): queue the 3 colours on the drop clock instead of scattering.

## 9. Port (fx-item2, 10-27): chests + items in the remaster
Code: `game/scripts/items.gd` (Items, one per arena: ItemChest / Item / ItemShot), fighter.gd "## Items (fx-item2)" +
marked one-line hooks (`# fx-item2 hook`) in `_core_actions`, `_core_tick` (velocity after the state handler, the 0 / 2 /
31 / 32 and 35 transitions, the air branch), `_gset`, `receive_hit`, `react_start`, `_rx_record`, `_spill_n`,
`_core_attack_tick`; arena.gd marked hooks in `gem_round_start` / `_drop_tick` / `_drop_gem` / `_free_spot` / `tick` /
`clear_gems`; cpu_game.gd `_w_item_objects` (FIND_KIND6 70 / FIND_KIND7 71). Data: `game/assets/fidelity/items.json`
(tools/item_mesh.py: parts per item, the 70 records of 0x0C33AB08). Meshes: `game/assets/ripped/items/*.glb`
(untracked, `tools/item_mesh.py` rebuilds them; contact sheet `tools/item_sheet.py`), the chest = bank parts 56 / 126 /
57 / 58 / 59 with EFKY_MODEL.BIN textures, items = ITEM_MODEL.BIN (texture tables 0x1C7414 / 0x1C76B4 in 1ST_READ; the
item init 0x0C05A990 takes node 0 from byte 0 of 0x0C335F28 + id * 4, items 7 / 8 / 9 two more nodes from
0x0C33C7A8). Both looks use the same disc mesh (Remaster: HD.stage_mats on it).
- **Chests** on the drop clock: chest 1 on fight frame 0, chest 2 at 599, later ones when a drop finds no queued gem.
  Per chest from its first row: shake +5 cm x at 320 / 322 / 324, the item at 355 (spot y + 9, vy 20, g 2), chest gone
  366, item ready 378 (chest 1: one row less, the disc makes it on the frame before its first row). Item = the
  category of the chest number + `CPUGame.crand() % count` (the C rand). A shot passing a closed chest opens it.
- **Floor item**: gone `floor_life` frames after ready while nobody is within 300 cm (362 / 457 / 277 by id).
- **Pick-up** (B, a ready item within 1.45 m): state 35, 5 rows of turn when the item is >= 90 deg off the core heading
  (the logged @place case), then the family's pick-up motion 24 rows (25 without the turn; item 9 = k2/219 17 / 18),
  the item in the right hand (joint b08, logged offsets for 1 / 3 / 5; item 9 overhead like a stage object).
- **Held**: idle = the family's idle; the stick = state 2 with the family walk at the move table's [3] (family 237) or
  [1] (the others), at least 10 rows; family 195 (3 / 4 / 5) = the core's run with k2/203 and a 30-row stop k2/204 at
  9.5 * (8 - k) / 7; jumps play the family's crouch / air / land; a hit drops it (falls from 180 cm, vy 10, g 2, 5 cm/f).
  Ids 3 / 4: dropped 600 rows after the pick-up, gone 51 later (items_id4 992 > 1592).
- **Uses** (X / Y): state 10 with the family's use motion for `Items.USE[id].n` rows. The hit comes from the item, not
  the fighter's hit data (none for k2 motions): shooters / thrown items = an ItemShot aimed at the opponent (the logged
  P1 faced away from P2 and still hit him) from the use frame in USE, swept hit test against his body axis; 3 / 4 / 5 / 6
  = a reach test on use frame 13 (PROVISIONAL, one logged hit at 281 cm; the k2/197 travel is not ported). Damage =
  Rules.game_damage on the matched record of 0x0C33AB08 (class, base, type b4: 7 = no gem bonus), its reaction through
  the reaction machine (`item_react_rec`), the gem spill by its byte 16. Item 9's blast is nobody's (40 to both, the
  thrower 6 frames later); item 10 hits twice (24 + 24). Used up: thrown items at the release, item 0 after 2 uses,
  item 2 after 6 (items_id2: 6 uses; the fx-obj "4 uses" log ended earlier). Fighters landing / lying / getting up from
  a launch are not hit (items_weapon: the 2nd shot passed Falcon in k2/99, the 3rd hit him the row after he stood up).
- **Harness** (tests/tape_run.gd): logs the arena's chests / items per row (`items`: [7 chest | 6 item, id, x, y, z,
  sub]); sets the C rand state to the disc's logged one at the start of every row (the disc's other draws, effects,
  are not ported, so the item picks only match that way: chest 2 / 3 of items_weapon exact), and hands chest 1 its
  logged item (drawn on the fight's first frame, before the harness's rand reset).

Proof (FID_OUT=/tmp/ps-fx-item2/fid, `tools/fidelity_run.py rem|diff`, `tools/item_port_check.py`):
| tape (Ryoma P1, item) | P1 state | P1 motion | P2 state | P2 health | note |
|---|---|---|---|---|---|
| items_weapon (1) | 96 -> 100 % | 60 -> 100 % | 89 -> 100 % | 67 -> 100 % | hit rows 1106 / 1197 = disc |
| items_id2 (2) | 94 -> 100 % | 75 -> 100 % | 84 -> 99 % | 67 -> 100 % | first hit 1 row late |
| items_id4 (4) | 91 -> 100 % | 64 -> 100 % | 91 -> 96 % | 67 -> 100 % | hit 1 row early; P1 x 66 % (k2/197 travel) |
| fxitem_id3 / 5 (3 / 5) | 91 -> 100 % | 64 / 60 -> 100 % | 91 -> 96 / 95 % | 67 -> 100 % | |
| items_id7 / fxitem_id8 (7 / 8) | 96 -> 100 % | 92 -> 100 % | 91 -> 94 % | 67 -> 100 % | hit 1 row late |
| fxitem_id9 (9) | 88 -> 94 % | 84 -> 92 % | 90 -> 94 % | 67 -> 100 % | both hit 1 row late |
| fxitem_id10 (10) | 96 -> 100 % | 92 -> 100 % | 90 -> 90 % | 67 -> 100 % | P2's class-21 reaction (k2/176 > 178 > 99) not in the machine |
Before = master 2f8da7d on the same tapes (FID_GAME snapshot, /tmp/ps-fx-item2/fid_master), after =
fx-item2 with Ryoma's in-fight family clips (tools/fight_clips.py, docs/CLIPS.md). The 1-row hit offsets: P2's @place
spot (the disc pushes him 12 cm off Londo's fountain base, the remaster leaves him on it). The 11 stage tapes give the
same numbers as master (nobody picks an item up there). Chests 1-2 over the 20 tapes (`tools/item_port_check.py`): drop /
item / ready / gone rows exact 125 / 160, within 1 row 145 / 160 (chest 1 shows 1 row late in the remaster's log: it is
made on the first fight tick; the rest: chests the disc's fighters opened early by hitting them), spots 36 / 40, items
40 / 40 (with the harness's rand sync). Later chests depend on who picks what up when (movement / CPU fidelity).
Not done: uses in the air (X / Y in the air does nothing while holding), the use motions' travel, the items' own hit
objects (USE is fitted on the logged hit rows), Power Change with an item in hand, food (option byte only), the
phase-4 drop rows (items_weapon / items_id4: the first drop after a spot frees comes 302 rows later, after a drop with a
spot free 301: the remaster's clock fires at 300; and items_weapon's chest 3 (1136) opened into no item at all), the
CPU's held-item logic (REG_HELD, _w_ai_item_held / _w_ai_kind still see stage objects only), item sounds.
Requests (fx-item2 -> owners): (lead, reaction machine) class 21 = k2/176 > k2/178 > k2/99 (item 10, records 9 / 10 /
38 / 51 / 55 / 57 / 64), today react_start declines it and the old reaction runs; (arena owner) the tapes' `@place 2 20 0
0` lands P2 on Londo's fountain base at (20, 56, 0), the disc pushes him to (31.9, 56, -29.9): the 1-row hit offsets of the
item tapes; (fx-cpu4) `_w_ai_kind` -> 6 / 7 for Items.Item / ItemChest and `_w_ai_item_held` / REG_HELD -> the held item
(Fighter.item, its id). Merge note: game/assets/ripped/items/ is untracked: run `tools/item_mesh.py` in the target checkout
(or `cp -cR` the folder) and `Godot --import`; Ryoma's / Falcon's rebuilt rigs (p00 / p01 / p10 / p11 in assets/ripped and
assets/hd, fx-item2-clips) are untracked too. items_id0 / id3 / id5: their disc runs did not take the chest poke (they hold
items 2 / 1 / 1), not usable as proof for ids 0 / 3 / 5 (fxitem_id3 / 5 are).
