# Bugs and differences from the original (fidelity pass, lane pstrailer2, from 2026-10-26)

the owner 10-26: "This game needs to work exactly like the original with no issues just updated graphics". Every entry is a
difference a player can feel or a breakage, found by MEASURING (same-input tape diffs against the disc in Flycast,
docs/FIDELITY.md) or by the remaster's own audits. Nothing is fixed until its tape diff / audit re-run passes.
Evidence paths: `dumps/fidelity/o_TAPE.jsonl` (original), `r_TAPE.jsonl` (remaster), tapes in `game/tests/tapes/`,
reports `dumps/fidelity/reports/`. Status: OPEN / FIXED (commit, retest).

Fix order (biggest first): BUG-1 (out of map), then the fighter core (BUG-6..9, 15..22: movement, jumps, attacks,
reactions, throws) because every other comparison depends on it, then round flow (10..13, 23), health (14), Power Change
(25), items (26), poles/walls (27), the CPU (24), BUG-2..5 in parallel (separate worktrees).

## Known from scope 1 (Part A)
- **BUG-1 Out of the map** (the owner saw it). Fighters stand on fog/void past the stage floor. Cause: arena.gd puts a 40x40 m
  invisible safety floor under every stage and clamps to one bounds rectangle; random points (gems, Battle Royale
  starts) come from that rectangle. The remaster also walls off area the original allows (Londo: the original's
  fighter walks to x -740 z 928 at y -50; the remaster stops at z 670). Evidence: trailer v1 contact sheet, o_move_basic.
  Fix lane: worktree fx-oom. OPEN.
  STATUS (fx-proof, 10-27): areas measured on all 11 stages incl. Final Valgas's arena (stga0, resumed Flycast probe);
  the original's raised floors joined (they were cut off: Ayame 82 -> 157 m2, Galuda 76 -> 109, ...); a fighter on a
  top the original has no floor at goes off it sideways, inside a block's footprint up onto it or out; out-of-map
  check counts grounded fighters with no floor of the original within 35 cm; Arena.core_ground for the fidelity core
  (tests/ground_check.gd: 1187/1200 settles, 10/15 runs as the original). Proof (seed 1, 11 stages x 2 looks + 3 Battle Royale): live out-of-map frames 0 on 10 stages, 1 on the ship (its crate top is 35 cm over the original's), 2 in Londo's Battle Royale; re-scored with one rule the master runs had up to 1887 frames on a non-floor (Londo, mostly fighters on each other's heads) and the boss 3.94 m under his floor. OPEN: seed 1 on Jack's stage Falcon stays frozen in DOWN at 2.3 m for all of round 3 (90 s; no physics tick, so no clamp: a per-fighter freeze left on after the round-2 KO, fighter.gd / cinema.gd; docs/fx-oom.md "Proof").
  STATUS (fx-oom2, 10-27, docs/fx-oom2.md): the area data was missing floors the disc uses and had floors it doesn't.
  (1) the probe's rasters ended where the probe stopped; area_logs.py dropped every logged centre past them (Rouge's
  1.2 / 1.85 m walkways to z 7.5 m, the ship's decks, Galuda's west / north floors): rasters grown to the logs, +47 / +31 /
  +27 m2 of the disc's own ground on stg70 / 80 / 50. (2) fake floors from air attacks' hit-stop and PC hovers (lead's
  moves_ryoma find): standing evidence = grounded rows only, one-cell levels dropped (55-189 levels per stage gone;
  moves_ryoma f792-820 = the disc). (3) log levels under the probe's own floor (block faces) dropped. (4) floor patches
  wherever the remaster has no collision under a floor of the original (every level, 9 points a cell: 0 holes on every
  stage). (5) clamp_fighter: a body inside a block is lifted / moved out; under the stage back onto the floor (BUG-60).
  (6) airborne feet over a raised top move onto it (fx-cpu4's Londo 240 trap). (7) Battle Royale starts, random floor
  points and set-down throwables on the original's floor and the remaster's.
- **BUG-2 KO freeze**: 20-48 frames with both fighters in AnimationTree "Start" (frozen pose) between the KO cinematic
  and the win shot. Fix lane: fx-ko. FIXED (fx-ko 23d4e75: the live AnimationTree stays active through the replay; proof
  tests/ko_watch.gd in run_tests + cine_tests: no clip / stuck / held frame from any KO to the next round, every stage).
- **BUG-3 Fight camera hides fighters**: Kraken's Ship 63-90% of frames, Dawnvolta 50-65%, Valgas's lair 14-75%; the
  per-stage camera presets are not the original's except on Londo. Fix lane: fx-cam. OPEN.
  STATUS (fx-proof, 10-27): on the original's own fights 0.0-2.0% hidden on every stage, yaw 0.05 deg on 8 stages,
  distance 21-55 cm, eye height 4-24 cm (unchanged by this pass). In-game the hidden frames were lying fighters the wall
  test didn't look at (fixed: body spheres, faster swing) and BUG-1 cases (the boss under the floor, a fighter wedged
  on a 7.2 m top). Seeded matches (seed 1, both looks identical): hidden 0.0-3.6% on every stage (was 0.9-14.0%, the boss arena 100%), heads cut 0.0-0.1%, feet 0.2-1.3% (docs/fx-cam.md "fx-proof"). Battle Royale still 7-22% hidden (old box rule).
- **BUG-4 Power Change cinematic whip**: ~12 frames where tall forms leave the top of the frame. Fix lane: fx-ko. FIXED
  (fx-ko a79f8a5: the camera frames the whole transform from the disc mesh's bone boxes; 38-114 of 130 frames out ->
  0 out for 10 fighters x both looks; tests/pc_check.gd, cine_tests). Cinematics are off by default anyway (BUG-5).

## Found by this audit
- **BUG-5 Cinematics on by default** (game.gd `cinematics := true`): KO slow-motion cameras, instant replays and Power
  Change freezes are Pass-5 extras that change Arcade/VS timing. Must default to Off (an option). Fix lane: fx-ko. FIXED
  (9918919: Game.cinematics = false, title menu CINEMATICS OFF (ORIGINAL) / ON, attract demo follows it).
- **BUG-6 Running**: (w3: per fighter from 1ST_READ 0x0C339540: Wang-Tang / Ayame 10.5, Jack / Rouge 10, Kraken 9,
  Gunrock 8.5, the rest 9.5, checked on the disc's CPU fights; jumps likewise) original = state 31 (k0/25) at 9.50 cm/frame from its first frame (no acceleration), facing set
  instantly to the D-pad direction, 2-frame input latency; a walk-start state 2 (k0/3, 4.6 cm/frame) appears when a
  run begins from some states. Remaster = accelerates at 40 m/s^2 to 10.0 cm/frame (6 m/s), turns over ~5 frames,
  run animation restarts every ~4 frames (k0/25 frame counter stuck at 0-3, o/r_move_basic). OPEN.
  STATUS: FIXED in the core (cf4f025): mv_turn/mv_run/move_basic match the original to 0.01 cm on open floor, state timeline frame-exact; what still differs is stage collision (BUG-1: the original lands on Londo's fountain base at 55.0 cm, the remaster mesh at 62.8).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mv_run / mv_turn P2 100% on every field; P1 first divergence f28 z -224.9 vs -222.52 (the fountain base, BUG-1 family), state at f33 (mv_turn) / f193 (mv_run). Stays FIXED.
- **BUG-7 Stopping**: original = stop state 32 (k0/26): speed drops 9.5/6 cm per frame for 6 frames (33 cm slide),
  23 frames in all before idle, any direction restarts the run. Remaster = no stop state or motion. OPEN.
  STATUS: FIXED in the core (cf4f025): state 32, 9.5*(7-k)/6 per frame, 23 frames, restart at any frame (mv_run exact).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mv_run P2 100% (the stop rows exact). Stays FIXED.
- **BUG-8 Jumping**: original standing jump = 3-frame crouch (state 4, k0/5), then state 5 (k0/6) vy 35.5 cm/frame,
  gravity 2.0 cm/frame^2 (apex 330 cm, 38 frames up+down), landing state 6 (k0/9) 4 frames. Moving jump = state 5
  k0/10 at once (no crouch), keeps ~10.5 cm/frame. Remaster = vy 15.8 cm/frame, gravity 0.72 cm/frame^2 (apex ~166 cm:
  half the height), no crouch frames. OPEN.
  STATUS: FIXED in the core (cf4f025): crouch 3 f, vy 35.5 (first frame 3 cm short), gravity 2, air control 10.5 / moving jump 9.75 (9.25 against the stick), landing 4 f, run start k0/24 after landings (mv_jump exact until landing on geometry).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mv_jump P2 100%, P1 state + motion exact to f443, x to f108 (the fountain base). Stays FIXED.
- **BUG-9 Falcon's double jump**: original: A again in the air = k3/16 (4 frames) then k0/7, apex 427 cm
  (o_flow_start P2). Remaster: none. (Check every fighter's air jump.) OPEN.
  STATUS: FIXED for Falcon (core): A while rising 6+ frames into the jump = k3/16 (row 0 moves, 3 rows held), k0/7 at
  28 cm/frame (first row 20), gravity 2: flow_start P2 timeline identical (k3/16 at 14, k0/7 at 18). k3/16's clip is
  not capturable in Motion Check (docs/CLIPS.md). Other fighters: no air jump logged.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): flow_start P2 (Falcon) st 49%: the crouch ends one row early (disc state 4 at f5, remaster 5 at f5) and the remaster's first air row already rises (f6 y 32.5 vs 0.0), so the whole double jump runs 19.5 cm high (k3/16 at f14 / k0/7 at f18 = disc). OPEN (the crouch / first-air-row timing).
- **BUG-10 Round clock**: original 99 s (u8 0x0C7F304D; hits 0 at frame 5939 of the fight), HUD also shows the elapsed
  arcade TIME. Remaster 60 s (Rules.ROUND_TIME). OPEN.
  STATUS: FIXED (Rules.ROUND_TIME 99); fx-flow: the clock runs on fight frames (0 at 5940, TIME at 5999, flow_diff exact),
  HUD shows the arcade's elapsed TIME (M'SS"hh, phase-3 frames up to each KO / TIME, carried across fights).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): timeout tape 100% on every field for 7,200 frames: PASS. The clock does not stop in a Power Change / Fusion flash as the disc's does: BUG-65.
- **BUG-11 Round start**: original = P1's intro motion (k3/0, state 22, ~62 frames), then P2's (~120 frames), then
  phase 2 "Ready" (round phase byte 0x0C7F302C = 2) 152-154 frames where attacks are locked, then phase 3 = fight.
  Round 2+: no intros, fighters reset to the start points, phase 2 152 frames. Remaster: one 1.6 s INTRO for both,
  no attack lock window. FIXED (fx-flow, docs/FLOW.md): lead-in 67 + P1 slot 120 + P2 slot 123 (k3/0 or k3/1), Ready 152
  with MV_OK 0/1/2 (directions + jump only), rounds 2+ reset on Ready's frame 1; flow_diff: phase 2 exact every round.
- **BUG-12 Gems at round start**: original: each fighter starts the round holding 1 gem (HUD + player +0x7230 = 1 at
  the fight's first frame), one gem on the floor. Remaster: 0 held, 3 scattered. OPEN.
  STATUS: FIXED (1v1: GEMS_HELD_AT_START 1 each + 1 on the floor, every round).
- **BUG-13 Start points**: original (Ryoma vs Falcon, Londo) (-58, -340) / (-340, -58); remaster (-320, 260) /
  (340, 260). Check every stage. FIXED: every logged round (stg00/20/40/60/80, rounds 2+) starts on spawns.json = the
  area files' spawn (all 10 stages agree); fx-flow puts the feet on the floor from frame 0 (no 5 cm drop + landing).
- **BUG-14 Health recovers**: original: after damage the health byte climbs back by 1 every ~20-40 frames (o_atk_ground
  P2 230 > 234 while lying/idle). Remaster: no recovery. (Measure the rule: cap, rate, when it pauses.) OPEN.
  MEASURED (all logs): +1 every 40 frames, the first 40 frames after the hit, in every state, until about floor(dmg x 7/8)
  of that hit is back (14 > 12, 12 > 10, 8 > 7, 1 > 0); some hits recover nothing (38, 23, 14 in PC fights: check the record type)
  and a new hit restarts it. OPEN (implement in the core with the per-record rule).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): the disc's real rule is in docs/HEALTH.md (ceiling +0x71D6, counter +0x720F, 0x0C055566 + 0x0C08E16C..2DE; tools/health_check.py: the tick exact on every non-frozen fight frame of 96 logs, 487/487 recoverable hits, 162/163 combo restarts). Differences of the provisional port: records with b4 != 0 (pole / air actions 1, throws 2, PC 3/4, objects 5) recover nothing; the ceiling loses int(d x 0.19999999f) of the FLOAT damage (a whole 10 gives 9 back, 10.5 gives 8); a new combo's first hit forfeits what is still pending, hits inside a combo add up; no tick outside phase 3 or in a world freeze (BUG-65). Provisional vs disc pending after a hit: same 1,461 / more 408 / less 181 of 2,050. OPEN (exact change for the lead in HEALTH.md).
- **BUG-15 Move selection**: original picks a different move by distance: Ryoma's punch at 120 cm = k1/74 (a 69-frame
  launcher, 10 damage, sends the victim 300 cm up); far = the k1/16 string. Remaster: always punch1 (k1/16). OPEN.
  STATUS: IMPROVED (c9d1cc9): every fighter's near punch k1/74 under 120 cm (near_*.tape); still open: the original also seems to need the victim facing you (his body facing isn't in the player struct; find it), Falcon's near kick k1/59.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): near_ryoma st 99/94, near_gunrock 99/89 (P1 first state diff f80 / f72). IMPROVED stands.
- **BUG-16 Strings and timing**: original Ryoma punch 16 (12 f) > 17 (18-30 f) > 18 (18-30) > 19 (63-71), kick
  24 (12) > 25 (24-40) > 26 (23) > 27 (66), chained by presses during the motion; remaster stops after 2 (punch) or
  2 (kick) with its own windows/durations (o/r_atk_ground). OPEN.
  STATUS: IMPROVED (e5b2171): strings follow the original's motion ids per fighter (chains.json from the logs, chain presses once the last attack step ends, automatic follow-ups), per-frame travel from the original (motions.json), 8-frame hit-stop; move chains identical in 27/80 per-fighter attempts (was 5/80). Open: victim reactions (BUG-17) change what follows.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): chain_ryoma P1 st 98% / P2 100%: first diff f42 st 10 -> 0 (the string drops one press). OPEN.
- **BUG-17 Hit reactions**: original picks the reaction per hit: light k2/0 > 1 > 2 (+ state 24 recovery 8 frames),
  k2/3 > 4 > 5, heavier k2/15 > 16 > 17, launch k2/96 > 97 > 98 > 152 > 153 > lying k2/144 (5 f) > get-up k2/146 (23 f),
  air hit k2/112; remaster: k2/118 for every hit, k2/153 for every knockdown. OPEN.
  STATUS: IMPROVED (core step 3b): the original's state-27 machine decoded from 1ST_READ (docs/REACT.md, fx-react:
  137/148 logged class-0 chains exact in tools/react_sim.py) and ported: class remap, hit side, stun meter, class 0
  (k2/base > +1 sliding by the knockback table > +2, state 24 8 rows), launches 1/2 from the hip with the record's
  speed / elevation, tumble 3 with its bounce, wall splat 22, lying 5 + get-up 23 + 7, KO = launch then state 8.
  atk_ground's first launch: states and rows identical to the original through the splat, lying and get-up (back to
  idle on the same frame, 172). Victim state match atk_ground 31% -> 56-61%, dist_* 59-70%. Open: the reaction clips
  (k2/0-50, 96-99, 111, 117, 128-131 ... not captured: nearest captured reaction shown; capture running), lying
  length rule (5 vs 10), splat-or-bounce test, hits on a lying fighter (13), guard, classes 5-29.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): every Ryoma hit tape (atk_ground, dist_ryoma, near_ryoma, hits_down, moves_ryoma) first diverges at P2 f28: the disc's victim is in state 27 with the damage at f28, the remaster's at f29 (BUG-66). After that: atk_ground P2 st 61%, dist_galuda / gunrock / jack / ryoma P2 st 65 / 65 / 65 / 51%, hits_down 87 -> 76%. Reaction rows over all 79 tapes: state 27 disc 26,842 in 67 tapes, remaster 11,814 in 40 (items / PC tapes: hits the remaster does not deliver, BUG-46 / BUG-91). PARTIAL.
- **BUG-18 Launch / knockback physics**: original launches fly ~300 cm up and 400-860 cm far (k2/96 flight); remaster
  knock-downs reach 64 cm. OPEN.
  STATUS: IMPROVED with BUG-17 (launch_speed[rec[0xc]] at rec[0xd] x 11.25 deg, gravity -2, from the hip bone).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): atk_ground: k2/96 > 97 > 98 > 152 identical after the 1-frame lag (BUG-66); the launch starts 30 cm further out (f29 x 81.88 vs 51.41) and splats at 699.6 vs 700.0. PARTIAL.
- **BUG-19 Damage per hit**: to verify move by move once BUG-15..17 match (the remaster uses the game's attack records
  for sphere hits; first hits agree: 10). OPEN.
- **BUG-20 Throws**: original grab k1/84 (state 37, 11 f) > throw k4/7 (state 28, 82 f), victim k4/66 (state 29) then
  flung k2/117 > 152 > 153 > 144 > 146, 60 damage (Ryoma on Falcon); remaster: generic grab, 0.3 s, 48 damage,
  no kind-4 motions. OPEN.
  STATUS: IMPROVED (core step 3c): per-fighter grab-throws from the logs (game/assets/fidelity/throws.json,
  tools/throw_table.py): k1/84 11 rows, the thrower's own k4 chain + travel, the victim held at the logged spot (150 cm;
  Kraken 180, Rouge 100), the logged damage events (Ryoma / Galuda / Valgas 60, others 48: type-2, no gem bonus),
  release into the launch machine with the logged velocity. moves_ryoma: grab 978 / throw 989 / idle 1071 / release
  1021 identical to the original. Open: k4 clips (none captured), grab reach / whiff, Jack (no logged throw).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): throw rows over all tapes: thrower state 28 disc 3,824 rows (24 tapes) / remaster 2,719 (21), victim 29: 2,838 / 1,968. PARTIAL.
- **BUG-21 Air attacks**: original jump+X = k1/10 (31 f, stays airborne, back to state 5 then lands), jump+Y = k1/12
  (26 f); remaster's "air" attack ends on landing with its own timing. OPEN.
  STATUS: IMPROVED (e5b2171): k1/10 / k1/12 on the jump's own arc, back to the air state at the motion end, landing cancels.
- **BUG-22 Dash attacks**: original run+X = k1/16 (Ryoma: the same first punch, 31 f), run+Y = k1/24; remaster adds a
  1.3x-speed lunge ("dash"). OPEN.
  STATUS: FIXED (e5b2171): run + X / Y start the same first motions as standing (per chains.json RX/RY), no extra lunge.
- **BUG-23 KO / round end**: original KO = the final hit's launch in slow motion (k2/96 runs 129 frames instead of
  18; the attacker slows too), phase 4 then phase 5: winner k3/2 or k3/3 (state 21), loser lying k2/144 (state 8),
  244 frames, then phase 2 of the next round. TIME OVER: phase 4 62 frames, both k3/5 / k3/6 (draw) 244 frames.
  Remaster: KO 2.2 s + ROUND_END 2.0 s with its own camera/slow-mo, no draw poses. FIXED (fx-flow): measured again =
  phase 4 three frames after the hit: 1 tick, 90 frames frozen, 15 ticks every 4th frame, then full speed until the
  loser lies + the winner is idle (+2); TIME: phase 4 183. Phase 5 245 (match end 307 / 275), poses on frame 2 on the
  stage's win spots. The remaster runs the same frames (flow_diff); phase 4's length still follows the knock-down
  motions (BUG-17/18).
- **BUG-24 CPU**: the remaster's CPU (cpu.gd) is its own AI, not the original's decision code. Port it per difficulty
  level from 1ST_READ; check by statistics vs the original's CPU fights. PARTIAL (fx-cpu2 10-27): the original's AI
  (cpu_game.gd, docs/CPU.md) is now the CPU of every 1-on-1 fight (Arcade / VS / attract), with the arcade level and
  fight index per fight, the stage objects by the disc's kinds, the zone / ledge / chain-window checks. Left: Final
  Valgas's own AI (decoded in CPU.md section 9, not ported: cpu.gd still drives him), the in-fight rank ramp (measured,
  writer not found), MOVE50, recoverable reactions; the statistics (CPU.md section 12) still differ mostly through
  fighter-core gaps (steps the original climbs, items, throws, Power Change, reactions).
- **BUG-25 Power Change trigger**: original: 3 gems start the change (k3/8, state 23, 130 f) the next free frame
  whatever set them; remaster only checks when a gem is picked up. Drives: original k1/16 for 1 frame then the drive
  motion (Ryoma k1/96 58 f, kick k1/105 > 110 > 111 > 112), air drives k1/99 / k1/106 > 107 > 110 > 111 > 112,
  Fusion P k1/108 (290 f), revert k3/9 > k3/10 (90 f). Remaster: own timings. MOSTLY FIXED (fx-pc, docs/PC.md "Port"):
  transform / Drives / Fusions / revert now play the original's own logged rows (pc_moves.json); 21 PC tapes, P1 in
  PC: state 56 -> 91.6%, motion 56 -> 91%, PC flag 10 -> 94%, gauge 26 -> 77% exact / 96.7% within 1 (one emulator
  lag frame after a transform; situation-dependent move lengths, see PC.md). Left: Galuda / Gunrock Fusion A+X never logged,
  Drive / Fusion projectiles' reach (P2 680 cm off is hit in the original, not in the remaster).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): pc_* (10 tapes): P1 state 85.8-100% (mean 96.5%: Kraken 85.8, Ayame 90.6, Falcon 91.9, the rest >= 98.9), PC flag Kraken 47% / Falcon 51% / the rest 95-100%; P2 health 5-55% (the first Drive hit: projectiles BUG-91; the frozen opponent BUG-65). gems_pc P1 st 43 -> 99%. MOSTLY FIXED stands.
- **BUG-26 Items**: original pick-up = state 35 k2/219 (18 f) > carry k2/220; X or Y throws (k1/60, 36 f); a thrown
  metal chair hit for 42 and sent Falcon 860 cm (k2/112 > 152 > 153), a plant for 26. Remaster: state/motion ids and
  timings differ (carry throw k1/78, damage 32 for every object). OPEN.
  STATUS: IMPROVED (core step 3a): pick-up state 35 k2/219 18 f, carrying in the core's idle / run (k2/220 / k2/221),
  X/Y = state 10 throw 36 f, release on its 15th frame from 50 cm ahead / 117 cm up, straight at 20.0 cm/frame toward
  the opponent's hip, break on hit + home respawn 2 frames later, thrown-object damage never recovers (all logged:
  items_londo + the chair's object record 0x0C7D5A50, world position +0xA4). items_londo P1 state match 53% -> 99%.
  Still open: k1/60 clip (not captured: k1/78 shown), per-object damage (chair base 40, plant 25; remaster 32), the
  object's spin, a missed throw past 8 frames, carry run speed / jump, k1/60 vs k1/78 choice (CPU logs show both).
  STATUS (lead w3, e09374a): punch next to an object = the disc's object punch (k1/153 > 154 fling over the head, k1/78,
  kick k1/59; fling start / speed provisional until fx-obj's object log), objects back 991 frames after a break (900
  hidden + 90 blinking; was 2). Open: per-object damage / speed (property index +0x314), heavy lifts (k2/226, weight
  byte 6), the airborne carry throw k2/225, the dropped-object state 4.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): items_londo P1 st 99 / P2 48%, P2 hp 27 -> 68%; P2 first diff f118: the remaster's chair victim is lying (15) while the disc's still reacts (27). PARTIAL.
- **BUG-27 Poles / walls / ledges**: to measure (pole_wall tape missed the pole: start point was on a lower step).
  B in the air near nothing = Ryoma k1/53 > 54 > 56 (an air move the remaster doesn't have). OPEN.
  STATUS (lead w3, 684e27a + e09374a, from docs/OBJ.md by fx-obj): poles = the disc's machine (catch only in the air on
  ACTION, 10 cm from the axis, hang, punch/kick = k1/150 10 f (Ryoma / Wang-Tang 18) > the hop solver at the opponent >
  k1/151 > k1/152 or k0/9; the old orbit + 17.3 cm/f flight and the ground / no-button catches are gone); wall kick =
  k2/206 8 f frozen > k0/13 vy 25 + 2 cm/f out, once per airtime, objects count; ledges: a runner runs off and falls
  (the first frame -3 cm at velocity 0, o_ledge_londo frame-exact) and the areas now include the disc's own fights
  (tools/area_logs.py: the probes missed whole floors, e.g. Dawnvolta +34.7 m2, Galuda +26.5). Retest by tape: fx-cov.
- **BUG-28 Breakage**: remaster test suite (Remaster look) 149/149 base; full breakage hunt (every button in every state,
  every fighter x stage) still to run. Tape runs so far: 0 Godot error/warning lines.
  STATUS (fx-hunt, 10-27): harness in (`tools/hunt.sh` -> counts per finding class, `tools/hunt_report.py NEW OLD`
  to diff), findings H-1..H-12 in docs/HUNT.md; fixed in branch: H-2 phantom invisible walls (arena.gd), H-4 pause
  toggle (fight.gd / ui.gd), H-9 NaN recursion (arena.gd); the rest are fighter.gd / capture requests (HUNT.md).

## Found by the breakage hunt (docs/HUNT.md: game/tests/hunt.gd + tools/hunt.sh, H-numbers) and the CPU port
- **BUG-29 (H-1) Moon jump**: air attacks handed to the old attack code fell at 26 m/s^2 from the core's 35.5 cm/frame
  launch (apex 6-9 m, frozen in the air). FIXED (lead, core gravity on handed-over air attacks): hunt tape h1_air_punch
  apex 618 -> 330 cm, 82 -> 36 frames airborne (= the original). Open: Falcon has no k1/10 clip (shows k1/12).
- **BUG-30 (H-2) Invisible walls inside the original's area** wedged fighters (20 of Londo's 111 boxes). FIXED
  (fx-hunt 32107ad).
- **BUG-31 (H-3) Final Valgas's arena**: no measured playable area; fighters hang under its overhang, CPU fights stall.
  OPEN (fx-proof measuring stga0).
  IMPROVED (fx-fv 10-27): the measured area (fx-proof) had 123 floor-raster cells with no level around Final Valgas's
  start point (the probe fighter was pushed off by his body), so the fidelity core 'fell' in place there at y -10 cm
  for whole rounds (seeded Falcon vs Final Valgas: 10 / 10 rounds TIME, Final Valgas 232-240 health). Filled at 0 cm
  from the disc's own feet there (tools/fv_area_fill.py, 435 logged frames at y 0). Still open: normal fighters on stga0
  (Falcon vs Ryoma, VS mode only) stall on the BUG-41 core gap (punch with a block in reach = the object move).
- **BUG-32 (H-4) Pause**: Start / Escape did not close the pause menu. FIXED (fx-hunt 8ea3013).
- **BUG-33 (H-5) One collision size for every fighter**: bodies inside each other. FIXED (lead: capsule + the game's
  radius delta per fighter). Open: Final Valgas's radius (not measured).
  fx-fv 10-27: Final Valgas's +0x258 = 140.0 cm (read in his fight; fighter_radius.json delta 110). The disc keeps Falcon
  >= 150.0 cm from him (4,336 frames): fighter-to-fighter that is the push spheres (the capsule with the delta gives 1.86 m).
- **BUG-34 (H-6 / H-13) Power Fusions**: fixed 2.0 / 2.2 s timing (short clips freeze on the last pose); a Fusion that
  keeps hitting never ends (hit-stop freezes its timer). FIXED (fx-pc): each Fusion is its logged rows (Ryoma k1/108
  290 f incl. its own holds at fr 25 / 140, k1/101 > 102 > 103 > 104 ...), the whole gauge on its logged row, it ends
  by itself; hits add no extra hold (the logs never show one).
- **BUG-35 (H-7) Revert length**: Rouge's / Valgas's revert clips 70 / 75 frames vs a 91-frame state. FIXED (fx-pc): the
  revert is the logged k3/9 > k0/9 rows (Rouge 79, Valgas 83, Ryoma / Gunrock k3/9 > k3/10 90), started the frame after
  the gauge shows 0 outside states 10 / 11 / 23, form + gems back on the logged swap row.
- **BUG-36 (H-8) Most actions are silent**: only 2 effects + 6 announcer lines play; jumps, landings, swings, pick-ups,
  throws, gems, Power Change, poles, wall kicks have their own sounds on the disc. OPEN (log the AICA per action).
  IMPROVED (fx-snd, docs/SOUND.md): the disc's AICA logged per frame on 17 tapes + CPU vs CPU on 10 stages (5738 effect
  key-ons, 87.6% explained); game/scripts/sfx_map.gd plays the same samples on the same motion frames / hits (by attack
  record) / gems / KO call: 18.6% of a tape's disc key-ons start the same sample on the same frame (66.9% where the
  remaster plays the same motion; before <= 7.1%). Open: objects, timer events, Final Valgas's own bank.
- **BUG-37 (H-9) NaN position -> endless recursion** in Arena.sdf_at. FIXED (fx-hunt d14b1aa).
- **BUG-38 (H-10) Objects leaked at exit** (~1 run in 3). OPEN, low.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): FIXED (harness, a5dfbc5): not the game. The leaked objects are the sound effects' AudioStreamPlaybackWAV + their AudioStreamWAV (--verbose on atk_move: 15 instances, 7 se/*.wav). Headless --fixed-fps runs go faster than the audio thread, the only one that frees a stopped / finished playback (probe: 17 leaked with --fixed-fps, 0 without it, 0 with a 300 ms real-time wait before quit). game/tests/quiet_exit.gd stops every player and waits 250 ms before quit() in run_tests / tape_run / hunt / flow_run: atk_move 12-17 -> 0; before it 41 of the 79 tape runs had the 2 leak lines.
- **BUG-39 (H-11) Getting up / lying inside another fighter**. OPEN (re-check after BUG-33).
- **BUG-40 (H-12) Fighters wedged into scenery hang in the air for the rest of the fight**. FIXED (lead: the core nudges
  a body that moved 0 in the air for 6 frames out along the contact); the H-12 repro runs clean (0 findings, 713 f).
- **BUG-43 Final Valgas's fight**: one round on the disc (his KO -> phase 5 307 -> ending; Falcon's -> 275 ->
  CONTINUE?), best of 3 in the remaster. FIXED (fx-fv, fight.gd _end_round). His own AI 0x0C08D5CE is ported (cpu_fv.gd,
  docs/CPU.md "Final Valgas port"); his fighter code is not: he moves in state 2 (~4 cm/frame), reacts to some hits
  (state 27 k2/0 60 f > state 5 k0/6), throws (k4/0-5), and his pad words start chains the
  remaster's boss attacks don't have (0x200 97 > 98 > 104, 0x204 102, 0x004 x2 3 > 17, 0x404 x2 99 > 100 > 101 | 103).
  OPEN (fighter.gd boss branch, requests in docs/CPU.md).
  IMPROVED (lead w3 7764e2f, docs/ITEMS.md by fx-item): the third gem drops at fight frame 299 on the stage's free drop spot farthest from both fighters (3 spots per stage from 1ST_READ 0x0C33CA80). Retest gems_drop / stg_* tapes.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): floor gem on the stage tapes, gems match P1/P2 (437b5da -> 2f8da7d): stg_00 14/98 -> 100/98, stg_10 60/98 -> 100/98, stg_20 47/52 -> 100/100, stg_70 3/72 -> 100/98, stg_80 84/56 -> 84/98, stg_90 100/30 -> 100/44; worse stg_30 99/48 -> 79/100 (P1 f1846), stg_50 83/93 -> 53/83. The drop clock must also stop in a world freeze (BUG-65: the disc's gem came at 469 instead of 299 after a transform + a Fusion). IMPROVED.
- **BUG-41 CPU fights end on time**: the ported original AI (fx-cpu2, docs/CPU.md) is now the CPU of every 1v1 fight,
  but its statistics still fail 191 / 270 rows against the disc and seeded CPU matches ended in 1 KO in 30 rounds (the
  rest TIME). Causes listed in CPU.md (moves the core can't do yet, objects, the rank counter, Final Valgas's own AI).
  OPEN, high (player-visible: arcade CPUs).
  IMPROVED (fx-cpu2 34ebd2b): the AI reads the core's own state ids (gst) and the core's reaches (pick-up 1.45 m, as on
  the disc): damage 55 -> 77 / min (disc 184), 4 KO rounds in 12. Biggest gap left (core): punch with a throwable in
  reach is the object move k1/153 > 154 on the disc (a plain punch here: Wang-Tang 56% of a fight whiffing next to an
  object), pole swing k1/150 likewise; raised-floor edges must let a runner fall off (Falcon held 3,796 frames at Londo
  (250, 250, 700)). docs/CPU.md "BUG-41".
  w3 (lead): the core gaps CPU.md named are in (object punch, poles from the air, run-offs, the disc's own area
  evidence); per-fighter movement table (1ST_READ 0x0C339540: jump vy / gravity, run 8.5-10.5) for every fighter.
  Seeded Rouge vs Falcon on stg70 L19: 6 pole swings + 5 object punches in 2 min, round 1 at 51 / 146 hp. Re-measure
  with fx-cpu2's b41 pairs next wave.
  w6 (11-02, master 86e83b9, 11-stage sweep CPU 29 seed 7, 150 s each): damage 199 / min per fight (disc 184; 55 when
  filed), round 1 ended by KO on 8 of 11 stages (filed: 1 KO in 30 rounds). IMPROVED. Left: CPU path down from raised
  floors (Rouge's walkway tip, BUG-100), the per-row statistics in CPU.md not re-scored.
- **BUG-42 Free-for-all: a launched fighter over the remaster mesh's missing edge on Londo's east side** (17 of 16,252
  frames, base suite 163/164 in the Remaster look at 35e21d4): Wang-Tang in a reaction flight (state 27) at (7.64, -0.35,
  1.65), 5 cm inside the original's area, where the disc mesh has no floor for the out-of-map ray. OPEN (BUG-1 family:
  a floor patch at Londo's east edge, or the out-of-map check on the original's floor levels).
  Not reproduced after the launch splats on the original's walls + the captured reaction clips (base 164/164 in both
  looks at the wave-2 end commit): re-check in the full test_all / hunt runs before closing.

## Found by the coverage pass (fx-cov 10-27, docs/COVERAGE.md; code 437b5da)
Evidence paths are under `dumps/fidelity/`: originals `o_TAPE.jsonl` (+ `o_TAPE.obj.jsonl`, the object pool), remaster
`cov/r_TAPE.jsonl` (+ `cov/r_TAPE.objs.jsonl`), reports `cov/reports/TAPE.txt` / `.blocks.json`. f = tape frame.
- **BUG-43 Floor gem: when, where, how long.** Original: the third Power Stone appears at frame 299 of the fight on a
  fixed spot per stage (Londo (-190, 170, 720), Ryoma's (-317, 50, 97), Wang-Tang's (-400, 50, -50), table in
  COVERAGE.md 3), hovers 50 cm over its floor, hops ~175 cm now and then; untaken it goes after 1,110 frames and comes back
  300 frames later on another spot (gems_drop: on 299, gone 1409, back 1709 at (430, 50, 0)). Remaster: frame 0 at a
  random floor point, dropped from 6 m (r_gems_drop.objs.jsonl f1 (-468.7, 604.4, 253.0)); P1 runs into it at f321 on
  stg_00 (gems 1 > 2 at (-515, 0, 172)) where the original's P1 keeps 1 all tape (stg_00 gems P1 14%). OPEN.
- **BUG-44 Gem spill flight.** Original: a launch (k2/96) spills 1 gem (gems_drop f98 P1 2 > 1; stg_00 f1748; stg_10
  f1739): it starts 100-130 cm from the victim toward the attacker and 100 cm up, flies 20.0 cm/frame flat, vy 30
  cm/frame, gravity 1.2 cm/frame^2, bounces off walls, lands after ~52 frames ~7.6 m away (gems_drop slot 2: (-112.8, 100,
  -285.2) f98 > (-673, 50, 450) f150). Remaster (arena.spill_gems): from the victim +1.2 m, a random direction at 6.7
  cm/frame, vy 11.7, gravity 0.56, lands ~1.9 m away (r_gems_drop.objs f53 (-162.4, 131.1, -240.5) > f100 (-88, 45,
  -414.6)). Pick-up: the original takes a gem on touch with the feet 65 cm from it (stg_20 f1209); the remaster's test is
  0.95 m from the hip. OPEN.
  IMPROVED (lead w3 7764e2f): spills on the hit record's byte 16 (&4 one, &8 two), 0.20 m/f + vy 0.30 toward the attacker, walls reverse at half speed. Retest gems_drop.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): gems_drop gems P1/P2 43/23 -> 98/26 (P2 first gems diff f496). IMPROVED.
- **BUG-45 Body push.** Original: two fighters placed inside each other are pushed apart on that same frame to the sum of
  their radii (dist_galuda f11: x 20 / 60 > 1 / 79, 78 cm). Remaster: one frame late and too far (f12: -27.08 / 107.08,
  134 cm), and it pushes fighters the original leaves alone (near_gunrock f12: 100 cm apart > 110.6, the original keeps
  -40 / 60). Every dist_* / near_* / moves_* tape diverges here first (reports/dist_*.txt: P1 f11 x). OPEN.
  IMPROVED (lead w3): Fighter.body_push after every frame (radii sum, half each, Final Valgas immovable with push
  radius 120), no capsule pushes in the core's moves: x match dist_galuda 66/36 -> 76/59 %, near_gunrock 81/65 -> 87/64,
  dist_ryoma 37/25 -> 53/40, atk_ground 17/5 -> 20/31. Open: dist_ryoma's victim enters state 27 one frame late (f29 vs
  f28; positions identical at f28): the disc probably tests hits after the push (order of the player updates).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): the push itself is right now: dist_galuda's first divergence f11 -> f25 (x 26.5 vs 24.25), near_gunrock f12 -> f20; dist_* P1 x 76-77%. What is left is the hit timing (BUG-66). FIXED (the push).
  fx-mv (docs/fx-mv.md 2, a request: fighter.gd _motion is the lead's): dist_ryoma's one-frame-late state 27 is the hit test reading the clip frame (one behind gmo_f on the frame the attack set appears), not the push order; _motion() = [gmo, gmo_f] for core attacks moves the P2 state divergence f28 -> f136 on dist_ryoma / atk_ground / near_ryoma (shares within 0.6 %).
- **BUG-46 Items (weapons) missing.** Original, every stage: an item chest (type 2 kind 7) at frame 0 on a per-stage spot,
  its item (type 3 kind 6, id 0-10 by rand) ready at 377, a second chest at 599 (item at 977), more every ~300-600
  frames (COVERAGE.md 3). Use (items_weapon, Londo, item id 1): B = state 35 k0/0 5 rows > k2/237 24 rows, carry k2/238 /
  k2/239, X / Y = state 10 k2/245 31 rows, hit Falcon for 31 twice, both k2/96 launches (P2 hp 240 > 209 > 178). Remaster:
  no chests, no items (CPU.md FIND_KIND6/7 too); X / Y are the plain k1/16 / k1/24 (items_weapon P1 mot 60%, P2 hp 67%).
  Five items logged (items_id*.tape, COVERAGE.md "Items on the disc"): id 2 use k2/86 39 rows 26 dmg, id 1 k2/245 31 rows
  31 dmg, id 4 k2/197 45-53 rows 42 dmg, id 0 k2/243 140 rows 16 + 33 dmg (used up), id 7 k2/235 36 rows 32 dmg (used up);
  each with its own pick-up / carry / walk motions. OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): unchanged: items_weapon P1 mot 60%; pick-up state 35 over all tapes disc 816 rows in 24 tapes, remaster 72 in 2. OPEN (fx-item2).
  PORTED (fx-item2, docs/ITEMS.md 9): chests on the drop clock (the disc's spots, shake / open / pop / ready rows),
  items 0-10 picked up (state 35, the 5-row turn), carried (family idle / walk state 2 / family-195 run), used (state 10,
  shots / thrown / reach from Items.USE, the item records 0x0C33AB08 + the reaction machine), dropped on a hit or the
  transform. Same tapes, master 2f8da7d -> fx-item2: items_weapon P1 st 96 -> 100 %, mot 60 -> 100 % (Ryoma's in-fight
  clips, tools/fight_clips.py), P2 st 89 -> 100 %, P2 hp 67 -> 100 % (hits on rows 1106 / 1197 = disc); all 9 item
  tapes P2 hp 67 -> 100 %, P1 st 100 % on 8 of 9 (fxitem_id9 94). Chests 1-2 over 20 tapes: rows within 1 of the disc
  145 / 160, spots 36 / 40, items 40 / 40. Stage tapes unchanged vs master. Left: uses in the air, the use motions'
  travel, item 10's class-21 reaction (k2/176 > 178 > 99), the phase-4 drop rows (+1-2), the CPU's held-item logic,
  the other fighters' family clips (fight_clips.py per fighter).
- **BUG-47 Wall kick.** Original: state 38 k2/206 for 8 rows, then state 5 k0/13 in the air (stg_30 P1 f117-125, kicked
  off at y 320). Remaster: state 5 k2/206 for 34 rows, then k0/13 for 7 (stg_30 f117-151). Over the 11 stage tapes the
  original has 72-128 rows of state 38 per tape, the remaster 0 (and 338-544 rows of k2/206). OPEN.
  FIXED (lead w3 684e27a, docs/OBJ.md 2): state 38 k2/206 8 rows frozen > k0/13 vy 25 + 2 cm/f out, once per airtime. Retest stg_30 by tape.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): state 38 rows per stage tape disc 72-128, remaster 0-56 (stg_10 56, stg_80 40, stg_70 32, stg_50 16, stg_20 8, stg_40 8; none on stg_00 / 30 / 60 / 90 / a0); every remaster kick is the disc's 8 rows of k2/206 (the old 338-544 rows of k2/206 in state 5 are gone); stg_30 P2 f117: the disc kicks (38), the remaster does not (5). PARTIAL (the kick is right; the trigger fires less).
- **BUG-48 Vault over a low obstacle (state 17) missing.** Original: a runner meeting a ~100 cm obstacle does state 17
  k0/48 6 rows (0.5 cm/frame), k0/57 9 rows (up 100 cm in one frame, 12 cm/frame across), k0/58 8 rows (down 100), then
  the run restarts with k0/24 (stg_10 P1 f709-732 at (-54, 0, -100) > (-195, 0, -56)); seen on 8 stages (23-140 rows per
  tape). Remaster: never (0 rows); it runs straight on (stg_10 f700-740 k0/25). OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): state 17 over all tapes: disc 475 rows (8 tapes), remaster 0. OPEN.
  FIXED (fx-mv, docs/fx-mv.md 6): the hop = state 17 decoded (run, 5 touching frames, hoppable boxes from the stage descriptors in game/assets/fidelity/mv_stage.json): 11 stage tapes state-17 rows 0 -> 301 (234 on the disc's frames; stg_10 f709-731 row for row). Open: stg_70 / stg_90 routes off before the box, stga0 has no part map.
- **BUG-49 Walls 4.6 cm further out.** Original wall stops: x / z = +-660 / -650 (Ryoma's), 700 / -750 (Londo); remaster
  664.6 / -654.6 / 704.6 / -754.6, on every launch splat too (atk_ground f59 P2 x 700.0 vs 704.6; stg_10 f583 660.0 vs
  664.6). On master 0fef882 (areas widened from the disc's fights) the atk_ground splat is at 717.58: 17.6 cm out. OPEN.
  Also unchanged on 0fef882: BUG-45 (dist_galuda f12 -27.08 / 107.08), BUG-47 (stg_30 k2/206 in state 5 f117-150),
  BUG-55 (mv_jump f15 k0/5), BUG-56 (stg_40 Ayame 9.5 cm/frame).
  FIXED (lead w3 6f3be84): the sdf zero on the last inside cell (atk_ground splat 704.6 -> 699.6, disc 700.0); the 17.6 cm of 0fef882 came from lying / pose positions used as area evidence (now locomotion / attacks only).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): atk_ground splat 699.6 vs 700.0 (0.4 cm, inside the 1 cm tolerance). FIXED stands.
- **BUG-50 Pole catch where the original bumps.** Original: 0 catches in 10 moving jumps into Londo's lamp post
  (-428, 0, -256) (pole_londo, pole_londo2, pole_wall): it stops 60 cm from the pole and drops straight down (pole_londo
  f14-52, x -385.57). Its only catch in all 51 tapes: Ayame, mash_s33 P2 f126, 15 rows into a moving jump at y 370 >
  state 34 k2/211 22 rows > state 10 k1/150 10 > k1/151 28. Remaster: catches the lamp post in 6 of the 10 tries (pole_londo
  f15: state 34 k2/211 12 rows > k1/151 22) and in 6 stage tapes (35-44 rows each, an 62-82 cm snap onto the pole). The
  catch rule (height / facing / approach) is still unknown: needs more disc tries. On 0fef882 (no catch from the ground)
  still 5 of 5 pole_londo catches, and more mid-jump catches on stages (stg_50 0 > 38 rows, stg_60 34 > 151). OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): pole_londo P1 st 66 -> 96%, pole_londo2 89 -> 100%, pole_wall 48 -> 85%; state 34 over all tapes disc 88 rows (1 tape) / remaster 0 (was 863 in 12): the false catches are gone; the disc's one catch (mash_s33 Ayame f126) is not reproduced (the mash diverged long before). IMPROVED.
  FIXED (fx-mv, docs/fx-mv.md 4): the pole tapes press no ACTION within 150 cm (that is why the disc never catches there); catch = nearest pole < 150 cm in the air + the body window + feet clamp; the bump = the radius-20 cylinder holding the feet at 20 + collision radius, velocity kept. pole_londo P1 state 96 -> 100 %, x 37 -> 61 %. pole_wall 97 -> 53 %: the route is 40 cm off upstream (fall-from-run landing, fx-mv request 2) so its B press lands 117 cm from the post.
- **BUG-51 Teleport onto Ryoma's stage's 7.3-7.6 m wall tops.** Running along the east / south wall, the remaster lifts
  the fighter from the floor to the wall top in one frame: stg_10 f603 P1 (662, 0 > 729, 193), f1234 P2 (-290, 0 > 755,
  -655), then he stands up there; the original stops in the corner ((660, -32.7, 170), (-260, 0, -650)). OPEN, high
  (player-visible, out of the map).
  FIXED (lead w3, arena.core_ground): a fighter moving on his own lifts at most the 65 cm step-up, one pushed inside a block at most 1.6 m (the dojo terrace); stg_10: the 7.3-7.6 m one-frame lifts are gone (one 113 cm rise left at f1694), P2 motion 74 -> 81%.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): stg_10: 0 one-frame moves over 60 cm (the 7.3-7.6 m lifts and the 113 cm rise are gone). FIXED by tape.
- **BUG-52 Step-up snaps.** Remaster runners jump 64-91 cm sideways in one frame onto 30-65 cm steps: stg_30 f1229 P1 at
  (-247, 30, -212), stg_40 f364 / f872 P2 at (37, 50, -185) / (158, 50, -134), stg_70 f247 / f917 P1 at (-407, 65, -178) /
  (-434, 65, -674); the original climbs its steps at run speed (stg_70 f553: +65 cm up, 10 cm across) and has none of
  these snaps (tools/cov_jumps.py). OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): one-frame snaps left: stg_30 f1226 P1 62 cm / +30, stg_60 f239 P1 60 / +33, stg_70 f96 / f247 / f556 (4-73 cm sideways, +65), stg_20 f99 P2 50 / +100, stg_90 f607 P1 +100 straight up in the air (stg_40's are gone). OPEN.
- **BUG-53 B (action) with nothing in reach.** Original: an attack (mash_s11 f12 Ryoma B+DOWN+LEFT = k1/16; mash_s33 f12
  Rouge B+DOWN = k1/24). Remaster: B is ignored and the fighter runs (k0/25). OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mash_s11 f12 P1 still runs (k0/25; disc k1/16), mash_s33 f12 the same. OPEN.
  FIXED (fx-mv, docs/fx-mv.md 1): ACTION (B, or punch / kick pressed with the other held) with nothing in reach = the first command-table attack (0x0C09E4AC: punch, Rouge kick), in the air the dive k1/53 > k1/54 (150 cm of air, opponent grounded; per-fighter table) else the air punch. B-press outcomes on the 5 mash tapes 1/18 -> 9/13. Open: k1/147 at a pole (state 10 kind 10), k1/156 beside a wall (kind 11).
- **BUG-54 Attack + jump pressed together.** Original: the ground attack wins (mash_s44 f12 Gunrock A+Y+DOWN+LEFT =
  k1/24 for 43 rows). Remaster: the jump wins (state 4 k0/5 crouch, then the air kick k1/12). OPEN.
  FIXED (lead w3 3c75e76): attack + jump on one frame = the ground attack.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mash_s44 P1 k1/24 from f12 = disc; first diff now f20 (the remaster's Gunrock is hit). Stays FIXED.
- **BUG-55 Jumps one frame short.** mv_jump f15: original k0/6 from the first air row, 36 rows airborne, lands f51;
  remaster one more k0/5 row, 35 rows, lands f50 (the same in pole_londo2: 39 vs 38 rows). BUG-8's "exact" holds for
  the arc, not the row count. OPEN.
  FIXED (lead w3 3c75e76): motions switch on the frame (no cross-fade frame), the landing is the frame after the floor is reached and has no move: mv_jump first divergence f15 -> f443, x 46 -> 56%.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mv_jump P1 state exact to f443. Stays FIXED (flow_start's crouch row: BUG-9).
- **BUG-56 Run speed per fighter.** Original (all tapes, steady k0/25 rows): Ayame / Wang-Tang 10.5 cm/frame, Jack /
  Rouge 10.0, Falcon / Galuda / Ryoma / Valgas 9.5, Kraken 9.0, Gunrock 8.5. Remaster: 9.5 for everyone (stg_40 f13
  Ayame steps 10.5 vs 9.5; stg_60 f13 Kraken 9.0 vs 9.5). OPEN.
  FIXED (lead w3 684e27a): run speed per fighter from 1ST_READ 0x0C339540 (tools/move_table.py).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): moves_* P1 state 52-70% -> 68-89% (galuda 69 -> 89, gunrock 57 -> 88, jack 52 -> 83, rouge 59 -> 85, valgas 70 -> 82, wangtang 69 -> 83, ayame 70 -> 84). Stays FIXED.
- **BUG-57 Jump physics per fighter.** Original moving jump = run speed + 0.25 (Ayame 10.75 ... Gunrock 8.75), air
  gravity Gunrock 1.15, Jack 1.08, Kraken 1.2, Rouge 1.3, Valgas 2.1, the rest 2.0 cm/frame^2, first rise of a standing
  jump Ayame / Wang-Tang 37, Valgas 34, Rouge 27, Jack / Kraken 24, Gunrock 22.8, Falcon / Galuda / Ryoma 32.5 cm.
  Remaster: Ryoma's numbers for all (9.75, 2.0). Table: COVERAGE.md 6. OPEN.
  FIXED (lead w3 684e27a): jump vy / gravity / moving jump (run + 0.25) per fighter from the same table, checked on the disc CPU fights.
- **BUG-58 Curved turn run (state 7) missing.** Original: a new direction far from the current one = state 7 k0/41 for
  21 rows, an arc at ~10.5 cm/frame turning ~1.5-2.5 deg per frame, then walk-start k0/4 and the run (mash_s22 P1 f12-33,
  mash_s11 P1 f46). Remaster: turns at once and runs (k0/25). OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): state 7 over all tapes: disc 42 rows (2 tapes), remaster 0. OPEN. turn_ryoma / turn_jack tapes (8 directions from standing + 7 switches from a run) recorded on the disc to find the trigger (COVERAGE.md 9).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): NOT a direction switch: turn_ryoma / turn_jack / turn2_ryoma (disc, 8 directions from standing, 7 + 9 switches 3-20 frames into a run, 5 directions held from the @place frame: 0 rows of state 7). In a run the disc turns the facing at once and swings the velocity over ~6 frames inside state 31 (turn_ryoma f880-889: (8.93, -3.24) > (-3.45, 8.85)). The 2 disc cases: mash_s22 Jack right after a @place with DOWN held (f12), mash_s11 Ryoma a 90-degree switch 6 frames into a run that began out of state 24 (hit recovery, f38 > f46). Next: a run out of state 24 / out of a landing, by tape.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): turn3_ryoma (disc, Falcon vs Ryoma on stg10): P2 just @placed facing 49152, DOWN+LEFT 18 frames later = state 7 k0/21 13 rows > state 2 k0/28 1 > state 31 k0/24 (a turn-around start with k0/21, not k0/41); the 5 runs out of state 24 started in state 2 (k0/3 / k0/28, up to 26 rows) and never entered state 7. Both @place cases (mash_s22 f12, turn3 f30) come right after a placement whose angle (+0x7248) may not be the heading the run code compares with (+0x7248 also stays 0 until the first move): treat a state 7 within ~20 frames of an @place as a possible tape artifact; mash_s11 f46 (36 frames after its place, out of a hit) is the real case.
  FIXED (fx-mv, docs/fx-mv.md 5): state 7 is the DODGE (0x0C09E910: opponent attacking early, <= 300 cm, a fresh stick press 20-100 deg off him = the k0/41 arc round him, over 100 = the k0/20-23 step). mash_s22 P1 f13-33 21 rows k0/41 (one row late: the P1-before-P2 tick order, fx-mv request 3). State 28 / the jump-dodge not decoded.
- **BUG-59 Stop slide falls off a step** (regression candidate): flow_start f307, P1's stop (state 32) at (-563, 0, 273)
  drops into state 14 to y -25; the 02:11 remaster run and the original stay in state 32 for 23 rows (the routes already
  differ by 56 cm at f300, so place a tape there to confirm the edge rule). flow_start P1 state 85 > 80%.
  On master 0fef882 flow_start is back to 85% (no fall), but mv_run f286 now drops off the fountain base (y 52) in the
  stop slide (P1 state 91 > 82%; the disc runs 5 more rows and stops on the plaza). OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): mv_run P1 82% (f193: the stop slide drops off the fountain base). OPEN.
- **BUG-60 Fighters below the lowest floor** (hunt5): Falcon on Londo to y -3.42 (classic + remaster
  `fight stg00 falcon,ryoma 3`, f1245, falling state 14), Wang-Tang running at y -1.43 on Ryoma's stage (`stg10
  ryoma,wangtang`, f3462), and in every stga0 run the second fighter starts at y -1.20 under the floor (f11; the remaster
  has no stga0 start points: tape stg_a0 P1 (1275, 1277), P2 (950, 950)). run4: 0. On master 0fef882 (hunt6, remaster
  half) also on stg30 / 40 / 50 / 80 / 90 (e.g. `stg30 wangtang,jack 3` f1542, `stg40 finalvalgas,falcon 3` f1840). OPEN.
- **BUG-61 Launched fighters frozen in the air** (hunt5, re-scored): 51 occurrences of a fighter in the reaction machine
  (gst 27) or air (5) not moving for 60+ frames 0.4-2.7 m above the floor (e.g. `stg60 ayame,rouge` f3510 Rouge at y 2.7,
  `stg10 ryoma,wangtang` f1315 Ryoma at 1.47, `stg80 rouge,kraken` f2565 Rouge at 1.51). run4: 10 in all. On 0fef882
  stuck_state 4 > 14 in the same 66 runs: lying k2/144 360+ frames (stg50 rouge,kraken f3539, stg80 ryoma,wangtang f3316),
  airborne 600+ frames on stga0, ATTACK k1/012 420+ frames (stg50 falcon,ryoma f2883, stg80 jack,gunrock f1217). OPEN.
- **BUG-62 Round clock stands still 4 s in FIGHT** (hunt5 `menus - - 3`, f1303, both looks, arcade). To triage. OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): FIXED (harness, a5dfbc5): not a game bug. hunt.gd's menu fuzz ended rounds by writing Fight.timer = 1.0 every frame; since fx-flow the clock is fight_t (timer recomputed each frame), so the detector saw a 1.0 that never moved for 240 frames and no round ever reached TIME. The fuzz (and the fight-mode 'time' situation) now advance fight_t: repro `menus - - 3 1363` classic, 0 softlocks. A real clock difference was found on the way: BUG-65.
- **BUG-63 Ledge hang (state 36) missing.** Original: a moving jump that meets a wall top catches it and hangs: state 36
  k2/207, velocity 0, 19 rows, then an attack from the hang k1/162 > k1/163 (mash_s22 P2 Wang-Tang f482-501 at (-546.66,
  408.9, 572.7), the jump's z stopped at the wall 572.7 at f478). Remaster: no state 36 in any tape. OPEN.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): state 36 over all tapes: disc 39 rows (1 tape), remaster 0. OPEN. ledge_hang tape (8 moving jumps from the disc's spot on stg20) recorded (COVERAGE.md 9).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): the catch rule, by tape (ledge_hang, disc, Wang-Tang from the mash_s22 spot): B (action) pressed in the air against the wall at its top = state 36 (ledge_hang f284 B at y 407 > f286 state 36 k2/207 20 rows > k2/208); UP+Y in the hang = state 10 k1/71 37 rows (mash_s22's k1/162 > 163 came on another frame of the hang), then state 36 k2/208 29 rows dropping 308 cm to the floor, k0/6 3, land k0/9 4. B lower on the wall (y 277 / 335) = the air action k1/53 > k1/54 instead; no B = no catch (the fighter slides up the wall and falls: v2 of the tape). 4 catches in 8 tries, both directions. OPEN (fighter.gd: a catch test in the core's air-action path).
  PORTED (fx-mv, docs/fx-mv.md 7): state 36 (class-9 undersides from the disc's stage tables stop a rising head; ACTION = hang k2/207, punch / kick = k1/162 > k1/163 25 cm/f dive > k1/171) and state 41 (kind-4 objects: snap, 20 f, hop off k0/8). Missing clips k2/208 / k2/209 (hold / hand-over-hand) not captured.
- **BUG-64 Through the floor after a wall kick (master 0fef882 only).** After k0/13 the fighter falls through the floor
  to y -255..-307 cm, then is snapped back onto it 45-95 cm sideways in one frame: cov_m/r_stg_10.jsonl f502-506 (z -692.6,
  33 cm outside the disc's wall at -660), r_stg_70 f326-331 (503, -287 > 413, 130), r_stg_80 f482-486 (20, -255 > -23,
  5). Not in the 437b5da runs. OPEN, high.
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): stg_10 / 70 / 80: no fall below the floor after a wall kick, 0 airborne one-frame moves over 60 cm on those 3 tapes. FIXED by tape.
- Harness request (not a game bug): game/tests/hunt.gd's `wedged` test asks CharacterBody3D.is_on_floor(), which the
  fidelity core never sets, so every standing fighter "hangs in the air" (hunt5: 721 of 808 per-run occurrences have a
  ground gst). Use the core's ground state (gst / its ground flag) there; tools/hunt_rescore.py splits them meanwhile.

  LIKELY FIXED (lead w3): the wall kick is the disc's (684e27a) and air-only area evidence is run-off falls only (c8cd328); retest stg_10 / 70 / 80 by tape.

## Found by the wave-4 measuring pass (fx-cov2 10-27, master 2f8da7d; BUG-65..89 are this helper's numbers)
- **BUG-65 World freeze in a Power Change transform and a Fusion flash.** Disc (new tape pc_freeze, Ryoma vs Falcon,
  o_pc_freeze.jsonl + .obj.jsonl + the recovery counters of every log): while a fighter transforms (state 23 k3/8, 130
  rows; Wang-Tang 122) and for the 40 frames of a Fusion's flash (Ryoma k1/108 holds fr 25 from its row 26: f228-268;
  every Fusion in pc_moves.json has one 41-row hold first) the WORLD stands still: the other fighter (P2 held UP f30-89
  and X f90-93 during P1's transform: no run, no punch, motion frame 43 held f10-141), the round clock (99 held 189
  frames = 59 + 130), both recovery counters (37,150 transform + 7,190 flash frames not ticked in 96 logs) and the stage's
  timers (the floor gem came at f469 = 299 + 130 + 40; chest 1 went at 535 instead of 365). Reverts and Drives don't
  freeze. Remaster (cov2/r_pc_ryoma): P2 animates through both (fr 43 -> 15 -> 55 ...), the clock runs (99 -> 97 by f120,
  Fusion 79 -> 78), gems / chests on their own clocks. FIX in branch fx-cov2 (fight.gd `_frozen_by` / `freeze_window`: the
  other fighters skip their tick, the clock and arena.tick stand still); the PC fighter's own recovery tick must stop too
  (fighter.gd _recover_tick: request in docs/HEALTH.md).
- **BUG-66 The hit's state + damage one frame late.** atk_ground / dist_ryoma / near_ryoma / hits_down / moves_ryoma
  P2 f28: the disc's victim shows state 27 (still on its old motion, k0/0) and the damage (240 > 230) at f28 and starts
  the reaction motion (k2/96) at f29; the remaster sets state 27 + damage + k2/96 together at f29 (positions identical at
  f28; from k2/96 on the timelines agree: atk_ground 29 k2/96, 47 k2/97, 51 k2/98, 59 k2/152 ... = disc). dist_galuda /
  gunrock / jack the same at f26 / f25. It is the first divergence of every hit tape (BUG-45's old note). OPEN
  (fighter.gd: take the damage and set gst 27 on the hit frame, the reaction's first motion row on the next).
  RETEST fx-cov2 10-27 (master 2f8da7d, 79 tapes, docs/COVERAGE.md 9): where (atk_ground f10-30): Ryoma's k1/74 hit step = frames 0-16 with hit id 19 (p10_hit.json). Both sides show the attacker at motion frame 16 on row 28 (rows = the state before the frame's update); the disc's victim is already hit on row 28 and the attacker HOLDS fr 16 for the hit-stop (rows 28-30 fr 16); the remaster's attacker advances to fr 17 on row 29 and only then is the victim hit (hit-stop holds fr 17). So the disc tests the attack spheres in the same update in which the motion frame reaches the step's frame, the remaster one update later. Request (fighter.gd _core_attack_tick / _game_hit_update): test the hit right after the motion frame advances, before the next frame's advance; the hit-stop then holds the frame the hit came on.

- **BUG-67 'ERROR: Parameter "material" is null' (material_get_instance_shader_parameters, servers/rendering/dummy/
  storage/material_storage.cpp:264)** once per base-suite run in the classic look, in the attract mode + menus test
  (lead's base_classic.log line 26, test_all cls t_stg50 / t_wangtang, fx-ko tests_classic t_falcon, fx-cam ta_c
  t_valgas). Headless (dummy renderer) only so far: an instance-shader-parameter read on a GeometryInstance3D whose
  material RID the dummy storage does not know (no GDScript backtrace: it comes from engine code, e.g. a scene
  instantiation or property-list walk on the classic title / attract path). OPEN, low (find the node: run
  attract_tests alone in classic with --verbose; check the same path in a windowed run).
## Found by the lead, wave 4 (10-27, master 2f8da7d; numbers 90+ so helpers' new entries (65-89) don't collide)
- **BUG-90 Battle Royale: a KO'd fighter stood up** (test_all ff61291 "downed fighters stay down" on 5 runs: NOT-DOWN
  kraken / ayame / wangtang hp 0, state IDLE gst 0, rx_on true). Cause: a thrower hit mid-throw by a third fighter got
  his reaction (rx_on) but thr_on stayed set, and the tick runs the throw before the reaction, so the throw ran to its
  end and _throw_end's _gset(0, IDLE) stood him up under the running reaction. FIXED (lead-w4 967a69c: _throw_cancel in
  react_start / react_launch: the thrower lets go, the victim falls from where he was held; the disc never logs it: two
  fighters only). Retest: test_all BR runs.
- **BUG-91 Power Drives / Fusions land ~1/4 of the disc's damage.** Same-input moves_* tapes: the PC motion chains are
  identical, P2's damage is not (Ryoma 101 > 42, Falcon 104 > 28, Wang-Tang 100 > 28, Gunrock 132 > 0, Jack's fusion 71
  > 16): the disc's Drive / Fusion hits come from effect objects (type 1 owned by the attacker, object hit 0x0C08DEEC,
  PC.md) the remaster doesn't have. Disc object logs: dumps/fidelity/o_moves_*.obj.jsonl (covlog.py, 64 slots). OPEN
  (helper fx-shot: docs/SHOTS.md + pc_shots.gd).
- **BUG-92 Attack strings chained on old presses.** The disc takes a chain press only if it reaches the motion (2-frame
  input latency) at most 1 frame before the window opens (HIT.BIN last attack step + 1): over every tape, 184 links start
  2 frames after the press, 6 one frame late (pressed 1 frame early), none from an older press. The remaster kept a press
  3 frames, so Ryoma's far X string went 16 > 17 > 18 > 19 (moves_ryoma; the disc stops at 18: its press reached k1/17 at
  frame 12, window 14). FIXED (lead-w4: _pbuf <= 1). Open: 25 of 233 logged links start with no press edge in the 2-3
  frames before (e.g. mash_s11 f446 Ryoma 17 > 18 at frame 20 with X held at 17's frames 0-6): a latch the core lacks
  (+0x7204?); decode the chain code (0x0C339070[char]).
- **BUG-93 Falcon's air punch.** The disc plays k1/10 on jump + X (670 times in the CPU logs, o_moves_falcon f775-808,
  34 frames); its MDT slot value is 0 (offset 0 of the kind-1 block), so Motion Check replays idle and the rig has no
  f0k1_010: the core falls back to the air kick k1/12. OPEN (needs an in-fight capture: asked fx-item2 for a generic
  tools/fight_clips.py).
- **BUG-94 Fighters stand in mid-air on fake floors** (moves_ryoma f796: Ryoma's jump + air punch lands at y 291 on Ryoma's
  stage at (-60, -330) and stays; the disc falls to 0): the area data had a one-cell 2.87 m level (tests/floor_probe.gd:
  floor_levels(-0.60, -3.30) = [0, 2.87]) from air-attack rows counted as standing. FIXED by fx-oom2 954355d (standing
  evidence = ground states with the feet flat, one-cell levels dropped: 55-189 fake levels per stage); retest moves_ryoma.
- **BUG-95 Breakable scenery doesn't drop pieces.** Disc (moves_ryoma / moves_jack near X, Londo): the launched
  Falcon flies into the scenery at x ~730 (a type-4 kind-15 breakable at (735, 538, -500)); a piece (type 2 kind 15,
  owner = the attacker) falls from y 419 at 25-30 cm/f and hits him on frame 173 for 32 (an object hit: base 32,
  reaction k2/112 tumble), the same frame in both tapes. OBJ.md 6: Londo has 7 breakables (type 4 kind 15). The
  remaster has no breakables: near X attempts lose 29-32 damage (Ryoma 39 > 10, Wang-Tang 39 > 10). FIXED (fx-brk,
  docs/BRK.md: trigger = a fighter in the wall splat (class 22) touching the breakable's collision box, the piece hangs
  70 + rand%20, falls y += vy, vy -= 1 from -2, its 50 cm sphere hits a hittable fighter once with record 32 of
  0x0C33AB08 (class 3, base 32, type 7); tools/breakables.py check 11/11 breaks, 9/9 timers, 297/297 fall rows, 7/7
  hits; game/scripts/breakables.gd; moves_ryoma: break f59, Falcon hit for 32 on f173 as the disc).
- **BUG-96 Body push cut the attacker's travel.** Disc: a ground attack's own travel pushes the other body the whole way
  (Jack's k1/74 keeps 6.5 / 4.2 cm per frame with Falcon in contact and Falcon moves the same, moves_jack f22-27);
  velocity movers split the overlap half each (1,800 logged contact frames, share 0.5). The remaster split every
  overlap half each, so Jack's near punch fell 13.5 cm short and missed (0 damage vs 14 + 29). FIXED (lead-w4:
  Fighter._travel_push in body_push). Retest moves_* near X.
- **BUG-98 Air throws and hit-grabs missing.** Disc: an air punch started with the opponent also in the air turns into a
  throw on its second frame (state 28 kind 4, the victim state 29 in the thrower's k4 victim chain): 24 times in the logs
  for every fighter but Rouge (Ryoma k1/10 > k4/3 > k4/4 24 dmg, Gunrock k1/10 > k4/2 20, Falcon k1/10 > k4/2 > k4/3 48,
  Ayame six hits of 7 ...); Galuda's near punch k1/74 is a grab on contact (frame 15 > k4/4 122 rows, 25 dmg; dist_galuda
  f27); Power Change grabs Rouge k1/107 > k4/9..18, Kraken k1/108 > k4/3 > k4/4. tools/hitgrab_table.py ->
  game/assets/fidelity/hitgrabs.json (per fighter and attack: contact frame, thrower / victim chains, held offsets,
  damage, release). The air trigger is not a plain distance (throws at 25-209 cm, misses at 79 cm with the victim
  airborne): decode the air attack handler's grab test (0x0C093EE8 path). OPEN (port through Fighter._core_grab with
  the hitgrabs table). Partial decode (lead w4): the attack press handler 0x0C09E910(p, state, kind) (called before
  0x0C09EA80 from 0x0C0938DA / 0x0C093A24 / 0x0C095F82 / 0x0C0963C2) writes the pending action +0x7221 that 0x0C09EA80
  turns into a state (9 = state 28 + the victim's +0x0A = 3, 12 = state 5 kind 4, else state 7 kind = the byte); one
  branch: skip if 0x0C09C6B8(p) or +0x72AF == 0; |y - opp.y| <= 100 cm (0x0C09E9D4); opp +0x71BC == 0; opp state 10 / 11
  with opp +0x7206 <= 15 and opp +0x100 != 0; then jump pressed -> 12, else a direction pressed -> heading 0x0C09DDFE
  and on (not decoded past 0x0C09E9EA). The air throws' victims are mostly in state 5, so the air grab is another branch.
  fx-brk (docs/BRK.md "Air throws"): the air grab is NOT that branch: hit-grabs enter state 28 through 0x0C0A2712(p, k4)
  from the per-character move code, gated on the opponent being in the attacker's hit list (+0x11C, filled by the
  collision pass's sphere test 0x0C0207CA / 0x0C02343C) with +0x108 == 1, not Final Valgas, PC or sub-step 1;
  tools/airgrab_check.py: 21 logged air throws, all on k1/10 row 1 (hit step attack set 0 = no spheres there: what
  the +0x148 spheres hold on that row is the open part).
- **BUG-99 2v2 / Battle Royale: a fighter stands on another's head for a few frames** (merge 11-02, run_tests 2v2 n6873:
  Falcon at (-5.5, 1.35, 2.67), floor 0.0, gst 27 after a hit in k1/27, 3 frames, then off). The remaster-side states
  read Godot's is_on_floor (a capsule on a capsule) as ground. The disc has 2 fighters only and no floor on a head
  (OBJ.md). Out-of-map check: Arena._rests_on_something now asks stage geometry only (the feet were over the stage's
  floor, inside the area). OPEN, low (extras only): body_push across 3-4 fighters / the core's ground for gst 27.
- **BUG-97 Drawn body / hit spheres ahead of the fighter, fighters the wrong size.** Disc spheres per frame in the 10
  moves_* tapes (tools/reachlog.py: RAM +0x148 / +0x188 / +0x330): the fight draws every fighter at a joint scale
  (each sphere radius = file radius x it; Gunrock 1.2, Jack 1.135, Kraken 1.3, Wang-Tang 0.91 ...) and the remaster's
  clips have the raw bone offsets: limbs 5-30 % short, feet hovering up to 21 cm (Kraken) or 8 cm in the floor (Ayame),
  every sphere radius too small. The core also drew the clip's own travel on top of the table travel (air attacks 1.1-
  1.9 m ahead, k1/74 20-38 cm), one frame late and cross-faded. FIXED (fx-reach, docs/REACH.md): b00 pose scale per
  form (body_scale.json), radius x joint scale, core_frame = clip frame g - 1 + the table travel or the disc's hip
  (hip_pin.json), throws pinned by the path. Live attack-sphere error vs disc 18.4 / p90 57.1 cm -> 0.0 / 21.9; Gunrock
  far X 0 -> 32 (disc 31), Jack far X 9 -> 19 (19), Galuda far X 14 -> 28 (27). Open: per-frame single-limb scaling
  (Gunrock's kicks), PC forms' hip rule.

## Found by the trailer v2 pass (11-02, master 90d0c26; 35 seeded CPU-vs-CPU recordings, $LANE_TMP/tr/rec)
- **BUG-100 Runners stuck at an edge in a run pose.** The run clip (k0/25) plays while the position does not change for
  8-88 frames: mutsu2 (stg10 ryoma,ayame seed 2) rf 933-1021 Ryoma at the porch edge over the pond, airborne-looking;
  storm1 (stg10 ryoma,galuda seed 2, storm) rf 10102-10170 Galuda at the frozen pond's edge. Likely the drop-edge /
  sdf push-back holding a grounded runner (lead-w3c drop rule) or the CPU running into a face it can't pass. OPEN.
  PARTLY FIXED (86e83b9, w6): two causes measured with PS_STUCK_DEBUG (cpu_game.gd: stuck counter +0x5C, the disc's own
  escape fires at 60 frames, so ~61-frame runs are true to the disc): (1) core_ground held a runner dead at a raised
  floor's face (Jack on Ryoma's porch, 480+ f); the disc slides along walls at speed x cos(angle) (its run logs: 4,770
  frames at 45 deg, 6.7 of 9.5 cm/f) -> Arena._wall_slide; (2) the drop rule saw the floor being left in the feet's 25 cm
  cell inside a step's face band and called it a wall (Londo 60 > 30 cm step, 600 f), and clamp_fighter pushed a runner
  stepping off back up -> fixed in _drop_edge / clamp_fighter / fighter_out_of_map. Same 4 fights, stalls >= 180 f:
  Londo 10 -> 2, Mahdad 6 -> 3, Tong 0 -> 0, Galuda's stage 8 -> 12 (diverged fight; 11-stage sweep below). Tapes: 86
  tapes 49,881 -> 49,877 match points, identical first divergences.
- **BUG-101 Out-of-map frames left in long CPU-29 fights:** k_mahdad3 (stg70 rouge,wangtang seed 3, 300 s) 2 frames,
  k_mutsu3 (stg10 ryoma,jack seed 3) 5 frames (cam_check oom). OPEN.
  FIXED (40e2ad1): fighters on a hoppable box's top (the disc's state 17 and standing on a moved box) count as on a
  floor (Fighter.on_hop_box); re-recorded k_mahdad3 / k_mutsu3 0 / 0 frames.
- **BUG-102 Objects out of the map:** k_londo4 (stg00 ryoma,falcon seed 4, CPU 29) 1,926 frames, k_tong3 (stg20
  wangtang,galuda seed 3) 6,944, k_fv1 (stga0 falcon,finalvalgas seed 1) 792 (cam_check oomo: gems / props / items /
  breakable pieces; which one: run_tests OOM-OBJ print). OPEN.
  FIXED (ce4dfa0): PS_OOMO_DEBUG named them: Londo part 25 and Wang-Tang's part 11 set down in front of a raised block
  at their home floor height (inside / under the block) -> Prop.drop puts it on the nearest floor at / under the
  carrier's feet; Final Valgas's gems spilled from a victim at the arena's edge started outside the walls -> the spill
  starts inside. Re-recorded k_londo4 / k_tong3 / k_fv1: 0 / 0 / 0 frames (were 1,926 / 6,944 / 792).
- **BUG-103 test_all 90d0c26:** "KO > replay > win: 64 held frames" (ryoma vs wangtang: the winner Wang-Tang's k3/006
  win clip ends and holds its last frame, round 3) and Battle Royale "downed fighters stay down" again (ryoma,
  wangtang, gunrock, galuda, rouge runs). OPEN.
  FIXED (40e2ad1): "downed": PS_HP_TRACE showed a shot's KO (shot_hit) sets hp 0 and the reaction starts the NEXT frame
  (the disc runs the object pool after the players: shot_hit's note); the test now allows that one pending frame
  (_shot_this_frame) and checks 2v2 too. The 6 failing test_all configs re-run: 165/165 each. The KO-held frame did not
  recur in those runs (watch in the next test_all). "KO test could not start" (kraken / FV / stga0): the cine tests
  pass 33/33 alone and 3x in parallel (deterministic); the fail came with seeds of a different run order (kept a
  diagnostic: the phase / pf / replay state print).
- Note (not a bug): the world freeze during a Power Change transform / Fusion flash (BUG-65, the disc's rule) shows the
  other fighter standing still mid-run for up to 130 frames before the cinematic camera; true to the disc.
- **BUG-104 A launched fighter starts its flight ~28 cm too far back and 10 cm high.** Disc (REACT.md class 1/2 step 0):
  position = the victim's hip bone; on the first launch of 18 tapes (atk_ground, dist_*, moves_*, near_*, hits_down,
  rnd_probe*) the disc's start is a median 6 cm in FRONT of the feet at 99.4 cm; the remaster's 21.9 cm BEHIND at 109.1
  cm (moves_ryoma f29 P2: disc x 51.4 / z -319.4, remaster 81.9 / -329.1). The remaster reads its own skeleton's b00 at
  -11.9 cm / 109 cm (Falcon idle, PS_HP_TRACE bone dump: no bone of the remaster's pose sits at the disc's point) and
  moves one launch step on the hit frame (+10 cm). Every moves_* tape's P2 position diverges here first (frame 29) and
  P1's move choice after it (near vs far). Also: the idle loop's frame counter runs 3 frames out of phase after @place
  (disc fr 0, remaster 3). OPEN.
  w7 TRIED (not kept): a constant start at the disc's median (feet + 6 cm toward the hit, 99.4 cm up) instead of the
  skeleton's b00. moves_ryoma f29: y exact (first y diff -> f189), x / z 31 -> 13 cm off; the 96-tape ledger mixed
  (sum of match points: P2 hp +26, P1 x +20, P1 st +17, P2 mot +12, P2 st -5, P2 x -28; items_weapon P2 x 86 -> 60%: a
  launch at feet 70 cm mid-move, disc hip 169.8, b00 163.3, constant 155.4). The hip is pose-dependent: next = find
  which bone the disc's +0x300 + 0x160 matrix is (0x30-byte 3x4 matrices -> bone 7.33? 0x40 -> 5.5: check the matrix
  stride in 1ST_READ 0x0C0CCF32) and read that bone of the ripped skeleton (same motion data).
  (The 1-point health gap in 9 of 10 moves_* tapes was the recovery tick, not damage: a P2 hit by P1 got its +1 at hit
  + 39 frames, the disc at + 40 for both players (210 / 210 logged): the hit's frame no longer counts down. FIXED:
  216 / 216 gaps at 40 on the 96 tapes, health match +10 points, the rest of the tape ledger unchanged.)
- **BUG-105 1-2 frame out-of-map / hold frames left in test_all 27f0088** (w6): stg50 Falcon rising in a jump (vy +10)
  3-8 cm past the edge of the disc's measured AIR area at (3.18, 2.62, 2.79) for 2 frames before clamp_fighter's air
  push-back (f16617-8, reproducible: PS_OOM_ONLY=1 PS_OOM_DEBUG=1 PS_STAGE=stg50 PS_TEST_CHARS=falcon,ryoma; the air area
  has a ~20 cm hole there = a pole's footprint (PS_AIR=1 tests/sdf_grid.gd): the jump overlaps the pole 2 frames); stg00 2v2
  Ayame attacking (k1/16, v -6.1 m/s) at (-5.09, 2.4, 9.24) 1 frame: 11 cm past Londo's back edge over NO floor (lv [],
  brawl_only falcon,ryoma stg00 n1657, reproducible): something after core_ground / body_push (both clamp) moves her; stg10 FFA Wang-Tang running at (-4.6, 1.0, 1.7) 1 frame; stg10 KO
  window: KO'd Ryoma's k2/98 held 5 frames in phase 2 (may be the disc's own k2/98 hold, REACT.md step 1: check).
  The jump take-off case (stg30 f447) FIXED (the drop-edge rule in the check). OPEN.
  w7 (11-02): the Londo 2v2 case = Ayame stepping off the 2.4 m ledge (3 frames in the step's 30 cm face band, which the
  raster has no floor in) and starting an attack there: the check now also looks for the floor just left (30 cm behind
  the feet / facing; af5f4df), 18/18 brawl_only stg00. The KO-window hold = the disc's own k2/98 fall hold (REACT.md
  class 1 step 1: held at its last row until the floor), not a freeze: ko_watch.gd counts it as resting and starts a new
  still run on every clip change (af5f4df). Ryoma's stage FFA (Power Change Wang-Tang 35 cm over no floor at (-4.87,
  1.0, 1.97), 2 frames) = the POLE BUMP (_mv_pole_push): a pole at the area's edge pushed the body straight out into the
  void with no area check (traced frame by frame: moved inside his own tick after the core clamp). Now the push goes the
  nearest way round the pole to a spot inside the area, then clamps (fighter.gd _mv_pole_push).
  Ryoma's stage FFA hit reactions (gst 27) 1.1-1.2 m over the plaza at (-3.5, 2.1), 5-11 frames: a standing hit's
  knockback (class 0) moved the body off the 1.2 m floor's edge with no gravity. Now it falls while the motion plays
  (the disc's move: pos += v, clamp, then gravity); ledger identical, brawl stg10 clean. Still OPEN: stg50 FFA a
  Power Change Falcon launched into Galuda's west wall splats at (-5.2..-5.5, 7.5): inside the disc's own air area
  (logged flights) but past the remaster's mesh (no geometry under: on_floor's ray), 43 + 21 frames.
- **BUG-106 CONTINUE replays the same fight** (w7, tools/arcade_ladder.sh lad2): with PS_SEED set every fight re-seeded the
  C rand + the arena, so a continued fight played out frame-identical (jack: 22 continues vs Falcon, 13,023 frames each).
  The disc never seeds rand (0x0C0DF920), so a retry differs. PS_SEED now seeds a process's first fight only (fight.gd
  _fights_in_process). FIXED (0c6ad2e): lad2 on the fix: every continued fight differs (Valgas 11 tries: 8,243-22,177 frames). (Players never set PS_SEED: renders only.)

- **BUG-107 CPU runners stuck at Londo's back stairs** (w7, ladder STALLAT + PS_STUCK_DEBUG recordings): the AI goes for
  the disc's gem drop spots (350, 240+50, 790) / (-190, 120+50, 720) (1ST_READ 0x0C33CA80) up the stairs 0 > 30 > 60 > 90 >
  120 > 150 > 180 > 210 > 240 cm. Each face is a 40-50 cm floorless band in the area raster (a fighter can't be placed on a
  face), wider than core_ground's 28 cm step look-ahead: the runner never met the step and ran in place (the disc's own
  stuck rule fires, the AI retries the same goal). Part 1 FIXED (d3da235): the look-ahead goes 25 cm on across an empty
  band, steps only (4 Londo fights: CPUSTUCK 134 -> 83; ledger neutral). Part 2 OPEN: the upper treads (150-210 cm,
  25-50 cm deep) have sdf <= 10 cm and the faces are holes in the 2D area, so the clamp still pushes runners back there.
  Part 2 FIXED (777e806): tools/area_stairs.py writes sdf_stairs / sdf_air_stairs per stage (8 stages: the plain area +
  every outside cell between two floors 15-65 cm apart within 60 cm, as a delta on the stored sdf). Runners / walkers
  (gst 2 / 4 / 31 / 32) clamp against it, the out-of-map check reads it for anyone on his own feet; reactions, throws and
  lying bodies keep the plain area (filling the area itself left a thrown Wang-Tang lying 73 frames in a stg40 band).
  8 recorded CPU fights: CPUSTUCK Londo 134 -> 51, Galuda + Rouge 234 -> 133. OPEN: Galuda's / Rouge's stalls left are
  ragged edges (posts, railings) with the AI steering straight at a goal behind them (the AI's stage hooks: ai_zone,
  route), and Rouge's raised 125 cm walkway (no way down found). Also seen: stg40 a 10 cm same-floor raster hole at
  (2.64, 5.29) a runner crosses (1 frame), reactions (gst 27) 1-11 frames on stg10 (-3.5, 1.1, 2.1) / stg50.

## Found in wave 8 (11-02, master 307f3f4+)
- **BUG-108 Power Drive / Fusion shots invisible** (SHOTS.md "Look": the shots hit, nothing was drawn). FIXED 118f19b +
  8c17dbc: the disc's draw nodes logged per frame (shot +0x2DC / +0x2E0, node matrix + part pointer), tools/shot_look.py
  -> pc_shot_look.json, PCShots draws the disc's own EFn0.MDL / common-bank parts there. Retest: 222 table shots carry
  parts; disc frames vs remaster at the same tape rows (Ryoma bolt, Gunrock boulders, Kraken bomb, Ayame blades, Jack
  beams, Valgas bursts) match in place and shape; suites 165/165 (ryoma, rouge, gunrock, valgas, base, stg30 classic),
  0 error lines. OPEN part: per-frame colours the disc gives some parts (Valgas' Drive X sphere hidden for it), effects
  that are not type-1 shot objects (Fusion Y body effects, petals' glow, Jack's kind-5 Drive bursts).
- **BUG-109 cine test's forced Fusion over a running Drive** (test only): the old attack path left the CPU a second real
  Fusion 33 frames later, the Fusion camera restarted (rouge,kraken "fusion camera hands back"). FIXED 8c17dbc (the test
  waits for the Drive; the game's core takes no Fusion mid-move). Retest rouge,kraken 165/165.
- **BUG-110 KO watch false "held"** (test only): on a launch's landing frame the reaction asks for k2/99 while the tree
  (advanced later in the frame) still shows the held k2/98 row, with the hold's 12 still frames already counted. FIXED
  8c17dbc (the watch reads the clip on screen too). Retest stg30 both looks 165/165.
- **BUG-111 Jack's Power Drives do no damage** (disc / remaster on the shot_ tapes: Drive X 26 / 4, Drive Y 38 / 0, air X
  22 / 0, air Y 38 / 0, Fusion X 120 / 0; pc_jack 133 / 0). His Drives spawn type-5 / 6 pool objects (visuals: no
  spheres at +0x148, no hit id at +0x100) and the victim takes record 112 (X) / 118 (AX) / 114 (Y) every ~5 frames from
  row 15 (Drive X: 10 hits with P2 240 cm ahead, 7 at 446 cm, nearest burst object 59-206 cm from his hips at the hits:
  the hit volume is not the burst objects). w8: SHOTS.md's "last-hit pointer 0x0C330F08 = a pool object" is the RECORD
  address (victim +0xF8 = Jack's table + 112 x 20). The two 0x0C08DEEC calls in Jack's move code (0x0C0768FA,
  0x0C076B26) are grabs (ids 48, 50). Next: find who writes victim +0xF8 = 0x0C330F08 (a Flycast write watch on P2
  +0xF8 during shot_jack row 288), port that test. OPEN, high (a playable fighter's PC attacks).
  w8 later: they are BODY hits (P1's own hit id 112 / 118 / 121 every row of k1/96 / k1/102 / k1/107, his hit steps),
  and three rules were missing. (1) Every step of a motion clears the already-hit list, one frame late (k1/96 has steps
  every 3 frames from 13: the disc hits at 13, 17, 20 .. 41; k1/102 at 13, 15, 18 .. 27): GameHits.at arms each later
  step at its start + 1. Ledger (96 tapes) base vs this alone: only moves_jack (P1 mot 85 -> 94 %, P2 mot 64 -> 76),
  shot_jack and one mash tape move, net +47. (2) Spinning moves: the disc turns the model heading (pool +0x30) per row
  while the body stays put (Falcon's Drive Y / air Y 4.0 turns, Ayame's Y 2.0 / AY 1.75, Jack's Fusion X 12.4: +182 a
  row up to 6735 a row; his k1/107 bar of 4 spheres on joint 1 sweeps the victim): pc_shots.py spins ->
  pc_spin.json, Fighter._pc_spin turns facing (not pc_ref). (3) A step the code holds (0-255, the motion frame never
  moves: Jack's k1/107) is re-armed every 5 frames (code_hits' rule). shot_jack disc / remaster: Drive X 26 / 16 (was
  4), Drive Y 38 / 38, Fusion X 120 / 70 (was 0), Fusion Y 122 / 99. Left: the air Drives pick k1/102 / k1/103 on
  the shot tapes (heading poked toward P2) but k1/97 / k1/99 on pc_ / moves_ tapes (stale heading) at the same jump
  frame: the choice rule (the opponent in front?) is not decoded; pc_moves holds k1/97 / 99 only, so the remaster's
  air Drives never reach (AX 22 / 0, AY 38 / 0).

## Found in wave 9 (11-02, master 5547176; test_all 5547176 both looks 42/46, the same 4 fails in both)
- **BUG-112 Power Change camera boxed in a corner** (stg50 config, Ryoma's change at (-2.52, 0, 4.46) in a Mutsu porch
  corner: every line round him had a wall within ~1.8 m, so the eye stopped 1 m short of it at 0.8 m out, lens at the
  72 deg cap, and the last 6 of 130 frames (the end pose) cut the body at the bars). Cinema._pc_try: when no line fits
  with the 1 m wall margin, the eye may go to PC_TIGHT = 0.35 m from the wall. FIXED (w9). Retest stg50 config 165/165.
- **BUG-113 CPU pinned behind the slanted wall on Final Valgas's stage** (stga0 config: Ryoma spawns into the pocket at
  x 7.6-9.6, z 7.2-12 behind the slanted wall (6.6, 9.6)-(7.4, 7.4) + block of the disc's measured area; the ported AI
  steers straight at every goal (all south-west of it) and ran in place for ~2 minutes of each round: 2 TIME rounds, the
  match did not finish in 6 game-minutes). The disc's stuck event 0x40 only picks a new random point within 5 m of the
  centre (all behind the same wall). REMASTER-ONLY unstick (not on the disc; named in RESULT): a runner the disc's own
  stuck count (+0x5C) has held 90 frames (the disc's own 0x40 fires at 61 and resets it, so its escape runs first) gets a waypoint from Arena.ai_detour (breadth-first over the measured area at
  25 cm, the fighter's margin + 15 cm, step-up / drops by floor_y_at; the farthest path cell in a straight line), re-
  planned every 10 frames until the line is clear, it is reached, or 240 frames. Normal play never reaches it. FIXED (w9).
- **BUG-113 (w9 later)**: the first unstick never fired where it was needed most: a runner pinned at an area edge
  (stg70 walkway at 1.25 m, Ayame 22 s at (4.81, 1.25, 0.15) with v 0) has its own cell and all neighbours inside the
  margin, so the search could not take a step. The first metre now accepts the start's own depth (detour probe
  $LANE_TMP/p2/w9/detour_probe.gd: walkway edge -> (-2, -4) reached in 5.5 ms of planning).
- **BUG-114 Knocked down for good** (ladders lad5 on 49bf790: Jack 9 x 5 s reports lying at (3.73, 0, 6.09), Falcon at
  (6.4, 0, 0.25) and 35 cm over stg50's floor at (-0.19, 3.61), Ryoma, Galuda: 20-60 s of no damage each). A knockdown
  that reaches the legacy S.DOWN branch (hit with no reaction record, launches outside the machine) waited for
  is_on_floor(), which never turns true on the core's ground where the disc's floor has no remaster collision. Now: on
  the physical floor or on the measured floor (floor_y_at within 3 cm, not rising), and 3 s down gets up regardless (the
  disc's lying state is timed). FIXED (w9); base both looks 165/165.
- **BUG-115 sdf_at recursed for ever off the raster** (stg70 config with the detour: 757 stack overflows): the clamped
  point went back through metres and rounding put it at v = -1e-15 -> row -1 -> recurse. The clamped cell is read
  directly now (same value). FIXED (w9); stg70 / stg10 / rouge configs 165/165, 0 script errors.
- **BUG-93 (w9)**: fx-item2's in-fight clip f0k1_010 (rip/mocap/clips_p0, 34 frames from moves_falcon f776) was
  merged as clip data but master's Falcon GLBs were never re-exported, so the core still fell back to the air kick.
  Rebuilt (gitignored assets; a fresh checkout redoes it): `tools/add_clips.py build 0 f0 none` (p00 / p01 + clip maps:
  only `air_punch -> f0k1_010` added), `tools/hd_mesh.py` p00 / p01 (build_hd.sh's command), Godot --import. 96-tape
  ledger 55,974 -> 55,993 (moves_falcon P1 mot 68 -> 69 %, the two Falcon mash tapes net +11). FIXED (w9).
- **BUG-107 (w9 find)**: kraken config (kraken vs valgas, Londo) on the w9 pin trigger: Kraken runs up the back stairs
  (0.3 > 0.6 > 0.9 m, f1100-1124) and at the stairs' top corner core_ground lets him into (0.29-0.38, 0.9, 6.44-6.61)
  where the raster has NO floor level (sdf -0.13..-0.20): the runner's sdf_stairs band reaches past the side of the
  steps, and _support finds the 0.9 floor next to it. 26 frames out (test FAIL). Trace: PS_TRACE_F=1100-1146
  PS_OOM_ONLY=1 PS_TEST_CHARS=kraken,valgas (run_tests TRACE lines). Fix idea: a runner may enter a floorless cell
  only inside a band whose far side has a floor along the run (the band look-ahead's own test), never sideways.
  FIXED (w9, core_ground: a floorless cell the plain area holds outside needs a floor within 70 cm ahead along the
  run): kraken config 165/165 with 0 out-of-map frames, stg00 config + base 165/165, 96-tape ledger unchanged (55,993).
- **BUG-113 (w9, pin trigger)**: the disc's 0x40 fires at 61 and resets the stuck count, its escape script ends, 61
  again ..: the count never reached 90 (Galuda pinned at (1.43, 0.55, 2.59) on stg50 for minutes in lad6 although the
  detour probe finds a way from there). A runner that has not left a 50 cm circle in 150 running frames counts as
  pinned too. Ladders (8 runs each, CPU 31 stand-in P1): STALL issues lad4 (777e806) 64, lad5 (49bf790) 63, lad6
  (c4cd77c) 57, lad7 (this) 52; KO rounds 99 / 98 / 112 / 127 (TIME 257 / 268 / 248 / 250); cleared 1 / 1 / 2 / 1.
  Left: Kraken's ship 16 of lad7's stall issues (the 2.2 m upper deck's area is the disc fighters' logged cells only:
  re-probe it, NEXT WAVE), Londo 8, Ryoma's stage 7.
- **BUG-60 (w9 find + fix)**: stg60 config on 865b5a6 (both looks): Ryoma's air kick k1/12 carried him into a 2.2 m
  block's 25 cm cell on Ayame's stage at (-4.13, 0.81); core_ground's "a wall, stay put" kept x / z at a spot inside the
  block too (its only floor 2.2 m), so nothing was under him and he sank through y 0 (17 frames out, y -0.36 and
  falling). Now that branch steps out sideways to the nearest spot with a floor at the feet (_out_of_solid, as
  clamp_fighter's _solid_guard): he lands at (-4.08, 0, 0.81). stg60 config 165/165, base both looks 165/165.
- **BUG-116 Every test run ended with Godot leak lines** (w10): "5 ObjectDB instances were leaked at exit" + "ERROR: 1
  resources still in use at exit" in all 46 test_all logs. --verbose: two Node3D (an Arena and a plain Node3D), the
  Arena's RandomNumberGenerator and arena.gd, made by tests/remix_tests.gd's "Original = no remix" check and never put
  in the tree. Freed by hand (772bac1). FIXED: unit run + base both looks + wangtang / kraken configs end with 0
  error / warning lines.
- **BUG-117 A thrown object flew past Londo's back edge** (test_all 865b5a6, wangtang config, both looks, 1 frame):
  part 26 flung from (2.24, 5.01) broke only 30 cm past the area line (prop.gd inside(-0.3)), but between z 6.3 and 6.6
  there is no stage floor at all (area sdf -0.1 .. -0.2, no ray hit, no level). A flying object past the area's edge
  over no stage floor now breaks there (the wall). FIXED 3cb6e0c: wangtang config 165/165.
- **BUG-118 A body push shoved a fighter into a raised block** (test_all 865b5a6, stg80 2v2, both looks, 4 frames):
  Ayame reeling (gst 28) on the ship's main deck was pushed by another fighter 50 cm into the 1 m platform's cells at
  y 0 ((-3.58, 0, 1.58): the original's floors there 1.0 / 7.82 m), clamp_fighter's ray-lift then flickered her
  y 0 <-> 1.01. Body pushes only respected the 2D edge; now a push that would put the feet against a block's side
  (a floor of the original here, every one over the step-up) leaves that fighter's x / z where they were
  (Arena.wall_block). FIXED 3cb6e0c: the case is gone on the stg80 config; base 165/165 both looks.
- **BUG-119 Fighters over a column with no floor in either game** (w10, configs re-run after BUG-117/118): stg80 FFA
  Wang-Tang launched across the ship stopped against the 1 m platform's side at (5.22, 2.12) (no level, no mesh: an air
  area cell from the disc fighters' logged flights) and fell to y -2.7 (11 frames out); stg70 FFA Falcon ran into an
  edge sliver at (-1.3, 1.0, 3.88) (sdf +0.01, no level, no mesh within 30 cm) and stayed pinned there 100 frames (108
  frames out). clamp_fighter now moves a fighter whose feet have no floor of the original and no stage mesh under
  them (nor 15 / 30 cm inward, as on_floor) to the nearest spot with one (air: into the walkable area first; ground:
  Arena._off_top's ring search). FIXED a1c20c5: stg70 / stg80 / stg50 / stg10 configs + base both looks 165/165.
- **BUG-120 The knockdown bounce (k2/115) was ~3x too high** (w10, atk_ground P2 first divergence after BUG-66 was
  fixed: f200, the disc's P2 gets up while the remaster's is still in the air and takes another hit). Disc (657 logged
  rows, 40 bounces): 11.6 cm/f up with gravity -2.97 already on the first row (rises 8.63, 8.63, 5.66, 2.69 ...: apex
  25.6 cm, floor after 9 rows), then 2 more k2/115 rows on the floor still sliding at half speed (vy 2.87 / -0.97 there:
  the -0.97 the port had taken for the bounce's gravity), then lying k2/144. The remaster bounced 11.6 / -0.97 (apex
  69 cm, ~24 rows) and lay down on the landing row. Now as the disc. Ledger on the 28 tapes with a bounce: 15,283 ->
  15,563 (+280: moves_valgas +158, atk_ground +53, wangtang / rouge +24 / +23). FIXED 410a605 (all 96 tapes:
  55,993 -> 56,227).
- **BUG-66 re-measured (w10, 410a605)**: the first hit of every Ryoma hit tape now lands on the disc's frame (atk_ground
  / moves_ryoma / near_ryoma P2 first state diff f28 -> f200 at 3cb6e0c, f285 after BUG-120; dist_ryoma f241,
  hits_down f279). What diverges first now is the launch's start point (BUG-104: disc 51.4 / 99.4, remaster 81.9 /
  109.1 on the same frame) and the moves after it. FIXED for the hit frame; BUG-104 stays OPEN.
- **BUG-121 Reaction classes the port doesn't play** (w10 sweep: vertical acceleration per motion, all disc vs remaster
  tape logs): the disc's k2/108 (held 10-14 rows) > k2/111 pop-up (16.67 up, -1.39 per row, 25 rows: a victim on a
  raised floor, mash_s22 / mash_s55) > k2/131 landing WITH the k2/115-style bounce (11.6 / -2.97); and k2/173 >
  k2/99 bounce landing (11 logged). The remaster never shows k2/108 / 173 / 157 / 163 / 176 / 178 / 225 in the air:
  REACT.md classes 5 / 6 / 8 / 14 / 24 ("not decoded"). The ported launch path (96 > 97 > 98 > 99, no bounce) matches
  the disc's 66 logged landings. OPEN (decode the class handlers in 1ST_READ, REACT.md table).
- **BUG-122 A cleared arcade run ends with Godot leak lines** (w10 ladders lad8 on 410a605): the 3 runs that cleared
  the whole ladder incl. Final Valgas (falcon s2, ryoma s1, ryoma s2) end with "3 ObjectDB instances were leaked" +
  "ERROR: 1 resources still in use"; the 5 that didn't clear end clean. So the clear / ending path leaves 3 objects out
  of the tree (as BUG-116). OPEN (repro: one cleared ladder with --verbose, ~30 min; tests/arcade_ladder.gd).
