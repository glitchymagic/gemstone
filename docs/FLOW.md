# Round + game flow: the original, frame by frame, and the remaster (lane pstrailer2, helper fx-flow, 2026-10-27)

Bar (the owner 10-26): only the graphics may differ. This file is the measured timeline of everything between and around the
fighting itself: round intros, Ready, the clock, KO / TIME OVER, poses, between fights, continue, game over, attract.

## How it was measured
- `tools/flowlog.py` (isolated Flycast via tools/fcinst.py, instances f1/f2): one capseg per frame of the round phase byte
  0x0C7F302C, MV_OK 0x0C7F3050, round clock 0x0C7F304D, the arcade block 0x0C7F2E40.., both players' feet x/y/z, motion
  kind/id/frame, state, health, CPU flag, gems, plus three raw global blocks (0x0C7F2E40/2F00/3000) for screen bytes;
  `tools/flow_shots.lua` (hot-loaded with the driver's `lua` command) saves a screenshot every 30 frames on the same count.
- Runs (logs + shots: /tmp/ps-fx-flow/, segment summaries committed in docs/flow/*.seg):
  - `o_round`: arcade Ryoma vs Falcon on Londo (P1 = the game's own AI via +0x71ED = 1, P2 at 20 health each round, P1 at
    200 in round 1) = a 2-round KO match (round 2 by a throw), the between-fights screens, then fight 2 (Ayame's stage)
    with nobody moving: round 1 clock poked to 4, round 2 the full 99 s = two TIME draws, then the continue countdown left
    alone, THE END, the attract start.
  - `o_screens`: power-on > title > ARCADE > select (Falcon) > map / stage / VS / loading > fight vs Wang-Tang with P1 idle
    at 10 health = 2 KO losses > continue left alone > THE END > title > 3 attract demo cycles.
  - `o_cont`: same start, 2 losses, START on the continue countdown (+306 frames), select, A, the rematch; then a TIME
    OVER won on health (P1 207 vs 200) and one lost on health.
  - `o_ladder`: Ryoma, fight index poked to 6 (Kraken > Valgas > Final Valgas), P1 = AI, every opponent round at 20.
- Remaster: `game/tests/flow_run.gd -- ko|time OUT.jsonl` (same scenarios, `Fight.flow_row` in the same schema),
  `tools/flow_diff.py ORIG[:a-b] REM` = phase sequence + lengths + MV_OK + per phase each fighter's (state, motion) runs.

## The original's round (phase byte 0x0C7F302C)
| phase | what | frames (logged) |
|---|---|---|
| 1 intro (round 1 only) | 67-frame lead-in (fighters idle k0/0 on the start points), then **P1's slot 120 f**, then **P2's slot 123 f**: each slot starts that fighter's intro motion (state 22, **k3/0 or k3/1**, both seen, looks random) which runs its own length (motion frames + 1: Ryoma k3/0 106, Falcon k3/0 120 / k3/1 119, Wang-Tang k3/0 100, Ayame k3/0 120) then idle k0/0 to the slot's end | 310 (o_screens 2651-2960, o_cont 2605-2914); 309 once (o_round fight 2: lead-in 66) |
| 2 Ready | frame 0 MV_OK 0 (no input), frames 1-150 MV_OK 1 = directions + jump only (the AI runs and jumps here, logged), frame 151 MV_OK 2; rounds 2+: the fighters stay in their poses on frame 0 and are back on the start points, idle, health 240, clock 99 on frame 1 | 152, every round of every log |
| 3 fight | clock 99 for 60 frames, -1 every 60 frames (0x0C7F304E counts 60 > 0), **0 at fight frame 5940, held 60 frames**, the TIME event at 5999: MV_OK 0 on frame 6001, phase 4 on 6002 (o_round 6148 > 12149/12150). KO: the hit on frame H (health <= 0), H+1 the launch motion, H+2 MV_OK 0, phase 4 on H+3 | - |
| 4 KO | the whole world: one tick on the phase's first frame, **frozen 90 frames**, then **15 ticks one every 4 frames** (1/4 speed, 60 frames), then full speed until the KO'd fighter is lying (state 15, k2/144 or k2/145) **and** the winner idle (state 0); phase 5 two frames later. Length therefore follows the launch / throw motions: 218, 194 (throw), 218 (o_screens), 210 | 151 + the flight |
| 4 TIME | nobody moves on their own; the clock stays 0 | 183 (o_round x2, o_cont x2) |
| 5 poses | frames 0-1 as they were; frame 2 (once 3): KO winner state 21 k3/2 or k3/3 (no rule found in 6 samples: random) placed on the stage's **win spot**, the KO'd loser state 8 lying k2/144 on the stage's **lose spot** (off camera); TIME with a winner: winner k3/2 on the win spot, loser state 8 standing k0/0 on the lose spot; TIME draw: P1 k3/5, P2 k3/6 where they stand | **245** between rounds (draws too); the match's last: **307** when P1 (the player) won (o_round, o_ladder), **275** when the CPU won (o_screens) |
| 7 continue | (after a lost match: phase 5, then 7) | 1001 + 1 frame of phase 8 |
- Win spots (feet cm): Londo stg00 win (350, 0, 0) lose (-50, y, -400); Wang-Tang's stg20 (-50, 50, 50) / (-450, 97,
  -350); Gunrock's stg40 (0, 50, 0) / (-340, 0, -340); Kraken's ship stg80 (0, 220, 170) / (-400, 100, -230); Valgas
  stg90 (0, 0, 0) / (-329.6, 100, -407.7); Final Valgas stga0 (307, 0, -307) / (-93, 0, -707) (he stays standing, state 0
  k0/0); Ayame's stg60 (0, 120, 250) / (-400, 0, -150) (attract demo pose); Ryoma's stg10 (-150, 0, -320) / (-550, 120,
  -630); Jack's stg30 (0, 0, -100) / (-400, 30, -500); Galuda's stg50 (307, 0, -307) / (-52, 0, -604); Rouge's stg70 (0, 0,
  -500) / (-400, 122, -762) (o_spots*: `flowlog.py spots`). All 11 stages now have their spots (the loser's y is the
  height he had, the game only moves his x / z).
- Bosses (o_ladder): Valgas beaten (match end, P1 won): phase 5 = **1132** frames: win pose to frame 276, then P1 goes
  off camera (-340, 100, -400) and Valgas to (0, 0, 0), state 42, his change k3/13 60 > k3/14 240 > k3/15 240 > k3/16 316;
  then **167** frames of phase 0 and straight into Final Valgas's fight (no map / stage / VS screens). Final Valgas's
  phase 1 = **165**: no lead-in, no P1 intro, his own state-22 slot (motion k0/0) from frame 2 for 163 frames.
- Start points: every round of every log starts on game/assets/fidelity/spawns.json's points (stg00, stg20, stg40,
  stg60, stg80 checked in these logs, rounds 2+ included) - BUG-13 data is right; the remaster now also starts them
  standing (no 5 cm drop).
- Two drawn rounds end the match (o_round fight 2: draw, draw > continue), modelled as a round point for both.
- HUD (shots): phases 1-2 show only `TIME 0'00"00` (top left) and `PRESS START BUTTON` (the free side); health bars,
  gems, faces and the clock scroll only in phase 3; phases 4-5 show TIME and `PLEASE WAIT` on both sides. TIME = the
  arcade run's elapsed fight time M'SS"hh, counting phase-3 frames up to the KO hit / TIME event, carried across fights
  (0'01"71 after a 103-frame round, 0'40"18 in fight 2).

## Between fights and around them (phase byte 0 unless noted; shots every 30 frames, so screen edges are +-30 f)
- Power-on: the Lua driver is live ~145 frames in; story text / attract intro; START skips to the title.
- Title > START > menu > A (ARCADE) > select screen (0x0C7F2E4A = 1, a 20-count timer, 0x0C7F2E52 its frame counter)
  appears 262 frames after the A. Pick (A) > select outro ~100 > airship map ~130 > stage name panel ~110 > "STAGE N"
  ~120 > map ~70 > VS screen ~180 > loading map ("The World of Power Stone", 0x0C7F306E = 1) **180** > phase 1. Pick to
  phase 1 = **892** frames (o_screens 1759 > 2651).
- Fight won: phase 5 (307) > **1036** frames (o_round: world map, airship, stage panel, "STAGE 2", VS, loading) > phase 1
  of the next fight; 1093 from Kraken's stage to Valgas's (o_ladder: the map flight looks distance-dependent).
- Fight lost (or two draws): phase 5 (275 / 245) > phase 7 `CONTINUE?` with the loser posing (state 21, k3/5 lead-in
  then its loop; k3/6 seen) and a count 0x0C7F306C: **10 on frame 2, one count every 91 frames, 0 on frame 911**, phase
  8 on frame 1002 > `THE END` + PLEASE WAIT **307** frames > everything resets (0x0C7F302C/304C/health = 0) > attract.
  START during the count (o_cont, +306) > PLAYER SELECT with its 20-count timer > A > loading map 186 > phase 1 against
  the **same opponent** on the same stage.
- Attract cycle (o_screens after game over): film-leader / story text / character intros / title, then a CPU-vs-CPU demo
  fight: straight into phase 3 (no intro, no Ready, MV_OK 2 from frame 0), the clock frozen at 99, health stays 240,
  **2181 frames** (2180 in the second demo), `PRESS START BUTTON` + www.capcom.com on screen; then phase 9 **380 frames**
  ("VS RANKING": P1 state 21 k3/2 on the stage's win spot, P2 state 8 k0/0 on the lose spot), then
  logos / character intros ("WANTED" cards) / title ~3694, loading 183, the next demo. Period 6437 frames (3 cycles).
  The first demo starts 3878 frames after the reset.
- Ending (o_ladder, Ryoma): Final Valgas's phase 5 (307) > 1 frame > loading map > "the final act of a play" story-book
  pages (the fighter's ending: art + dialogue, 2778 frames, phase byte 1) > white > staff credits over Falcon's biplane at
  sea (7183 frames, phase byte 2) > "The End" (543) > PLEASE WAIT > the VMU prompt "A new feature has been added. Would
  you like to save now?" (waits for input; still waiting 18,000 frames later).
- Not logged yet: VS mode (two humans) flow, the select screen's 20-count running out, a continue after it.

## The remaster (branch fx-flow)
- `fight.gd` "Round flow" section: phases INTRO / READY (new) / FIGHT / KO / ROUND_END run on frame counters with the
  constants above (FL_*), in every mode (test runs included; Training: no intro / Ready / clock). MV_OK masks the pad
  (human and CPU) to directions + jump during Ready. The clock is counted in fight frames (99 > 0 at 5940, TIME at 5999).
  KO: phase 4 three frames after the hit, the 90-frame freeze + 15 quarter-speed ticks are the world's own tick pattern
  (fighters + props skip their tick, models hold); the remaster's old 0.3x / 1.2 s slow motion is gone. Phase 5 places
  winner / loser on the logged win spots (game/assets/fidelity/flow.json) and the camera frames the winner alone
  (`Fight.cam_targets`, fight_cam.gd). Cinematics (Pass-5 extra, Off by default) keep their own KO camera / replay and
  skip the freeze pattern.
- `hud.gd`: bars / gems / faces / clock only in FIGHT; `PLEASE WAIT` in KO / poses; arcade TIME top-left (game.gd carries
  it fight to fight). `PRESS START BUTTON` (join-in) is not drawn: the remaster has no mid-arcade join.
- `arcade_flow.gd` + game.gd: arcade has no results screen any more; won > a 1036-frame STAGE N / VS screen (disc HUD
  portraits; the original's map / VS art is not ripped) > next fight; lost / draw > CONTINUE? 10..0 on the original's
  frames, START/Enter/A > character select > the same opponent, no input > THE END 307 frames > title. VS mode keeps the
  results screen (VS flow not measured).
- Attract (1v1 demos): no intro / Ready, clock frozen at 99, 2181 fight frames, then the 380-frame pose (P1 k3/2 on the
  win spot, P2 state 8 k0/0) and back to the title. The demo's no-damage rule and its Battle Royale / remix extras are
  the remaster's own (Pass 5); the title / story / character-intro screens around it are not ripped.
- Bosses: the Valgas change (k3/13-16 on the frames above) runs in the remaster's phase 5 when P1 beats Valgas in
  arcade, then a 167-frame cut (arcade_flow "boss") into Final Valgas's fight, which has his 2 + 163-frame intro. The
  ending (story pages, credits, save prompt) is not in the remaster: its art / text are not ripped; arcade clear still
  goes to the results screen.
- fighter.gd: one marked block `## --- fx-flow round-flow hooks ---` (flow_pose(kind, mot, state): plays the original's
  motion by kind/id through the clipmap names / _gplay and sets gst via _gset).

## Proof (tools/flow_diff.py; reports in docs/flow/)
- TIME OVER scenario (o_round 4805-12578 vs flow_run time): phases 2, 3, 4, 5 of both rounds **exact** (152 / 302 / 183 /
  245, then 152 / 6002 / 183 / 245, MV_OK runs identical); motion runs identical in 12 / 14 phase-x-fighter cells; the
  2 left are phase 1's lead-in (67 vs this log's 66; 2 other logs say 67).
- KO-loss scenario (o_screens 2651-4497 vs flow_run lose: Falcon idle at 10 health vs Wang-Tang's CPU on his stage):
  phase 1 **exact for both fighters** (310: lead-in 67, Falcon k3/0 120, Wang-Tang k3/0 100, idle to the slot ends),
  phase 2 = 152 x2, phase 5 = 245 then 275 (the CPU won the match), the winner's k3/2 on the win spot exact; 6 / 14
  motion cells identical, the rest = the CPU's own Ready run (BUG-24) and the knock-down (st27 k2/96 > 152 > 153 > st15
  k2/144 in the original, st15 k2/153 > st8 in the remaster: BUG-17/18 + the state-15 request below). docs/flow/diff_lose.md.
- KO scenario (o_round 0-3768 vs flow_run ko): phase 2 = 152 with the same MV_OK pattern, phase 5 = 245 then 307 (match
  won by P1) exact, win poses k3/2 > k3/3 on the win spot, KO'd fighter lying k2/144 on the lose spot; the phase-4
  freeze / quarter-speed tick pattern is frame-identical (tick, 90 still, 15 ticks every 4th frame, full speed from
  frame 151). Phase 4's length differs (166 vs 218) only because the remaster's knock-down is not the original's
  launch k2/96 > 152 > 153 (BUG-17/18, fighter core); CPU behaviour in Ready / fight differs (BUG-24).

- Tests: `game/tests/arcade_flow_test.gd` (the real Game autoload: fight won > STAGE/VS 1036 > fight > CONTINUE? 1002
  + THE END 307 > title; intro 310, Ready 152 x2, poses 245 / 307; arcade TIME carried): 8/8. `cine_only.gd` (the
  cinematics checks alone): 33/33. Old test expectations changed (the remaster's own inventions): cine_tests "KO: slow
  motion" now accepts the KO registered 3 frames before phase 4 (the original's lag); tools/test_all.sh per-run timeout
  400 > 600 s (the old test-mode shortcuts of 0.3 / 0.6 / 0.3 s per phase are gone: ~550 more frames per round).
- Fidelity tapes are unaffected: move_basic on this branch vs master's remaster run = same state / motion on all 1499
  frames (positions within 1 cm except 4 frames); tapes still start on the first fight frame.

## Requests for fighter.gd (lead)
- set_state's game-state table maps S.KO to 8. The original keeps the KO'd fighter in state 15 (lying, k2/144 / k2/145)
  through phase 4 and switches to 8 only with the phase-5 pose (flow_pose already sets 8 there): map S.KO -> 15
  (o_round / o_screens / o_ladder, every KO; flow_diff's phase-4/5 loser cells would then match on the state).
- The KO launch: the original's final hit plays k2/96 > 97/98 > 152 > 153 > 144 (st27, then st15) on the launch arc;
  the remaster goes st15 k2/153 at once. That decides phase 4's length (218 vs 166 frames) - BUG-17/18.

## Open
- Win spots for stg10, stg30, stg50-stga0 (log a KO per stage: `flowlog.py round INST P1 P2`).
- The intro pick k3/0 vs k3/1 and the win pose k3/2 vs k3/3: random in the remaster; find the game's rule (rand call?).
- Final Valgas's intro (no state 22), his story screens, the ending + credits, VS mode, the select timer, the attract
  demo content (character intro / story art isn't ripped) - not done.
- fighter.gd (lead): the KO'd fighter's game state is 8 from its knock-down on (set_state S.KO -> 8); the original keeps
  15 (lying) through phase 4 and switches to 8 with the phase-5 pose (flow_pose already sets 8 there).
