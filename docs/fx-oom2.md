# fx-oom2: out of the map, wave 4 (BUG-1, BUG-60, the objects; lane pstrailer2, 10-27)

the owner's bar: a fighter's feet always have the stage's own floor under them and stay inside that stage's playable area
(the original's, measured from the disc). Exemptions only where the disc itself puts a fighter. Before = test_all on
ff61291 (the lane logs) and this branch's first runs on master 2f8da7d.

## What was wrong (measured)

1. **The probe's rasters ended where the probe stopped, the disc's fighters didn't.** `stage_area.py build` sizes the
   sdf / floor rasters to the probe's placements + 60 cm. The flood fill never crossed onto some raised floors, so
   tools/area_logs.py threw away every logged centre past the raster: Rouge's stage (raster z <= 2.6 m, the disc's
   fighters run on 1.2 / 1.85 m walkways to z 7.5 m and x 7.7 m: 13,025 of 60,752 logged centres off the raster), the
   ship (raster z <= 1.6 m, logs to 6.4 m: 23,814 off), Galuda's (3,813 off), Dawnvolta (218), Valgas (205).
   Fix: area_logs.py grows the rasters (same grid) to every logged centre + 1.5 m. Ground gained from the logs:
   stg70 +47.0 m2, stg80 +31.3, stg50 +27.0, stg40 +26.5, stg60 +10.8, stg10 +9.8, stg90 +7.5.
2. **Fake floors from air attacks (lead's find, moves_ryoma).** area_logs counted a row as standing when it was in a
   ground/attack state with vy 0 and y flat over 3 frames. An air attack's hit-stop holds the attacker still in mid-air
   for 8 frames in state 10 (Ryoma's k1/10 at (-60, -330) on stg10: a 287 cm level), Kraken's Power Change hovers in
   state 11 (Londo 179 cm). The remaster's fighters landed on them and stood there. Fix: standing evidence only while
   the fighter is on the ground = a ground state (idle 0, walk-start 2, land 6, run 31, stop 32) reached with the feet
   flat; attacks only count while that holds. Plus: a level no neighbouring 25 cm cell has is dropped. Removed per
   stage (levels): stg00 57, stg10 87, stg20 130, stg30 70, stg40 137, stg50 70, stg60 189, stg70 59, stg80 117, stg90
   183, stga0 55. moves_ryoma f792-820 now equals the disc row for row (y 322.5 > 284.5 > 214.5 > 112.5 > 0 at f808).
3. **Log levels inside blocks.** Runners along a block's face put the plaza's level into 25 cm cells whose centre is
   the block (the probe placed a fighter on the centre 30 cm over the start floor and the game lifted it onto 120 cm):
   Ayame's stage cells [0 / -33, 120] where the probe has [120], and the remaster's fighters stood 1.2 m inside the
   block (FFA 1,255 frames at (5.68, 0.01, -5.0)). Fix: no log level under the probe's own lowest floor at that lattice
   point (469 / 4421 / 68 / 145 / 346 / 1176 / 1724 / 89 / 0 / 449 / 267 rows, stg00..stga0).
4. **No remaster collision under floors the original has.** The out-of-map rule needs the remaster's own geometry under
   the feet. tests/area_check.gd only tested each cell's top level at its centre: Galuda's ground floor under the 1.0 /
   3.05 m tops, mesh edges inside a cell, the edge cells. Now every level, 9 points per cell, cells to 20 cm outside the
   area; `stage_area.py patch floor` boxes them (patches before -> after: stg00 25 -> 35, stg10 27 -> 33, stg20 13 -> 15,
   stg30 0 -> 6, stg40 331 -> 422, stg50 3 -> 425, stg60 91 -> 137, stg70 1 -> 185, stg80 35 -> 110, stg90 170 -> 206,
   stga0 988 -> 1047). Every stage: 0 holes after.
5. **Bodies inside blocks.** The 2D area holds a block's top, so the push-back can't see its sides; core_ground stops a
   fighter's own moves at them, but body pushes, throws and launches only go through clamp_fighter (Dawnvolta FFA:
   Ayame at (-2.26, -0.36, 5.61) under a 4.3 m top for 14 frames, then lifted 4.7 m onto it). clamp_fighter now lifts a
   body whose feet are under every floor there onto the top when it is <= 40 cm over the feet (the original lifts a
   fighter put 40 cm under Londo's fountain base onto it, probe), else moves it out sideways to the nearest spot with a
   floor at the feet.
6. **Air push-back over a raised top (fx-cpu4's Londo 240 cm trap).** Airborne feet over the face band of a raised
   floor whose top is just under them (<= 60 cm) move onto it: the band is outside in the area (a fighter placed on the
   face is moved) but the disc's jumps land on the top (OBJ.md 5). A cell without a floor (a wall / fence) never opens.
7. **Battle Royale starts / random floor points** on the original's floor (closest to the start floor), never under
   another floor of the original (an overhang / a block's foot), on the remaster's floor too; BR starts at +5 cm like
   the two real starts (they were dropped from 1.2 m over the remaster mesh's height: Dawnvolta's FFA started Ayame
   at y -2.26 inside a 50 cm block).

## Tools added

- `PS_OOM_ONLY=1` (run_tests.gd): the plain match then the Battle Royale only (out-of-map iteration, ~4 min a stage).
- `PS_OOM_DEBUG=1` now prints the Battle Royale's runs too (`OOMB n.. out|back fighter pos state gst gmo v sdf air lv
  run`).

## Proof

Stage runs = `PS_STAGE=stgN0 PS_TEST_CHARS=falcon,ryoma run_tests.gd` (test_all's stage runs) with `PS_OOM_ONLY=1`: the
plain 1v1 match, then the Battle Royale free-for-all and 2v2 on that stage, every frame of every phase checked by
`Arena.fighter_out_of_map` and `CamCheck.objects_out` (unchanged rules, nothing loosened). Before = test_all ff61291
(the brief's logs); in both looks the counts are identical on every stage (the looks play the same matches), so the
after runs are in the Remaster look and the base suite runs in Classic.

| stage | before ff61291: 1v1 frames / objects / FFA / 2v2 | after (this branch) |
|---|---|---|
| stg00 Londo | 0 / 0 / 0 / 0 | |
| stg10 Ryoma | 4 / 0 / 158 / 306 | |
| stg20 Wang-Tang | 0 / 0 / 95 / 12 | |
| stg30 Jack | 55 / 0 / 1448 / 57 | |
| stg40 Dawnvolta | 0 / 0 / 251 / 310 | |
| stg50 Galuda | 2303 / 24 / 9041 / 11976 (+ random floor points FAIL) | |
| stg60 Ayame | 67 / 0 / 143 / 476 | |
| stg70 Rouge | 364 / 14560 / 73 / 1742 | |
| stg80 Kraken's ship | 758 / 10607 / 3029 / 764 | |
| stg90 Valgas | 0 / 0 / 49 / 113 | |
| stga0 Final Valgas | 0 / 0 / 7 / 0 | |
