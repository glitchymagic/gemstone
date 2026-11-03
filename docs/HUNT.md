# Breakage hunt (BUG-28, lane pstrailer2, helper fx-hunt, 2026-10-27)

the owner: "I'm sure there a lot of other bugs I haven't noticed myself yet". This hunt drives the remaster like a player and
flags every breakage frame by frame, with a repro. It is built to be re-run on new code with one command and diffed.

## Harness

- `game/tests/hunt.gd` (Godot `-s` script):
  - **fight**: one stage, two fighters, BOTH human-driven through the keyboard path a player uses (Input key events ->
    `PInput.poll_human`: P1 WASD/J/K/Space/L/U/I/Enter, P2 arrows/keypad). Seeded fuzz: chords (direction + any of
    punch/kick/jump/action/fusion) held 1-24 frames, mashed buttons, rare Start. Every 3-7 s a forced situation (like the
    tape's `place` command): fighters face to face (ground / one in the air), at a pole, next to a throwable, at the stage
    edge, 3 gems (Power Change via `pick_gem`), low health (KO + next round), clock run down (TIME), pause opened and
    driven. The match restarts when it ends, until FRAMES. Real presentation path (HUD, music, look, camera), no replay
    saved.
  - **menus**: the whole flow from the title through the Game autoload: random menu keys on title / options / select /
    arcade / VS / results / continue / pause / replays; P1 fights through the same keys, every round ends on TIME after
    ~3 s so the run reaches many screens; title QUIT is disabled.
  - **static**: every sound / music id the scripts ask for exists on disk; every stage has its own music track.
- Detectors (per frame, after physics and animation, i.e. the frame as drawn): every Godot error / warning / script
  error (an `OS.add_logger` Logger, keyed by the GDScript file:line), NaN position, health outside 0-240, gems outside
  0-3, timer outside 0-99, falling under the stage's lowest floor, standing out of the map 20+ frames
  (`Arena.out_of_map`), a state lasting longer than any real motion in it (ATTACK 420, GRAB 300, HITSTUN 240, DOWN 360,
  GETUP 150, TRANSFORM 300, POLE 360, JUMP 600 frames; KO during FIGHT; WIN during FIGHT; few-frame game states 2/4/6/24/32
  over 120), hanging in the air without moving 60+ frames (`wedged`: H-2 / H-3 / H-12), AnimationTree on Start/End/empty
  3+ frames, pose frozen while the clip's data moves (tests/ko_watch.gd),
  pose still 20+ frames in a state that animates (RUN / ATTACK / HITSTUN / GETUP / TRANSFORM / GRAB, hit-stop excluded),
  rest pose (T-pose), bodies (the game's body spheres) 30 cm inside each other for 30+ frames, round phases that never
  end, round clock standing still, nothing moving for 10 s, pause menu not leaving, a menu screen not left after 120 s
  of keys. Runs that hit 20000 error lines stop early (`error_flood`).
- `tools/hunt.sh` takes an APFS snapshot of game/ (edits made while it runs don't mix in; commit in commit.txt), runs
  the matrix, `JOBS` Godot processes at once (default 4), logs in `/tmp/ps-fx-hunt/run_MMDD_HHMM/`,
  then `tools/hunt_report.py` prints counts per finding class
  (diff two runs: `tools/hunt_report.py NEW OLD`) and writes findings.json (each distinct finding, how many runs, the
  first repro command). It adds hang (timeout), crash (no HUNT_END) and exit_leak (Godot's leak lines at exit).
- Matrix (default): 11 stages x 6 pairs = every fighter (10 + Final Valgas) on every stage, both looks
  (`PS_LOOK=remaster|classic`), SEEDS (default 1), 3600 frames (60 s of play) per fight run; one menus run per look and
  seed (3 x FRAMES); one static run. Slices: `STAGES=... FIGHTERS=... SEEDS=... LOOKS=... tools/hunt.sh`; another
  checkout of the game: `GAME=/path/to/game` (before/after runs).
- Repro: every finding carries seed, frame, stage, fighters, look and the state of both fighters; rerun with the
  printed command (fixed-fps, seeded: the same frame comes back as long as the code under test is the same).

## How to run

    tools/hunt.sh                                     # full matrix, 1 seed, both looks (135 runs, ~25 min on a loaded M4)
    SEEDS="1 2" tools/hunt.sh                          # more seeds
    tools/hunt_report.py /tmp/ps-fx-hunt/run_NEW /tmp/ps-fx-hunt/run_OLD

## Findings

(numbers: see "Runs" below; H-numbers are referenced from the commits that fix them)
Status: FIXED (commit) = fixed in branch fx-hunt and re-run; LEAD = the cause is in game/scripts/fighter.gd (the lead's)
or needs Flycast captures; the exact request is in the entry.

- **H-1 Moon jump: air attacks that fall back to the old air attack fly 6-9 m high and freeze.** LEAD (fighter.gd).
  Evidence (run1): pose still 20+ frames in ATTACK with the air clip `*k1_012` 59 times in 32 runs (Falcon, Ayame,
  Rouge, Wang-Tang, both looks); Falcon in ATTACK 420+ frames (7 s) at y 7.1 m. Repro:
  `PS_LOOK=remaster Godot --headless --path game --fixed-fps 60 -s res://tests/hunt.gd -- fight stg00 ayame,rouge 1 2532 /tmp/h.jsonl`
  (Ayame in Power Change jumps at frame 2411, kicks, reaches y 8.26 m at 2459, clip over at 2454, still airborne at
  2475; still there on 9bb48c5). Deterministic, no fuzz: `game/tests/hunt_tapes/h1_air_punch.txt` (README there):
  Falcon's standing jump + kick (core, k1/12) peaks at 330 cm and lands after 36 frames like the original; jump + punch
  peaks at 618 cm, 82 frames in the air, plays the kick clip k1/12, lands still in ATTACK.
  Cause: `_core_tick` states 5/14 hand the attack to the old `_start_attack("air")` after `vel_to_legacy()` (a) always
  when `powered`, (b) when `_core_attack("AX"/"AY")` fails. The old ATTACK/JUMP code then applies `GRAVITY` 26 m/s^2
  (0.72 cm/frame^2) to the core's launch of 35.5 cm/frame (the original: 2 cm/frame^2): apex 21.3^2 / 52 = 8.7 m
  instead of 3.3 m, ~2.5 s in the air while the 26-frame clip has ended. (b) happens on every Falcon jump + punch:
  chains.json AX = k1_010, but Falcon's p00/p01 GLBs have no k1_010 clip (the other 9 fighters have it).
  Request: run powered air attacks in the core too (chains.json already has PAX / PAY for 9 fighters), and never run
  the old air physics on a core velocity (or give it GRAV_CM); capture Falcon's k1_010 (tools/add_clips.py, Flycast).
- **H-2 Invisible walls inside the original's area wedged fighters in mid-air for good.** FIXED 32107ad (arena.gd).
  Evidence (run1, master's walls): JUMP 600+ frames on Londo / Mutsu (Galuda, Kraken at Londo x 4.7 z 6.3, Ryoma);
  the fighter's capsule touches 4-5 `AreaBounds` boxes, `move_and_slide` spends its 6 slides on them, position frozen,
  fall speed growing (-188 cm/frame) and the state never ends (Galuda: forced to the edge, then 25 cm of her own air
  attack into the pinch). Same-seed slice (stg00/10/40, 18 runs): master's walls 3 lying fighters wedged in
  `AreaBounds` boxes on Dawnvolta (Rouge traced at (4.61, 0.5, 6.23): 6 boxes, DOWN for good), fixed walls 0. Cause: `_build_bounds` offsets a 0.5 m box 0.41 m out
  of every contour segment; across the contour's small notches (raster steps, thin posts, segments of 7-14 cm) that
  puts boxes back inside the area: 20 of Londo's 111 boxes had their centre inside it (8 deeper than 30 cm). Fix: a
  box any part of which lies more than 5 cm inside the area is not built (the SDF clamp in `clamp_fighter` still holds
  that edge, like the original's straight push back). Boxes kept: Londo 79, Mutsu 164, Tong-An 67, Manches 43,
  Dawnvolta 179, Dullstown 57, Oedo 31, Mahdad 25, Ship 29, Valgas 119. Base suite 164/164 after the change.
- **H-3 Final Valgas's arena (stga0): fighters hang under its overhang, the fight stands still.** LEAD / fx-oom.
  Evidence (run1): JUMP 600+ frames on stga0 for 6 fighters, "nothing moves for 10 s in FIGHT" in 5 runs (both
  fighters hanging). Normal play, no forced placement: `fight stga0 ryoma,wangtang 1 251`: Wang-Tang starts at P2's
  start point (6.73, -3.94, 6.74), runs at frame 100, makes a moving jump and is stuck from frame 110 at
  (5.94, -1.79, 7.54) for the rest of the fight. Cause: stga0 has no measured playable area (no
  assets/fidelity/stga0_area.json; fx-oom measured stg00-stg90), so the old bounds rectangle clamp holds x/z
  (z = 7.54 every frame) while the capsule sits against the back of the arena's sloped rim (slide normal
  (-0.70, -0.72, 0) at x 6.2, y -0.15): never lands, is_on_floor false, is_on_ceiling true, fall speed growing.
  Request: measure stga0's area like the others (tools/area_probe.py, Flycast) so clamp_fighter's SDF path runs
  there; fighter.gd: an airborne fighter that has not moved for N frames should be resolved (the original never
  leaves one hanging). This is the final boss's arena: every arcade run ends here.
- **H-4 Pause: Start / Escape did not close the pause menu.** FIXED 8ea3013 (fight.gd, ui.gd). Evidence (run1,
  detector added mid-run): 77 times in 35 runs, only the menu's Resume button resumed. The original: Start toggles the
  pause. Also Escape paused on "held", so holding it re-paused right after Resume. Now: pad Start / Escape close the
  menu (Enter / Cross still press the focused button), Escape pauses on its press.
- **H-5 Big fighters' bodies stand inside each other.** LEAD (fighter.gd). Evidence (run1): body spheres 30+ cm inside
  each other for 30+ frames: Final Valgas with anyone 234 times (72 runs x keys), Gunrock-Jack 20, Kraken-Valgas 12,
  Kraken-Rouge 7, Galuda-Gunrock 5. Repro: `fight stg00 finalvalgas,falcon 1 3351` (frame 3291). Cause: every fighter
  gets the same collision capsule (`Fighter.CAPSULE_R` 0.38 m in `setup`), while the game's own radius differs per
  fighter (assets/fidelity/fighter_radius.json delta_cm, measured by fx-oom: Gunrock +30, Kraken +22, Valgas +20.4,
  Galuda +18 cm; Final Valgas not measured and far bigger). Request: capsule radius 0.38 + delta_cm / 100 per
  fighter, Final Valgas's from his struct +0x258 (Flycast).
- **H-6 Power Fusions: the last pose stands still while the move goes on.** LEAD (BUG-25). Evidence (run1): pose
  still 20+ frames in ATTACK 43 times in 34 runs (run2: 34): Galuda l0k1_105, Gunrock g0k1_097 (fusion1_b), Kraken
  k0k1_106 (fusion1_c), Jack j0k1_108 (fusion1_c), Valgas v0k1_108 (fusion2_b), Ryoma r0k1_104 (fusion2_d), Wang-Tang
  w0k1_106 (fusion2), Ayame a0k1_103 (fusion1), Ayame a0k0_026 (her fusion2 > fusion2_b part is mapped to k0/26,
  the run-stop motion, by the clip map: check it against the log). Cause: Fusions still run through the old `_start_attack` with the
  remaster's fixed timing (`Rules.ATTACKS` fusion1 2.0 s / fusion2 2.2 s, `atk_k` 1 for fusions) while the captured
  chain of parts (fusion1 > fusion1_b > ...) is shorter for these fighters, so its last frame holds until the timer
  ends (the original: Ryoma's Fusion P k1/108 290 frames, logged; BUG-25). Port the Fusions to the core with each
  motion's own length.
- **H-7 Revert from Power Change: Rouge's and Valgas's last revert pose stands still.** LEAD (fighter.gd timing or
  captures). Evidence (run1): Rouge TRANSFORM with a still pose 20+ frames (o0k3_009) in 6 runs (run2: 5). Cause:
  the revert state lasts 91 frames for everyone (`tf_len = 91 / 60`, logged on Ryoma: k3/9 39 f + k3/10 51 f), but the
  captured revert clips are Rouge 70, Valgas 75, Galuda 85 frames (Falcon / Wang-Tang / Jack / Kraken 91, Ayame 90,
  Ryoma and Gunrock 39 + 51 chained): their last frame holds 21 / 16 / 6 frames. Request: read the revert's length per
  fighter from the original's logs (state 23 after the gauge runs out) and use it for tf_len, or recapture k3/9 (+ a
  follow-up) for those three.
- **H-8 Most actions are silent.** LEAD (audio). Evidence: the static check passes (every id the scripts ask for has a
  file, every stage has its own track), but the scripts only ever play 2 sound effects (`se_hit`, `se_hit_heavy`) and
  6 announcer lines. `se_throw` is extracted from the disc (tools/sfx_extract.py) and never played (only
  tools/trailer.py uses it). Jumps, landings, swings, pick-ups, item throws, throws, gems, Power Change, poles and wall
  kicks make no sound; the original has one for each. Request: log the AICA channels per action in Flycast
  (tools/ref_londo.py snd, as for the hits) and map them; hook se_throw to the throw once its frame is logged.
- **H-9 A NaN position froze the game in an endless recursion.** FIXED d14b1aa (arena.gd). `Arena.sdf_at` sends an
  off-raster point back through itself clamped; NaN stays NaN, so it recursed until "Stack overflow" every frame
  (20000+ error lines a second, run1: 2 runs, 770 MB log). Only the harness produced a NaN (a forced placement on a
  pole without a floor, fixed in the harness), but any future NaN would hang the game the same way; sdf_at now
  answers "nowhere" for a non-finite point (probe: sdf -1e9, out_of_map true, clamp_point back on the stage).
- **H-10 Leaked objects at exit.** LOW. About 1 run in 3 ends with "N ObjectDB instances were leaked at exit" and
  "N resources still in use at exit" (run1: 47 of 135), the existing suite's logs show the same (t_base*.log: 5 / 1).
  Not reproducible on demand (a --verbose rerun of a leaking case was clean); no effect seen during play.
- **H-11 Getting up / lying inside another fighter.** LEAD (fighter.gd, with H-5). Body overlap 30+ frames with one
  fighter in GETUP (Jack's get-up clip j0k0_051, Gunrock k2/146) and the other attacking or idle, 4 runs; GETUP once
  lasted 150+ frames (Falcon, menus run, frame 554). Same cause family as H-5 (one capsule size, nothing pushes a
  lying fighter out); re-check after H-5.
- **H-12 Fighters wedged into stage / scenery collision hang in the air for the rest of the fight.** LEAD
  (fighter.gd / collision). Evidence (run2, normal play, no forced placement): Tong-An `fight stg20 ryoma,wangtang 2 712`
  on 32107ad: Wang-Tang runs, makes a moving jump off the 1 m ledge at frame 138; at frame 150 (y 3.91, rising) his
  capsule overlaps placed part 29's trimesh (ConcavePolygonShape3D, SceneryCollision) and from frame 151 every
  `move_and_slide` spends its 6 slides at depth 0 against it (normal (-0.5, 0, 0.87)): position frozen, fall speed
  growing to -112 cm/frame, JUMP > ATTACK > DOWN 360+ frames (`safe_margin` is Godot's 0.001). Same end state as H-2
  (invisible walls) and H-3 (stga0 rim); run2: stuck JUMP 600+ / DOWN 360+ / ATTACK 420+ in 18 runs, 11 of them on
  stga0; run4 (9aa456d): `wedged` 23 times in 17 runs (stga0 16, Tong-An 8, Dawnvolta, Ship, Mutsu, Mahdad). Current-code
  repro (6e6f4cb, repeats exactly): `fight stg20 kraken,valgas 3 400`: Kraken's air punch wedges him at y 3.85 from
  frame ~262. Request: an airborne or lying fighter whose position has not changed for N frames while the core moves it
  must be resolved (push out along the contact, or drop to the floor below: `Arena.floor_y_at`); then check a bigger
  `safe_margin` / convex shapes for placed parts. The original never leaves a fighter hanging.
- **H-13 A Fusion that keeps connecting never ends (Final Valgas melts).** LEAD (fighter.gd, BUG-25). Evidence
  (run4): Falcon in ATTACK 420+ frames with his Fusion f0k1_101 in 4 runs (stg40 / stg80, both looks). Repro:
  `fight stg40 finalvalgas,falcon 3 3001` on 9aa456d (run4/game_snapshot): Falcon starts fusion1 at frame ~2797;
  200 frames later the 2.0 s move's own timer (`state_t`) has advanced 0.6 s, the clip (2.48 s) ended at frame ~2950
  and holds, and Final Valgas has gone 136 > 67 hp in 3-6 point hits every ~5 frames. Cause: fusions hit again on
  every check (`not attack_hit or cur_attack.begins_with("fusion")`), each hit sets the attacker's seconds-based
  `hitstop`, and the old `tick` returns before `state_t += dt` while `hitstop > 0`: against a victim who is never
  knocked away (Final Valgas has no hit reactions), the hit-stops chain and the move's timer almost stops. Request:
  the Fusion port (BUG-25) with the original's per-motion length and hit list; until then don't freeze `state_t` of a
  multi-hit move in hit-stop.

Not bugs (harness, kept as notes so nobody chases them): a NaN position (run1 stg10 ryoma-wangtang, stg30 rouge-kraken:
the harness placed a fighter at a pole with no floor under it: fixed d019296); fighters wedged in scenery right after a
forced "edge" placement (a spot inside the original's area that the remaster's collision fills: that is
tests/area_check.gd's "blocked" list, fx-oom's; the harness now only places where the capsule fits, 9bb48c5). Every
repro command is valid for the commit the run used: a code change moves every later frame.

Clean classes in every run so far: no Godot / script error or warning line from the game itself, no hang, no crash,
no health outside 0-240, no gems outside 0-3, no timer outside 0-99, no fighter under the lowest floor, no fighter on
the ground out of the map, no AnimationTree Start / empty clip, no T-pose, no menu screen that could not be left, no
missing sound file.

## Runs (logs + findings.json under /tmp/ps-fx-hunt/RUN/)

| run | code | matrix | frames | notes |
|---|---|---|---|---|
| run1 | a7b7b29 (master) + harness, H-2 from ~01:22 | 135 runs, seed 1, both looks | 489,733 (136 min of play) | exploratory; 2 runs killed (harness NaN flood) |
| run2 | 32107ad (H-2), H-4 from 01:44 on | 135 runs, seed 2, both looks | 496,935 (138 min) | pause class only on stg00-30 remaster (before H-4) |
| run2_oldwalls | master's arena.gd (APFS clone) | stg00/10/40 remaster seed 2 (18 runs) | 64,819 | H-2 before/after slice |
| run4 | 9aa456d (all fixes, every detector, snapshot) | 135 runs, seed 3, both looks | 496,935 (138 min) | THE BASELINE to diff new code against: all 135 exit 0 |

Counts per finding family (occurrences; one occurrence = one detector firing, e.g. one 30-frame overlap stretch):

| family | run1 | run2 | run4 (baseline) | run2 slice (new walls) | same slice, master's walls |
|---|---|---|---|---|---|
| H-1 air attack moon jump (pose still / ATTACK 420+ with k1_010/012) | 59 | 55 | 23 | 9 | 7 |
| hanging in the air, JUMP 600+ (H-2 / H-3 / H-12) | 18 | 17 | 4 (+ wedged: 23 in 17 runs, 16 on stga0) | 1 (harness placement in scenery) | 0 |
| lying 360+ (DOWN) | 3 | 9 | 0 | 1 (same) | 3 (all wedged in invisible walls, H-2) |
| nothing moves 10 s (H-3) | 6 | 7 | 0 | 1 (same) | 0 |
| H-4 pause | 77 | 30 (0 after 8ea3013) | 0 | 15 | 24 |
| H-5 overlap with Final Valgas / others | 234 / 50 | 218 / 32 | 176 / 38 | 31 / 4 | 26 / 3 |
| H-6 fusions pose still | 43 | 34 | 32 (+ Ayame k0/26: 10 runs) | 7 | 7 |
| H-7 revert pose still | 7 | 5 | 4 | 0 | 1 |
| H-10 exit leak (runs) | 47 | 60 | 89 | 1 | 8 |
| godot error / warning lines from the game | 0 | 0 | 0 | 0 | 0 |
| hang / crash / oom / fell / hud_range / anim_empty / tpose / menu_stuck / sound_missing | 0 | 0 | 0 | 0 | 0 |

H-13 (fusion never ends): run4 4 runs (ATTACK 420+). (run1's 27 error / warning lines, 2 NaN and 2 "crash" all come from the harness's pole placement, see "Not bugs".)

Menus runs cover: title, options (quality / look / impact / cinematics / lighting toggles), select, arcade fights,
versus fights, pause, results (next fight / continue / rematch), replay theater, back to the title; no finding on a
menu screen; fight-side only (overlap, H-1, wedged, Falcon GETUP 150+ while Rouge holds her win pose, Rouge's run-stop
state 32 for 120+ frames: both in run4's menus runs, which were not repeatable yet: menus runs seed the global RNG
and PS_SEED since the commit after 7b186ce, so later ones are).

## Requests for the lead (game/scripts/fighter.gd), most player-visible first

1. H-3 / H-12 (and H-2's leftovers): resolve a fighter that hangs in the air without moving (push out / drop to
   `Arena.floor_y_at`); with it Final Valgas's arena stops freezing fights (needs stga0's measured area too).
2. H-1: powered air attacks in the core (chains.json PAX / PAY), no old air physics on core velocities; Falcon k1_010
   capture.
3. H-5 / H-11: capsule radius per fighter (0.38 m + fighter_radius.json delta_cm; Final Valgas measured).
4. H-13 / H-6 (BUG-25): Fusions on the core with their own lengths, no state_t freeze in hit-stop.
5. H-7 (revert length per fighter: Rouge 70 / Valgas 75 / Galuda 85 frames of clip vs 91), H-8 (sounds
   per action, logged).
