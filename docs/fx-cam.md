# BUG-3: the fight camera, calibrated from the original's own camera (lane pstrailer2, branch fx-cam, 2026-10-26)

Bar: the remaster's fight camera follows the same framing rules as the disc running in Flycast, measured, not eyeballed;
only where the wider 16:9 frame (and the remaster's HUD band) needs it does the remaster add its own corrections, and
each of those is listed under Deviations.

## Method

1. **Log the original on every stage** (`tools/stagelog.py`, isolated Flycast instances via `tools/fcinst.py`): arcade as
   P1 vs the stage's owner on his home stage (`tools/reflog.py boot`), then both fighters are the game's own AI (P1 CPU
   flag +0x71ED frozen at 1), both healths are frozen at 240, and the round timer **0x0C7F304D** (seconds, counting down
   from 99) is held. 0x0C7F2F28, which an earlier note called the timer, is another clock: holding it let the first
   logs run into time-overs. Every frame we capture 188 bytes: the camera object 0x0C7F2664 (view matrix +0x3C0, eye
   +0x450, desired target +0x474, smoothed target +0x480, desired eye height +0x448, +0x3A0 projection words with focal
   640), both fighters' hips +0x148, feet +0x020 and state words, and a screenshot every 600 frames. Per stage there
   are two logs: `cl<NN>` (2 rounds, ~12k fight frames) and `cm<NN>` (10 min with the timer held, ~30k fight frames).
   They live in the main repo at `dumps/cap/` (untracked, like every RAM capture).
2. **Read the rule off the logs** (`tools/cam_stage.py`). Frames count only before the match end and while neither
   fighter is in the intro, the round end or a Power Change (states 22 / 21 / 23). The tool writes
   `game/assets/fidelity/<stg>_cam.json` (tracked) and simulates its own model on the original's fighter positions to
   score it against the original's camera (the "model vs original" table).
3. **Implement it**: `game/scripts/fight_cam.gd` `_rule()` is the same model as `cam_stage.py sim()`. It reads the
   per-stage file and falls back to `stgN0_info.json` cam_zones / cam_levels (the 10-23 Londo calibration) or to the
   stage's single yaw. Battle Royale (3-4 fighters) keeps its old box rule on top of the stage's preset.
4. **Measure the remaster's camera** two ways:
   - `game/tests/cam_replay.gd` replays the original's fight into the remaster's stage: both fighters are placed at the
     feet positions the original logged, every frame. The camera is either the original's own (`PS_MODE=orig`) or the
     remaster's (`PS_MODE=remaster`). It writes the same per-frame audit as `scripts/cam_check.gd`, plus the
     original's camera for that frame. `tools/cam_fid.py` reports hidden / cut frames and the median |error| of yaw,
     distance and eye height against the original. This is the fidelity number, and the only fair hidden-fighter
     number while the remaster's fighters can still leave the playable area (BUG-1, lane fx-oom).
   - Seeded in-game CPU-vs-CPU matches (`tests/record_match.gd`, `PS_SEED` 1 and 2, both looks) through
     `tools/cam_audit.py`, before (master) and after.

## The original's camera rule (all 11 stages)

| part | the original (measured) | before this pass (remaster) |
|---|---|---|
| aim (desired target) | midpoint of the fighters' **feet** (+0x020) + **100 cm** up, exactly (median error 0.0 cm on every stage, p90 0) | hip midpoint + 105 cm over the feet |
| smoothing | the camera looks at S: S.x/z close **1/8** of the gap per frame (13.5% was a rounded 12.5%), S.y moves in **whole cm, truncated** (1/8 of the gap), so S.y rests up to 7 cm off and ignores hops under 8 cm | 13.5% on all axes |
| yaw | **three presets 20 deg apart** per stage (ship -155/-135/-115, Dawnvolta 115/135/155, lair 25/45/65, Londo -155/-135/-115, ...), picked by where the target is on the stage, eased **10% of the gap per frame** (BAMS integer, ends 0.05 deg short) | one yaw per stage (Londo: 3 zones), eased 9% |
| distance | the horizontal eye distance follows R = max(593 cm, 353 + sqrt((0.93 x across)^2 + (1.13 x along)^2 + (1.07 x height gap)^2)) of the feet separation: up at 10.3% of the gap per frame when R is above it, down at 11.7% when R is more than 0.9 cm below it | 457 + 0.42 across + 0.90 along (dojo fit), Londo steps 594 / 683 / 1195 |
| eye height | desired eye y (+0x448) = min(**500 cm absolute world height**, S.y + **0.279** x distance), and the eye eases **5% per frame** toward it. On Kraken's upper deck (S.y 330) the eye sits only 170 cm above the aim, and when a fighter is high on a mast the eye drops below the aim | 0.36 x distance over the aim, cap 5 m (Londo); 2.6 m over the aim elsewhere |
| field of view | focal 640 px on 640x480 = 41.1 deg vertical (camera +0x3AC) | same; 16:9 shows more at the sides |

Not explained yet: (a) which preset the camera picks. A grid of the stage (200 cm cells over the target, with "keep"
cells where the original's choice is mixed and a few frames of hold) reproduces the original's yaw within 2 deg on
58-82% of frames in-sample and 49-74% held out (zones built from one log, scored on the other). The yaw is not
a function of the target position alone; we tested P1 / P2 / hip positions, a lateral threshold with hysteresis, a
per-preset line of sight and the fighters' states. The selection code was not found in the 1ST_READ decompile (the
camera object's fields are reached through a base pointer + 0x400). (b) About 30% of frames have a desired eye height
up to 1.4 m above the rule, after jumps. Both are the next targets for a decompile pass.

## Deviations (what the remaster adds on the original's rule; each is the minimum the 16:9 frame / HUD needs)

1. **Fit**: when a fighter's head would go under the HUD band (top 13.5%) or past an edge, the remaster aims higher,
   then dollies back while keeping the original's pitch (the eye rises 0.279 m per extra metre, but never past the 5 m
   cap on its own). The original lets heads and feet leave its 4:3 frame. Replayed on the original's own fights, the
   original's camera in 16:9 cuts feet / heads / goes under the HUD in up to 6 / 4 / 24% of frames (ship).
2. **Walls**: when the stage's own geometry hides a fighter or fills the lens, the camera swings from the original's
   preset in 12 deg steps (up to 48 deg), then pulls in or cranes up, and returns once the preset's view is clear. It is
   anchored to the original's preset yaw, distance and eye height.
3. **Scenery fades** (scripts/scenery_fade.gd) and the see-through fighter at the lens are unchanged.
4. The remaster's fit, walls and fades run on the original's smoothed target and yaw, so the controls (camera-relative
   D-pad) follow the original's yaw except while a wall swing is active.

## Numbers

### Fidelity (the number the bar asks for): the remaster's camera vs the original's

Here is the remaster's camera fed the original's own fight, frame by frame (the last table's "AFTER" rows; "rule
alone" = scripts/fight_cam.gd `_rule()` before the remaster's fit and walls). The median absolute error against the
original's camera on the same frame is:
- **yaw: 0.05 deg on 10 of 11 stages** (Ryoma's stage 1.1 deg, the boss arena 0.3 deg). Before: 16-20 deg on 8
  stages, 1.8 deg on Rouge's (its single preset happened to match), 0.05 on Londo (its zones were already measured)
  and 90 deg on the boss arena.
- **distance: 22-42 cm live, 18-25 cm for the rule alone** (boss arena 53 / 51 cm). Before: 57-85 cm (boss 437 cm).
- **eye height over the aim: 4-15 cm live, 2-9 cm for the rule alone** (boss 23 / 21 cm). Before: 34-84 cm (boss
  140 cm).
- aim point: 0.0 cm median (it is computed exactly as the original computes it).
- The yaw within 2 deg of the original: 58-82% of frames (in-sample); a zone grid built from one log and scored on the
  other reaches 49-74%. The median is exact, but the preset choice in about a third of frames is still not the
  original's (see "Not explained yet").

### Hidden fighter / cut frames, measured on the original's own positions

On the original's fighter positions, the remaster's camera hides a fighter in **0.0-3.3% of fight frames on every
stage**: ship 0.9, Dawnvolta 0.9, Valgas's lair 0.0, Londo 1.7, Rouge's 3.3 (the original's own camera hides one there
2.9% of the time), boss arena 0.1. Heads are cut in 0.0-0.1% of frames, feet in 0.3-2.6%, and a head is under the HUD
in 0.0-3.0%. The original's own camera shown in 16:9 cuts heads in 0.1-6.4% of frames, feet in 1.3-6.1%, and puts a
head under the HUD in 0.1-14.2%: that is what the fit deviation removes.

### Why the in-game audits still show 38-100% hidden on the ship / Dawnvolta / lair / boss arena (BUG-1, not the camera)

The 63-90% / 50-65% / 14-75% hidden-fighter figures in BUG-3 come from frames where the remaster's fighters are where
the original's never are:
- Dawnvolta: the remaster's fighters stand at y -3.6 m (the safety floor under the stage); the original's floor is at
  0, with platforms at 0.5 / 0.91 / 1.44 m that the remaster's collision lacks.
- Valgas's lair: fighters at -0.8 m.
- Ship: the remaster's bounds reach x 106 m, and fighters stand at 1.4 / 2.4 m on surfaces the original doesn't have.
- Boss arena: both fighters at -3.94 m.
- Several matches also have a fighter frozen in one spot (state 10, inside an object) for 15-60 s.
None of that is a camera problem: the original's own camera hides those fighters just the same. With the original's
positions every stage is under 3.3% (the table above). Lane fx-oom owns floors and areas (I sent them the numbers).

In-game seeded CPU-vs-CPU matches (`tests/record_match.gd`, PS_SEED 1 and 2, falcon vs ryoma, 150 s; Classic gives the
SAME numbers in all 48 seed x stage pairs, so only Remaster is listed). A changed camera means a different match, because the CPU's
stick input is camera-relative, so before / after on one seed are not the same fight. "Area" = both fighters' feet on
the original's measured floor cells, within 30 cm of its floor heights. "Stuck" = the hidden fighter hasn't moved for
2 s.

| stage | seed | hidden % before | hidden % after | both fighters inside the original's area (after) | hidden %, area frames only (after) | hidden %, stuck fighters (>2 s still) left out (before / after) | head / feet cut % (after) |
|---|---|---|---|---|---|---|---|
| stg80 | s1 | 84.2 | 99.8 | 43% | 99.9 | 13.0 / 17.1 | 0.0 / 0.0 |
| stg80 | s2 | 60.2 | 69.2 | 33% | 7.3 | 18.2 / 21.3 | 0.0 / 0.0 |
| stg40 | s1 | 64.4 | 67.5 | 0% | 0.0 | 11.7 / 12.7 | 0.0 / 2.2 |
| stg40 | s2 | 53.1 | 38.1 | 0% | 0.0 | 11.5 / 35.0 | 0.1 / 5.1 |
| stg90 | s1 | 5.8 | 27.1 | 42% | 12.6 | 5.8 / 13.6 | 0.0 / 0.2 |
| stg90 | s2 | 68.4 | 54.8 | 45% | 12.4 | 48.2 / 28.5 | 0.0 / 0.2 |
| stg00 | s1 | 4.5 | 4.6 | 100% | 4.6 | 4.5 / 4.6 | 0.0 / 0.3 |
| stg00 | s2 | 5.8 | 6.6 | 100% | 6.6 | 5.7 / 6.6 | 0.0 / 0.6 |
| stg10 | s1 | 0.1 | 0.7 | 26% | 0.5 | 0.1 / 0.7 | 0.0 / 0.0 |
| stg10 | s2 | 0.2 | 0.6 | 69% | 0.8 | 0.2 / 0.6 | 0.0 / 0.2 |
| stg20 | s1 | 6.8 | 1.3 | 79% | 1.4 | 6.8 / 1.3 | 0.0 / 0.5 |
| stg20 | s2 | 5.0 | 8.5 | 95% | 8.9 | 5.0 / 8.5 | 0.0 / 0.0 |
| stg30 | s1 | 8.8 | 9.5 | 69% | 12.4 | 8.5 / 9.5 | 0.1 / 0.6 |
| stg30 | s2 | 5.0 | 5.3 | 100% | 5.4 | 5.0 / 5.3 | 0.0 / 0.0 |
| stg50 | s1 | 0.9 | 13.1 | 100% | 13.1 | 0.9 / 2.6 | 0.0 / 0.3 |
| stg50 | s2 | 2.1 | 0.4 | 100% | 0.4 | 2.1 / 0.3 | 0.0 / 0.0 |
| stg60 | s1 | 0.1 | 0.6 | 66% | 0.8 | 0.1 / 0.6 | 0.0 / 0.2 |
| stg60 | s2 | 12.3 | 18.3 | 62% | 28.6 | 3.6 / 5.9 | 0.0 / 0.2 |
| stg70 | s1 | 0.9 | 7.9 | 97% | 6.3 | 0.9 / 7.9 | 0.0 / 0.1 |
| stg70 | s2 | 0.8 | 1.2 | 100% | 1.2 | 0.8 / 1.2 | 0.0 / 0.0 |
| stga0 falcon vs ryoma | s1 | 100.0 | 100.0 | 0% | 0.0 | 35.2 / 35.6 | 0.0 / 0.0 |
| stga0 falcon vs ryoma | s2 | 99.9 | 100.0 | 0% | 0.0 | 55.9 / 22.8 | 0.0 / 0.3 |
| stga0 falcon vs finalvalgas | s1 | 100.0 | 100.0 | 0% | 0.0 | 1.6 / 1.2 | 0.0 / 0.0 |
| stga0 falcon vs finalvalgas | s2 | 100.0 | 100.0 | 0% | 0.0 | 1.2 / 1.2 | 0.0 / 0.0 |

### Model vs the original (Python model, the same code as fight_cam.gd, on all ~43k fight frames per stage)

| stage | logs (fight frames) | presets (deg) | target err med | yaw med abs err | yaw within 2 deg (held-out zones) | distance med / p90 (cm) | eye height med (cm) |
|---|---|---|---|---|---|---|---|
| stg80 Kraken's Ship | cl80, cm80 (43735) | -155 / -135 / -115 | 0.0 | 0.05 | 0.78 (0.74) | 23.0 / 77.5 | 2.0 |
| stg40 Dawnvolta | cl40, cm40 (44674) | 115 / 135 / 155 | 0.0 | 0.05 | 0.72 (0.66) | 22.4 / 69.9 | 3.4 |
| stg90 Valgas's lair | cl90, cm90 (43136) | 25 / 45 / 65 | 0.0 | 0.05 | 0.66 (0.61) | 20.5 / 67.7 | 3.8 |
| stg00 Londo | cl00, cm00 (43540) | -155 / -135 / -115 | 0.0 | 0.05 | 0.68 (0.70) | 24.7 / 76.8 | 3.8 |
| stg10 Ryoma (Yamato) | cl10, cm10 (44984) | 115 / 135 / 155 | 0.0 | 0.25 | 0.58 (0.49) | 20.0 / 62.2 | 4.2 |
| stg20 Wang-Tang's dojo | cl20, cm20 (44218) | 115 / 135 / 155 | 0.0 | 0.05 | 0.63 (0.53) | 19.5 / 71.7 | 4.6 |
| stg30 Jack's mansion | cl30, cm30 (44026) | -20 / 0 / 20 | 0.0 | 0.05 | 0.82 (0.68) | 19.5 / 63.3 | 6.9 |
| stg50 Galuda's | cl50, cm50 (44134) | 115 / 135 / 155 | 0.0 | 0.05 | 0.79 (0.67) | 24.3 / 81.7 | 2.3 |
| stg60 Ayame's | cl60, cm60 (43665) | -155 / -135 / -115 | 0.0 | 0.05 | 0.67 (0.63) | 22.4 / 85.6 | 3.2 |
| stg70 Rouge's | cl70, cm70 (43996) | -155 / -135 / -115 | 0.0 | 0.05 | 0.80 (0.73) | 21.2 / 74.2 | 2.7 |
| stga0 Final Valgas's arena | cfa0 (31115) | boss camera (follows the boss -> player line) | aim 0.0 | 0.29 | 0.68 (-) | 49.8 / 166.2 | 21.0 |

### The original's fight replayed into the remaster (tests/cam_replay.gd on the cl<NN> logs, cfa0 for the boss arena)

| stage | frames | camera | hidden % | head cut % | feet cut % | under HUD % | yaw err med (deg) | distance err med (cm) | eye height err med (cm) |
|---|---|---|---|---|---|---|---|---|---|
| stg80 | 12380 | original's own camera | 0.9 | 4.9 | 5.6 | 12.9 | 0.00 | 0 | 0 |
| stg80 | 12380 | remaster BEFORE (master) | 0.8 | 0.0 | 2.2 | 2.5 | 19.95 | 57 | 84 |
| stg80 | 12380 | remaster AFTER (rule + fit/walls) | 0.9 | 0.0 | 2.6 | 2.5 | 0.05 | 40 | 13 (rule alone: 0.05 / 20 / 3) |
| stg40 | 12242 | original's own camera | 0.9 | 4.1 | 2.4 | 11.0 | 0.00 | 0 | 0 |
| stg40 | 12242 | remaster BEFORE (master) | 0.9 | 0.1 | 1.3 | 2.0 | 15.95 | 76 | 66 |
| stg40 | 12242 | remaster AFTER (rule + fit/walls) | 0.9 | 0.1 | 1.4 | 1.9 | 0.05 | 29 | 8 (rule alone: 0.05 / 22 / 3) |
| stg90 | 12452 | original's own camera | 0.0 | 6.4 | 2.5 | 14.2 | 0.00 | 0 | 0 |
| stg90 | 12452 | remaster BEFORE (master) | 0.0 | 0.0 | 0.9 | 3.0 | 19.86 | 63 | 69 |
| stg90 | 12452 | remaster AFTER (rule + fit/walls) | 0.0 | 0.0 | 1.3 | 3.0 | 0.05 | 35 | 15 (rule alone: 0.05 / 19 / 4) |
| stg00 | 12168 | original's own camera | 1.5 | 5.1 | 6.1 | 9.2 | 0.00 | 0 | 0 |
| stg00 | 12168 | remaster BEFORE (master) | 1.4 | 0.0 | 4.2 | 2.7 | 0.05 | 85 | 34 |
| stg00 | 12168 | remaster AFTER (rule + fit/walls) | 1.7 | 0.0 | 2.4 | 1.8 | 0.05 | 42 | 13 (rule alone: 0.05 / 25 / 4) |
| stg10 | 12426 | original's own camera | 0.9 | 3.9 | 3.1 | 8.9 | 0.00 | 0 | 0 |
| stg10 | 12426 | remaster BEFORE (master) | 0.8 | 0.0 | 1.0 | 2.1 | 19.95 | 66 | 61 |
| stg10 | 12426 | remaster AFTER (rule + fit/walls) | 1.0 | 0.0 | 1.2 | 2.2 | 1.09 | 32 | 11 (rule alone: 1.09 / 22 / 4) |
| stg20 | 12279 | original's own camera | 1.9 | 3.4 | 1.3 | 8.4 | 0.00 | 0 | 0 |
| stg20 | 12279 | remaster BEFORE (master) | 1.7 | 0.0 | 0.5 | 2.3 | 19.95 | 60 | 57 |
| stg20 | 12279 | remaster AFTER (rule + fit/walls) | 2.0 | 0.0 | 0.9 | 2.3 | 0.05 | 23 | 11 (rule alone: 0.05 / 18 / 5) |
| stg30 | 12375 | original's own camera | 0.6 | 2.8 | 1.8 | 7.2 | 0.00 | 0 | 0 |
| stg30 | 12375 | remaster BEFORE (master) | 0.7 | 0.1 | 1.0 | 1.3 | 19.95 | 65 | 59 |
| stg30 | 12375 | remaster AFTER (rule + fit/walls) | 0.6 | 0.1 | 0.7 | 1.6 | 0.05 | 22 | 13 (rule alone: 0.05 / 19 / 9) |
| stg50 | 12310 | original's own camera | 1.3 | 4.5 | 5.1 | 9.0 | 0.00 | 0 | 0 |
| stg50 | 12310 | remaster BEFORE (master) | 1.1 | 0.0 | 2.1 | 2.5 | 19.95 | 76 | 64 |
| stg50 | 12310 | remaster AFTER (rule + fit/walls) | 1.3 | 0.0 | 1.5 | 2.5 | 0.05 | 39 | 8 (rule alone: 0.05 / 25 / 2) |
| stg60 | 12172 | original's own camera | 1.2 | 3.0 | 4.5 | 7.2 | 0.00 | 0 | 0 |
| stg60 | 12172 | remaster BEFORE (master) | 1.0 | 0.0 | 1.3 | 1.7 | 17.40 | 77 | 66 |
| stg60 | 12172 | remaster AFTER (rule + fit/walls) | 1.2 | 0.0 | 1.2 | 1.7 | 0.05 | 31 | 6 (rule alone: 0.05 / 20 / 3) |
| stg70 | 12166 | original's own camera | 2.9 | 2.0 | 4.9 | 6.1 | 0.00 | 0 | 0 |
| stg70 | 12166 | remaster BEFORE (master) | 3.0 | 0.0 | 0.9 | 1.2 | 1.79 | 84 | 60 |
| stg70 | 12166 | remaster AFTER (rule + fit/walls) | 3.3 | 0.0 | 0.8 | 1.1 | 0.05 | 29 | 4 (rule alone: 0.05 / 24 / 2) |
| stga0 | 31115 | original's own camera | 0.2 | 0.1 | 2.4 | 0.1 | 0.00 | 0 | 0 |
| stga0 | 31115 | remaster BEFORE (master) | 0.1 | 0.0 | 0.2 | 0.1 | 90.24 | 437 | 140 |
| stga0 | 31115 | remaster AFTER (rule + fit/walls) | 0.1 | 0.0 | 0.3 | 0.0 | 0.29 | 53 | 23 (rule alone: 0.29 / 51 / 21) |

### In-game seeded CPU-vs-CPU matches (tests/record_match.gd + PS_AUDIT, PS_SEED 1/2, falcon vs ryoma, 150 s)

## fx-proof (2026-10-27): the merged master audited, what the audit found, fixes

On master a7b7b29 (fx-cam + fx-oom merged), two audits per stage: (1) the original's logged fights replayed into the
remaster (`tools/cam_proof.sh` = tests/cam_replay.gd PS_MODE=remaster + tools/cam_fid.py, the first 6000 frames of
cl<NN> / cfa0 per stage) and (2) seeded CPU-vs-CPU matches as a player sees them (`tools/oom_proof.sh`: tests/match_movie.gd
PS_AUDIT + tools/cam_audit.py, PS_SEED=1, falcon vs ryoma, every stage in both looks + 4-fighter Battle Royale on
Londo / Dawnvolta / the ship; it now prints the hidden / head / feet % next to the out-of-map counts).

Found:
- On the original's positions the merged camera is fine everywhere (hidden 0.0-2.0%, yaw 0.05 deg on 9 stages).
- In-game, the hidden frames were mostly a fighter **lying / getting up** (states DOWN / GETUP: 40-50% of hidden frames
  on every stage) next to a wall or the ship's upper deck: the wall test (`_clear`) and the fades only looked at three
  points over the feet, while a lying body stretches 1.7 m along the floor, so the camera saw a clear view and stayed.
- Final Valgas's arena: 100% hidden = the boss standing at y -3.94 m under the floor (no area file for stga0: the old
  info floor_y -361.8 cm put his start 2.4 m under the disc floor onto the safety floor). BUG-1, fixed with the stga0
  area (docs/fx-oom.md).
- Jack's mansion (seed 1, after the camera fix): 31.6% hidden = Falcon stuck 100 s wall-kicking on a 7.2 m top (after
  a pole swing to 17 m) where the original's floors are 0-100 cm. BUG-1 (a surface the original never lets anyone on),
  fixed in arena.gd clamp_fighter; the pole swing to 17 m is the lead's (fighter.gd pole code).

Changes (scripts/fight_cam.gd): the wall test also checks every body sphere (its near side, as CamCheck.occluded does;
3 of 11 behind the stage's geometry = blocked), the fades test the spheres too, and while the view from where the
camera is now hides a fighter the swing eases at 24% a frame instead of 8%; the swing goes up to 60 deg (was 48) and
the crane has a 3.6 m step (fighters against Jack's room wall, the original's eye outside it: seed 1 6.7 -> 3.4%). The original's rule (`_rule`, the presets,
distance, eye height) is untouched: the replay fidelity numbers below are the same before and after.

### In-game, seed 1 (falcon vs ryoma, both looks; Battle Royale falcon/ryoma/wangtang/gunrock): before (master) -> after

| run (look_stage_fighters) | frames before / after | hidden % before -> after | head cut % | feet cut % | out-of-map frames (fighters) before -> after | gems / throwables out |
|---|---|---|---|---|---|---|
| classic_stg00_falcon-ryoma | 13475 / 10084 | 5.1 -> 2.2 | 0.3 -> 0.1 | 1.2 -> 0.6 | 0 -> 0 | 0 -> 0 |
| classic_stg10_falcon-ryoma | 12283 / 10075 | 1.4 -> 1.0 | 0.2 -> 0.1 | 1.1 -> 0.4 | 0 -> 0 | 0 -> 0 |
| classic_stg20_falcon-ryoma | 13353 / 10103 | 4.3 -> 0.4 | 0.0 -> 0.0 | 0.4 -> 0.3 | 0 -> 0 | 0 -> 0 |
| classic_stg30_falcon-ryoma | 10645 / 18669 | 10.1 -> 2.6 | 0.3 -> 0.1 | 1.1 -> 0.4 | 0 -> 0 | 0 -> 0 |
| classic_stg40_falcon-ryoma | 12112 / 10926 | 2.3 -> 0.2 | 0.1 -> 0.0 | 0.7 -> 0.3 | 0 -> 0 | 0 -> 0 |
| classic_stg50_falcon-ryoma | 7785 / 8778 | 1.0 -> 0.4 | 0.0 -> 0.0 | 0.6 -> 0.2 | 0 -> 0 | 0 -> 0 |
| classic_stg60_falcon-ryoma | 6702 / 10096 | 3.5 -> 0.8 | 0.0 -> 0.0 | 1.2 -> 0.2 | 0 -> 0 | 0 -> 0 |
| classic_stg70_falcon-ryoma | 12870 / 15922 | 6.3 -> 1.0 | 0.3 -> 0.2 | 0.9 -> 0.8 | 0 -> 0 | 0 -> 0 |
| classic_stg80_falcon-ryoma | 7678 / 7820 | 14.0 -> 3.6 | 0.0 -> 0.1 | 2.1 -> 0.9 | 0 -> 1 | 0 -> 0 |
| classic_stg90_falcon-ryoma | 9672 / 8376 | 0.9 -> 0.0 | 0.0 -> 0.0 | 0.4 -> 0.4 | 0 -> 0 | 0 -> 0 |
| classic_stga0_falcon-finalvalgas | 12617 / 18338 | 100.0 -> 0.4 | 0.0 -> 0.0 | 0.7 -> 1.3 | 0 -> 0 | 0 -> 0 |
| remaster_stg00_falcon-ryoma | 13475 / 10084 | 5.1 -> 2.2 | 0.3 -> 0.1 | 1.2 -> 0.6 | 0 -> 0 | 0 -> 0 |
| remaster_stg00_falcon-ryoma-wangtang-gunrock | 21600 / 21600 | 16.4 -> 22.3 | 0.1 -> 0.1 | 9.9 -> 4.4 | 0 -> 2 | 0 -> 0 |
| remaster_stg10_falcon-ryoma | 12283 / 10075 | 1.4 -> 1.0 | 0.2 -> 0.1 | 1.1 -> 0.4 | 0 -> 0 | 0 -> 0 |
| remaster_stg20_falcon-ryoma | 13353 / 10103 | 4.3 -> 0.4 | 0.0 -> 0.0 | 0.4 -> 0.3 | 0 -> 0 | 0 -> 0 |
| remaster_stg30_falcon-ryoma | 10645 / 18669 | 10.2 -> 2.6 | 0.3 -> 0.1 | 1.1 -> 0.4 | 0 -> 0 | 0 -> 0 |
| remaster_stg40_falcon-ryoma | 12112 / 10926 | 2.3 -> 0.2 | 0.1 -> 0.0 | 0.7 -> 0.3 | 0 -> 0 | 0 -> 0 |
| remaster_stg40_falcon-ryoma-wangtang-gunrock | 21600 / 19260 | 27.2 -> 7.0 | 0.1 -> 0.0 | 6.6 -> 7.8 | 0 -> 0 | 0 -> 0 |
| remaster_stg50_falcon-ryoma | 7785 / 8778 | 1.0 -> 0.4 | 0.0 -> 0.0 | 0.6 -> 0.2 | 0 -> 0 | 0 -> 0 |
| remaster_stg60_falcon-ryoma | 6702 / 10096 | 3.5 -> 0.8 | 0.0 -> 0.0 | 1.2 -> 0.2 | 0 -> 0 | 0 -> 0 |
| remaster_stg70_falcon-ryoma | 12870 / 15922 | 6.3 -> 1.0 | 0.3 -> 0.2 | 0.9 -> 0.8 | 0 -> 0 | 0 -> 0 |
| remaster_stg80_falcon-ryoma | 7678 / 7820 | 14.0 -> 3.6 | 0.0 -> 0.1 | 2.1 -> 0.9 | 0 -> 1 | 0 -> 0 |
| remaster_stg80_falcon-ryoma-wangtang-gunrock | 18715 / 13750 | 32.4 -> 15.6 | 0.3 -> 0.6 | 12.2 -> 17.1 | 0 -> 0 | 0 -> 0 |
| remaster_stg90_falcon-ryoma | 9672 / 8376 | 0.9 -> 0.0 | 0.0 -> 0.0 | 0.4 -> 0.4 | 0 -> 0 | 0 -> 0 |
| remaster_stga0_falcon-finalvalgas | 12617 / 18338 | 100.0 -> 0.4 | 0.0 -> 0.0 | 0.7 -> 1.3 | 0 -> 0 | 0 -> 0 |

### The original's fights replayed (6000 frames per stage, Remaster look): before (master) -> after

| stage | frames | hidden % before -> after | head / feet cut % after | under HUD % after | yaw err med (deg) live before -> after | distance err med (cm) live before -> after (rule) | eye height err med (cm) live before -> after (rule) |
|---|---|---|---|---|---|---|---|
| stg00 | 5351 | 1.5 -> 1.5 | 0.0 / 2.7 | 1.9 | 0.05 -> 0.05 | 46.76 -> 46.76 (27.0) | 14.0 -> 14.0 (4.0) |
| stg10 | 5602 | 1.1 -> 1.1 | 0.0 / 1.2 | 2.1 | 2.14 -> 2.14 | 28.09 -> 28.09 (21.0) | 11.0 -> 11.0 (5.0) |
| stg20 | 5511 | 2.0 -> 2.0 | 0.0 / 0.7 | 1.9 | 0.21 -> 0.21 | 20.59 -> 20.59 (17.0) | 10.0 -> 10.0 (6.0) |
| stg30 | 5535 | 0.7 -> 0.7 | 0.1 / 0.5 | 1.8 | 0.05 -> 0.05 | 21.03 -> 21.03 (19.0) | 14.0 -> 14.0 (10.0) |
| stg40 | 5321 | 1.2 -> 1.2 | 0.1 / 2.2 | 1.9 | 0.05 -> 0.05 | 30.41 -> 30.41 (23.0) | 7.0 -> 7.0 (2.0) |
| stg50 | 5537 | 1.2 -> 1.2 | 0.0 / 1.7 | 2.8 | 0.05 -> 0.05 | 38.92 -> 38.92 (25.0) | 9.0 -> 9.0 (3.0) |
| stg60 | 5342 | 0.5 -> 0.5 | 0.0 / 0.9 | 2.1 | 0.07 -> 0.07 | 26.07 -> 26.07 (18.0) | 5.0 -> 5.0 (3.0) |
| stg70 | 5147 | 1.3 -> 1.3 | 0.0 / 1.0 | 1.4 | 0.05 -> 0.05 | 31.23 -> 31.23 (22.0) | 4.0 -> 4.0 (2.0) |
| stg80 | 5346 | 0.8 -> 0.8 | 0.0 / 2.9 | 1.9 | 0.05 -> 0.05 | 53.74 -> 53.74 (24.0) | 12.0 -> 12.0 (2.0) |
| stg90 | 5400 | 0.0 -> 0.0 | 0.1 / 1.8 | 2.7 | 0.05 -> 0.05 | 41.1 -> 41.1 (22.0) | 17.0 -> 17.0 (5.0) |
| stga0 | 5218 | 0.2 -> 0.2 | 0.0 / 0.3 | 0.0 | 0.33 -> 0.33 | 55.03 -> 55.03 (56.0) | 24.0 -> 24.0 (20.0) |

Identical before and after on all 11 stages: replayed fighters stand in their logged spots (no one lies along the floor),
so the sphere test agrees with the old three points and the faster swing never triggers; the original's rule is
untouched. Hidden 0.0-2.0% (target < 5%) on the original's own positions; yaw median 0.05 deg on 8 stages (Ryoma's
2.14, the dojo 0.21, the boss arena 0.33: the preset choice, "Not explained yet" above); distance 21-55 cm live, 17-27 cm
for the rule alone (boss 56); eye height 4-24 cm live, 2-10 cm for the rule (boss 20): the same as fx-cam measured.

## Files

- `tools/stagelog.py` (fcinst port; `boot_boss` for Final Valgas), `tools/cam_stage.py` (fit + model + `sim_boss`),
  `tools/cam_fid.py` (replay summary), `game/tests/cam_replay.gd` (replay the original's fight into the remaster;
  `PS_SHOTS` renders stills to put next to the original's Flycast shots).
- `game/assets/fidelity/stg00..stga0_cam.json` (tracked): presets, zone grid, distance / height / smoothing constants,
  the original's playable area (50 cm cells: where its fighters' feet were), and each file's own model-vs-original
  score. `game/scripts/fight_cam.gd` reads them.
- Logs (untracked, main repo): `dumps/cap/cl<NN>.bin` + `cm<NN>.bin` (+ .meta.json), `cfa0.bin`, shots
  `dumps/shots/cl<NN>_*.png` / `cm<NN>_*.png`.

## Left

- The preset choice: find the camera code in 1ST_READ (fields via base + 0x400, the code that writes +0x474 / +0x450)
  for the exact zone rule and the eye-height cases the rule misses.
- In-game "under 5% hidden" on Dawnvolta / ship / lair / boss arena needs BUG-1 (floors, playable areas, stuck
  fighters). Re-run the seeded audits once fx-oom is merged.
- Battle Royale still uses the old box rule on top of each stage's preset.
