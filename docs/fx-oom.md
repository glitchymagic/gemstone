# fx-oom: fighters "outside the map" (BUG-1) — the original's playable area, measured

the owner (10-26): "some of the characters are fighting outside the map". In the remaster fighters stood on white fog / void
beyond the stage floor. Causes in `game/scripts/arena.gd` (before this branch): a 40 x 40 m invisible safety floor
under every stage, ONE clamp rectangle per stage (`bounds_cm` = the bounding box of the floor-level world vertices),
and gems / Battle Royale starts / random points picked in that rectangle. The rectangles were 1.4x (Ryoma's stage) to
360x (Kraken's ship: 160 x 140 m of sea) the area the original lets you stand on; Londo's rectangle also walled off
19 m2 the original lets you reach (its west street to z 9.3 m at y -0.5, the terrace stairs).

## Method: probe the original in Flycast (tools/area_probe.py)

The stage collision is not in STGn0.MDL (only drawn parts; a 55 cm fountain base the remaster draws at 62.8 cm) and
the code that resolves it (the player update at 0x0C097B10: state handler table 0x0C339260, prev-pos copy, velocity =
pos - prev at 0x0C0A2C4A) reads it through tables I could not tie to data in the time box, so the area is measured on
the running game instead, as the game itself resolves it:

- Boot arcade P1 (Falcon; Ryoma on Londo) vs the stage owner on his home stage (`reflog.boot`; Final Valgas: fight 1
  poked to Valgas and won, his arena next), both fighters human and idle, gems, health and the round clock frozen.
  **Round clock = u8 0x0C7F304D** (seconds left, counts down; freeze it at 99). 0x0C7F2F28 (in common.md / reflog) is
  a sub-second counter of another timer: freezing it does not stop time-over, and the first runs here were thrown away
  because the rounds kept ending under the probe (state 21 = time over).
- A probe tape: each job `place`s a fighter (feet x y z cm) and lets the game's own collision settle it (14 frames,
  40 for drops), then puts both fighters back on their start points for 3 frames (a placed fighter keeps the fall
  speed it had: +0x7270 is derived, pos - prev).
- Flood fill on a 50 cm lattice from the round's start points: A = placed 30 cm over the start floor, B = dropped from
  7 m where A failed, C = 17 cm higher where the game held the fighter at its placement height (Londo: inside some
  collision volumes a fighter gets neither gravity nor a push: no floor there). A node is inside when the fighter
  settles where it was put; the fill also crosses nodes nudged < 25 cm (step edges). Then every lattice edge with a
  class change or a floor step is refined at 25 cm, then every 25 cm point next to an inside node is probed (fill:
  floor heights at 25 cm everywhere), then a radius calibration.
- What the game does, measured: placed past a wall it is moved back out on the next frame (any height up to 10 m);
  beyond the stage's collision volumes there is nothing (a fighter placed 300 m out falls forever); on a floor edge it
  is nudged off; inside some volumes it is lifted on top.
- `tools/stage_area.py build` turns the samples into `game/assets/fidelity/STG_area.json`: evidence = every placed
  point (inside / outside) + every pushed fighter's resting place (exactly on the edge) -> nearest-evidence 10 cm
  raster, a wall push's plane cuts everything past it (not where a floor the game settles fighters on lies just
  beyond: Londo's fountain ring), the part connected to the start points, solid holes < 4 m2 filled (the stage's own
  collision handles a fountain column) -> signed distance (cm, + inside), edge contours, the 25 cm floor raster (up
  to 4 levels per cell), every spot the probe stood on, the original's round-start feet.

### Per-fighter reach: player struct +0x258 is the stage-collision radius

Every probe boot dumps both player structs. The calibration (the same wall pushes probed by Falcon and by the stage
owner) gives the owner's reach against Falcon; its median equals the difference of +0x258 for all nine owners measured:

| fighter | +0x258 (cm) | delta vs Falcon | calibration median |
|---|---|---|---|
| falcon | 30.0 | 0 | ref |
| ryoma | 40.0 | +10.0 | +10.0 |
| wangtang | 27.3 | -2.7 | -2.7 |
| jack | 34.05 | +4.05 | +4.0 |
| gunrock | 60.0 | +30.0 | +30.0 |
| galuda | 48.0 | +18.0 | +18.0 |
| ayame | 31.5 | +1.5 | +1.5 |
| rouge | 31.5 | +1.5 | +1.5 |
| kraken | 52.0 | +22.0 | +22.0 |
| valgas | 50.4 | +20.4 | +20.4 |

`game/assets/fidelity/fighter_radius.json`. The area files are for Falcon's centre; Arena.clamp_fighter keeps each
fighter delta further in. (The remaster's capsule is 38 cm for everyone; its walls sit 38 cm out from the edge.)

## Per stage (probe counts, area before / after)

Probe samples = every placement the probe made (placed points / those inside); "raised floors joined" (fx-proof,
10-27): the first build cut every raised floor off the area (the wall pushes round a block's sides cut its top off from
the start floor, then "connected to the start points" dropped it), so the remaster walled off floors the original
stands fighters on: Galuda's / Rouge's 60-65 cm floors a run climbs, Ayame's 120 cm and the ship's 100 cm decks a
jump reaches (37-44% of those stages' settled probe spots were outside the area file). `stage_area.py build` now
joins an island when settled fighters rest on it, its floor is at most a standing jump's apex (330 cm) over the
start floor and it is within a moving jump's reach (3.7 m) of the start floor's part; Final Valgas's arena is in the
proof section.

| stage | probe samples (placed / inside points) | raised floors joined | old rectangle m2 | original area m2 (fx-oom -> now) | rectangle not in the area m2 | walled off by the rectangle m2 | stand spots | ok | missing | higher | blocked | on throwables |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| stg00 Londo | 4289 (3294 / 2487) | 5 | 156 | 156.7 -> 178.6 | 14 | 36.9 | 3207 | 2640 | 164 | 7 | 73 | 396 |
| stg10 Ryoma | 3776 (2944 / 2157) | 2 | 1089 | 130.1 -> 146.3 | 943 | 0.0 | 2838 | 2601 | 86 | 37 | 105 | 114 |
| stg20 Wang-Tang | 3290 (2372 / 1968) | 0 | 403 | 131.6 -> 131.6 | 271 | 0.0 | 2423 | 1801 | 33 | 0 | 9 | 589 |
| stg30 Jack | 2229 (1844 / 1443) | 0 | 196 | 98.4 -> 98.4 | 98 | 0.0 | 1829 | 1676 | 86 | 0 | 4 | 67 |
| stg40 Dawnvolta | 3784 (2798 / 2071) | 1 | 570 | 123.5 -> 135.1 | 434 | 0.0 | 2450 | 2155 | 53 | 65 | 145 | 177 |
| stg50 Galuda | 2824 (2125 / 1636) | 1 | 228 | 76.0 -> 109.1 | 119 | 0.0 | 2193 | 2018 | 10 | 0 | 41 | 165 |
| stg60 Ayame | 4160 (3086 / 2312) | 3 | 905 | 82.0 -> 157.0 | 748 | 0.0 | 2977 | 2922 | 13 | 1 | 172 | 41 |
| stg70 Rouge | 2339 (1887 / 1398) | 2 | 336 | 70.4 -> 97.5 | 238 | 0.0 | 1708 | 1588 | 24 | 0 | 25 | 96 |
| stg80 Kraken ship | 1995 (1540 / 1186) | 1 | 22559 | 62.9 -> 78.8 | 22480 | 0.0 | 1410 | 1259 | 11 | 0 | 80 | 140 |
| stg90 Valgas | 3803 (3064 / 2508) | 4 | 1279 | 139.3 -> 158.8 | 1120 | 0.0 | 2893 | 2763 | 39 | 0 | 75 | 91 |

Area before = the old clamp rectangle; "rect not in the area" = void / walls a fighter could reach before; "walled off"
= area the original lets you reach that the rectangle cut off (only Londo). Stand spots = settled probe positions in
the area; tests/area_check.gd stands a 26 cm capsule on each and casts a ray down in the remaster: ok = the remaster's
floor within 12 cm of the original's, missing = no floor there (edge spots within 50 cm of another floor height are
left alone: the disc mesh's and the collision's edges differ by < 25 cm), higher = the remaster's floor is higher,
blocked = the remaster's collision is in the way, on throwables = spots where a throwable stands in the remaster.

## In the remaster (game/scripts/arena.gd)

- No safety floor where the stage has measured data (kept only for runs without the stage's files).
- Invisible walls on their own collision layer (`Arena.BOUNDS_LAYER` = 4, `bounds_body`): one thin box per edge
  segment, from 6 m under the lowest floor to 16 m over the highest, set out by the capsule radius. Fighters only
  (clamp_fighter adds the layer to their mask): the camera's rays and the ground rays never see them, so the fight /
  cinematic cameras are unchanged.
- clamp_fighter (the one call fighter.gd already makes after moving): every frame, every state, the original's push-
  back (the fighter's x/z onto the nearest point inside its area, speed into the wall dropped); feet never under the
  original's floor (nothing of the stage under them -> up onto the floor the original has there: a pole release inside
  a pillar used to drop fighters under the dojo floor); below every floor -> back on the nearest floor.
- Collision corrected from the data: throwables were built as solid walls on every stage but Londo (JSON numbers are
  floats; `11 in [11.0]` is false in GDScript) and now are Props; disc surfaces / placed parts that the remaster stands
  fighters on where the original's floor is clearly lower and never agrees are left out of the collision (Ryoma's
  stage: four placed parts + one surface); floor patches (invisible 50 cm boxes, layer 1 so ground rays see them)
  where the original stands fighters and the disc mesh has no floor (Dawnvolta's raised floors: 328 patches).
- Start points = the original's round-start feet (logged at the first free frame of every probe boot; these match the
  fx-cam lane's AI logs). Gems / respawns (random_floor_point) on the original's floors inside the area, the start
  floor first; Battle Royale starts pushed 0.8 m inside the area; gems clamped inside; a dropped throwable is set on the
  original's floor inside the area; a flying one breaks at the original's walls / floor; CPU retreat targets clamped.
- fx-proof (10-27): the original's raised floors are in the area (see the table); a fighter standing, lying or stuck
  (held at one height 30 frames in idle / run / jump / down / get-up) where the original has no floor within 35 cm of
  its feet (centre and 25 cm round it) goes down onto the original's floor under it, or, inside a block's footprint
  under its top, out sideways to the nearest spot with the original's floor at the feet (clamp_fighter); poles, grabs,
  throws and Power Change are never moved; a fighter standing on another's head (the remaster's capsules collide; the
  original's push spheres keep bodies apart) goes off him sideways; nobody gets higher than 4.5 m over the stage's
  highest floor of the original (a pole release from it rises 1.85 m over a 2.6 m hang; the remaster's pole swings
  reached 17-24 m), Power Change forms excepted. `out_of_map(pos, tol, grounded)` counts that case too (cam_check,
  run_tests, brawl_tests pass `is_on_floor()`), and `tools/oom_rescore.py` scores any audit log with the same rule.
- `core_ground(feet, prev, char_id, climb)`: the original's floor / walls / step-up / hop for the fidelity core (see
  "Step-up").
- Helpers for any movement code (the movement port on master can call these every frame): `sdf_at(x, z)`,
  `inside(x, z, margin)`, `push_out(pos, char_id)` / `clamp_point(pos, margin)`, `floor_levels(x, z)`,
  `floor_y_at(x, z, from_y, step)` (the highest floor at most `step` over the feet, default the step-up),
  `wall_at(x, z, y, char_id)`, `on_floor(pos)`, `out_of_map(pos)`, `fighter_margin(char_id)`, `step_up`.

## Step-up (running into a ledge), measured with D-pad runs (runtest, Flycast)

Runs aimed straight at a floor step found in the probe's floor raster (fx-oom `runtest.py` D-pad, `runtest2.py` analog
stick; P1 placed 1.2 m back on the lower floor, 50 frames of running, per-frame feet + state):

| stage | step (cm) | runs | result in the original |
|---|---|---|---|
| Wang-Tang's dojo | 0 -> 50, 50 -> 100 | 4 | held 4 frames at the edge (state 31, centre 18-22 cm short of the raster's step), then on the upper floor, running on |
| Galuda's | 0 -> 60 | 1 | same: 4 frames held, then up |
| Rouge's | 0 -> 65 | 2 | 4 frames held at 0, 4 more at 59, then 65 (two collision tops) |
| Londo | 0 -> 50, 0 -> 55 (fountain base) | 5 | climbed (D-pad diagonal runs: 3 of 5 straight enough to time) |
| Wang-Tang's dojo | 50 -> 150 | 2 | held 5 frames, then the hop: state 17 for 6 frames, then placed ~50 cm on, on the upper floor, running |
| Wang-Tang's dojo | 0 -> 100 | 1 | stopped (a wall: the hop is not every 100 cm ledge) |
| Dawnvolta | 0 -> 91, 0 -> 144, 0 -> 430 | 5 | stopped |
| Kraken's ship | 0 -> 100 (upper deck) | 3 | stopped (held 21-75 cm out from the deck's raster edge depending on the run-start) |
| Ayame's | 0 -> 120 | 1 | stopped |

So the step-up is 65 cm (largest climbed), every measured rise of 91 cm or more stops a run except the dojo's
50 -> 150 cm ledges (the hop). Placing a fighter inside a block (tools/area_probe.py, fx-oom `steptest.py` on Londo)
lifts it onto the block's top: 5-10 cm under the terrace's top, up to 40 cm under the fountain base, 150 cm under the
second terrace; deeper than that (terrace) it is pushed out sideways. Running off a 25-33 cm step keeps the run state
and falls at 2 cm/f^2 (o_move_basic, FIDELITY.md).

`Arena.core_ground(feet, prev, char_id, climb)` (game/scripts/arena.gd) is that rule for the fidelity core: the
original's push-back (its area and this fighter's radius), the floor under the feet from the probe's 25 cm floor
raster (lift up to 10 cm, follow rises / drops up to 15 cm, fall off anything bigger), a ledge in front of a grounded
fighter returned as "step" (hold LEDGE_HOLD_F = 4 frames, then call with climb = true), "hop" (HOP_HOLD_F 5 + HOP_F 6
frames, then climb: HOP_IN 50 cm on) or "wall" (the run stops), airborne feet held out of a block that is higher than
them. tests/ground_check.gd replays the original's cases through it (game/assets/fidelity/ground_samples.json,
tools/ground_samples.py: 120 settled + 120 pushed probe samples per stage + every run test):

- settle (dropped from the probe's placement): 1188 / 1200 land within 2 cm of where the original settled them (the
  12 others: 7 m drops onto roofs / ledges that are not in the area: Ryoma's 7.3 m roof, Dawnvolta's 2.2 m ledge).
- push (placed past a wall): x/z error vs the original's resting place median 5.8 cm, p90 50 cm (the area raster is
  10 cm; the p90 is pushes off ledges, where the original pushes sideways and core_ground lifts onto the top).
- runs: 10 of 15 straight runs as the original (climbed / stopped, the frame the feet go up within 2 frames, the
  held spot within 12 cm). Off: Rouge's double top (65 cm: climbed 4 frames early; one run now stops), one Londo
  fountain run 3 frames early, the dojo's 0 -> 50 run the original stops at (a wall the raster can't tell from a
  step), Dawnvolta's 144 cm wall held 15 cm further out.

## Proof

`tools/oom_proof.sh` with PS_SEED=1 (falcon vs ryoma; falcon vs Final Valgas on his arena), every stage in both looks,
plus 4-fighter Battle Royale (falcon, ryoma, wangtang, gunrock) on Londo, Dawnvolta (multi-level) and Kraken's ship;
before = master a7b7b29 (a clean copy), after = this branch. The live count is tests/match_movie.gd + CamCheck
(`out_of_map` = a fighter's feet not over the stage's own floor inside the original's area, or, new in this pass,
resting on something with no floor of the original within 35 cm; `obj_out` = gems / throwables). The master run
counted 0 everywhere but its rule could not see what was wrong: Final Valgas stood 3.94 m under the floor of his
arena (no area file, the safety floor), fighters stood on 1.2-2.2 m tops (each other's heads), wall-kicked 100 s on
a 7.2 m top and ran on a 24 m roof after the remaster's pole swings. `tools/oom_rescore.py` re-scores both runs with
one rule (this branch's areas; feet outside the area / standing with no floor of the original, pole hangs left out).

What the audits found and what was fixed, in order: the raised floors cut out of the areas (stage_area.py), the boss
arena's missing area (resumed probe), fighters on the original's no-floor tops (clamp: off sideways), inside a
block's footprint (up onto it or out), on each other's heads (off sideways), above any height the original's physics
reaches (the remaster's pole swings: capped 4.5 m over the stage's highest floor), and the out-of-map rule itself.

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

Re-scored with one rule (frames):

| run | out-of-map frames, same rule (before -> after): feet outside the area / standing with no floor of the original |
|---|---|
| classic_stg00_falcon-ryoma | 0 / 1887 -> 0 / 5 |
| classic_stg10_falcon-ryoma | 0 / 44 -> 0 / 0 |
| classic_stg20_falcon-ryoma | 0 / 0 -> 0 / 0 |
| classic_stg30_falcon-ryoma | 0 / 0 -> 0 / 4891 |
| classic_stg40_falcon-ryoma | 0 / 0 -> 0 / 0 |
| classic_stg50_falcon-ryoma | 0 / 0 -> 0 / 0 |
| classic_stg60_falcon-ryoma | 0 / 0 -> 0 / 8 |
| classic_stg70_falcon-ryoma | 0 / 0 -> 0 / 15 |
| classic_stg80_falcon-ryoma | 0 / 0 -> 0 / 7 |
| classic_stg90_falcon-ryoma | 0 / 0 -> 0 / 0 |
| classic_stga0_falcon-finalvalgas | 0 / 0 -> 0 / 0 |
| remaster_stg00_falcon-ryoma-wangtang-gunrock | 0 / 0 -> 0 / 73 |
| remaster_stg00_falcon-ryoma | 0 / 1887 -> 0 / 5 |
| remaster_stg10_falcon-ryoma | 0 / 44 -> 0 / 0 |
| remaster_stg20_falcon-ryoma | 0 / 4 -> 0 / 0 |
| remaster_stg30_falcon-ryoma | 0 / 309 -> 0 / 4891 |
| remaster_stg40_falcon-ryoma-wangtang-gunrock | 0 / 0 -> 0 / 5 |
| remaster_stg40_falcon-ryoma | 0 / 159 -> 0 / 0 |
| remaster_stg50_falcon-ryoma | 0 / 0 -> 0 / 0 |
| remaster_stg60_falcon-ryoma | 0 / 0 -> 0 / 8 |
| remaster_stg70_falcon-ryoma | 0 / 5 -> 0 / 15 |
| remaster_stg80_falcon-ryoma-wangtang-gunrock | 0 / 0 -> 0 / 6 |
| remaster_stg80_falcon-ryoma | 0 / 74 -> 0 / 7 |
| remaster_stg90_falcon-ryoma | 0 / 2 -> 0 / 0 |
| remaster_stga0_falcon-finalvalgas | 2741 / 2897 -> 0 / 0 |

run_tests.gd / brawl_tests.gd: both count `Arena.fighter_out_of_map` every frame of every phase and fail on any
(verified on the merged code: the 01:35 run of the base suite failed "free-for-all: no fighter out of the map (29 of
14643 frames)" on a head-stand, i.e. the check fires); tests/ground_check.gd builds every stage and checks the rule
itself (start points in, 1 m past the edge out, 3 m under the start floor out). The base suite on the final code
(4f24aa5..24bf69c): 1 frame in the free-for-all (Ayame landing on Londo's fountain centre piece at 1.96 m, off it the
next frame), so it still fails there.

Live results above: 0 out-of-map frames on 10 of 11 stages in both looks (Classic and Remaster play the same match),
1 on the ship (Falcon running over a crate whose disc top is 1.70 m, the original's 1.35: exactly the 35 cm
tolerance), 2 in Londo's Battle Royale; gems / throwables 0 everywhere. The re-score finds what the live check can't
see: Jack's stage after = 4891 frames of Falcon lying (DOWN, k2/144) at (-2.81, 2.3, 0.02) from round 3's start
(frame ~13300) to the time-over 90 s later, x/z fixed, y creeping up 16 cm: nothing of the stage is under him (the
stage collision there is at 0) and Arena._off_top finds a spot 10 cm off, so his own physics / clamp_fighter never
ran: a fighter frozen for the whole round (the per-fighter freeze / time scale of fighter.gd + cinema.gd after the
round-2 KO and win poses). For the lead: dumps in /tmp/ps-fx-proof/proof_s1/
remaster_stg30_falcon-ryoma.jsonl (PS_SEED=1, match_movie, both looks). The rest is 0-73 frames (Battle Royale
landings).

## Tools

- `tools/area_probe.py STAGE INST [cal|fill]` (Flycast, tools/fcinst.py instances), `AREA_OUT` = sample folder.
- `tools/area_finalize.sh STAGE` = `stage_area.py build` + tests/area_check.gd + `stage_area.py patch` (surfaces off,
  floor patches) + the final check. `tools/stage_area.py radius` -> fighter_radius.json.
- Out-of-map checks: `CamCheck.frame` writes `oom` / `sd` per fighter and `oomo` (gems / throwables) per frame;
  `tools/cam_audit.py` reports `out_of_map` / `obj_out`; run_tests.gd and brawl_tests.gd fail on any frame out of the
  map; `tools/oom_proof.sh` = seeded match_movie audits on every stage in both looks + Battle Royale.

## What's left

- **fighter.gd (the lead's): call `Arena.core_ground` from the fidelity core.** In `_core_move(d, on_floor)`, instead
  of the ray step-up and `move_and_slide` landing: `var prev := global_position; var r := arena.core_ground(prev +
  d * 0.01, prev, char_id, _climb); _climb = false; global_position = r.pos`. Ledges: `r.ledge_kind == "step"` ->
  `_hold += 1`, and when `_hold >= Arena.LEDGE_HOLD_F` set `_climb = true` (the next frame's call puts the feet on the
  upper floor and the run goes on); `"hop"` -> at `_hold == Arena.HOP_HOLD_F` play state 17 for `Arena.HOP_F` frames,
  then `_climb = true`; `"wall"` or `""` -> `_hold = 0`. `r.wall` -> drop the velocity into `r.normal`
  (`vcm -= r.normal * minf(0.0, vcm.dot(r.normal))`). `r.grounded` replaces `is_on_floor()` for the core's
  transitions (false = in the air: state 14 from idle, the run keeps falling at 2 cm/f^2; landing when it turns
  true). Fighter-vs-fighter pushes stay with the physics. clamp_fighter stays as the safety net (it never moves a
  fighter core_ground left on the original's floor).
- fighter.gd (the lead's): pole swings reach 17-19 m on Jack's mansion and Galuda's stage (seed 1: Ryoma k1/151 at
  19.35 m; the original: 36 cm/f up, 3.5 cm/f^2 = about 1.9 m over the catch), and a wall kick (k2/206) can loop for
  100 s when the fighter is wedged on a top (the original: k2/206 8 f > k0/13). clamp_fighter now takes the fighter
  down onto the original's floor after 30 frames, but the loop itself is the state machine's.
- The hop: only the dojo's 50 -> 150 cm ledges are measured (`Arena.HOP`); what makes a ledge hoppable (the dojo's
  0 -> 100 cm one stops a run) is in the collision data, not decoded.
- Inside a block the original lifts a fighter onto some tops (fountain base from 40 cm under, a terrace from 150 cm)
  and pushes it out of others (the first terrace deeper than 10 cm): per collision volume. core_ground lifts; pushes
  off ledges are 50-99 cm off at p90 on Ryoma's / Dawnvolta's stages (tests/ground_check.gd).
- Rouge's 65 cm ledge has two tops (59, 65): the original holds the run 4 + 4 frames, core_ground 4.
- The 25 cm floor raster can't tell a 50 cm wall from a 50 cm step (one dojo spot stops a run, another climbs).
- Final Valgas's arena: no radius calibration (the boss is never placed); his spot is filled in as his body.
- Battle Royale camera: the old box rule (fx-cam's "Left"); hidden 16-32% in the 4-fighter audits.
