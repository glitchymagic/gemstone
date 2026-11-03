# fx-mv: the disc's movement / action states (lane pstrailer2, 10-27)

Decoded from 1ST_READ (`tools/ghidra/sh4dis.py`, Ghidra `all_resolved.c`), measured on the disc's tape logs
(`dumps/fidelity/o_*.jsonl`) and the 48 CPU logs (`dumps/fidelity/cpu/*.jsonl`), diffed by tape
(`tools/fidelity_run.py rem|diff`). Code: `game/scripts/fighter.gd` section "Movement states (fx-mv)" + hook lines in
`_core_tick` (first line), `_core_actions` (the ACTION branch) and the air branch of `_core_tick`.
Units: cm, cm/frame, frames (60 Hz); headings u16, 0 = +z, 0x4000 = +x.

## 1. BUG-53: the ACTION button with nothing in reach

**ACTION input** (0x0C0A22D6) = punch pressed while kick is held, or kick pressed while punch is held (pad B = both bits
0x600 at once). Ground handlers (state 0 0x0C093812, 2/3 0x0C093998, 31 0x0C095EF8, 32): after the no-floor and the Power
Change tests, ACTION -> the ground action list **0x0C0A2490** (holding something: drop it; else grab 0x0C0A18F8 ->
state 37; pole touching 0x0C0A239A -> state 10 kind 10 (k1/147, section 1b); throwable at rest 0x0C0A19DC -> state 35
pick-up, a flying one -> state 25; in a run / get-up next to a wall 0x0C09D3C4 -> state 10 kind 11 (k1/156)). When the
list takes nothing, the attack press test **0x0C09E71C** runs as for any punch / kick press -> state 10 kind 0 (2 from a
run). Its selector **0x0C09E4AC** walks the fighter's command table **0x0C338E4C[char]** (16-byte entries: b0 = 0 a
string start, 1 a link, 9 a finisher, 99 the end; +4 the button 0x400 / 0x200; +8 a stick mask) and takes the FIRST
string start whose button was pressed. Entry 0 is the punch for every fighter but **Rouge, whose entry 0 is the kick**,
so B (both bits) = k1/16 for nine fighters, k1/24 for Rouge. +0x721E = 0 when punch was pressed (the punch/kick flag).
In the air the selector's air branch skips the table: punch pressed -> the air punch (k1/10).

Logged (every ground start of state 10 with ACTION-type presses, tapes): B / X+Y / B+X / B+Y from idle or a run = k1/16
for Falcon, Ryoma, Jack, Gunrock, Galuda, Kraken, Ayame (27 of 27), k1/24 for Rouge (5 of 5); the exceptions are the
list's own entries (k1/147 at Londo's lamp post 2x, k1/156 next to a wall 2x, the grab k1/84, the pick-up k2/219).

**Port** (`_mv_act`, `_mv_first_btn`, `_mv_action_attack`): the ACTION branch of `_core_actions` takes the disc's
ACTION input (B, or punch / kick pressed with the other held); grab, pick-up, then the selector's attack through the
same path as a plain press (object punch, run R-prefix, near). Rouge's B = her kick.

### 1a. The air ACTION dive (0x0C09E470, state 10 kind 4; also BUG-27)
Last entry of the air ACTION list: at least **150 cm above the floor below** and the **opponent not airborne** ->
k1/53 (shared init 0x0C06384A: horizontal 0, vy0, gravity 2.8), then k1/54 straight down, faster every row, until the
floor, then the landing chain from the frame after the floor. Measured on 66 dives (48 CPU logs + mash tapes):

| fighter | k1/53 rows | vy0 | k1/54 speed (from its 2nd row) | +per row | landing |
|---|---|---|---|---|---|
| Falcon | 14 | 20 | -15 | -1 | k1/146 18 |
| Rouge | 14 | 20 | -15 | -1 | k1/146 31 |
| Ayame | 14 | 20 | -15 | -1 | k1/146 25 |
| Ryoma | 14 | 20 | -25 | -1 | k1/56 16 |
| Kraken | 10 | 20 | -15 | -1 | k1/146 18 |
| Galuda | 10 | 40 | -20 | -1 | k1/56 27 > k1/146 30-32 |
| Valgas, Gunrock | 10 | 40 | -20 | -1 | k1/56 27 > k1/147 23 |
| Wang-Tang | 10 | 0 (no gravity) | -8 | -1.5 | state 6 k0/9 |
| Jack | 14 | 0 (no gravity) | -10 | -1 | k1/56 16 |

The first k1/53 row keeps the jump's own move; the first k1/54 row still follows the k1/53 arc (Falcon -16.4). A dive
that connects bounces off the victim on the disc (k1/55 46 > k1/56 9 > k1/10): **not ported** (the remaster keeps
diving after the hit-stop). No dive in Power Change (not logged) or for Final Valgas.
**Proof**: mash_s11 P2 f160-212 (Falcon): state, motion and y identical to the disc for all 53 rows (k1/53 316 > 397.6 >
k1/54 > floor at f190 > k1/146 18 rows > idle f209). Otherwise B in the air = the air punch (AX).

**B-press outcomes** (tools: scratch bmatch.py; every B press where the disc and the remaster were in the same state
before it, 5 mash tapes): **1 of 18 -> 9 of 13** matching the disc's next state + motion. Left: k1/147 (lamp post,
section 1b), k1/156 (wall), one pick-up reach, one pole catch.

### 1b. Not ported yet (decoded entry points)
- **Ground ACTION at a pole** (0x0C0A239A: +0x71C8 = a pole touching, on the floor): y clamped to the pole's foot, the
  body snapped onto the axis, state 10 kind 10: **k1/147 45 rows** in place > **k1/148** flight (Falcon: 27.5 cm/f
  out, -0.98 per row, vy 42.5 > -1.5 per row) until the floor > **k1/149 ~20 rows** (or k1/168 42 > k1/169 21 when it
  connects?). Gunrock / Galuda / Valgas and any fighter in Power Change instead pull the pole out (0x0C0ABE44(obj, 5)
  = it becomes a carried object, +0x7236 = 1). 13 logged (scratch seqscan.py 1 147).
- **ACTION in a run / get-up beside a wall** (0x0C09D3C4 on +0x7254): heading snapped to the nearest axis, state 10
  kind 11 = k1/156 > k1/157 (24 logged); in the air touching a wall with the stick held: kind 12.

## 2. dist_ryoma: the victim enters state 27 one frame late (request for the lead, not changed here)
Not the push order: the hit test reads the motion frame from the clip position (`_motion()`: clip frame + 1), and for
core attacks that frame is one behind the game's own counter `gmo_f` on the frame the attack sphere first appears
(Ryoma k1/74 attack set 1 from game frame 16; the disc hits at fr 16 = f28, the remaster at f29). Experiment (a scratch
copy of game/ with `_motion()` returning `[gmo, gmo_f]` while `core_atk` and the clip on display is `gmo`):
| tape | P2 state first divergence before -> after | P2 state share |
|---|---|---|
| dist_ryoma | f28 -> f136 | 50.6 -> 50.7 % |
| atk_ground | f28 -> f136 | 60.7 -> 60.3 % |
| near_ryoma | f28 -> f136 | 93.5 -> 93.3 % |
| dist_galuda | f26 -> f27 | 65.0 -> 65.1 % |
| dist_jack | f28 -> f28 | 64.6 -> 64.0 % |
The victim then shows k2/96 on f28 already (the disc: k0/0 on f28, k2/96 from f29) and is launched one frame early: the
reaction machine's first row needs the same one-frame hold.

## 3. Stage geometry off the disc: `game/assets/fidelity/mv_stage.json`
Read from fight-start RAM dumps by the fx-mv decode helpers (object pool 0x0C7D0980 + slot * 0x31C; shape lookup
0x0C02649A -> 0x0C022952; stage collision tables 0x0C33EB20 / 0x0C33EB60 per stage index; object descriptors
0x0C33BF58 + 8 * stage, 13-byte entries, byte [11] = hoppable):
- `poles` [x, z, bottom, top, radius]: 20 poles on 9 stages (stg90 / stga0 none), all radius-20 cylinders standing on
  the object (Londo's lamp posts 0-520, stg10's raised ones 120-580, Kraken's 220-710 ...).
- `push_out_cm`: feet-to-axis stop distance = 20 + the fighter's collision radius, measured exact on the tape logs
  (Ryoma 60.0, Falcon 50.0, Ayame / Rouge 51.5, Kraken 72.0, Valgas 70.4, Wang-Tang 47.3; Galuda 68 p5).
- `body_height_cm` (0x0C02651E): Falcon 200, Ryoma 210, Wang-Tang 191.1, Jack 215.7, Gunrock 276, Galuda 252, Ayame 180,
  Rouge 199.5, Kraken 273, Valgas 252, Final Valgas 330.
- `kind4` [x, y, z]: the state-41 hang objects at rest (Londo 2, stg30 1, stg50 4, stg80 1).
- `class9` [x0, x1, z0, z1, bottom, top]: the class-9 stage boxes = the undersides of state 36 (stg10, 20, 30, 40, 60,
  80, 90).
- `hop` {part: [top, bottom, home x, y, z]}: the 44 hoppable kind-1 boxes (100 cm; the 14 hopped on the logs measured,
  the rest home.y +- 50).

## 4. BUG-50: the pole catch rule and the bump
**Catch** (touch scan 0x0C0ABF64 at the start of the update + 0x0C09FE68 in the air ACTION list): the nearest pole by
horizontal feet-to-axis distance **< 150 cm airborne** (100 on the floor) whose cylinder overlaps the body window
(feet + 100 > bottom, top > head - 100), on the ACTION edge (holding B does nothing), nothing carried. **No facing,
approach or run-jump test.** The init clamps the feet into the pole (below the bottom -> bottom; head over the top ->
top - body height: mash_s33 Ayame 550 - 180 = 370). Scored (decode helper): CPU logs 71/71 catches predicted, 353/353
presses beyond 150 cm no catch; tape logs 2/2 (mash_s33 f126 at 95 cm, f1506 at 138 cm), 0 false. The pole tapes
(pole_londo / pole_londo2 / pole_wall) press **no ACTION within 150 cm** (0 B presses in the first two; pole_wall's B at
165.9 cm = the dive): the disc's 0 catches there are the rule, not a different catch condition.
**Bump**: plain collision with the radius-20 cylinder: the feet are held at `push_out_cm` from the axis, the velocity
is kept (pole_londo f18-51: 60.0 cm every row, vx / vz -6.89 unchanged), so a jump aimed at the axis drops straight
down beside the post. The remaster had no pole collision at all (it flew through the lamp post).
**Port**: `_mv_pole_catch` (the condition in `_try_pole`, feet clamp), `_mv_pole_push` after every core move.
Not ported: the reaction-flight auto-catch (state 27 with the recovery input held, 0x0C08F6C8: too loose on the logs,
a piece is missing), the nearer-throwable-steals-the-pointer rule.

| tape | before (master 2f8da7d) | after |
|---|---|---|
| pole_londo P1 | state 95.9 %, x 36.7 % (flies through the post) | **state 100 %, x 61 %** (bumps at 60 cm, drops beside it) |
| pole_londo2 P1 | state 100 %, x 48 % | 100 %, 48 % |
| pole_wall P1 | state 85 % (97 % with the dive) | **53 %**: the remaster's route is 40 cm off from f176 (it lands a fall from a run straight into the run, the disc lands with state 6 > 2 > 31: request 2 below), so its f196 B press is 117 cm from the post and catches where the disc's (166 cm) dives. The rule is right; the route upstream is not. |

## 5. BUG-58 = the dodge (state 7)
Trigger 0x0C09E910, tested in the handlers of states 0, 2, 31, 32 after the attack tests: not carrying, the opponent
on the floor in an attack (state 10 / 11) early (motion frame <= 15) with a hit armed (+0x100), |dy| <= 100, distance
D <= 300 (+0x72AF), and a **newly pressed stick direction**: d = stick (8-way + camera) - heading to him. |d| <= 20 deg
= state 28 (toward him; not decoded, left to the normal move); 20-100 deg = the **arc** k0/41 (sub 10 / 11 by the sign):
L = 2 sin(2 deg) D frozen at the trigger, 20 moves of L along heading(him) +- 90 deg, re-facing him every frame (a
circle round him), 21 rows; over 100 deg = the **step** k0/20-23 (octant of the step against him: [20, 23, 23, 23, 21,
22, 22, 22]): 32 cm/f along the stick, -2 per frame, 12 moves, 13 rows. Then the neutral exit: stick held = state 2
walk start and the run, else idle. No button read during it; un-hittable for the first 11 frames (+0x106 = 11). The
jump in that window = a jump-dodge (state 5 sub 4, not decoded). Decode scores: 16/16 entries, arc step = L 143/170
rows (the rest wall slides), facing tangent 170/170, step speeds 84/84, clips 7/7.
**Update order**: on the disc a press can see an attack that starts on the same frame (mash_s22 f12: P2's k1/74 and
P1's dodge on one row). The remaster ticks P1 before P2, so a press on the frame the opponent's attack started is taken
one frame late (mash_s22: the arc starts on row 13, not 12, after one run step). Request 3 below.
**Proof**: mash_s22 P1 f13-33: state 7 k0/41 21 rows, step 10.49 cm/f (disc 10.47); state-7 rows on the 5 mash + 11
stage tapes 0 -> 102 (20 on the disc's frames: the mash routes diverge early for other reasons; disc 42).

## 6. BUG-48 = the hop onto a box (state 17)
Trigger 0x0C0A1162 in the run handler: touching a hoppable box (descriptor byte [11]) whose base is within 8 cm of the
feet and whose centre lies within 40 deg of the run, **5 frames running** (counted from the frame after the contact
starts; the box halves the run's step into it: stg_10 f704-708 -4.46 of -8.93 cm/f). Init: k0/48 at 1 cm/f along the
run (6 rows, Jack 11), no move on the trigger frame. Then k0/57: feet onto the box top and 50 cm toward its centre,
12 cm/f along the heading (the stick steers after 6 frames; jump = state 4; stick released = stand on it, k0/1);
when the feet leave the box: 100 cm down at once, k0/58 8 rows at 8.33 cm/f (its root motion; Jack 0), then the run
(k0/24, Jack k0/25) if the stick was held, else neutral. Box contact (fitted on the logs): the fighter's collision
radius - 10 cm off the box face (stg_10 Falcon 20, stg_30 Galuda 38), on top radius + 10 (Falcon kept at 32.1, off at
43.4). Boxes the remaster keeps as scenery (stg10 part 11 ...) stand at their logged home.
**Proof** (11 stage tapes, state-17 rows): disc 573; remaster **0 -> 301, 234 on the disc's own frames** (stg_10 23/23
row for row f709-731 incl. k0/48 > k0/57 > k0/58 > k0/24, x within 0.5 cm; stg_30 26/26; stg_60 26/26; stg_40 70/88;
stg_50 60/140; stg_80 29/30). Missing: stg_70 / stg_90 (the routes are 20-74 cm off before the box), stg_a0 (no part
map for Final Valgas's stage).

## 7. States 41 and 36 (BUG-63)
- **41** (0x0C0A01EC / 0x0C0A0B78 / 0x0C097864): the air ACTION edge with a kind-4 object within 200 cm horizontally
  and 250 cm vertically: x, z snapped onto it, feet = its y - body height, k2/207, no input; 20 frames later the hop
  off (vy 18, gravity 1.5, 5 cm/f along the facing, k0/8) to the landing k0/9. Logged 3/3. Ported (`_mv_hang41`).
- **36** (0x0C09FF0C / 0x0C0A07E4 / 0x0C09701A): the class-9 undersides stop a rising head (feet pinned at bottom -
  body height, velocity kept); the ACTION edge with the head against one (or within 30 cm / 20 cm below where it
  touched this airtime) = the hang: feet = bottom - body height + 3, k2/207 20 f then the k2/208 hold; punch / kick =
  k1/162 in place 26 f (Gunrock 20) > k1/163 a 25 cm/f straight dive at him (pitch >= 50 deg below level, D <= 200,
  aim 50 cm over his feet, no gravity) > k1/171 22 f; off the underside's span or a floor = fall. Ported
  (`_mv_hang36`, `_mv_ceiling`). Not ported: k2/208 / k2/209 (not captured off the disc: the hold shows k2/207's last
  pose, no hand-over-hand walk), the +132 cm bone snap on k1/163's first row, Rouge's fixed pitch.
