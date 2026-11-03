# fx-ko (lane pstrailer2): BUG-2 KO freeze, BUG-4 Power Change whip, cinematics default Off

Branch `fx-ko`. Godot only (no Flycast). the owner's bar: everything a player can feel matches the disc; only graphics differ.

## BUG-2: frozen fighters after every KO

**Cause.** The instant replay (cinema.gd) poses both fighters straight from the recording through their
AnimationPlayers and, before this fix, switched their AnimationTrees off (`PSModel.pose`). Switching a tree back on
(`unpose`) restarts its state machine in the empty `Start` node. Nothing played until the fighter's next `play()`:
the winner stood in the rest pose / froze mid-air (Ryoma) until he moved again, and the KO'd fighter stayed in `Start`
until he went from DOWN to KO, so both sat in `Start` for 20-48 frames before the win shot. The recorder stored those
frames as clip `"Start"`, which the replay theater cannot pose, so replays froze there too. Three more things came out
of the per-frame check:
- DOWN -> KO called `play_then("down", "lying")` again: a fighter already lying replayed his knock-down from its
  first frame (popped back up into the air, fell a second time), both with cinematics on and off.
- Cinematics Off: the KO slow motion (`fight.slowmo`, 1.2 s at 0.3x) slowed the fighters' logic but not their
  animation, so the winner's attack clip ran out early and its last frame stood frozen (~40-90 frames per KO).
- The replay seeked non-looping clips to their very end, which stops the AnimationPlayer (no clip for that frame);
  a form switch re-activated a tree that only took its clip on the next advance, so one recorded frame said `Start`.

**Fix** (`game/scripts/psmodel.gd`, `fighter.gd`, `fight.gd`).
- `pose()` leaves the live tree active (it is advanced by hand in `_process`, which posing skips, so it just waits);
  `unpose()` puts the live form + pin back and the tree resumes exactly where it was (clip, position, cross-fade).
- `play()` teleports (`start`) out of an empty `Start` / `End` node instead of travelling from it (that blended the
  rest pose in); its looping-clip early return now checks the tree really is on that clip.
- `set_form()` advances the new form's tree by 0 so the clip is there on the frame of the switch.
- `pose()` clamps non-looping clips 0.5 ms short of their end.
- KO from DOWN keeps the knock-down > lying chain (k2/153 > k2/144), like the original.
- The fighter's PSModel time scale follows its own clock in every case (cinematics or the plain KO slow motion).

**Proof.** `game/tests/ko_watch.gd` watches every frame from each round-ending KO to the next round (or the match end):
- *no clip*: a fighter's current clip is `""` / `Start` / `End` (the replay: its AnimationPlayer has none);
- *stuck*: the clip's own track data moved since the last frame but the drawn skeleton did not (2+ frames);
- *held*: a fighter in a round-end state (DOWN / KO / WIN) standing still 12+ frames (the trailer audit's "frozen")
  outside the end poses the game holds (lying k2/144; a win motion that doesn't loop, e.g. Gunrock k3/2);
- reported separately, *finishing a move*: the same 12+ frame stand-still for a fighter still in an attack / pole state
  (see "Left" below).
`tests/ko_check.gd` runs one seeded CPU-vs-CPU match in the real flow (HUD, real KO / round-end timings, cinematics
forced on or off, no replay saved); `tools/ko_proof.sh LOGDIR "SEEDS"` runs every stage (11) x seeds x cinematics
on/off. Same 66 matches (seeds 1-3), old code (`git show 329a36d`) vs this branch, same watcher:

| 66 matches (33 per mode), 44 with a KO, 67 KO windows, 24,118 frames | before (329a36d) | after (fx-ko) |
|---|---|---|
| cinematics on: frames x fighters with no clip | **2575** (22 of 33 matches fail) | **0** |
| cinematics on: stuck / held at round end | 0 / 0 | 0 / 0 |
| cinematics off: no clip / stuck / held at round end | 0 / 0 / 0 | 0 / 0 / 0 |
| finishing a move (reported, not BUG-2): cinematics off / on | 1379 / 246 | 72 / 1 |

KOs landed on 10 of the 11 stages (none on stg40 in these seeds: those CPU fights end on time). The cinematics-off
1379 were the KO slow motion's frozen attack clips; what is left (72 frames in one match: Galuda's pole flight
outlasting k1/151, see "Left"; 1 frame: Wang-Tang's punch1 state outlasting its clip) is move timing. The KO'd
fighter's re-played fall is a pop, not a stand-still, so the watcher does not count it; it is gone by construction
(KO from DOWN no longer calls play).

The watcher also runs in the test suite (`run_tests.gd` plain match, `cine_tests.gd` cinematics match, every
test_all run), with a check that the cinematics recording has a clip for every fighter in every frame.

## BUG-4: Power Change camera whip

**Cause.** The transform motion (k3/8, 130 frames) is not a stand-still: Falcon's robot crouches, leaps (feet 2.1 m,
head 3.1 m off the floor around 1.0-1.15 s) and lands; Valgas rises 2-3.6 m. The swoop (cinema.gd `_cam_power`) circled
at chest height, closed in to ~3.3 m (and the spring arm pulled it to 0.8-2.2 m near walls) and aimed at a fixed point
1.25 m up, so the body left the frame in most of the cutscene, not just the ~12-frame whip the trailer audit saw.

**Fix** (`cinema.gd` "Power Change framing", `assets/fidelity/bone_boxes.json`).
- `game/tests/bone_boxes.gd` writes, for all 21 forms on the disc, each bone's box of the vertices it carries (the
  disc's own meshes, rigid skin) into the tracked `game/assets/fidelity/bone_boxes.json`.
- At the Power Change the camera poses those boxes along the transform clip's own tracks every 1/30 s: the body's
  extent for the whole motion is known up front.
- Every frame it aims at the middle of what the live pose plus the next 0.4 s cover, and puts the eye on the swoop
  line as far back as needed for all of it to sit between the letterbox bars (3.5% margin). If a wall / floor is in
  the way it takes the nearest clear line round him (yaw / pitch candidates, the other fighter not in between,
  eased; a straight cut only when easing would cut him), and only where a wall stops the eye short does it widen the
  lens (up to 72 deg, back to 41.1 deg after). The blend-in from the fight camera keeps the same rule against the
  bars as they slide in.

**Proof.** `CamCheck.skin_points` / `points_box` (cam_check.gd) measure the screen box of the mesh actually drawn
(HD mesh in Remaster, disc mesh in Classic: per bone, the posed box of its vertices), stricter than the game's body
spheres (`screen_box`, also reported). `tests/pc_check.gd STAGE a,b`: a real-flow CPU-vs-CPU fight with cinematics,
P1 gets three stones once the fight runs, every cutscene frame measured. 10 fighters on their home stage:

Before = branch base 329a36d, seed 1, both looks (260 cutscene frames per fighter). After = this branch: seeds 1-3 x
both looks (60 runs, the first framing version) + seed 1 x both looks on the final closed-form version (20 runs), 1040
frames per fighter. "Past the edge" = the drawn mesh's box leaves the 16:9 frame; "under the bars" = it reaches into
a letterbox bar (or past the edge). Height = the body's mean share of the screen height (before: 0.95, i.e. too
close). Jump = the largest frame-to-frame move of the body's screen centre after the 0.18 s blend-in (before, the
camera sat inside some bodies, hence the huge values).

| fighter | before: past edge / under bars | before: jump | after: past edge / under bars | after: height | after: jump |
|---|---|---|---|---|---|
| Falcon | 134 / 210 | 0.23 | 0 / 0 | 0.42 | 0.075 |
| Ryoma | 227 / 242 | 0.21 | 0 / 0 | 0.49 | 0.117 |
| Wang-Tang | 155 / 219 | 0.41 | 0 / 0 | 0.44 | 0.048 |
| Jack | 122 / 190 | 6.37 | 0 / 0 | 0.45 | 0.058 |
| Gunrock | 101 / 221 | 7.83 | 0 / 0 | 0.42 | 0.076 |
| Galuda | 95 / 189 | 0.17 | 0 / 0 | 0.43 | 0.080 |
| Ayame | 93 / 145 | 0.13 | 0 / 0 | 0.42 | 0.073 |
| Rouge | 85 / 181 | 0.07 | 0 / 0 | 0.49 | 0.064 |
| Kraken | 98 / 224 | 0.55 | 0 / 0 | 0.47 | 0.052 |
| Valgas | 162 / 188 | 5.91 | 0 / 0 | 0.39 | 0.061 |
| **total** | **1272 / 2009 of 2600** | | **0 / 0 of 10400** | | |

The game's body spheres (CamCheck.screen_box) agree: 907 of 2600 frames out before, 0 of 10400 after. Cost: ~1 ms a
frame on the M4 for the framing (23 lines tried), ~5-12 ms once at the Power Change for the motion's envelope.

`cine_tests.gd` now checks the same every test_all run (the P2 fighter's Power Change: 0 frames out).

## Cinematics default Off

`Game.cinematics = false` (game.gd); the title menu keeps CINEMATICS ON/OFF and shows `OFF (ORIGINAL)` by default;
the attract demo follows the setting (it forced cinematics on before). There are no saved settings to migrate.
Tests and tools that need cinematics force them (`cine_force`: cine_tests, match_movie, record_match, ko_check,
pc_check; main.gd `--highlight` renders set it). `attract_tests.gd` checks the default, the label, and the demo both
ways.

## Also

- `theater_tests.gd` round-trips its recording through `user://test_tmp/cine_<checkout>_<look>.psr` instead of the
  shared `user://replays/_test_cine.psr` (two looks at once, or another worktree, loaded a half-written file).
- `Fight.no_replay` keeps proof runs out of the player's replay list (seven early proof matches of mine had landed
  there; moved out to the lane scratch folder).

## Left (for the lead)

- *Finishing a move* holds (not round-end): an attack state can outlast its clip (`Fighter._start_attack` clamps the
  timing scale to >= 0.7 of `Rules.ATTACKS[..].t2`, so a shorter motion holds its last frame), and a pole flight can
  outlast k1/151 (the remaster's parabola from a high pole runs past the logged 22-36 frames). Gameplay timing, not
  touched here.
- Is there a KO slow motion in the original at all? With cinematics Off the remaster still slows the world to 0.3x for
  1.2 s after the final hit (`fight.gd _on_ko`). Now the animation slows with it; whether it should exist needs a
  Flycast log of a round-ending KO (per-frame motion frame counter +0x719E of both fighters).
- The remaster always plays `win` (k3/2); the original picks k3/2 or k3/3 (rule unknown).
- The attract demo still rolls the other Pass-5 extras (30% a 4-fighter Battle Royale, 3 in 5 a remix lighting); the
  original's demo is a 1v1 in the stage's own light. Not changed here (only cinematics were in scope).
