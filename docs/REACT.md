# The original's hit-reaction machine (BUG-17 / BUG-18): decoded spec

Lane pstrailer2, helper fx-react, 2026-10-27. Source: 1ST_READ disassembly (tools/ghidra/sh4dis.py; Ghidra's C for
0x0C08ED56 is wrong wherever floats or FPSCR appear, every number below is from the instructions), checked against the
per-frame reference logs (dumps/fidelity/o_*.jsonl). Tables + every fighter's records: game/assets/fidelity/react_code.json
(`tools/react_sim.py export`). Simulation + check: `tools/react_sim.py verify [-v]`, `show TAPE ROW P`.

Angles are u16 (0 = +z, 0x4000 = +x). One record angle unit = 2048 (737280.0 / 360.0 in the code = 11.25 deg).
"Row" below = one logged frame; row 0 = the frame the health drops (state 27 already set, motion not yet changed).

## Entry: how a hit starts state 27
- **Body hit** 0x0C08DACC(victim, hit_id) (called from the sphere test, 0x0C0555C4 / 0x0C338534 handlers):
  +0xF8 = record (table 0x0C338A98[opponent's char] + hit_id*20), +0x71BD = hit id, +0x10A = 1, +0x7294 = victim+0x1C
  (the attacker; 0 = no attacker), **+0x10B = rec[2]** (hit-stop, the attacker gets the same in 0x0C08DBC8),
  +0x71DE = old class, +0x71DD = rec[0] (class), +0x7211 = rec[0xd], +0x7212 = rec[0xe], +0x7213 = rec[0xc],
  **+0x72A8 = victim+0x30** (the collision code has just written the attacker->victim direction there: measured, the
  knockback heading follows atan2(victim - attacker), not the attacker's facing: 170/170 class-0 hits, 6 where the two
  differ), +0x7236 = 0, combo count (+0x720E of the attacker, 0x0C08D6AA, unless rec[4] == 7), hit sound
  0x0C0A3762(char, rec[0x12]) unless 99, damage 0x0C08DFA4 (stun meter: below), then +9 = 1, **+10 = 0**,
  +0xB..D = 0, +0x71BB = old state, **+0x71BA = 27**, +0x100 = 0.
- **Object / projectile hit** 0x0C08DEEC(obj, hit_id): same record fields from the object's owner table, +10 = 2,
  +0x72A8 = obj+0x30 (or 0x0C08D662() and rec[0xe] -= 0x20 when rec[0xe] >= 0x20).

## 0x0C08ED56 (state 27, called every frame): sub-step byte +10
| +10 | address | what |
|---|---|---|
| 0 | 0x0C08EDA8 | full init (body hits), then falls into 1 the same frame |
| 1 | 0x0C08EF36 | per frame: hit-stop countdown, shake, ground gravity, tech buffer, class handler |
| 2 | 0x0C091F0A | short init (object hits: no gem/side/remap calls, no sound), +10 = 3, falls into 3 |
| 3 | 0x0C091EEE | per frame for object hits: 0x0C098C82 + class handler (no hit-stop, no gravity) |
| 4 | 0x0C092814 | guard (block) reaction: k0/33-38, CPU random guard (table 0x0C1508C4), not in this pass |

Init (+10 = 0): +0x38..+0x4C (velocity, acceleration) = 0, +0x71E8 = 0, +0x72AC = 0, +0x72A4 = 20 (tech lock-out
frames), +0x721A = 0 (wall hits), 0x0C099B60 / 0x0C09A7BA, +0x720A = 0, face/hands = 1/1/1 (+0x710A only if not
PC), then **0x0C08E8D6** (side), +0x7216 = 0, **0x0C08E704** (class remap), 0x0C08ED08, 0x0C08E980 (reads
health: gem drop, not decoded), **0x0C08E4BC** (status effects rec[0x11] & 0xE0: 0x20 = +0x7226 effect 300 f,
0x40/0x60 180 f + effect sounds 0x27/0x28, 0x80 = 60-frame stun effect with +0xEE = 0; voices for rec[4] 1 (first
combo hit) / 6 / 7: sample 0x2B/0x15, 0x29/0x13, 0x28/0x12 by player), sound: rec[5] == 0 -> rec[0x13] == 0 ?
0x0C0D905E(10) : 0x0C0DAB92(rec[0x13], player).

Per frame (+10 = 1, 0x0C08EF36):
1. **Hit-stop**: if +0x10B != 0: --+0x10B (== 0 -> +6 = 0). Every class handler returns at once while +0xB > 0 and
   +0x10B != 0. Net effect: the init frame runs the handler's step 0, then **rec[2] - 2 frozen rows** (rec[2] <= 1:
   none), then step 1. Measured: launch rec[2] = 8 -> 6 frozen rows (o_atk_ground rows 30-35).
2. Shake 0x0C08E57E(p, 10) on odd hit-stop frames (class 23 excepted).
3. 0x0C098C82(p): per-frame fighter update incl. the body push against the other fighter (this is why a victim of a
   moving attack drifts 0.35-7 cm/frame beyond the knockback table, see "mismatches").
4. Ground gravity: if +0x71BC != 2 (not airborne), +0x274 <= 0 (no floor under the feet) and class != 23:
   +0x71E8 += +0x71E4; y += +0x71E8 (falls off a step while reeling). Else +0x71E8 = 0.
5. Tech buffer: 0x0C08EEF4(p) (a button) and +0x72AC == 0 -> +0x72AC = 5.
6. handler 0x0C338FF8[+0x71DD](p).

## Side: 0x0C08E8D6 -> +0x7205 (rows of every motion table)
Skipped when +0x71BC == 3 (lying). +0x7205 = 0; if +0x7294 != 0: d = s16((+0x72A8 - rec[0xe]*2048) - +0x30)
(+0x30 = the victim's body yaw): |d| <= 0x1C71 (40 deg) -> 1 (**hit from behind**), 0x1C71 < d <= 0x638E -> 2,
-0x638E <= d < -0x1C71 -> 3 (sides), else 0 (front).

## Class remap: 0x0C08E704 -> +0x71DD (the class that actually runs)
In order: rec class 23 -> unchanged, stop. **Health < 0 (KO) -> +0x71DE = class, class = 1** (always the launch).
+0x71BC 0/1 (standing): rec[0xb] == 3 and old state 9 -> 17. +0x71BC 2 (airborne): class 0,4,8-15,17,18 -> 1
(rec[4] == 0) or 2; 24 -> 3. +0x71BC 3 (lying) -> 13. Old state 7 -> 3; 34 (pole) -> 19; 36 -> 20; old state 27
with old class 11 or 7 -> 1. rec[0x11] & 0xE0 == 0x80 -> 7. Else **stun meter +0x7214 == 0** and (+0x71DF != 0 or
class not in {1-6, 16, 22} (table 0x0C1507A8)) -> class 2 with +0x7211 = 7, +0x7213 = 6 (the dizzy launch).
- **Stun meter** +0x7214: 20 at round start and after the dizzy state (table 0x0C338E12[char] = 20 for all; writes
  0x0C09961A, 0x0C0A1F52); each damaging hit subtracts rec[7] & 63 (0x0C08E2F2, clamped at 0) and sets +0x7215 = 180.
  Refill when +0x7215 runs out is ASSUMED (refill after 180 quiet frames reproduces every logged dizzy: 7 x 3 = 21 > 20
  on the dist_* tapes' 111-frame jab cadence). After a dizzy launch the get-up ends in **state 13** (k2/175 dizzy,
  58-180 rows, ended early by the next hit) instead of 0; class 0 also ends in 13 instead of 24 when the meter is 0.

## Which classes occur (records referenced by the fighters' HIT.BIN steps, 11 fighters)
| class | handler | used records | logged hits | what |
|---|---|---|---|---|
| 0 | 0x0C08F418 | 156 | 162 | standing hit: k2/base > base+1 (knockback table) > base+2, state 24 |
| 1 | 0x0C08FBE8 | 87 | 31 | launch (front k2/96>97>98>99 / back k2/128>129>130>131), lying, get-up; KO |
| 2 | 0x0C08FBE8 | 21 | 20 | same handler; rec[4] != 0 air version; the dizzy launch |
| 3 | 0x0C08FE4E | 83 | 14 | tumble k2/112 > bounce k2/115 > lying |
| 5 | 0x0C090304 | 15 | 0 | not decoded |
| 6 | 0x0C090540 | 15 | 0 | not decoded |
| 8 | 0x0C0908DA | 5 | 0 | not decoded |
| 9 | 0x0C09098C | 1 | 0 | not decoded |
| 14 | 0x0C090D1C | 9 | 0 | not decoded |
| 22 | 0x0C091B3C | (runtime) | 28 | wall splat k2/152 > slide > k2/153 > lying |
| 23 | 0x0C091DAE | 3 | 0 | no reaction (no shake, no remap) |
| 24 | 0x0C091DD0 | 33 | 0 | not decoded (airborne victims run class 3 instead, see the remap) |
| 27, 29 | 0x0C09215C / 0x0C0923F0 | throw records | 9 | thrown (k4 motions), not decoded |
Class counts over ALL records in the tables (incl. unused): 0 561, 3 493, 27 162, 1 151, 2 47, 24 37, 5 20, 9 19, 6 18,
99 12, 14 12, 23 10, 8 8, 98 7, 29 6, 4 3, 16 3, 22 3, 18 4, 19 2, 240 2, 7/11/28/255 1 (98/99/240/255 = filler).

## Class 0 (0x0C08F418): standing hit
Step 0 (init row): old state 27/24 -> +0x30 turned toward the opponent (0x0C09DB78) or by 0x4000. Base motion
**k2/base**: rec[6] != 0 -> T[side*6 + rec[6] - 1]; rec[6] == 0 -> T[side*6 + col], col = 0 (+0x71DC 1/2), 1 (3..5),
2 (else), +3 when rec[0xc] > 3; +0x71DC = attacker+0x103 (written in 0x0C08D6F0, meaning not decoded). T = 0x0C1507CE when +0x71BC == 0, else
0x0C1507E6 ("000333<<<???EEEEEEKKKKKK"):
`side0 [0,6,18,3,9,21] side1 [12,12,12,15,15,15] side2 [27,27,36,27,27,39] side3 [33,33,42,33,33,45]`, air
`[48x3,51x3] [60x3,63x3] [69x6] [75x6]`. +0xF0 = max(1, rec[3] - 1); +0xEE = (entries > 0 in the knockback table) -
(base motion's first key length), min 1; **heading +0x7248 = (+0x7294 ? +0x72A8 : +0x30) - rec[0xe]*2048**;
+0x3C = +0x48 = 0; +0xF2 = 0.
Step 1 (first row after hit-stop): k2/base+1, +0x71A8 = 0, +0x71A9 = +0xEE, then step 2 the same row.
Step 2 (each row): --+0xEE (< 1: motion runs); v = KB[rec[0xc]][+0xF2]: v >= 0 -> move v cm along the heading,
+0xF2++; v < 0 -> **k2/base+2**, +0xF0 = max(+0xF0, 2), +0x71A6 = +0x71A7 = +0xF0 - 1, step 3. Then --+0xF0.
Step 3: motion runs, --+0xF0. **+0xF0 reaches 0 -> 0x0C0A2E26(p, stun == 0 ? 13 : 24)** (that row shows the new state).
State 24 (hit recovery): 8 rows k0/0, then state 0 (measured 147/151; the rest were hit again).
Knockback tables 0x0C338C34[rec[0xc]] (cm per row): 0 [0,0,0], 1 [10,5,3,1,1], 2 [20,10,5,3,1,1], 3 [30,15,7,4,2,1,1],
4 [40,20,10,5,3,1,1], 5 [50,25,12,6,3,2,1], 6 [20,18,16,14,12,10,8,6,4x5], 7 [22,20,...,4x6], 8-15 [40,32,26,23,20,
18,...,4x7]. Rows: init 1 + (rec[2]-2 frozen) + n_kb rows of base+1 + (rec[3] - 2 - n_kb) rows of base+2.
Example Ryoma jab (hit 1, rec 000a0019..0204..): k2/0 1, k2/1 6 (20,10,5,3,1,1 cm), k2/2 17, state 24 8.

## Class 1 / 2 (0x0C08FBE8): launch, KO
Step 0 (0x0C08F794): **position = the victim's hip bone world position** (0x0C0CCF32 copies the bone matrix at
player+0x300+0x160 (+0xDC0 in Power Change) into +0x20: +83..100 cm up, a few cm toward the attacker; the remaster
takes its own skeleton's hip), +0x71BC = 2, velocity 0x0C08E5B4: **v = R_y(yaw) R_x(-rec[0xd]*11.25 deg) (0, 0,
S)**, S = 0x0C338CB4[rec[0xc]] = [7,12,14,16,18,36,40,44,48,52,56,60,64,68,72,76], yaw = +0x72A8 - rec[0xe]*2048
(object hits the same with their angle), i.e. vy = S sin(rec[0xd]*11.25), horizontal S cos(.) along yaw;
**gravity +0x48 = -2.0**, +0x44 = +0x4C = 0. +0xEC = 0, +0xF0 = 3 (wall check delay), +0xEE = |vy / g|.
Motion +0xF2 (body hits, class and record class both 1/2): rec[6] 2 -> 128 if side != 1 (side := 1) else 96
(side := 0); rec[6] 3/4 -> 112; else **96 (front) / 128 (side 1 = behind)**. Object hits: 96/128 by side only.
Then k2/+0xF2, +0x71A8/9 = 1; health < 0 and Power Change -> 0x0C0A167C (revert) and gems +0x7230 = 0 (KO).
Step 1 (0x0C08F9FC), every row after the hit-stop: +0xF0 > 0 -> --+0xF0, else **wall check** 0x0C08F4D8; pole tech
0x0C08F6C8 (class 1, tech buffer, +0x72A4 == 0, a pole in reach -> state 34); --+0xEE; motion runs; for 96/128:
motion end -> **+1 (97 / 129, held)**, +0x71A9 = +0xEE; then **vy < 0 (before the move) -> +2 (98 / 130)**, hold
trunc(sqrt(|2y/g|)). If vy < 0 and the feet are on the floor (0x0C09E7B8): snap to the floor, landing 0x0C08F71C
= **k2/99 (side != 1) / k2/131 (side 1)**, sound, +0x71BC = 3, step 2. Else move (0x0C09D990: pos += v, floor and
wall collision clamp) then gravity (0x0C09D9BC: v += a).
Step 2 (0x0C08FB7E): motion runs; at its end **state 15 lying** (0x0C0A2E26(p, 15, side == 1): k2/144 face up /
k2/145 face down), then state 16 get-up k2/146 / k2/147 23 rows, state 16 k0/0 7 rows, state 0.
Air tech (class 1 only, handler 0x0C08FBE8 tail): +0x72AC (button within 5 frames), +0x72A4 == 0 (20 frames after the
hit), health >= 0, 0x0C0555C4() and step 1: y > floor+100 -> state 24 recovery in the air (0x0C0A2E26(p, 24, 4)),
else y = floor - 1 and state 16 (0x0C0A2E26(p, 16, 2)): the quick get-up. Wall tech: in the wall check, class 1 + the same conditions -> state 38 (wall kick).
Measured (Ryoma k1/74 launcher, hit 19, rec 010a0818..0604..07): hip (51.4, 99.4) then 28.284 / 28.284 cm per row,
-2 per row, k2/96 18 rows (1 + 6 frozen + 11), k2/97 4, k2/98 until the floor or a wall: exact in the logs.

### Walls during a launch: 0x0C08F4D8
Only when +0x721A < 2 (two wall hits per reaction). side = 0x0C09CD32(p) (0 = no wall). +0x721A++, sound, 0x0C09B7A4.
Wall tech (above) else, if side != 8 and 0x0C09D818(p, side) >= 0 and (rec[0x10] & 1) == 0: **wall splat, class 22**:
+0xB = 0, +0x30 = (side - 4)*0x4000 + 0x8000 (back to the wall), k2/152, y -= 0x0C09B74C(p) (119.0 on every logged
splat), y >= floor, +0xEC = 20, +0xEE = 13, v = 0, **gravity -1.0**, sound 10. Otherwise **bounce**: sides 4/6: vx /= 2,
vz = -vz/2; sides 5/7: vx = -vx/2, vz /= 2 (speed halved, one component reflected).

## Class 22 (0x0C091B3C): wall splat
Step 0: +0xEC > 0 -> --+0xEC (motion runs while +0xEE > 0): **20 rows stuck** on the wall. Then each row: vy < 0 and on
the floor -> **k2/153**, step 1; else move + gravity (-1/row: slides down 1, 2, 3 ... cm). Step 1: motion runs; end ->
state 15 (k2/144). Measured: 152 x (1 + 20 + slide), 153 x 40, lying 5, get-up 23 + 7.

## Class 3 (0x0C08FE4E): tumble
Step 0: +0x71BC = 2, velocity 0x0C08E5B4 (as class 1), position = hip bone, **k2/112**, voice 0x0C04B054. Step 1:
wall check (no 3-row delay); vy < 0 and on the floor -> **bounce**: vx, vz x 0.5, **vy = 11.6, gravity -0.97**, k2/115,
+0x71BC = 3, snap, dust; then (every row) motion, move, gravity. Step 2: move, gravity; vy < 0 and on the floor ->
state 15 (k2/144).

## KO (health < 0)
Class forced to 1 (launch, front/back by side) with the record's own speed/elevation; Power Change reverted and gems
cleared at step 0 of the launch. After landing the state is 8 (KO'd lying, k2/144 206+ rows) instead of 15; the
slow motion of the final hit (k2/96 129 rows instead of 18 in o_hits_down) is a global timer outside this machine
(BUG-23), and the substep-4 path (+0x71D4 < 0 -> back to state 27 init) covers a KO while guarding.

## Verification (tools/react_sim.py verify; 374 logged hits, 31 tapes)
Inputs per hit: record, attacker->victim direction, body yaw, position, old state, health, stun meter (tracked over
the tape), hip position (first launch row), wall contact row + clamped position (stage geometry).
| class run | hits | motion chain exact | rows per motion exact | travel within 1 cm |
|---|---|---|---|---|
| 0 | 148 | 137 (93%) | 135 (91%) | 120 (81%) |
| 0 -> 2 (dizzy) | 14 | 8 | 6 | 13 |
| 1 (open floor) | 4 | 4 | 2 | 2 |
| 1 -> 22 (wall splat) | 27 | 25 | 20 | 22 |
| 2 | 20 | 17 | 15 | 16 |
| 3 / 3 -> 22 | 14 | 14 | 11 | 7 |
| 0 -> 1 KO, 2 -> 1 KO | 2 | 0 | 0 | 0 |
| 27 / 29 (throws) | 9 | not simulated | | |
| hit id 0 (objects, throws, projectiles: attacker +0x100 = 0) | 136 | not simulated | | |
Mismatches, explained:
- **Lying time 5 vs 10 rows** (most "rows" misses of classes 1/2/3/dizzy): state 15 k2/144 lasts 5 rows in 66 of the
  89 logged lyings and 10 in 23, after every kind of landing (99, 115, 153), with no victim input in either case
  (checked against the tapes). The sim uses 5; the rule is in state 15's handler (not decoded).
- **Side (+0x30) in combos** (class 0 chain misses: k2/33 or k2/12 vs k2/0): the body yaw +0x30 isn't logged; mid-combo
  the game turns it (0x0C09DB78), the sim assumes "facing the attacker".
- **Body push** (class 0 travel misses with exact chains, 0.35-7 cm/row extra): the attacker's moving attack pushes
  the victim through 0x0C098C82, not the knockback table (the core's push already exists).
- KO: slow motion (BUG-23) stretches k2/96; dizzy k2/175 length = until the next hit.

## What the lead ports (fighter.gd requests)
1. On a landed hit: run the remap (KO -> 1, airborne -> 1/2/3, stun meter -> dizzy 2) and the side (+0x7205) exactly as
   above; hit-stop = rec[2] - 2 frozen rows for the victim (the attacker's own hit-stop is 0x0C08DBC8's +0x10B).
2. Class 0: motion ids from motion_table[side*6 + rec[6]-1], knockback table rows along heading = atan2(victim -
   attacker) - rec[0xe]*2048, rec[3] - 1 rows in state 27, then 8 rows state 24 (13 when the stun meter is 0).
3. Class 1/2/3: start at the hip bone, v = launch_speed[rec[0xc]] at rec[0xd]*11.25 deg, gravity -2 (bounce 11.6 /
   -0.97 for class 3), motion switch rules above, landing k2/99/131 -> lying k2/144/145 (state 15) -> k2/146/147 23 +
   k0/0 7 (state 16). Walls: splat (k2/152, -119 cm, 20 rows, slide at -1) or bounce (halve, reflect).
4. Stun meter per fighter: 20, minus rec[7] & 63 per hit.
All numbers are in game/assets/fidelity/react_code.json ("records" = every fighter's 20-byte records by hit id).

## Open
State 15 / 16 handlers (lying length vs input, get-up roll), 0x0C09B74C (the 119 cm splat drop: constant or
per-fighter), 0x0C09D818 (when a wall splats vs bounces), the stun refill timer, guard (+10 = 4), classes 5, 6, 8,
9, 14, 17-21, 24, 27-29 handlers, object-hit records (hit id 0 in the logs: thrown items, throws, projectiles), the
motion "hold" fields +0x71A6..A9 (rows per motion are right; the motion frame counter inside a held motion is not
modelled).
