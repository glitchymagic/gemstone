# Fidelity ledger: the remaster vs the Dreamcast original

Bar (the owner, 10-26): only the graphics may differ. Everything below is measured against the disc running in our Flycast.

## The measuring stick
- **Same-input tapes** (`game/tests/tapes/*.tape`, `tools/tapes.py`): per frame, both pads. `@place P X Y Z ANG`,
  `@hp`, `@gems` set up a situation on the frame they're on, in both games.
- **Original**: `tools/reflog.py` boots an arcade fight P1 vs P2 on P2's home stage in an isolated Flycast
  (`tools/fcinst.py`: own HOME + command folder, a pad on port B), makes P2 human (CPU flag +0x71ED held at 0), sets
  the C rand state to 1, and on the first frame of round phase 3 (0x0C7F302C = 3: the fight is on) starts the tape
  (`tape` / `tapelog` in `tools/flycast_drive.lua`) and the per-frame log. The original is deterministic for a tape:
  two boots of move_basic gave bit-identical player fields for all 1498 frames (the rand state drifted by one call).
- **Remaster**: `game/tests/tape_run.gd` (Fight.tape / tape_log): both fighters read the tape from the first FIGHT
  frame; the D-pad maps through the ORIGINAL's logged camera that frame (isolates movement from the camera, which has
  its own audit); one log row per frame BEFORE that frame's input (as Flycast captures).
- **Diff**: `tools/fidelity_diff.py` / `tools/fidelity_run.py orig|rem|diff TAPE..` -> `dumps/fidelity/reports/`;
  `tools/fidelity_show.py LOG P` prints (state, motion) segments with lengths, travel and health.
- **Tolerances**: state, motion kind/id, motion frame, health, gems, Power Change: exact. Position 1 cm (the original
  keeps f32 cm and moves 1.5-36 cm per frame, so a faithful port is within float rounding; 1 cm is invisible on screen
  and far above f32 noise at stage scale), velocity 0.05 cm/frame, facing 64/65536 of a turn (0.35 deg).

## RAM map found in this pass (player struct + offsets; P1 0x0C7E40C4, P2 0x0C7EB394, stride 0x72D0)
+0x020 x,y,z f32 cm at the FEET · +0x7264 previous x,y,z · +0x7270 velocity x,y,z cm/frame · +0x7248 u16 facing
(0 = +z, 0x4000 = +x) · +0x719E motion frame · +0x71A4/5 kind/motion · +0x71BA state · +0x71D4 health · +0x71ED CPU flag ·
+0x71F3 Power Change · +0x71F4 gauge · +0x7230 gems. Globals: round phase 0x0C7F302C (2 ready, 3 fight, 4 KO/TIME call,
5 win/draw poses), round clock 0x0C7F304D (99 s), camera 0x0C7F2664, rand state 0x0C346A50.
States seen: 0 idle, 2 walk-start, 4 jump crouch, 5 air, 6 land, 8 KO'd lying, 10 attack, 11 Power Change attack,
14 falling off a step, 15 lying, 16 get-up, 21 win/draw pose, 22 intro, 23 transform/revert, 24 hit recovery, 27 hit
reaction, 28 thrower, 29 thrown, 31 run, 32 stop, 35 pick-up, 37 grab.

## Coverage matrix, wave 4 (fx-cov2 2026-10-27 07:00, master 2f8da7d: 79 tapes, docs/COVERAGE.md section 9; the
## 437b5da matrix below stays as the history). Numbers = match % P1/P2 unless noted; Ryoma vs Falcon on Londo unless noted.
| Area | Mechanic | Original (evidence) | Remaster (2f8da7d) | Status | Bug |
|---|---|---|---|---|---|
| Move | run speed / start | 9.50 cm/f from frame 1; per fighter 8.5-10.5 (1ST_READ 0x0C339540) | mv_run / mv_turn P2 100% every field; P1 diverges only at the fountain base (f28 z 2.4 cm) | PASS | 6, 56 |
| Move | stop | state 32 k0/26 23 f | mv_run P2 exact; P1 f193 the stop slide drops off the fountain base | PASS (flat floor) | 7, 59 |
| Move | 8 directions | camera-relative | move_basic st 90/96 (P2 first diff f16: an edge the disc slides along) | PARTIAL | 3, 6 |
| Move | turn in a run | facing at once, velocity swings over ~6 frames inside state 31 (turn_ryoma / turn2_ryoma, 31 switches) | mv_turn P2 100% | PASS | - |
| Move | curved run state 7 | k0/41 21 rows; NOT from a direction switch (0 in 31 switches + 13 starts): the 2 disc cases follow a placement with the direction held (Jack) / a run out of state 24 (Ryoma) | never | FAIL | 58 |
| Move | body push | the radii sum on the overlap frame | dist_galuda first diff f11 -> f25, near_gunrock f12 -> f20 | PASS | 45 |
| Move | steps / falling / step-up | stage tapes, 16 runs each | run ends <= 1 cm: 0-5 of 16 per stage (was 0-1); one-frame snaps 0-5 per stage (stg_70 5) | FAIL | 1, 52 |
| Move | vault (state 17) | k0/48 > 57 > 58 over ~100 cm obstacles, 475 rows in 8 tapes | 0 rows | FAIL | 48 |
| Walls | wall stop | 700 / -750 (Londo) | atk_ground splat 699.6 (disc 700.0) | PASS | 49 |
| Walls | wall kick | state 38 k2/206 8 f > k0/13; 72-128 rows per stage tape | 8-row kicks = disc, but 0-56 rows per stage tape (none on stg_00 / 30 / 60 / 90) | PARTIAL (trigger) | 47 |
| Walls | ledge hang state 36 | k2/207 19 rows > k1/162: B in the air at a wall top (mash_s22 f480 X+Y > f482); ledge_hang tape | never | FAIL | 63 |
| Jump | standing / moving / per fighter | st4 3 f > st5 vy per fighter, run + 0.25 | mv_jump P1 state exact to f443, P2 100% | PASS | 8, 55, 57 |
| Jump | double jump (Falcon) | k3/16 4 f then k0/7 | k3/16 at 14 / k0/7 at 18 = disc; crouch one row short, first air row rises (19.5 cm high all jump) | PARTIAL | 9 |
| Attack | strings | chains per fighter | chain_ryoma 98/100 (f42 one press dropped); moves_* P1 st 68-89% | PARTIAL | 16 |
| Attack | close-range move | k1/74 under 120 cm | near_ryoma 99/94, near_gunrock 99/89; k1/74 one row short (hits_down f80 vs 81) | PARTIAL | 15 |
| Attack | dash / air attacks | run+X/Y = the standing first motions; k1/10 / k1/12 on the arc | atk_move 96/97 | PASS (states) | 21, 22 |
| Input | B with nothing in reach | an attack (mash_s11 / s33 f12) | still runs | FAIL | 53 |
| Input | attack + jump together | the ground attack | mash_s44 k1/24 from f12 = disc | PASS | 54 |
| Hit | when a hit lands | state 27 + damage on the hit frame, the reaction motion the next | both one frame later (f29 vs f28 on every Ryoma hit tape) | FAIL (1 frame) | 66 |
| Hit | reactions | state-27 machine (REACT.md) | timelines = disc after the 1-frame lag (atk_ground 29 k2/96 ... 142 k2/146); atk_ground P2 st 61, dist_* 51-65 | PARTIAL | 17, 66 |
| Hit | launch / knockback | launch tables | rows exact, launch start 30 cm further out (atk_ground f29) | PARTIAL | 18 |
| Hit | damage formula | 56/56 body hits | Rules.game_damage | PASS (formula) | - |
| Health | recovery | docs/HEALTH.md (ceiling +0x71D6 / counter +0x720F, b4-0 records only, combo restart forfeits; scored 487/487 hits) | provisional: +1 / 40 f to floor(d x 7/8) of the last hit: the disc's pending amount after 1,461 of 2,050 hits | FAIL (spec ready) | 14 |
| Throw | grab / throw | throws.json chains | state 28 / 29 rows 2,719 / 1,968 vs disc 3,824 / 2,838 | PARTIAL | 20 |
| Items | props: pick up / carry / throw | items_londo | items_londo 99/48, P2 hp 27 -> 68% | PARTIAL | 26 |
| Items | weapons (chests + items) | chests at 0 / 599 ..., item use k2/245 ... | none: items_weapon P1 mot 60%, pick-up state 35 72 rows vs 816 | FAIL | 46 |
| Poles | catch / swing | 1 catch in 51 tapes (Ayame mash_s33); 0 of 10 Londo tries | 0 catches (was 863 rows in 12 tapes): pole_londo 96/100, pole_londo2 100/100 | PASS (no false catches) | 50 |
| Stage | start points | spawns.json | stage tapes: frame-0 rows identical on 10 stages | PASS | 13 |
| Gems | at round start / floor gem | 1 held each, 3rd at f299 on a fixed spot | gems % stg_00 100/98, stg_10 100/98, stg_20 100/100, stg_70 100/98; stg_30 79/100, stg_50 53/83 | PARTIAL | 12, 43 |
| Gems | spill / pick-up | 1 per launch, 20 cm/f, ~7.6 m | gems_drop gems 98/26 | PARTIAL | 43, 44 |
| PC | trigger / revert / gauge | k3/8 st23 130 f; revert rows | pc_* P1 state 86-100% (mean 96.5%), gems_pc 99% | PASS (P1) | 25, 35 |
| PC | world freeze | the transform's 130 rows + a Fusion's 40-frame flash stop the opponent, clock, recovery and stage timers (pc_freeze: floor gem 469 = 299 + 170) | none: the opponent moves, the clock runs | FAIL (fix in fx-cov2) | 65 |
| PC | Drives / Fusions | logged rows per fighter | P1 rows as above; P2 health 5-55% (projectiles, BUG-91) | PARTIAL | 25, 91 |
| Flow | round start / clock / TIME / KO | docs/FLOW.md | timeout 100% for 7,200 frames | PASS | 10, 11, 23 |
| Fighters | all 10 by tape | moves_* tapes | P1 state 68-89% (Kraken 68, Falcon 73, Ryoma 78, the rest 82-89) | FAIL | 16, 17, 66 |
| Stages | all 11 by tape | stg_NN | state 66-87%, motion 52-79% per side; stga0 not comparable | FAIL | 47, 48, 52 |
| Random | seeded mash | mash_s11..s55 | state 28-58%, first divergence f12 on 3 of 5 (BUG-53 / 58) | FAIL | 53, 58 |
| Breakage | Godot errors in tape runs | - | only the exit leaks (41 of 79; harness, fixed a5dfbc5) | PASS | 38 |
| Breakage | hunt (seed 3, 135 runs, both looks) | - | see docs/HUNT.md "hunt7" | see HUNT.md | 60, 61 |

## Coverage matrix (first audit 2026-10-26; REFRESHED by fx-cov 2026-10-27 on code 437b5da: 51 tapes, numbers =
## match % P1/P2 from dumps/fidelity/cov/reports, per-tape table in docs/COVERAGE.md; Ryoma vs Falcon on Londo unless noted)
Master 0fef882 re-run (docs/COVERAGE.md section 8): the statuses below hold; flow_start / atk_move / mash_s11 / s22 /
ledge_londo better, mv_run / stg_60 / stg_40 worse, BUG-64 new.
| Area | Mechanic | Original (evidence) | Remaster (today) | Status | Bug |
|---|---|---|---|---|---|
| Move | run speed / start | 9.50 cm/f from frame 1 for Ryoma; per fighter 8.5 (Gunrock) - 10.5 (Ayame, Wang-Tang) (COVERAGE 6) | w3: per fighter from 1ST_READ 0x0C339540 (move_table.json), checked on the disc CPU fights | PASS (rule) | 6, 56 |
| Move | stop | state 32 k0/26, 23 f (o_move_basic) | w3: the stick release frame has no run step (move_basic P2 exact to f11) | PASS (rule) | 7 |
| Move | 8 directions | camera-relative, UP = camera forward (o_move_basic) | move_basic st 94/96, x 2/80 | FAIL (via camera) | 3, 6 |
| Move | turn arc | far direction change = state 7 k0/41 21 f arc (mash_s22 f12) | turns at once | FAIL | 58 |
| Move | body push | overlap pushed apart on the same frame to the radii sum (dist_galuda f11 20/60 > 1/79) | w3: Fighter.body_push after the frame to the radii sum (dist_galuda x 66/36 -> 76/59 %); dist_ryoma victim 1 f late | PARTIAL | 45 |
| Move | steps / falling / step-up | per stage (stage tapes, 16 runs into walls / edges each) | run ends within 10 cm: 2-9 of 16 per stage (median 4.7-112 cm); step snaps 64-91 cm in one frame (stg30/40/70); vault missing | FAIL | 1, 6, 48, 52 |
| Move | vault (state 17) | k0/48 6 > k0/57 9 (+100 cm) > k0/58 8 over ~100 cm obstacles, 8 stages | never | FAIL | 48 |
| Walls | wall stop | +-660 / -650 (stg10), 700 / -750 (Londo) | w3: sdf zero on the last inside cell: atk_ground splat 699.6 (disc 700.0) | PASS (splat) | 49 |
| Walls | wall kick | state 38 k2/206 8 f > state 5 k0/13 (72-128 rows per stage tape) | w3: state 38 k2/206 8 f frozen > k0/13 vy 25 + 2 cm/f, table gravity (OBJ.md 2) | PORTED (retest by tape) | 47 |
| Jump | standing | st4 3 f > st5 k0/6 vy 35.5, g 2, 36 rows air (Ryoma) | w3: motion switch on the frame + landing the frame after the floor, no move on it: mv_jump first diff f15 -> f443 | PASS (mv_jump to f443) | 8, 55 |
| Jump | moving | run speed + 0.25 per fighter (9.75 Ryoma), lands into a run | w3: run + 0.25 per fighter (move_table) | PASS (rule) | 8, 57 |
| Jump | gravity per fighter | 1.08 (Jack) - 2.1 (Valgas) cm/f^2 | w3: table [6] per fighter for jumps + wall kicks, 2 for falls (checked on CPU logs) | PASS (rule) | 57 |
| Jump | double jump (Falcon) | k3/16 4 f then k0/7 (o_flow_start P2) | k3/16 at 14, k0/7 at 18 = disc; crouch row lag, lands 1 f early (flow_start P2 st 49%) | PARTIAL | 9, 55 |
| Attack | punch string | Ryoma 16 > 17 > 18 > 19 (12 / 24 / 22 rows in move_basic) | k1/17 14 rows (move_basic f28), k1/16 30 vs 31 (chain_ryoma f42) | FAIL | 16 |
| Attack | kick string | Ryoma 24 > 25 > 26 > 27 | chains.json ids; timing as punches | FAIL | 16 |
| Attack | close-range move | k1/74 under 120 cm | near_ryoma st 99/94, near_gunrock 98/87 | PARTIAL | 15 |
| Attack | dash attacks | run+X k1/16, run+Y k1/24 | atk_move st 99/80 (was 72/66) | PASS (states) | 22 |
| Attack | air attacks | k1/10 31 f / k1/12 26 f | on the jump's arc | PARTIAL | 21, 29 |
| Attack | air action | B in the air = Ryoma k1/53 > 54 > 56 | none | FAIL | 27 |
| Input | B with nothing in reach | an attack (Ryoma k1/16, Rouge k1/24; mash_s11 / s33 f12) | ignored, runs | FAIL | 53 |
| Input | attack + jump together | the ground attack (mash_s44 f12) | w3: the ground attack | PASS (rule) | 54 |
| Hit | reactions | state-27 machine (docs/REACT.md) | atk_ground P2 st 61%, dist_* 59-70%; stand-in reaction clips freeze 20+ f (hunt pose_frozen) | PARTIAL | 17 |
| Hit | launch / knockback | launch_speed / tables | atk_ground launch rows exact; walls +4.6 cm | PARTIAL | 18, 49 |
| Hit | knockdown / get-up | lying k2/144 5 f, get-up k2/146 23 f | ported | PARTIAL | 17 |
| Hit | damage formula | 56/56 body hits (pass 4) | Rules.game_damage | PASS (formula) | - |
| Hit | damage per move | Ryoma 10 / 8 / 15, throw 60 ... | first hits 10; atk_ground P2 hp 14% | FAIL (depends) | 19 |
| Health | recovery | +1 every 40 f from 40 f after the hit, to floor(dmg x 7/8) | the same: atk_ground P2 hp 230 > 231 at 68, 108, 148 = disc | PASS (rule) | 14 |
| Throw | grab / throw | throws.json chains | ported; victim rows with no motion (k4 clips not captured: 1,451 rows) | PARTIAL | 20 |
| Items | props: pick up / carry / throw | items_londo | w3: object punch k1/153>154 / k1/78 / k1/59, flings + carry throws from the speed table 0x0C33C05C, hit bases per property, respawn 991 f (OBJ.md 3/6b) | PARTIAL (retest) | 26 |
| Items | weapons (chests + items) | a chest on every stage at frame 0, item at 377, next chest 599 ...; use k2/245 31 f, 31 dmg launch (items_weapon) | fx-item2: chests on the drop clock, items 0-10 picked up / carried / used (ITEMS.md 9): items_weapon P1 st 96 -> 100 %, mot 60 -> 100 %, P2 hp 67 -> 100 %; 9 of 9 item tapes P2 hp 100 %; other fighters' family clips via tools/fight_clips.py | PARTIAL | 46 |
| Poles | catch / swing | 0 catches in 10 Londo tries (bumps at 60 cm); 1 catch (Ayame mash_s33 f126 at y 370) | w3: OBJ.md 1 port: catch only in the air on ACTION, hop solver at the opponent; the disc's extra bump rule (BUG-50) still unknown | PARTIAL | 50 |
| Stage | playable area | probe per stage (fx-oom / fx-proof) | w3: areas + floors from the disc's own fights (tools/area_logs.py), no lifts over 65 cm for runners / 1.6 m pushed (BUG-51) | PARTIAL (stairs: step fronts outside, BUG-41) | 1, 51, 60, 64 |
| Stage | start points | spawns.json (10 stages) | stage tapes: frame-0 rows identical on all 10; stga0 none (1275, 1277) | PASS (10 stages) | 13, 60 |
| Gems | at round start | 1 held each, the 3rd on the floor at frame 299 on a fixed spot | w3: the 3rd colour queued, dropped at f299 on the farthest free drop spot (ITEMS.md 2) | PORTED (retest) | 12, 43 |
| Gems | pick-up / drop / respawn | 1 per launch, 20 cm/f flight ~7.6 m; touch 65 cm; untaken 1,110 f then 300 f later elsewhere | w3: spills by hit record byte 16, 20 cm/f + vy 30, walls x -0.5, 990 f unattended = gone (ITEMS.md 3-4) | PORTED (retest) | 43, 44 |
| PC | trigger | 3 gems -> k3/8 st23 130 f the frame they count (from st 0/31/32/5/6/10/15/16); pick-up only with gauge 0, < 3 gems | same (fx-pc: CorePC + pc_moves.json rows, morph row per fighter) | PASS (pc_ tapes: st23 / PC flag / gems exact) | 25 |
| PC | Drives / Fusions | k1/16 1 f > the move's rows, per-move cost on its row (120-480), Fusions = whole gauge, fixed rows (docs/PC.md) | the original's logged rows per fighter (fx-pc) | PARTIAL (21 tapes: st 91.5%, motion 91%; some lengths depend on the opponent; shots = the disc's pool objects replayed with their spheres, docs/SHOTS.md (fx-shot): shot_ tapes P2 damage 605 -> 1477 of 4035, homing open) | 25, 34 |
| PC | revert | gauge 0 outside st 10/11/23 -> k3/9 > k0/9 (Rouge 79, Valgas 83; Ryoma/Gunrock k3/9 > k3/10 90) | logged rows (fx-pc) | PASS (pc_ tapes) | 35 |
| PC | gauge | 2400, -1/f in round phase 3 only, set at the morph row | ported (fx-pc, game units) | PASS (77% exact; the rest = 1 emulator lag frame after a transform, off by 1) | - |
| Flow | round start | docs/FLOW.md | phase 2 exact every round (fx-flow) | PASS | 11 |
| Flow | round clock | 99, -1 per 60 frames | timeout tape 100/100 (7200 f) | PASS | 10 |
| Flow | KO | docs/FLOW.md | same tick pattern (fx-flow) | PASS (flow) | 23 |
| Flow | TIME OVER | phase 4 183 f, phase 5 245, draw poses | timeout tape: every row exact to f6186 | PASS | 10, 23 |
| Flow | title / menus / ladder / VS / continue / endings | docs/FLOW.md | arcade flow ported, own title / VS screens | PARTIAL | - |
| Flow | arcade row | rand()-rolled | ported | PASS | - |
| CPU | decisions | 0x0C04C24C (docs/CPU.md) | cpu_game.gd | PARTIAL | 24, 41 |
| Camera | rule | fx-cam | fight_cam.gd | PASS (replays) | 3 |
| Cinematics | default | none | Off by default (game.gd cinematics := false) | PASS | 5 |
| Fighters | all 10 by tape | moves_* tapes | P1 state 52-70%, motion 51-70% (per-fighter run / jump, chains, reactions) | FAIL | 16, 17, 56, 57 |
| Stages | all 11 by tape | stg_NN tapes (COVERAGE 3) | state 71-88%, motion 58-77% per stage; stga0 not comparable yet | FAIL | 43-52 |
| Random | seeded mash (5 pairs / stages) | mash_s11..s55 | state 32-56%, first divergence f12 on 4 of 5 (input priority) | FAIL | 53, 54, 58 |
| Breakage | Godot errors in tape runs | - | 0 error lines in 51 tape runs | PASS | - |
| Breakage | hunt (seed 3, 135 runs) | - | vs run4: fell 0 > 7,877, real wedges 10 > 87, pose_frozen 77 > 194, softlock 0 > 9 | FAIL | 60, 61, 62 |
