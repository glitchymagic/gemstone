# Coverage: every tape, the original vs the remaster (fx-cov, 2026-10-27, code 437b5da)

Measure, don't fix. Every number here is a same-input tape diff against the disc in our Flycast (docs/FIDELITY.md "The
measuring stick"); bugs found are BUG-43..BUG-63 in docs/BUGS.md.

## Status (fx-cov2, 10-27 07:00): section 9 = all 79 tapes re-run on master 2f8da7d (supersedes the per-tape numbers of
## sections 1, 2 and 8 as the current state; those stay as the history). New disc tapes this wave: pc_freeze (BUG-65),
## turn_ryoma / turn_jack / turn2_ryoma (BUG-58), ledge_hang (BUG-63): section 10.

## Status (fx-cov, 10-27 03:45) and next steps
Done: all 31 old tapes re-run on 437b5da + diffed; 20 new originals recorded with the object pool (11 stage tapes,
gems_drop, pole_londo, pole_londo2, items_weapon, 5 seeded mashes) + remaster runs + diffs; hunt re-run (hunt5) + re-score;
FIDELITY.md matrix refreshed; BUG-43..62 filed. 1 of 51 tapes passes (timeout).
Master 0fef882 re-run DONE (section 8: BUG-64 new, BUG-59 gone, mv_run / stg_60 worse; hunt6 remaster half: more falls
below the floor, stuck lying / airborne states). 5 disc items logged (section 7).
Next (in this order, if the lane restarts me):
1. On each new master commit: `git -C a checkout archive master game | tar -x -C DIR` + APFS clones of
   game/assets/{ripped,audio,hd} and game/.godot + this branch's game/tests/tape_run.gd, `Godot --headless --path DIR/game
   --import`, `FID_GAME=DIR/game FID_OUT=dumps/fidelity/cov_m tools/fidelity_run.py rem -j 3 ALL` + diff, then
   /tmp/ps-fx-cov/delta.py-style table (cov vs cov_m) and `tools/cov_stages.py`.
2. stg_a0: record Final Valgas's arena with fx-fv's boot (the fight-index-8 poke started on Wang-Tang's start points).
3. Pole catch rule (BUG-50): more Londo tries at different heights / facings (pole_londo2 tries 2-4 missed the pole by
   ~100 cm: aim them from the logged run direction), and Ayame's stage where the one catch happened (mash_s33 P2 f111-126).
4. Item ids 0-10: one items_weapon-style tape per id (place P1 at each stage's chest-2 spot at f985; ids come from rand,
   so vary the tape's early frames) to log each weapon's motions / damage.
5. State 36 (ledge hang, BUG-63) and state 7's trigger (BUG-58): placed tapes.

## How to re-run
- Original (Flycast instance, object pool logged too): `tools/covlog.py orig INST TAPE...` -> `dumps/fidelity/o_TAPE.jsonl`
  (+ `.obj.jsonl`: per frame every live object of the pool 0x0C7D0980 + slot x 0x31C: type / owner / kind / xyz / item id /
  sub-state). `tools/fidelity_run.py orig INST TAPE` still works for tapes without the object log.
- Remaster: `FID_OUT=dumps/fidelity/cov tools/fidelity_run.py rem -j 3 TAPE...` then `diff TAPE...` (reports in
  `dumps/fidelity/cov/reports/`); `game/tests/tape_run.gd` now also writes `r_TAPE.objs.jsonl` (the arena's gems + props).
- Tables: `tools/cov_report.py` (per tape), `tools/cov_blocks.py TAPE` (per `@place` block: run ends, states only one side
  has), `tools/cov_stages.py` (per stage), `tools/cov_jumps.py TAPE` (one-frame teleports), `tools/hunt_rescore.py RUN OLD`.
- New tapes: `tools/cov_tapes.py all` writes `stg_NN.tape` (11 stages) and `mash_sSEED_P1_P2.tape` (5 seeded mashes);
  hand-written: `gems_drop`, `pole_londo`, `pole_londo2`, `items_weapon`.

## 1. Every tape (51; fields P1/P2 match %, tolerances as FIDELITY.md; PASS = st/mot/x/z/hp/gems 100%)
`fr` = the motion frame counter, `ang` = +0x7248 (stays 0 in the original until the first move: not a bug). First
divergence = the earliest frame any of st/mot/x/y/z/hp/gems differs, original -> remaster.

| tape | P1 v P2 | stage | frames o/r | st % | mot % | fr % | x % | y % | z % | ang % | hp % | gems % | first divergence | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| atk_ground | ryoma v falcon | stg00 | 1258/1259 | 82/61 | 72/48 | 44/8 | 17/5 | 89/68 | 79/44 | 88/50 | 89/14 | 89/79 | P1 f25 x -25.0->-26.01; P2 f28 st 27->0 | FAIL |
| atk_move | ryoma v falcon | stg00 | 849/850 | 99/80 | 99/75 | 44/1 | 19/58 | 90/84 | 76/93 | 59/89 | 100/44 | 100/75 | P1 f23 x -368.0->-373.89; P2 f373 x 57.5->60.0 | FAIL |
| chain_ryoma | ryoma v falcon | stg00 | 3568/3569 | 98/100 | 97/100 | 90/2 | 19/100 | 100/100 | 25/100 | 100/100 | 100/100 | 100/100 | P1 f42 st 10->0 | FAIL |
| dist_galuda | galuda v falcon | stg00 | 2230/2231 | 91/66 | 89/63 | 82/6 | 66/36 | 100/93 | 100/86 | 100/45 | 100/3 | 100/97 | P1 f11 x 1.0->20.0; P2 f11 x 79.0->60.0 | FAIL |
| dist_gunrock | gunrock v falcon | stg00 | 2230/2231 | 96/62 | 92/60 | 62/4 | 59/35 | 95/88 | 86/78 | 100/38 | 100/14 | 100/92 | P1 f11 x -5.0->20.0; P2 f11 x 85.0->60.0 | FAIL |
| dist_jack | jack v falcon | stg00 | 2230/2231 | 97/70 | 93/68 | 82/5 | 71/52 | 100/91 | 100/82 | 100/40 | 100/1 | 100/1 | P1 f11 x 7.97->20.0; P2 f11 x 72.03->60.0 | FAIL |
| dist_ryoma | ryoma v falcon | stg00 | 2230/2231 | 96/59 | 93/55 | 82/8 | 37/25 | 100/85 | 100/74 | 100/41 | 100/14 | 100/100 | P1 f11 x 5.0->20.0; P2 f11 x 75.0->60.0 | FAIL |
| flow_start | ryoma v falcon | stg00 | 360/361 | 80/49 | 46/46 | 8/4 | 9/35 | 70/7 | 12/35 | 20/0 | 100/35 | 82/35 | P1 f28 mot 17->18; P2 f5 st 4->5 | FAIL |
| gems_drop | ryoma v falcon | stg00 | 1884/1885 | 84/87 | 79/83 | 5/2 | 3/3 | 40/29 | 3/3 | 31/84 | 3/25 | 43/23 | P1 f47 st 27->0; P2 f42 mot 16->74 | FAIL |
| gems_pc | ryoma v falcon | stg00 | 2136/2137 | 43/59 | 43/61 | 1/2 | 25/27 | 90/79 | 48/51 | 100/100 | 100/15 | 76/100 | P1 f11 st 23->0; P2 f280 st 0->27 | FAIL |
| hits_down | ryoma v falcon | stg00 | 1202/1203 | 100/87 | 94/80 | 41/43 | 39/16 | 100/65 | 86/60 | 85/60 | 100/38 | 100/99 | P1 f25 x -25.0->-26.01; P2 f28 st 27->0 | FAIL |
| items_londo | ryoma v falcon | stg00 | 430/431 | 99/47 | 98/48 | 30/3 | 3/53 | 100/76 | 59/53 | 10/81 | 100/27 | 40/100 | P1 f11 x -379.5->-385.35; P2 f117 st 0->15 | FAIL |
| items_weapon | ryoma v falcon | stg00 | 1645/1646 | 96/89 | 60/90 | 20/0 | 94/60 | 100/72 | 94/60 | 6/40 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| mash_s11_ryoma_falcon | ryoma v falcon | stg00 | 1578/1579 | 32/33 | 7/9 | 21/19 | 1/3 | 29/59 | 2/3 | 4/14 | 4/18 | 6/58 | P1 f12 st 10->31; P2 f39 st 10->0 | FAIL |
| mash_s22_jack_wangtang | jack v wangtang | stg20 | 1575/1576 | 40/33 | 13/10 | 25/19 | 1/1 | 30/18 | 1/1 | 5/6 | 20/2 | 50/70 | P1 f12 st 7->31; P2 f0 y 0.0->100.0 | FAIL |
| mash_s33_rouge_ayame | rouge v ayame | stg60 | 1572/1573 | 38/50 | 14/17 | 20/30 | 1/2 | 46/57 | 1/3 | 15/17 | 1/77 | 55/61 | P1 f12 st 10->31; P2 f37 st 10->0 | FAIL |
| mash_s44_gunrock_galuda | gunrock v galuda | stg50 | 1571/1572 | 56/32 | 15/7 | 31/17 | 2/1 | 74/23 | 2/3 | 6/2 | 17/2 | 21/46 | P1 f12 st 10->4; P2 f0 x 129.0->167.0 | FAIL |
| mash_s55_falcon_kraken | falcon v kraken | stg80 | 1577/1578 | 47/40 | 22/13 | 20/18 | 2/1 | 45/45 | 3/1 | 13/4 | 4/7 | 39/81 | P1 f37 z -348.97->-347.49; P2 f12 st 2->31 | FAIL |
| move_basic | ryoma v falcon | stg00 | 1498/1499 | 94/96 | 80/96 | 15/4 | 2/80 | 21/94 | 3/1 | 67/99 | 100/100 | 18/100 | P1 f28 mot 17->18; P2 f6 x -360.15->-366.87 | FAIL |
| moves_ayame | ayame v falcon | stg00 | 3516/3517 | 70/71 | 70/70 | 18/8 | 27/22 | 91/87 | 80/72 | 100/56 | 100/17 | 72/67 | P1 f27 x 1.84->-17.6; P2 f27 x 63.34->60.0 | FAIL |
| moves_falcon | falcon v ryoma | stg10 | 3516/3517 | 68/66 | 63/64 | 9/4 | 10/15 | 29/47 | 0/0 | 64/84 | 100/1 | 80/80 | P1 f11 z -69.82->-89.0; P2 f11 x -39.2->-57.0 | FAIL |
| moves_galuda | galuda v falcon | stg00 | 3516/3517 | 69/70 | 68/67 | 4/3 | 43/41 | 90/91 | 71/66 | 100/72 | 100/2 | 70/83 | P1 f23 x -28.0->-34.01; P2 f25 x 64.5->60.0 | FAIL |
| moves_gunrock | gunrock v falcon | stg00 | 3516/3517 | 57/53 | 56/49 | 11/1 | 44/32 | 83/81 | 83/52 | 100/80 | 100/7 | 88/65 | P1 f15 x -42.06->-45.81; P2 f20 x 67.17->60.0 | FAIL |
| moves_jack | jack v falcon | stg00 | 3516/3517 | 52/61 | 51/59 | 3/4 | 66/21 | 86/84 | 90/70 | 100/69 | 100/1 | 93/89 | P1 f21 x -14.0->-20.09; P2 f22 x 61.53->60.0 | FAIL |
| moves_kraken | kraken v falcon | stg00 | 3516/3517 | 69/61 | 68/59 | 13/4 | 28/21 | 91/84 | 52/36 | 82/86 | 100/11 | 80/80 | P1 f28 x -30.88->-38.02; P2 f19 st 27->0 | FAIL |
| moves_rouge | rouge v falcon | stg00 | 3516/3517 | 60/62 | 59/60 | 12/2 | 40/28 | 88/83 | 69/50 | 100/87 | 100/1 | 91/89 | P1 f17 x -12.19->-17.53; P2 f19 x 64.22->60.0 | FAIL |
| moves_ryoma | ryoma v falcon | stg00 | 3516/3517 | 66/62 | 64/58 | 10/4 | 26/25 | 95/77 | 54/29 | 91/86 | 100/20 | 82/77 | P1 f25 x -25.0->-26.01; P2 f28 st 27->0 | FAIL |
| moves_valgas | valgas v falcon | stg00 | 3516/3517 | 70/56 | 69/54 | 9/2 | 49/26 | 93/85 | 78/49 | 100/52 | 100/1 | 73/49 | P1 f15 x -30.0->-36.45; P2 f17 x 65.2->60.0 | FAIL |
| moves_wangtang | wangtang v falcon | stg00 | 3516/3517 | 70/67 | 70/65 | 17/5 | 31/19 | 91/83 | 80/46 | 100/53 | 100/5 | 81/81 | P1 f30 x -9.56->-13.32; P2 f21 st 27->0 | FAIL |
| mv_jump | ryoma v falcon | stg00 | 723/724 | 89/100 | 88/100 | 36/0 | 49/100 | 84/100 | 49/100 | 98/98 | 100/100 | 100/100 | P1 f15 mot 6->5 | FAIL |
| mv_run | ryoma v falcon | stg00 | 627/628 | 91/100 | 90/100 | 16/0 | 19/100 | 89/100 | 18/100 | 98/98 | 100/100 | 100/100 | P1 f28 z -224.9->-222.52 | FAIL |
| mv_turn | ryoma v falcon | stg00 | 658/659 | 98/100 | 98/100 | 8/0 | 27/100 | 97/100 | 31/100 | 98/98 | 100/100 | 100/100 | P1 f28 z -224.9->-222.52 | FAIL |
| near_gunrock | gunrock v falcon | stg00 | 4346/4347 | 98/87 | 97/88 | 33/1 | 81/65 | 90/96 | 88/88 | 100/22 | 100/1 | 100/44 | P1 f12 x -40.0->-45.31; P2 f12 x 60.0->65.31 | FAIL |
| near_ryoma | ryoma v falcon | stg00 | 4346/4347 | 99/94 | 98/93 | 36/4 | 42/57 | 100/96 | 100/88 | 100/22 | 100/4 | 100/13 | P1 f19 x -19.94->-26.01; P2 f24 x 61.44->60.0 | FAIL |
| pole_londo | ryoma v falcon | stg00 | 627/628 | 66/100 | 64/100 | 8/0 | 5/100 | 6/100 | 5/100 | 45/98 | 100/100 | 100/100 | P1 f14 mot 10->25 | FAIL |
| pole_londo2 | ryoma v falcon | stg00 | 642/643 | 89/100 | 89/100 | 16/0 | 2/100 | 72/100 | 2/100 | 79/98 | 100/100 | 100/100 | P1 f11 x -255.87->-216.0 | FAIL |
| pole_wall | ryoma v falcon | stg00 | 348/349 | 48/100 | 46/100 | 8/0 | 9/100 | 40/100 | 8/100 | 14/97 | 100/100 | 100/100 | P1 f11 st 0->14 | FAIL |
| rnd_probe1 | ryoma v falcon | stg00 | 252/253 | 99/100 | 99/100 | 87/19 | 58/60 | 100/73 | 100/60 | 96/96 | 100/100 | 100/100 | P1 f42 st 10->0; P2 f149 st 27->0 | FAIL |
| rnd_probe2 | ryoma v falcon | stg00 | 548/549 | 93/73 | 87/72 | 67/12 | 36/37 | 100/76 | 100/81 | 93/50 | 100/73 | 100/100 | P1 f53 x -25.0->-26.01; P2 f56 st 27->0 | FAIL |
| stg_00 | ryoma v falcon | stg00 | 2340/2341 | 85/75 | 76/58 | 16/13 | 25/10 | 81/65 | 15/11 | 82/57 | 100/72 | 14/98 | P1 f30 z -221.72->-219.09; P2 f20 x -391.37->-393.74 | FAIL |
| stg_10 | falcon v ryoma | stg10 | 2340/2341 | 86/87 | 72/74 | 16/22 | 31/18 | 70/55 | 28/21 | 60/61 | 94/72 | 60/98 | P1 f24 y 0.0->-2.0; P2 f28 x -77.91->-76.63 | FAIL |
| stg_20 | gunrock v wangtang | stg20 | 2340/2341 | 86/88 | 75/76 | 13/23 | 9/11 | 65/63 | 8/12 | 54/54 | 79/72 | 47/52 | P1 f14 x -177.02->-178.44; P2 f14 x -432.15->-433.57 | FAIL |
| stg_30 | galuda v jack | stg30 | 2340/2341 | 87/77 | 77/60 | 17/8 | 28/15 | 80/58 | 39/34 | 53/52 | 79/72 | 99/48 | P1 f56 z -315.0->-318.0; P2 f15 z 130.0->128.5 | FAIL |
| stg_40 | ayame v gunrock | stg40 | 2340/2341 | 84/66 | 71/50 | 20/5 | 20/13 | 64/57 | 5/10 | 49/51 | 77/20 | 38/79 | P1 f14 x 382.15->383.56; P2 f14 x 127.02->128.44 | FAIL |
| stg_50 | rouge v galuda | stg50 | 2340/2341 | 75/88 | 66/76 | 12/14 | 20/20 | 62/66 | 18/30 | 68/56 | 93/72 | 83/93 | P1 f15 x 427.79->428.85; P2 f28 x 270.74->274.48 | FAIL |
| stg_60 | kraken v ayame | stg60 | 2340/2341 | 83/81 | 69/61 | 8/12 | 6/5 | 66/47 | 7/7 | 75/55 | 100/72 | 100/28 | P1 f15 z -422.54->-421.18; P2 f14 z -184.02->-182.21 | FAIL |
| stg_70 | valgas v rouge | stg70 | 2340/2341 | 85/76 | 74/61 | 18/22 | 33/8 | 64/57 | 40/7 | 53/52 | 87/63 | 3/72 | P1 f42 gems 1->2; P2 f15 z -202.18->-200.82 | FAIL |
| stg_80 | wangtang v kraken | stg80 | 2340/2341 | 71/71 | 69/58 | 9/14 | 6/7 | 62/47 | 6/8 | 62/46 | 84/73 | 84/56 | P1 f14 z -425.98->-427.79; P2 f15 z -187.46->-188.82 | FAIL |
| stg_90 | jack v valgas | stg90 | 2340/2341 | 74/73 | 66/64 | 10/16 | 10/34 | 63/62 | 7/30 | 63/61 | 77/72 | 100/30 | P1 f15 x -112.21->-111.15; P2 f46 gems 1->2 | FAIL |
| stg_a0 | ryoma v finalvalgas | stga0 | 2340/2341 | 77/22 | 60/29 | 14/0 | 0/0 | 10/0 | 0/0 | 53/0 | 100/72 | 40/100 | P1 f0 x -165.0->1274.97; P2 f0 x -447.0->950.0 | FAIL |
| timeout | ryoma v falcon | stg00 | 7200/7201 | 100/100 | 100/100 | 3/2 | 100/100 | 100/100 | 100/100 | 0/0 | 100/100 | 100/100 | P1 f6186 st 21->0; P2 f6186 st 21->0 | PASS |

Reading it: 1 of 51 tapes passes (timeout: two idle fighters, 7200 frames, the round clock + TIME flow exact). Most
first divergences are in the first 30 frames: the attack that starts the tape (BUG-16 chain timing, BUG-56 run speed per
fighter, BUG-45 body push on `@place`), so the later % are cascades; the per-block numbers below isolate stages.
`stg_a0` is not a valid comparison: the arcade boot at fight index 8 started on Wang-Tang's start points with a human
P2 that runs and wall-kicks (not Final Valgas), and the remaster has no stga0 start points (P1 (1275, 1277), P2 (950, 950),
P2 idle all tape): re-record with fx-fv's boot.

## 2. Existing tapes: the previous reports vs today (master 437b5da)
| tape | old report (time) | st P1/P2 | mot P1/P2 | x P1/P2 | hp P1/P2 | now (437b5da) st | mot | x | hp |
|---|---|---|---|---|---|---|---|---|---|
| atk_ground | 10-27 03:06 | 82/61 | 72/48 | 17/5 | 89/14 | 82/61 | 72/48 | 17/5 | 89/14 |
| atk_move | 10-26 22:06 | 72/66 | 66/67 | 19/51 | 84/33 | 99/80 | 99/75 | 19/58 | 100/44 |
| dist_galuda | 10-27 02:01 | 91/66 | 89/56 | 70/42 | 100/3 | 91/66 | 89/63 | 66/36 | 100/3 |
| dist_gunrock | 10-27 02:01 | 95/65 | 88/54 | 60/54 | 100/1 | 96/62 | 92/60 | 59/35 | 100/14 |
| dist_jack | 10-27 02:01 | 97/70 | 93/60 | 71/52 | 100/1 | 97/70 | 93/68 | 71/52 | 100/1 |
| dist_ryoma | 10-27 03:06 | 96/59 | 93/55 | 37/25 | 100/14 | 96/59 | 93/55 | 37/25 | 100/14 |
| flow_start | 10-27 02:11 | 85/49 | 51/46 | 9/35 | 100/35 | 80/49 | 46/46 | 9/35 | 100/35 |
| gems_pc | 10-26 22:09 | 42/59 | 43/61 | 25/27 | 100/14 | 43/59 | 43/61 | 25/27 | 100/15 |
| hits_down | 10-27 03:06 | 100/87 | 94/80 | 39/16 | 100/38 | 100/87 | 94/80 | 39/16 | 100/38 |
| items_londo | 10-27 03:06 | 99/47 | 98/48 | 3/53 | 100/27 | 99/47 | 98/48 | 3/53 | 100/27 |
| move_basic | 10-27 02:40 | 94/96 | 80/96 | 2/80 | 100/100 | 94/96 | 80/96 | 2/80 | 100/100 |
| moves_ayame | 10-27 02:02 | 70/71 | 66/67 | 27/23 | 100/17 | 70/71 | 70/70 | 27/22 | 100/17 |
| moves_falcon | 10-27 02:47 | 68/67 | 61/62 | 10/15 | 100/1 | 68/66 | 63/64 | 10/15 | 100/1 |
| moves_galuda | 10-27 02:02 | 69/71 | 65/66 | 43/46 | 100/2 | 69/70 | 68/67 | 43/41 | 100/2 |
| moves_gunrock | 10-27 02:02 | 56/50 | 51/45 | 44/32 | 100/1 | 57/53 | 56/49 | 44/32 | 100/7 |
| moves_jack | 10-27 02:02 | 52/61 | 51/58 | 66/22 | 100/1 | 52/61 | 51/59 | 66/21 | 100/1 |
| moves_kraken | 10-27 02:02 | 69/57 | 52/56 | 36/23 | 100/0 | 69/61 | 68/59 | 28/21 | 100/11 |
| moves_rouge | 10-27 02:02 | 60/62 | 56/58 | 40/28 | 100/1 | 60/62 | 59/60 | 40/28 | 100/1 |
| moves_ryoma | 10-27 03:06 | 66/62 | 64/58 | 26/25 | 100/20 | 66/62 | 64/58 | 26/25 | 100/20 |
| moves_valgas | 10-27 02:02 | 70/57 | 65/52 | 49/26 | 100/1 | 70/56 | 69/54 | 49/26 | 100/1 |
| moves_wangtang | 10-27 02:02 | 70/68 | 65/61 | 35/19 | 100/5 | 70/67 | 70/65 | 31/19 | 100/5 |
| mv_jump | 10-27 02:40 | 89/100 | 88/100 | 49/100 | 100/100 | 89/100 | 88/100 | 49/100 | 100/100 |
| mv_run | 10-27 02:40 | 91/100 | 90/100 | 19/100 | 100/100 | 91/100 | 90/100 | 19/100 | 100/100 |
| mv_turn | 10-26 22:36 | 97/100 | 95/100 | 26/98 | 100/100 | 98/100 | 98/100 | 27/100 | 100/100 |
| pole_wall | 10-26 22:09 | 63/100 | 62/100 | 0/97 | 100/100 | 48/100 | 46/100 | 9/100 | 100/100 |
| timeout | 10-26 22:06 | 97/97 | 97/97 | 0/0 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 |

Changes since the old reports: atk_move P1 state 72 -> 99% (the wave-2 core), timeout 97 -> 100% (flow), moves_kraken
motion 52 -> 68% (the k0 key fix), pole_wall P1 state 63 -> 48% (the core now falls off the lower step at frame 11 like
the disc, then catches the lamp post the disc never catches: BUG-50), flow_start P1 state 85 -> 80% (P1's stop slide at
frame 302 drops off a step at (-563, 0, 273) into state 14 since the wave-2 edge rule; the old run and the disc stay in
state 32 for 23 frames: BUG-59).

## 3. Stages (stg_NN tapes: each run / jump / attack block starts from the same @place on both sides)
Run ends = where each of the 16 runs into a wall / edge was at its 90th frame (P1 + P2, 8 directions).
| tape | run ends <=1 / <=10 cm of 16 | median cm | wall kick st38 o/r (k2/206 rows o/r) | ledge hop st17 o/r | pole st34 o/r | one-frame >60 cm moves o/r (remaster: frame P state at x,y,z) | floor gem (orig frame, x,y,z) |
|---|---|---|---|---|---|---|---|
| stg_00 | 0 / 6 | 34.0 | 88/0 (88/338) | 0/0 | 0/35 | 0/1 f1385 P2 st34 65/+36 cm at (-411,69,-251) | 299, [-190.0, 170.0, 720.0] |
| stg_10 | 0 / 3 | 112.1 | 80/0 (80/456) | 23/0 | 0/0 | 0/2 f603 P1 st31 10/+761 cm at (662,729,193); f1234 P2 st31 3/+755 cm at (-290,755,-655) | 299, [-317.0, 50.0, 97.0] |
| stg_20 | 0 / 6 | 33.0 | 112/0 (112/446) | 0/0 | 0/37 | 0/1 f103 P2 st5 50/+100 cm at (103,150,-335) | 299, [-400.0, 50.0, -50.0] |
| stg_30 | 0 / 9 | 4.7 | 128/0 (128/544) | 26/0 | 0/0 | 0/1 f1229 P1 st31 64/+30 cm at (-247,30,-212) | 299, [200.0, 50.0, 400.0] |
| stg_40 | 1 / 4 | 41.1 | 104/0 (104/544) | 88/0 | 0/35 | 0/3 f364 P2 st31 65/+50 cm at (37,50,-185); f872 P2 st31 65/+50 cm at (158,50,-134); f1420 P1 st34 62/+36 cm at (-5,51,285) | 299, [400.0, 50.0, -530.0] |
| stg_50 | 0 / 4 | 61.4 | 112/0 (112/461) | 140/0 | 0/0 | 1/0  | 299, [450.0, 50.0, 300.0] |
| stg_60 | 0 / 2 | 26.8 | 72/0 (72/529) | 26/0 | 0/34 | 0/1 f1483 P2 st34 62/+36 cm at (-17,314,-246) | 299, [590.0, 170.0, -120.0] |
| stg_70 | 0 / 6 | 14.1 | 72/0 (72/544) | 60/0 | 0/44 | 2/6 f247 P1 st31 69/+65 cm at (-407,65,-178); f555 P2 st31 30/+65 cm at (-391,65,-26); f917 P1 st31 91/+65 cm at (-434,65,-674) | 299, [280.0, 50.0, 60.0] |
| stg_80 | 0 / 5 | 27.6 | 72/0 (72/479) | 30/0 | 0/0 | 0/0  | 299, [320.0, 50.0, -200.0] |
| stg_90 | 0 / 8 | 11.6 | 128/0 (128/544) | 82/0 | 0/0 | 0/0  | 299, [200.0, 50.0, -300.0] |
| stg_a0 | 0 / 0 | None | 112/0 (112/238) | 98/0 | 0/0 | 0/0  | 299, [-14.1, 150.0, 414.1] |

### Objects per stage (original, from the object pool log)
| stage (tape) | floor gem: frame, x,y,z (cm) | gem despawn / respawn | chests: frame appear > item ready, spot, item id | poles (kind 2) | throwables (kind 1) at f0 |
|---|---|---|---|---|---|
| stg_00 | f299 slot4 on floor (-190,170,720) | f1748 slot3 on floor (-291,100,-107); f2176 slot4 taken/gone (-190,170,720) | f0>377 (350,281,790) id 9; f319>- (355,281,790) id 9; f599>977 (430,41,0) id 2; f919>- (435,41,0) id 2 | (440,0,-256), (-428,0,-256) | 9 |
| stg_10 | f299 slot4 on floor (-317,50,97) | f1739 slot3 on floor (-88,100,-407) | f0>377 (360,161,550) id 8; f319>- (365,161,550) id 8; f599>977 (-577,161,-140) id 0; f919>- (-572,161,-140) id 0 | (282,120,214), (-443,120,214) | 6 |
| stg_20 | f299 slot4 on floor (-400,50,-50) | f1229 slot4 taken/gone (-400,50,-50); f2231 slot3 on floor (375,150,550) | f0>377 (-50,91,-50) id 10; f319>- (-45,91,-50) id 10; f599>935 (0,141,400) id 2; f877>- (5,141,400) id 2 | (-130,50,-240), (-130,100,170), (260,100,170) | 12 |
| stg_30 | f299 slot4 on floor (200,50,400) | f1846 slot2 on floor (109,100,100); f2190 slot3 on floor (-150,100,-93) | f0>319 (-500,41,300) id 8; f261>- (-495,41,300) id 8; f599>977 (-500,41,300) id 0; f900>1278 (0,41,-150) id 5 | (0,0,300) | 2 |
| stg_40 | f299 slot4 on floor (400,50,-530) | f914 slot4 taken/gone (400,50,-530); f2187 slot3 on floor (321,100,-128) | f0>377 (-580,191,-550) id 10; f319>- (-575,191,-550) id 10; f599>977 (300,41,250) id 1; f919>- (305,41,250) id 1 | (0,0,-340), (0,0,340) | 10 |
| stg_50 | f299 slot4 on floor (450,50,300) | f1258 slot4 taken/gone (450,50,300); f1737 slot3 on floor (216,100,-400) | f0>377 (-100,341,560) id 9; f319>- (-95,341,560) id 9; f599>977 (0,41,0) id 1; f919>- (5,41,0) id 1 | (-110,56,-170), (290,305,320) | 11 |
| stg_60 | f299 slot4 on floor (590,170,-120) | f1748 slot3 on floor (-140,100,-285) | f0>377 (21,161,570) id 8; f319>- (26,161,570) id 8; f599>743 (-290,41,-220) id 0; f685>- (-285,41,-220) id 0 | (-296,120,238), (450,119,238), (0,0,-246) | 6 |
| stg_70 | f299 slot4 on floor (280,50,60) | f2132 slot3 on floor (48,100,-305) | f0>377 (-650,101,60) id 10; f319>- (-645,101,60) id 10; f599>977 (650,161,-400) id 2; f919>- (655,161,-400) id 2 | (0,0,-50), (0,0,-350), (-350,185,520) | 4 |
| stg_80 | f299 slot4 on floor (320,50,-200) | f1738 slot3 on floor (-218,100,-222); f1955 slot2 on floor (-389,100,-31) | f0>377 (480,261,515) id 7; f319>- (485,261,515) id 7; f599>769 (-270,41,-465) id 1; f711>- (-265,41,-465) id 1 | (224,220,152), (-222,220,152) | 4 |
| stg_90 | f299 slot4 on floor (200,50,-300) | f1053 slot4 taken/gone (200,50,-300); f2175 slot3 on floor (20,100,80) | f0>377 (400,41,400) id 8; f319>- (405,41,400) id 8; f599>977 (-300,41,200) id 1; f919>- (-295,41,200) id 1 | - | 3 |
| gems_drop | f98 slot2 on floor (-113,100,-285) | f299 slot4 on floor (-190,170,720); f1409 slot4 taken/gone (-190,170,720); f1709 slot4 on floor (430,50,0) | f0>377 (350,281,790) id 8; f319>- (355,281,790) id 8; f599>977 (430,41,0) id 2; f919>- (435,41,0) id 2 | (440,0,-256), (-428,0,-256) | 9 |

Chest rows: the frame the chest object (type 2 kind 7) appears > the frame its item (type 3 kind 6) is ready (sub 0), its
spot, the item id inside (+0x30C). The same chest object moves 5 cm at ~319 (listed twice). Every stage spawns chests on
the same clock: chest 1 at frame 0 (item at 377; Jack's 319), chest 2 at 599 (item at 977; Wang-Tang's 935, Ayame's 743,
Kraken's 769), more every ~300-600 frames; the item id changes run to run (rand). The remaster has no chests or items.

## 4. All tapes: frames per state id (both fighters, 50 tapes)
50 tapes (stg_a0 excluded), fighter-frames per state id, original / remaster:
| state | original frames (tapes) | remaster frames (tapes) |
|---|---|---|
| 0 | 108436 (50) | 134628 (50) |
| 2 | 387 (21) | 47 (12) |
| 4 | 312 (30) | 345 (31) |
| 5 | 14563 (35) | 14948 (34) |
| 6 | 1009 (34) | 1296 (35) |
| 7 | 42 (2) | 0 (0) |
| 8 | 2199 (10) | 244 (1) |
| 10 | 22747 (44) | 22869 (43) |
| 11 | 6606 (11) | 0 (0) |
| 13 | 1791 (10) | 473 (6) |
| 14 | 34 (5) | 263 (18) |
| 15 | 840 (39) | 1098 (38) |
| 16 | 4174 (39) | 2287 (38) |
| 17 | 475 (8) | 0 (0) |
| 21 | 2687 (11) | 732 (2) |
| 23 | 3149 (11) | 131 (1) |
| 24 | 1176 (33) | 1050 (32) |
| 27 | 20652 (40) | 11830 (39) |
| 28 | 3717 (22) | 2628 (20) |
| 29 | 2599 (22) | 1913 (20) |
| 31 | 18400 (25) | 20049 (26) |
| 32 | 3351 (22) | 3024 (24) |
| 34 | 88 (1) | 863 (12) |
| 35 | 330 (7) | 108 (4) |
| 36 | 39 (1) | 0 (0) |
| 37 | 222 (22) | 274 (23) |
| 38 | 975 (11) | 0 (0) |

States only the original enters: 7 (a 21-frame curved run k0/41 on a direction change: BUG-58), 11 (Power Change attacks:
BUG-25), 17 (the low-obstacle vault k0/48 > 57 > 58: BUG-48), 36 (ledge hang k2/207 19 rows > hang attack k1/162 > 163, Wang-Tang at y 409 on a wall top in mash_s22: BUG-63),
38 (wall kick: BUG-47). The remaster enters 34 (pole swing) 863 frames in 12 tapes where the original swings 88 frames in
1 (BUG-50). State 23 (Power Change): 3149 vs 131 (BUG-25: the remaster does not start the change from @gems).

## 5. Breakage hunt re-run (tools/hunt.sh seed 3, 3600 frames, 135 runs, both looks, code 437b5da)
Output /tmp/ps-fx-cov/hunt5 (summary.txt, findings.json). Against run4 (9aa456d):

| class | run4 occurrences / distinct | hunt5 | hunt5 re-scored (tools/hunt_rescore.py) |
|---|---|---|---|
| exit_leak | 178 / 2 | 166 / 2 | (as is) |
| fell | 0 / 0 | 7877 / 9 | 2152 per-run occurrences: Londo, Ryoma's stage, every stga0 run (BUG-60) |
| overlap | 214 / 25 | 197 / 27 | 114 / 27 |
| pose_frozen | 77 / 10 | 194 / 16 | 150 / 33 (HITSTUN on stand-in reaction clips k2_002/005/017/020: BUG-17) |
| softlock | 0 / 0 | 9 / 1 | "round clock stands still 4 s in FIGHT" (menus run, frame 1303, both looks) |
| stuck_state | 12 / 6 | 9 / 5 | Falcon / Valgas PC attack (gst 11) 420+ frames vs Final Valgas; HITSTUN k2_152 240+ on stga0 |
| wedged | 23 / 12 | 1262 / 79 | 721 false positives (the core never sets is_on_floor(); gst = a ground state) + 87 real (gst 5/14/27/34/38), 51 of them 0.4-2.7 m off the floor (launched fighters frozen in the air) |

0 matches finished in 135 x 60 s of fuzz (run4: 22): rounds are 99 s now and the fuzz rarely KOs; not a finding by itself.
The hunt's `wedged` test needs the core's ground flag (hunt.gd asks CharacterBody3D.is_on_floor()): request in BUGS.md.

## 6. Per fighter: run and jump (every tape; steady rows of state 31 k0/25 on flat floor, moving jump k0/10 rows)
| fighter | run cm/frame orig / rem | moving jump cm/frame orig / rem | air gravity cm/frame^2 orig / rem | standing jump first rise cm orig / rem |
|---|---|---|---|---|
| ayame | 10.5 / 9.5 | 10.75 / 9.75 | 2.0 / 2.0 | 37.0 / - |
| falcon | 9.5 / 9.5 | 9.75 / 9.75 | 2.0 / 2.0 | 32.5 / 32.5 |
| galuda | 9.5 / 9.5 | 9.75 / 9.75 | 2.0 / 2.0 | 32.5 / 32.5 |
| gunrock | 8.5 / 9.5 | 8.75 / 9.75 | 1.15 / 2.0 | 22.8 / - |
| jack | 10.0 / 9.5 | 10.25 / 9.75 | 1.08 / 2.0 | 24.0 / - |
| kraken | 9.0 / 9.5 | 9.25 / 9.75 | 1.2 / 2.0 | 24.0 / - |
| rouge | 10.0 / 9.5 | 10.25 / 9.75 | 1.3 / 2.0 | 27.0 / - |
| ryoma | 9.5 / 9.5 | 9.75 / 9.75 | 2.0 / 2.0 | 32.5 / - |
| valgas | 9.5 / 9.5 | 9.75 / 9.75 | 2.1 / 2.0 | 34.0 / - |
| wangtang | 10.5 / 9.5 | 10.75 / 9.75 | 2.0 / 2.0 | 37.0 / - |
(modes over 1,000-2,600 run rows per fighter; "-" = no standing jump with that row pattern in the remaster's logs.)
The pass-3 measurements (9.5 run, 35.5 / 2.0 jump) were Ryoma's; the core uses them for everyone (BUG-56, BUG-57).

## 7. Gems, items, poles: what the original does (numbers for BUG-43, 44, 46, 50)
- Gems (gems_drop, stage tapes): each fighter holds 1 at frame 0; the 3rd appears at frame 299 on a fixed spot per stage
  (table 3), hovering 50 cm over the floor (Londo's 170 = on a 120 cm top), hops ~175 cm now and then (gems_drop
  420-450); not taken, it goes after 1,110 frames (1409) and comes back 300 frames later elsewhere ((430, 50, 0) at 1709).
  A launch (k2/96) spills 1 gem (2 > 1 gems_drop f98, 1 > 0 stg_00 f1748, stg_10 f1739): it starts 100-130 cm from the
  victim toward the attacker, 100 cm up, flies 20.0 cm/frame flat (14.1 per axis), vy 30 cm/frame, gravity 1.2,
  bounces off walls, lands ~52 frames / ~7.6 m later. Touching takes it (stg_20 f1209: feet 65 cm from the gem).
- Items (items_weapon): B next to the item = state 35 k0/0 5 rows > k2/237 24 rows (the item object's owner 2 > 0, held
  at the hand), then k2/238 idle / k2/239 walk-start with it; X or Y = state 10 k2/245 31 rows; item id 1 hit Falcon
  twice for 31 each, both launches (k2/96). Remaster: no item, X / Y = k1/16 / k1/24.
- Poles: in 10 lamp-post tries on Londo (pole_londo 5, pole_londo2 4, pole_wall) the original never caught the pole: it
  stops 60 cm from it and drops straight down (pole_londo f14-52 x stays -385.57). Its only catch in all tapes: Ayame on
  her stage, mash_s33 P2 f126, a moving jump 15 rows in at y 370 > state 34 k2/211 22 rows > state 10 k1/150 10 > k1/151
  28. The remaster caught the Londo lamp post in 6 of the 10 tries and in 6 stage tapes (state 34, 35-44 rows each).

### Items on the disc, per item (items_id*.tape: items_weapon with a poke8 of the chest's +0x30C at frame 900)
The poke did not set the id 1:1 (the chest's byte maps / re-rolls: poke 0 > item 2, 3 > 1, 4 > 4, 6 > 0, 7 > 7, ...), but
the 11 runs gave 5 different items (ids 0, 1, 2, 4, 7, read from the item object at 977). P1 picks it up at 985, then
LEFT, 3 x X, 3 x Y at P2 (300 cm away, facing him):
| item id | item ready (frame, id seen) | P1 after B at 985 (state k/motion x rows) | P2 hp after | P2 reactions |
|---|---|---|---|---|
| 0 | (977, 2) | s0k0/0x2 s35k0/0x5 s35k2/80x24 s0k2/81x34 s2k2/82x10 s0k2/81x23 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x65 | 240 > 214 > 188 | k0/0 k2/96 k2/97 k2/98 k2/152 k2/153 |
| 1 | (977, 1) | s0k0/0x2 s35k0/0x5 s35k2/237x24 s0k2/238x34 s2k2/239x10 s0k2/238x23 s10k2/245x31 s0k2/238x13 s10k2/245x31 s0k2/238x13 s10k2/245x31 s0k2/238x73 | 240 > 209 > 178 | k0/0 k2/96 k2/97 k2/98 k2/99 |
| 2 | (977, 2) | s0k0/0x2 s35k0/0x5 s35k2/80x24 s0k2/81x34 s2k2/82x10 s0k2/81x23 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x65 | 240 > 214 > 188 | k0/0 k2/96 k2/97 k2/98 k2/152 k2/153 |
| 3 | (977, 1) | s0k0/0x2 s35k0/0x5 s35k2/237x24 s0k2/238x34 s2k2/239x10 s0k2/238x23 s10k2/245x31 s0k2/238x13 s10k2/245x31 s0k2/238x13 s10k2/245x31 s0k2/238x73 | 240 > 209 > 178 | k0/0 k2/96 k2/97 k2/98 k2/99 |
| 4 | (977, 4) | s0k0/0x2 s35k0/0x5 s35k2/195x24 s0k2/194x34 s31k2/203x3 s32k2/204x30 s10k2/197x53 s0k2/194x35 s10k2/197x45 s0k2/194x59 s10k2/197x45 s0k2/194x43 | 240 > 198 | k0/0 k2/112 k2/152 k2/153 |
| 5 | (977, 1) | s0k0/0x2 s35k0/0x5 s35k2/237x24 s0k2/238x34 s2k2/239x10 s0k2/238x23 s10k2/245x31 s0k2/238x13 s10k2/245x31 s0k2/238x13 s10k2/245x31 s0k2/238x73 | 240 > 209 > 178 | k0/0 k2/96 k2/97 k2/98 k2/99 |
| 6 | (977, 0) | s0k0/0x2 s35k0/0x5 s35k2/237x24 s0k2/238x34 s2k2/239x10 s0k2/238x23 s10k2/243x140 s0k2/238x52 s10k2/243x52 s0k0/0x36 s10k1/24x33 s0k0/0x249 | 240 > 224 > 191 | k0/0 k2/112 k2/152 k2/153 |
| 7 | (977, 7) | s0k0/0x2 s35k0/0x5 s35k2/229x24 s0k2/230x34 s2k2/231x10 s0k2/230x23 s10k2/235x36 s0k0/0x8 s10k1/16x31 s0k0/0x13 s10k1/16x31 s0k0/0x73 | 240 > 208 | k0/0 k2/112 k2/152 k2/153 |
| 8 | (977, 2) | s0k0/0x2 s35k0/0x5 s35k2/80x24 s0k2/81x34 s2k2/82x10 s0k2/81x23 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x65 | 240 > 214 > 188 | k0/0 k2/96 k2/97 k2/98 k2/152 k2/153 |
| 9 | (977, 0) | s0k0/0x2 s35k0/0x5 s35k2/237x24 s0k2/238x34 s2k2/239x10 s0k2/238x23 s10k2/243x140 s0k2/238x52 s10k2/243x52 s0k0/0x36 s10k1/24x33 s0k0/0x249 | 240 > 224 > 191 | k0/0 k2/112 k2/152 k2/153 |
| 10 | (977, 2) | s0k0/0x2 s35k0/0x5 s35k2/80x24 s0k2/81x34 s2k2/82x10 s0k2/81x23 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x5 s10k2/86x39 s0k2/81x65 | 240 > 214 > 188 | k0/0 k2/96 k2/97 k2/98 k2/152 k2/153 |

Per item: pick-up k2/80 (id 2), k2/237 (ids 0, 1), k2/195 (id 4), k2/229 (id 7), always 24 rows after state 35 k0/0 5 rows;
carry idle / walk-start k2/81 / 82, 238 / 239, 194 / 203 (+ stop 204), 230 / 231; use (state 10) k2/86 39 rows 26 dmg
launch, k2/245 31 rows 31 dmg launch, k2/197 45-53 rows 42 dmg tumble k2/112, k2/243 140 rows 16 + 33 dmg (then used up:
P1 kicks k1/24 again), k2/235 36 rows 32 dmg (used up after one). Remaster: none of these (BUG-46).

## 8. Re-run on master 0fef882 (the lead's object vault / no ground pole catch / run-off-an-edge / disc-fight areas)
Same 51 originals + ledge_londo (master's tape), remaster from a `git archive 0fef882 game` snapshot (+ APFS clones of the
untracked assets, this branch's tape_run.gd): `FID_GAME=/tmp/ps-fx-cov/gm/game
FID_OUT=dumps/fidelity/cov_m`. Reports in `dumps/fidelity/cov_m/reports/`. 0 Godot error lines in 52 runs.

| tape | 437b5da st P1/P2 | 0fef882 st | 437b5da mot | 0fef882 mot | 437b5da x | 0fef882 x | 437b5da hp | 0fef882 hp | first divergence 0fef882 |
|---|---|---|---|---|---|---|---|---|---|
| atk_ground | 82/61 | 82/61 | 72/48 | 72/48 | 17/5 | 17/5 | 89/14 | 89/14 | P1 f25 x -25.0->-26.01; P2 f28 st 27->0 |
| atk_move | 99/80 | 96/96 | 99/75 | 95/91 | 19/58 | 19/58 | 100/44 | 100/100 | P1 f23 x -368.0->-373.89; P2 f373 x 57.5->60.0 |
| chain_ryoma | 98/100 | 98/100 | 97/100 | 97/100 | 19/100 | 19/100 | 100/100 | 100/100 | P1 f42 st 10->0 |
| dist_galuda | 91/66 | 91/66 | 89/63 | 89/63 | 66/36 | 66/36 | 100/3 | 100/3 | P1 f11 x 1.0->20.0; P2 f11 x 79.0->60.0 |
| dist_gunrock | 96/62 | 96/62 | 92/60 | 92/60 | 59/35 | 59/35 | 100/14 | 100/14 | P1 f11 x -5.0->20.0; P2 f11 x 85.0->60.0 |
| dist_jack | 97/70 | 97/70 | 93/68 | 93/68 | 71/52 | 71/52 | 100/1 | 100/1 | P1 f11 x 7.97->20.0; P2 f11 x 72.03->60.0 |
| dist_ryoma | 96/59 | 96/59 | 93/55 | 93/55 | 37/25 | 37/25 | 100/14 | 100/14 | P1 f11 x 5.0->20.0; P2 f11 x 75.0->60.0 |
| flow_start | 80/49 | 85/49 | 46/46 | 51/46 | 9/35 | 9/35 | 100/35 | 100/35 | P1 f28 mot 17->18; P2 f5 st 4->5 |
| gems_drop | 84/87 | 84/87 | 79/83 | 79/83 | 3/3 | 3/3 | 3/25 | 3/25 | P1 f47 st 27->0; P2 f42 mot 16->74 |
| gems_pc | 43/59 | 43/59 | 43/61 | 43/61 | 25/27 | 25/27 | 100/15 | 100/15 | P1 f11 st 23->0; P2 f280 st 0->27 |
| hits_down | 100/87 | 100/87 | 94/80 | 94/80 | 39/16 | 39/16 | 100/38 | 100/38 | P1 f25 x -25.0->-26.01; P2 f28 st 27->0 |
| items_londo | 99/47 | 99/47 | 98/48 | 98/48 | 3/53 | 3/53 | 100/27 | 100/27 | P1 f11 x -379.5->-385.35; P2 f117 st 0->15 |
| items_weapon | 96/89 | 96/89 | 60/90 | 60/90 | 94/60 | 94/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 |
| ledge_londo | - | 99/100 | - | 99/100 | - | 4/100 | - | 100/100 | P1 f11 st 0->14 |
| mash_s11_ryoma_falcon | 32/33 | 48/29 | 7/9 | 11/9 | 1/3 | 1/3 | 4/18 | 4/18 | P1 f12 st 10->31; P2 f39 st 10->0 |
| mash_s22_jack_wangtang | 40/33 | 47/33 | 13/10 | 12/10 | 1/1 | 1/2 | 20/2 | 22/2 | P1 f12 st 7->31; P2 f0 y 0.0->100.0 |
| mash_s33_rouge_ayame | 38/50 | 42/51 | 14/17 | 15/18 | 1/2 | 1/2 | 1/77 | 1/77 | P1 f12 st 10->31; P2 f37 st 10->0 |
| mash_s44_gunrock_galuda | 56/32 | 54/31 | 15/7 | 11/6 | 2/1 | 2/1 | 17/2 | 17/2 | P1 f12 st 10->4; P2 f0 x 129.0->167.0 |
| mash_s55_falcon_kraken | 47/40 | 47/38 | 22/13 | 21/10 | 2/1 | 2/1 | 4/7 | 4/7 | P1 f37 z -348.97->-347.49; P2 f12 st 2->31 |
| move_basic | 94/96 | 92/96 | 80/96 | 79/95 | 2/80 | 2/80 | 100/100 | 100/100 | P1 f28 mot 17->18; P2 f6 x -360.15->-366.87 |
| moves_ayame | 70/71 | 70/74 | 70/70 | 70/73 | 27/22 | 27/24 | 100/17 | 100/17 | P1 f27 x 1.84->-17.6; P2 f27 x 63.34->60.0 |
| moves_falcon | 68/66 | 68/61 | 63/64 | 63/60 | 10/15 | 10/15 | 100/1 | 100/1 | P1 f11 z -69.82->-89.0; P2 f11 x -39.2->-57.0 |
| moves_galuda | 69/70 | 69/70 | 68/67 | 68/67 | 43/41 | 43/41 | 100/2 | 100/2 | P1 f23 x -28.0->-34.01; P2 f25 x 64.5->60.0 |
| moves_gunrock | 57/53 | 57/55 | 56/49 | 56/51 | 44/32 | 44/32 | 100/7 | 100/7 | P1 f15 x -42.06->-45.81; P2 f20 x 67.17->60.0 |
| moves_jack | 52/61 | 52/61 | 51/59 | 51/59 | 66/21 | 66/21 | 100/1 | 100/1 | P1 f21 x -14.0->-20.09; P2 f22 x 61.53->60.0 |
| moves_kraken | 69/61 | 68/63 | 68/59 | 68/61 | 28/21 | 28/21 | 100/11 | 100/11 | P1 f28 x -30.88->-38.02; P2 f19 st 27->0 |
| moves_rouge | 60/62 | 59/62 | 59/60 | 59/60 | 40/28 | 40/28 | 100/1 | 100/1 | P1 f17 x -12.19->-17.53; P2 f19 x 64.22->60.0 |
| moves_ryoma | 66/62 | 65/63 | 64/58 | 63/59 | 26/25 | 26/25 | 100/20 | 100/5 | P1 f25 x -25.0->-26.01; P2 f28 st 27->0 |
| moves_valgas | 70/56 | 70/58 | 69/54 | 69/55 | 49/26 | 49/26 | 100/1 | 100/1 | P1 f15 x -30.0->-36.45; P2 f17 x 65.2->60.0 |
| moves_wangtang | 70/67 | 69/70 | 70/65 | 69/67 | 31/19 | 31/19 | 100/5 | 100/5 | P1 f30 x -9.56->-13.32; P2 f21 st 27->0 |
| mv_jump | 89/100 | 88/100 | 88/100 | 87/100 | 49/100 | 49/100 | 100/100 | 100/100 | P1 f15 mot 6->5 |
| mv_run | 91/100 | 82/100 | 90/100 | 81/100 | 19/100 | 19/100 | 100/100 | 100/100 | P1 f28 z -224.9->-222.52 |
| mv_turn | 98/100 | 97/100 | 98/100 | 95/100 | 27/100 | 27/100 | 100/100 | 100/100 | P1 f28 z -224.9->-222.52 |
| near_gunrock | 98/87 | 98/87 | 97/88 | 97/88 | 81/65 | 81/65 | 100/1 | 100/1 | P1 f12 x -40.0->-45.31; P2 f12 x 60.0->65.31 |
| near_ryoma | 99/94 | 99/94 | 98/93 | 98/93 | 42/57 | 42/57 | 100/4 | 100/4 | P1 f19 x -19.94->-26.01; P2 f24 x 61.44->60.0 |
| pole_londo | 66/100 | 66/100 | 64/100 | 64/100 | 5/100 | 5/100 | 100/100 | 100/100 | P1 f14 mot 10->25 |
| pole_londo2 | 89/100 | 89/100 | 89/100 | 89/100 | 2/100 | 2/100 | 100/100 | 100/100 | P1 f11 x -255.87->-216.0 |
| pole_wall | 48/100 | 48/100 | 46/100 | 46/100 | 9/100 | 9/100 | 100/100 | 100/100 | P1 f11 st 0->14 |
| rnd_probe1 | 99/100 | 99/100 | 99/100 | 99/100 | 58/60 | 58/60 | 100/100 | 100/100 | P1 f42 st 10->0; P2 f149 st 27->0 |
| rnd_probe2 | 93/73 | 93/73 | 87/72 | 87/72 | 36/37 | 36/37 | 100/73 | 100/73 | P1 f53 x -25.0->-26.01; P2 f56 st 27->0 |
| stg_00 | 85/75 | 85/75 | 76/58 | 76/58 | 25/10 | 25/9 | 100/72 | 100/72 | P1 f30 z -221.72->-219.09; P2 f20 x -391.37->-393.74 |
| stg_10 | 86/87 | 86/89 | 72/74 | 72/76 | 31/18 | 30/18 | 94/72 | 94/72 | P1 f25 y -3.0->0.0; P2 f28 x -77.91->-76.63 |
| stg_20 | 86/88 | 86/88 | 75/76 | 75/76 | 9/11 | 9/11 | 79/72 | 79/72 | P1 f14 x -177.02->-178.44; P2 f14 x -432.15->-433.57 |
| stg_30 | 87/77 | 88/77 | 77/60 | 78/60 | 28/15 | 28/11 | 79/72 | 79/72 | P1 f56 z -315.0->-318.0; P2 f15 z 130.0->128.5 |
| stg_40 | 84/66 | 81/66 | 71/50 | 70/51 | 20/13 | 9/10 | 77/20 | 77/20 | P1 f14 x 382.15->383.56; P2 f14 x 127.02->128.44 |
| stg_50 | 75/88 | 74/85 | 66/76 | 65/74 | 20/20 | 20/20 | 93/72 | 93/72 | P1 f15 x 427.79->428.85; P2 f28 x 270.74->274.48 |
| stg_60 | 83/81 | 76/76 | 69/61 | 65/59 | 6/5 | 6/6 | 100/72 | 64/72 | P1 f15 z -422.54->-421.18; P2 f14 z -184.02->-182.21 |
| stg_70 | 85/76 | 84/77 | 74/61 | 74/63 | 33/8 | 32/8 | 87/63 | 87/63 | P1 f52 x 349.6->350.89; P2 f15 z -202.18->-200.82 |
| stg_80 | 71/71 | 71/73 | 69/58 | 70/62 | 6/7 | 5/7 | 84/73 | 84/73 | P1 f14 z -425.98->-427.79; P2 f15 z -187.46->-188.82 |
| stg_90 | 74/73 | 72/72 | 66/64 | 65/64 | 10/34 | 10/32 | 77/72 | 77/72 | P1 f15 x -112.21->-111.15; P2 f81 x 649.6->654.51 |
| stg_a0 | 77/22 | 77/22 | 60/29 | 60/29 | 0/0 | 0/0 | 100/72 | 100/72 | P1 f0 x -165.0->1274.97; P2 f0 x -447.0->950.0 |
| timeout | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | P1 f6186 st 21->0; P2 f6186 st 21->0 |

Better on 0fef882: flow_start P1 state 80 > 85% (BUG-59's fall at f307 gone), atk_move P2 80 > 96% / hp 44 > 100%,
mash_s11 P1 32 > 48%, mash_s22 P1 40 > 47%, ledge_londo 99 / 100% (the edge rule), stg_30's step snap (f1229) and stg_20's
(f103) gone. Worse: mv_run P1 91 > 82% (f286: the stop slide on the fountain base, y 52, now drops off it into state 14;
the disc runs 5 more rows and stops on the plaza; positions already 24 cm apart from the base climb), stg_60 P1 83 > 76% /
hp 100 > 64% (f114: a pole catch at (365, 291, 218) where the disc's jump just lands), stg_40 P1 x 20 > 9%. Pole rows:
stg_50 0 > 38, stg_60 34 > 151 (BUG-50 not fixed by "no catch from the ground": the catches are mid-jump). New breakage:
**BUG-64**, after a wall kick the fighter falls through the floor to y -255..-307 and is snapped back 45-95 cm sideways
in one frame (stg_10 f502-506 at z -692.6, 33 cm outside the disc's wall; stg_70 f326-331; stg_80 f482-486).

### Hunt on master 0fef882 (hunt6, stopped at wrap-up after the 66 remaster-look fight runs + 2 classic)
`GAME=<0fef882 snapshot> SEEDS=3 FRAMES=3600 tools/hunt.sh` -> /tmp/ps-fx-cov/hunt6_0fef882. Same 66
runs, re-scored with tools/hunt_rescore.py:
```
66 remaster-look runs (seed 3, 3600 f), 437b5da (hunt5) vs 0fef882 (hunt6), per-run occurrences / distinct, re-scored
fell         437b5da  1076 / 1076   0fef882  1166 / 1166
overlap      437b5da    57 /  27   0fef882    42 /  17
pose_frozen  437b5da    74 /  31   0fef882    61 /  30
stuck_state  437b5da     4 /   4   0fef882    14 /  13
wedged       437b5da    43 /  39   0fef882    44 /  38
wedged_fp    437b5da   344 / 152   0fef882   359 / 172
```
New on 0fef882: fighters below the lowest floor on Jack's, Gunrock's, Galuda's, Kraken's and Valgas's stages too
(stg30 wangtang,jack f1542; stg40 finalvalgas,falcon f1840; stg50 valgas,finalvalgas; stg80 ryoma,wangtang; stg90
wangtang,jack; 437b5da: only Londo, Ryoma's, stga0) = BUG-60; stuck_state 4 > 14: lying (gst 15, k2/144) 360+ frames on
stg50 / stg80 / stga0, in the air (gst 5) 600+ frames on stga0, Falcon / Jack ATTACK k1/012 420+ frames (stg50 falcon,ryoma
f2883; stg80 jack,gunrock f1217) = BUG-61 family. The classic half was not run (stopped for the session end).

Stages on 0fef882 (compare with section 3):
| tape | run ends <=1 / <=10 cm of 16 | median cm | wall kick st38 o/r (k2/206 rows o/r) | ledge hop st17 o/r | pole st34 o/r | one-frame >60 cm moves o/r (remaster: frame P state at x,y,z) | floor gem (orig frame, x,y,z) |
|---|---|---|---|---|---|---|---|
| stg_00 | 0 / 5 | 35.3 | 88/0 (88/338) | 0/0 | 0/35 | 0/1 f1385 P2 st34 65/+36 cm at (-411,69,-251) | 299, [-190.0, 170.0, 720.0] |
| stg_10 | 0 / 1 | 103.5 | 80/0 (80/414) | 23/0 | 0/0 | 0/3 f506 P1 st5 59/+312 cm at (376,5,-635); f603 P1 st31 10/+761 cm at (662,729,193); f1234 P2 st31 3/+755 cm at (-290,755,-655) | 299, [-317.0, 50.0, 97.0] |
| stg_20 | 0 / 6 | 38.6 | 112/0 (112/445) | 0/0 | 0/38 | 0/0  | 299, [-400.0, 50.0, -50.0] |
| stg_30 | 0 / 7 | 27.9 | 128/0 (128/544) | 26/0 | 0/0 | 0/0  | 299, [200.0, 50.0, 400.0] |
| stg_40 | 0 / 2 | 52.5 | 104/0 (104/446) | 88/0 | 0/35 | 0/2 f872 P2 st31 65/+50 cm at (158,50,-134); f1420 P1 st34 62/+36 cm at (-5,51,285) | 299, [400.0, 50.0, -530.0] |
| stg_50 | 0 / 3 | 147.5 | 112/0 (112/329) | 140/0 | 0/38 | 1/2 f456 P2 st34 63/+36 cm at (-112,190,-177); f458 P2 st34 62/+29 cm at (-135,252,-242) | 299, [450.0, 50.0, 300.0] |
| stg_60 | 0 / 1 | 55.5 | 72/0 (72/324) | 26/0 | 0/151 | 0/5 f127 P1 st34 95/+36 cm at (434,327,214); f237 P1 st31 105/+33 cm at (-456,33,-110); f238 P1 st31 0/+87 cm at (-456,120,-110) | 299, [590.0, 170.0, -120.0] |
| stg_70 | 0 / 2 | 121.4 | 72/0 (72/494) | 60/0 | 0/44 | 2/8 f247 P1 st31 69/+65 cm at (-407,65,-178); f331 P2 st5 96/+417 cm at (413,130,-437); f501 P2 st5 104/+460 cm at (83,190,199) | 299, [280.0, 50.0, 60.0] |
| stg_80 | 0 / 2 | 106.4 | 72/0 (72/348) | 30/0 | 0/41 | 0/5 f486 P2 st5 180/+260 cm at (-23,5,32); f669 P1 st5 118/+375 cm at (401,105,-636); f986 P2 st5 79/+284 cm at (450,2,-269) | 299, [320.0, 50.0, -200.0] |
| stg_90 | 0 / 5 | 21.7 | 128/0 (128/484) | 82/0 | 0/0 | 0/1 f607 P1 st5 0/+100 cm at (-513,101,388) | 299, [200.0, 50.0, -300.0] |
| stg_a0 | 0 / 0 | None | 112/0 (112/238) | 98/0 | 0/0 | 0/0  | 299, [-14.1, 150.0, 414.1] |

## Requests for the lead (fighter.gd / arena.gd are not this lane's; what, why, evidence)
1. Per-fighter run / moving-jump / gravity / rise constants (BUG-56, 57): the table in section 6 (modes of 1,000-2,600 rows
   per fighter); today every fighter uses Ryoma's 9.5 / 9.75 / 2.0 / 35.5.
2. Wall kick = state 38 for k2/206's 8 rows, then state 5 k0/13 (BUG-47: stg_30 f117 P1 / P2, 72-128 rows per stage tape).
3. Vault state 17 k0/48 6 > k0/57 9 (+100 cm in one row, 12 cm/f) > k0/58 8 > k0/24 (BUG-48: stg_10 P1 f709-732) and the
   ledge hang state 36 k2/207 19 rows > k1/162 > 163 (BUG-63: mash_s22 P2 f482).
4. Input priority on one frame: attack beats jump (BUG-54, mash_s44 f12); B with nothing in reach = the fighter's attack
   (BUG-53, mash_s11 / s33 f12).
5. Body push on the overlap frame to the radii sum, no push at 100 cm for Gunrock-Falcon (BUG-45: dist_galuda f11,
   near_gunrock f12).
6. Turn arc state 7 k0/41 21 rows (BUG-58: mash_s22 P1 f12-33, velocity + facing per row in o_mash_s22_jack_wangtang.jsonl).
7. Jump row count: k0/6 from the first air row (BUG-55: mv_jump f15, lands f51).
8. core_ground: no one-frame lift onto Ryoma's 7.3-7.6 m wall tops (BUG-51: stg_10 f603, f1234), no 64-91 cm step snaps
   (BUG-52), walls 4.6 cm in (BUG-49).
9. Gems (BUG-43, 44) and items / chests (BUG-46): numbers in section 7 and table 3; the item object layout in covlog.py.
10. Harness: hunt.gd's `wedged` test should use the core's ground state instead of is_on_floor() (721 false positives).

## 9. Re-run on master 2f8da7d (fx-cov2, 10-27 06:00; wave 4's measuring stick)
All 79 tapes (the 52 of section 8 + fx-pc's 10 pc_*, fx-item's items_id* / fxitem_*), remaster runs from this branch
(= 2f8da7d + the test-harness fixes of a5dfbc5, no game change): `FID_OUT=dumps/fidelity/cov2 tools/fidelity_run.py rem
-j 2 TAPE...` + `diff`; tables by /tmp/ps-fx-cov2/delta.py (`full` / delta), `tools/cov_stages.py`.
Godot lines: only the exit leaks (41 of 79 runs: BUG-38, a harness artifact, fixed in a5dfbc5), no script errors.
1 of 79 passes (timeout). The first divergence of every hit tape is now the hit's own frame (BUG-66), of every PC tape
the world freeze (BUG-65); body push (BUG-45), the Ryoma's-stage wall tops (BUG-51) and the wall-kick fall (BUG-64)
are gone by tape.

### Every tape on 2f8da7d
| tape | frames o/r | st % | mot % | fr % | x % | y % | z % | hp % | gems % | first divergence | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| atk_ground | 1258/1259 | 82/61 | 72/48 | 22/8 | 20/31 | 89/68 | 80/44 | 89/14 | 89/100 | P1 f29 x -17.73->-12.94; P2 f28 st 27->0 | FAIL |
| atk_move | 849/850 | 96/97 | 96/92 | 18/4 | 55/89 | 77/91 | 76/100 | 100/100 | 100/100 | P1 f23 x -368.0->-373.89; P2 f373 x 57.5->60.0 | FAIL |
| chain_ryoma | 3568/3569 | 98/100 | 97/100 | 40/2 | 19/100 | 100/100 | 25/100 | 100/100 | 100/100 | P1 f42 st 10->0 | FAIL |
| dist_galuda | 2230/2231 | 91/65 | 87/62 | 24/4 | 76/59 | 100/90 | 100/86 | 100/3 | 100/5 | P1 f25 x 26.5->24.25; P2 f25 x 104.5->102.25 | FAIL |
| dist_gunrock | 2230/2231 | 95/65 | 88/65 | 27/4 | 76/59 | 100/93 | 76/68 | 100/1 | 100/1 | P1 f20 x 32.67->28.91; P2 f20 x 105.58->102.17 | FAIL |
| dist_jack | 2230/2231 | 96/65 | 91/63 | 28/3 | 77/59 | 100/84 | 100/78 | 100/1 | 100/1 | P1 f23 x 43.97->39.96; P2 f23 x 108.03->104.01 | FAIL |
| dist_ryoma | 2230/2231 | 96/51 | 93/44 | 29/9 | 53/40 | 100/58 | 100/52 | 100/14 | 100/100 | P1 f29 x 22.35->29.81; P2 f28 st 27->0 | FAIL |
| flow_start | 360/361 | 82/49 | 44/47 | 10/1 | 11/35 | 84/7 | 12/35 | 100/35 | 100/35 | P1 f28 mot 17->18; P2 f5 st 4->5 | FAIL |
| fxitem_id10 | 1645/1646 | 96/90 | 92/90 | 14/0 | 64/60 | 100/67 | 65/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| fxitem_id3 | 1645/1646 | 91/91 | 64/91 | 10/0 | 65/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| fxitem_id5 | 1645/1646 | 91/91 | 60/91 | 10/0 | 65/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| fxitem_id8 | 1645/1646 | 96/91 | 92/92 | 14/0 | 64/60 | 100/67 | 65/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| fxitem_id9 | 1645/1646 | 88/90 | 84/90 | 11/0 | 64/60 | 95/67 | 64/60 | 68/67 | 68/92 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| fxitem_shot0 | 1314/1315 | 94/87 | 76/88 | 6/0 | 80/75 | 100/84 | 80/75 | 100/84 | 89/85 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| fxitem_shot2 | 1314/1315 | 95/89 | 76/90 | 6/0 | 80/75 | 100/84 | 80/75 | 100/84 | 100/84 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| gems_drop | 1884/1885 | 90/87 | 85/83 | 5/1 | 4/4 | 40/26 | 20/4 | 3/25 | 98/26 | P1 f47 st 27->0; P2 f42 mot 16->74 | FAIL |
| gems_pc | 2136/2137 | 99/56 | 96/56 | 47/1 | 27/28 | 71/78 | 28/28 | 100/14 | 99/100 | P1 f279 x -98.09->-100.01; P2 f288 st 27->0 | FAIL |
| hits_down | 1202/1203 | 86/76 | 67/65 | 10/22 | 27/45 | 100/60 | 90/44 | 100/33 | 100/95 | P1 f29 x -17.73->-12.94; P2 f28 st 27->0 | FAIL |
| items_id0 | 1645/1646 | 94/84 | 75/85 | 14/0 | 64/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id10 | 1645/1646 | 94/84 | 75/85 | 14/0 | 64/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id2 | 1645/1646 | 94/84 | 75/85 | 14/0 | 64/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id3 | 1645/1646 | 96/89 | 60/90 | 19/0 | 64/60 | 100/72 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id4 | 1645/1646 | 91/91 | 64/91 | 10/0 | 65/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id5 | 1645/1646 | 96/89 | 60/90 | 19/0 | 64/60 | 100/72 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id6 | 1645/1646 | 91/90 | 78/90 | 12/4 | 64/60 | 100/68 | 64/60 | 100/67 | 71/68 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id7 | 1645/1646 | 96/91 | 92/92 | 14/0 | 64/60 | 100/67 | 65/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id8 | 1645/1646 | 94/84 | 75/85 | 14/0 | 64/60 | 100/67 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_id9 | 1645/1646 | 91/90 | 78/90 | 12/4 | 64/60 | 100/68 | 64/60 | 100/67 | 71/68 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| items_londo | 430/431 | 99/48 | 98/48 | 25/3 | 44/53 | 100/76 | 100/53 | 100/68 | 40/28 | P1 f173 gems 2->1; P2 f118 st 27->15 | FAIL |
| items_weapon | 1645/1646 | 96/89 | 60/90 | 19/0 | 64/60 | 100/72 | 64/60 | 100/67 | 100/67 | P1 f987 st 35->0; P2 f986 x 31.94->20.0 | FAIL |
| ledge_londo | 550/551 | 99/100 | 99/100 | 3/0 | 17/100 | 52/100 | 6/100 | 100/100 | 81/100 | P1 f11 st 0->14 | FAIL |
| mash_s11_ryoma_falcon | 1578/1579 | 48/37 | 13/8 | 24/23 | 1/2 | 46/65 | 1/2 | 1/2 | 6/63 | P1 f12 st 10->31; P2 f33 st 10->27 | FAIL |
| mash_s22_jack_wangtang | 1575/1576 | 39/37 | 14/13 | 18/25 | 1/1 | 24/23 | 1/0 | 8/2 | 75/7 | P1 f12 st 7->31; P2 f0 y 0.0->100.0 | FAIL |
| mash_s33_rouge_ayame | 1572/1573 | 40/38 | 14/24 | 24/23 | 1/2 | 52/52 | 1/4 | 1/21 | 57/72 | P1 f12 st 10->31; P2 f37 st 10->0 | FAIL |
| mash_s44_gunrock_galuda | 1571/1572 | 56/34 | 17/15 | 16/20 | 2/2 | 86/22 | 2/2 | 1/2 | 98/12 | P1 f20 st 10->27; P2 f0 x 129.0->167.0 | FAIL |
| mash_s55_falcon_kraken | 1577/1578 | 58/28 | 24/9 | 21/11 | 3/1 | 34/38 | 6/2 | 4/7 | 67/70 | P1 f37 z -348.97->-347.59; P2 f12 st 2->31 | FAIL |
| move_basic | 1498/1499 | 90/96 | 77/96 | 7/0 | 3/6 | 51/97 | 4/84 | 100/100 | 100/100 | P1 f28 mot 17->18; P2 f16 x -393.05->-397.1 | FAIL |
| moves_ayame | 3516/3517 | 84/71 | 84/71 | 26/7 | 30/34 | 65/88 | 80/72 | 100/17 | 81/68 | P1 f27 x 1.84->0.17; P2 f27 x 63.34->61.67 | FAIL |
| moves_falcon | 3516/3517 | 73/62 | 68/61 | 22/4 | 10/17 | 43/44 | 0/0 | 100/1 | 73/68 | P1 f11 z -69.82->-89.0; P2 f0 x -93.66->-141.0 | FAIL |
| moves_galuda | 3516/3517 | 89/68 | 88/64 | 25/2 | 61/28 | 86/90 | 71/66 | 100/2 | 86/60 | P1 f25 x -13.5->-15.75; P2 f25 x 64.5->62.25 | FAIL |
| moves_gunrock | 3516/3517 | 88/49 | 86/46 | 29/1 | 67/31 | 32/83 | 83/54 | 100/1 | 89/40 | P1 f20 x -8.92->-12.51; P2 f20 x 67.17->63.59 | FAIL |
| moves_jack | 3516/3517 | 83/60 | 82/56 | 31/5 | 66/22 | 73/84 | 90/70 | 100/1 | 89/1 | P1 f23 x 3.98->-0.03; P2 f23 x 68.03->64.01 | FAIL |
| moves_kraken | 3516/3517 | 68/59 | 65/56 | 18/3 | 42/30 | 72/85 | 52/38 | 100/8 | 69/80 | P1 f20 x -39.0->-30.88; P2 f19 st 27->0 | FAIL |
| moves_rouge | 3516/3517 | 85/54 | 83/52 | 28/2 | 41/31 | 71/82 | 58/51 | 100/1 | 88/71 | P1 f19 x 2.72->0.61; P2 f19 x 64.22->62.11 | FAIL |
| moves_ryoma | 3516/3517 | 78/56 | 76/52 | 23/4 | 26/32 | 88/77 | 43/34 | 100/5 | 77/82 | P1 f29 x -17.73->-12.94; P2 f28 st 27->0 | FAIL |
| moves_valgas | 3516/3517 | 82/53 | 81/49 | 17/4 | 56/31 | 87/85 | 77/49 | 100/1 | 84/30 | P1 f17 x -15.2->-17.8; P2 f17 x 65.2->62.6 | FAIL |
| moves_wangtang | 3516/3517 | 83/62 | 82/59 | 26/6 | 44/33 | 72/82 | 80/48 | 100/5 | 75/81 | P1 f22 x -13.56->-9.56; P2 f21 st 27->0 | FAIL |
| mv_jump | 723/724 | 90/100 | 90/100 | 9/0 | 56/100 | 66/100 | 56/100 | 100/100 | 100/100 | P1 f107 z -224.9->-222.52 | FAIL |
| mv_run | 627/628 | 82/100 | 82/100 | 2/0 | 19/100 | 89/100 | 18/100 | 100/100 | 100/100 | P1 f28 z -224.9->-222.52 | FAIL |
| mv_turn | 658/659 | 97/100 | 97/100 | 4/0 | 86/100 | 94/100 | 86/100 | 100/100 | 100/100 | P1 f28 z -224.9->-222.52 | FAIL |
| near_gunrock | 4346/4347 | 99/89 | 98/90 | 10/2 | 87/64 | 100/98 | 88/88 | 100/1 | 100/1 | P1 f20 x 3.0->-0.8; P2 f20 x 75.25->71.88 | FAIL |
| near_ryoma | 4346/4347 | 99/94 | 98/93 | 12/4 | 44/79 | 100/96 | 100/88 | 100/4 | 100/100 | P1 f29 x -7.65->-0.19; P2 f28 st 27->0 | FAIL |
| pc_ayame | 5396/5397 | 91/85 | 91/86 | 19/0 | 69/62 | 76/98 | 100/85 | 100/6 | 96/36 | P1 f344 x -121.73->-124.31; P2 f303 st 27->0 | FAIL |
| pc_falcon | 5396/5397 | 92/84 | 92/84 | 25/3 | 0/0 | 72/61 | 0/0 | 100/5 | 47/76 | P1 f11 x -266.21->-297.0; P2 f11 x -39.2->-57.0 | FAIL |
| pc_galuda | 5396/5397 | 99/95 | 99/95 | 20/3 | 74/63 | 91/97 | 82/72 | 100/6 | 100/100 | P1 f547 y 219.0->225.0; P2 f307 st 27->0 | FAIL |
| pc_gunrock | 5396/5397 | 100/81 | 100/82 | 27/2 | 100/64 | 4/96 | 100/68 | 100/6 | 100/36 | P1 f79 y 172.0->183.0; P2 f310 st 27->0 | FAIL |
| pc_jack | 5396/5397 | 99/96 | 99/96 | 23/1 | 100/72 | 81/100 | 100/100 | 100/5 | 100/36 | P1 f354 st 0->11; P2 f293 st 27->0 | FAIL |
| pc_kraken | 5396/5397 | 86/79 | 86/80 | 19/1 | 37/14 | 81/93 | 32/14 | 100/55 | 43/100 | P1 f556 mot 96->98; P2 f313 st 27->0 | FAIL |
| pc_rouge | 5396/5397 | 99/88 | 99/88 | 21/1 | 100/72 | 80/94 | 100/72 | 100/6 | 100/100 | P1 f506 y 73.0->80.0; P2 f311 st 27->0 | FAIL |
| pc_ryoma | 5396/5397 | 100/86 | 100/87 | 25/1 | 100/66 | 100/94 | 100/66 | 100/10 | 100/100 | P1 f5132 st 0->23; P2 f515 st 27->0 | FAIL |
| pc_valgas | 5396/5397 | 100/91 | 98/92 | 25/3 | 80/62 | 98/98 | 80/66 | 100/6 | 100/52 | P1 f758 mot 97->101; P2 f296 st 27->0 | FAIL |
| pc_wangtang | 5396/5397 | 100/95 | 100/96 | 22/1 | 71/62 | 81/98 | 100/92 | 100/6 | 100/36 | P1 f587 st 0->11; P2 f298 st 27->0 | FAIL |
| pole_londo | 627/628 | 96/100 | 96/100 | 10/0 | 37/100 | 73/100 | 39/100 | 100/100 | 100/100 | P1 f14 x -363.72->-370.43 | FAIL |
| pole_londo2 | 642/643 | 100/100 | 100/100 | 11/0 | 48/100 | 78/100 | 14/100 | 100/100 | 100/100 | P1 f11 x -255.87->-216.0 | FAIL |
| pole_wall | 348/349 | 85/100 | 83/100 | 5/0 | 9/100 | 54/100 | 11/100 | 100/100 | 100/100 | P1 f11 st 0->14 | FAIL |
| rnd_probe1 | 252/253 | 99/100 | 99/100 | 40/19 | 60/88 | 100/73 | 100/60 | 100/100 | 100/100 | P1 f42 st 10->0; P2 f149 st 27->0 | FAIL |
| rnd_probe2 | 548/549 | 93/73 | 87/72 | 32/7 | 76/53 | 100/76 | 100/81 | 100/73 | 100/100 | P1 f57 x -15.5->-12.94; P2 f56 st 27->0 | FAIL |
| stg_00 | 2340/2341 | 77/77 | 70/66 | 4/2 | 34/28 | 81/73 | 36/20 | 100/73 | 100/98 | P1 f30 z -221.72->-219.09; P2 f20 x -391.37->-393.74 | FAIL |
| stg_10 | 2340/2341 | 86/85 | 77/76 | 3/5 | 34/20 | 72/63 | 33/40 | 84/73 | 100/98 | P1 f25 y -3.0->0.0; P2 f28 x -77.91->-76.63 | FAIL |
| stg_20 | 2340/2341 | 87/82 | 77/71 | 4/7 | 49/31 | 67/61 | 54/38 | 79/72 | 100/100 | P1 f74 x -537.65->-536.28; P2 f49 x -177.3->-179.71 | FAIL |
| stg_30 | 2340/2341 | 76/80 | 66/60 | 2/9 | 42/21 | 78/70 | 48/43 | 79/72 | 79/100 | P1 f56 z -315.0->-318.0; P2 f117 st 38->5 | FAIL |
| stg_40 | 2340/2341 | 80/66 | 71/52 | 4/2 | 29/12 | 78/75 | 32/18 | 77/20 | 38/79 | P1 f61 x 38.67->33.19; P2 f81 x 529.72->527.72 | FAIL |
| stg_50 | 2340/2341 | 79/73 | 73/64 | 3/1 | 25/20 | 74/72 | 25/20 | 77/72 | 53/83 | P1 f74 x 10.59->17.66; P2 f28 x 270.74->274.48 | FAIL |
| stg_60 | 2340/2341 | 85/81 | 74/62 | 3/4 | 28/36 | 78/70 | 36/29 | 100/72 | 100/29 | P1 f41 x 131.25->132.5; P2 f41 y 0.0->11.0 | FAIL |
| stg_70 | 2340/2341 | 85/86 | 79/76 | 4/5 | 32/21 | 81/70 | 31/23 | 87/72 | 100/98 | P1 f52 x 349.6->350.89; P2 f77 z -762.0->-758.1 | FAIL |
| stg_80 | 2340/2341 | 72/75 | 72/68 | 5/3 | 29/15 | 79/61 | 27/17 | 84/73 | 84/98 | P1 f53 x 185.62->187.27; P2 f42 x -390.0->-387.6 | FAIL |
| stg_90 | 2340/2341 | 73/66 | 64/57 | 3/2 | 19/41 | 77/74 | 16/31 | 77/72 | 100/44 | P1 f61 x -437.48->-436.31; P2 f102 z 509.04->516.64 | FAIL |
| stg_a0 | 2340/2341 | 72/22 | 58/29 | 5/0 | 0/0 | 10/0 | 0/0 | 100/72 | 100/0 | P1 f0 x -165.0->1274.97; P2 f0 x -447.0->950.0 | FAIL |
| timeout | 7200/7201 | 100/100 | 100/100 | 3/2 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | P1 f6186 st 21->0; P2 f6186 st 21->0 | PASS |

### Before (0fef882, section 8) -> 2f8da7d (st / mot / x / hp match %, P1/P2; "-" = no earlier remaster run)
| tape | before st P1/P2 | 2f8da7d st | before mot | 2f8da7d mot | before x | 2f8da7d x | before hp | 2f8da7d hp |
|---|---|---|---|---|---|---|---|---|
| atk_ground | 82/61 | 82/61 | 72/48 | 72/48 | 17/5 | 20/31 | 89/14 | 89/14 |
| atk_move | 96/96 | 96/97 | 95/91 | 96/92 | 19/58 | 55/89 | 100/100 | 100/100 |
| chain_ryoma | 98/100 | 98/100 | 97/100 | 97/100 | 19/100 | 19/100 | 100/100 | 100/100 |
| dist_galuda | 91/66 | 91/65 | 89/63 | 87/62 | 66/36 | 76/59 | 100/3 | 100/3 |
| dist_gunrock | 96/62 | 95/65 | 92/60 | 88/65 | 59/35 | 76/59 | 100/14 | 100/1 |
| dist_jack | 97/70 | 96/65 | 93/68 | 91/63 | 71/52 | 77/59 | 100/1 | 100/1 |
| dist_ryoma | 96/59 | 96/51 | 93/55 | 93/44 | 37/25 | 53/40 | 100/14 | 100/14 |
| flow_start | 85/49 | 82/49 | 51/46 | 44/47 | 9/35 | 11/35 | 100/35 | 100/35 |
| fxitem_id10 | - | 96/90 | - | 92/90 | - | 64/60 | - | 100/67 |
| fxitem_id3 | - | 91/91 | - | 64/91 | - | 65/60 | - | 100/67 |
| fxitem_id5 | - | 91/91 | - | 60/91 | - | 65/60 | - | 100/67 |
| fxitem_id8 | - | 96/91 | - | 92/92 | - | 64/60 | - | 100/67 |
| fxitem_id9 | - | 88/90 | - | 84/90 | - | 64/60 | - | 68/67 |
| fxitem_shot0 | - | 94/87 | - | 76/88 | - | 80/75 | - | 100/84 |
| fxitem_shot2 | - | 95/89 | - | 76/90 | - | 80/75 | - | 100/84 |
| gems_drop | 84/87 | 90/87 | 79/83 | 85/83 | 3/3 | 4/4 | 3/25 | 3/25 |
| gems_pc | 43/59 | 99/56 | 43/61 | 96/56 | 25/27 | 27/28 | 100/15 | 100/14 |
| hits_down | 100/87 | 86/76 | 94/80 | 67/65 | 39/16 | 27/45 | 100/38 | 100/33 |
| items_id0 | - | 94/84 | - | 75/85 | - | 64/60 | - | 100/67 |
| items_id10 | - | 94/84 | - | 75/85 | - | 64/60 | - | 100/67 |
| items_id2 | - | 94/84 | - | 75/85 | - | 64/60 | - | 100/67 |
| items_id3 | - | 96/89 | - | 60/90 | - | 64/60 | - | 100/67 |
| items_id4 | - | 91/91 | - | 64/91 | - | 65/60 | - | 100/67 |
| items_id5 | - | 96/89 | - | 60/90 | - | 64/60 | - | 100/67 |
| items_id6 | - | 91/90 | - | 78/90 | - | 64/60 | - | 100/67 |
| items_id7 | - | 96/91 | - | 92/92 | - | 64/60 | - | 100/67 |
| items_id8 | - | 94/84 | - | 75/85 | - | 64/60 | - | 100/67 |
| items_id9 | - | 91/90 | - | 78/90 | - | 64/60 | - | 100/67 |
| items_londo | 99/47 | 99/48 | 98/48 | 98/48 | 3/53 | 44/53 | 100/27 | 100/68 |
| items_weapon | 96/89 | 96/89 | 60/90 | 60/90 | 94/60 | 64/60 | 100/67 | 100/67 |
| ledge_londo | 99/100 | 99/100 | 99/100 | 99/100 | 4/100 | 17/100 | 100/100 | 100/100 |
| mash_s11_ryoma_falcon | 48/29 | 48/37 | 11/9 | 13/8 | 1/3 | 1/2 | 4/18 | 1/2 |
| mash_s22_jack_wangtang | 47/33 | 39/37 | 12/10 | 14/13 | 1/2 | 1/1 | 22/2 | 8/2 |
| mash_s33_rouge_ayame | 42/51 | 40/38 | 15/18 | 14/24 | 1/2 | 1/2 | 1/77 | 1/21 |
| mash_s44_gunrock_galuda | 54/31 | 56/34 | 11/6 | 17/15 | 2/1 | 2/2 | 17/2 | 1/2 |
| mash_s55_falcon_kraken | 47/38 | 58/28 | 21/10 | 24/9 | 2/1 | 3/1 | 4/7 | 4/7 |
| move_basic | 92/96 | 90/96 | 79/95 | 77/96 | 2/80 | 3/6 | 100/100 | 100/100 |
| moves_ayame | 70/74 | 84/71 | 70/73 | 84/71 | 27/24 | 30/34 | 100/17 | 100/17 |
| moves_falcon | 68/61 | 73/62 | 63/60 | 68/61 | 10/15 | 10/17 | 100/1 | 100/1 |
| moves_galuda | 69/70 | 89/68 | 68/67 | 88/64 | 43/41 | 61/28 | 100/2 | 100/2 |
| moves_gunrock | 57/55 | 88/49 | 56/51 | 86/46 | 44/32 | 67/31 | 100/7 | 100/1 |
| moves_jack | 52/61 | 83/60 | 51/59 | 82/56 | 66/21 | 66/22 | 100/1 | 100/1 |
| moves_kraken | 68/63 | 68/59 | 68/61 | 65/56 | 28/21 | 42/30 | 100/11 | 100/8 |
| moves_rouge | 59/62 | 85/54 | 59/60 | 83/52 | 40/28 | 41/31 | 100/1 | 100/1 |
| moves_ryoma | 65/63 | 78/56 | 63/59 | 76/52 | 26/25 | 26/32 | 100/5 | 100/5 |
| moves_valgas | 70/58 | 82/53 | 69/55 | 81/49 | 49/26 | 56/31 | 100/1 | 100/1 |
| moves_wangtang | 69/70 | 83/62 | 69/67 | 82/59 | 31/19 | 44/33 | 100/5 | 100/5 |
| mv_jump | 88/100 | 90/100 | 87/100 | 90/100 | 49/100 | 56/100 | 100/100 | 100/100 |
| mv_run | 82/100 | 82/100 | 81/100 | 82/100 | 19/100 | 19/100 | 100/100 | 100/100 |
| mv_turn | 97/100 | 97/100 | 95/100 | 97/100 | 27/100 | 86/100 | 100/100 | 100/100 |
| near_gunrock | 98/87 | 99/89 | 97/88 | 98/90 | 81/65 | 87/64 | 100/1 | 100/1 |
| near_ryoma | 99/94 | 99/94 | 98/93 | 98/93 | 42/57 | 44/79 | 100/4 | 100/4 |
| pc_ayame | - | 91/85 | - | 91/86 | - | 69/62 | - | 100/6 |
| pc_falcon | - | 92/84 | - | 92/84 | - | 0/0 | - | 100/5 |
| pc_galuda | - | 99/95 | - | 99/95 | - | 74/63 | - | 100/6 |
| pc_gunrock | - | 100/81 | - | 100/82 | - | 100/64 | - | 100/6 |
| pc_jack | - | 99/96 | - | 99/96 | - | 100/72 | - | 100/5 |
| pc_kraken | - | 86/79 | - | 86/80 | - | 37/14 | - | 100/55 |
| pc_rouge | - | 99/88 | - | 99/88 | - | 100/72 | - | 100/6 |
| pc_ryoma | - | 100/86 | - | 100/87 | - | 100/66 | - | 100/10 |
| pc_valgas | - | 100/91 | - | 98/92 | - | 80/62 | - | 100/6 |
| pc_wangtang | - | 100/95 | - | 100/96 | - | 71/62 | - | 100/6 |
| pole_londo | 66/100 | 96/100 | 64/100 | 96/100 | 5/100 | 37/100 | 100/100 | 100/100 |
| pole_londo2 | 89/100 | 100/100 | 89/100 | 100/100 | 2/100 | 48/100 | 100/100 | 100/100 |
| pole_wall | 48/100 | 85/100 | 46/100 | 83/100 | 9/100 | 9/100 | 100/100 | 100/100 |
| rnd_probe1 | 99/100 | 99/100 | 99/100 | 99/100 | 58/60 | 60/88 | 100/100 | 100/100 |
| rnd_probe2 | 93/73 | 93/73 | 87/72 | 87/72 | 36/37 | 76/53 | 100/73 | 100/73 |
| stg_00 | 85/75 | 77/77 | 76/58 | 70/66 | 25/9 | 34/28 | 100/72 | 100/73 |
| stg_10 | 86/89 | 86/85 | 72/76 | 77/76 | 30/18 | 34/20 | 94/72 | 84/73 |
| stg_20 | 86/88 | 87/82 | 75/76 | 77/71 | 9/11 | 49/31 | 79/72 | 79/72 |
| stg_30 | 88/77 | 76/80 | 78/60 | 66/60 | 28/11 | 42/21 | 79/72 | 79/72 |
| stg_40 | 81/66 | 80/66 | 70/51 | 71/52 | 9/10 | 29/12 | 77/20 | 77/20 |
| stg_50 | 74/85 | 79/73 | 65/74 | 73/64 | 20/20 | 25/20 | 93/72 | 77/72 |
| stg_60 | 76/76 | 85/81 | 65/59 | 74/62 | 6/6 | 28/36 | 64/72 | 100/72 |
| stg_70 | 84/77 | 85/86 | 74/63 | 79/76 | 32/8 | 32/21 | 87/63 | 87/72 |
| stg_80 | 71/73 | 72/75 | 70/62 | 72/68 | 5/7 | 29/15 | 84/73 | 84/73 |
| stg_90 | 72/72 | 73/66 | 65/64 | 64/57 | 10/32 | 19/41 | 77/72 | 77/72 |
| stg_a0 | 77/22 | 72/22 | 60/29 | 58/29 | 0/0 | 0/0 | 100/72 | 100/72 |
| timeout | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 | 100/100 |

Better: moves_* P1 state +5..+31 points (per-fighter run / jump table, wall kicks, chains), pole_* (no false catches),
gems_pc P1 43 -> 99%, stage tapes' floor gem (stg_00 / 10 / 20 / 70), items_londo P2 hp 27 -> 68%, atk_move / mv_turn /
rnd_probe x. Worse: hits_down P1 100 -> 86% (Ryoma's near punch k1/74 one row shorter: ends f80, disc f81), stg_00 P1
85 -> 77%, stg_30 P1 88 -> 76% (f61), stg_50 P2 85 -> 73%, dist_ryoma P2 59 -> 51%, mash_s33 P2 51 -> 38%,
move_basic P2 x 80 -> 6% (the first divergence moved LATER, f6 -> f16: the disc slides along an edge at x -393 that the
remaster passes by 4 cm, and the cascade never re-converges).

### Stages on 2f8da7d (compare sections 3 and 8)
| tape | run ends <=1 / <=10 cm of 16 | median cm | wall kick st38 o/r (k2/206 rows o/r) | ledge hop st17 o/r | pole st34 o/r | one-frame >60 cm moves o/r (remaster: frame P state at x,y,z) | floor gem (orig frame, x,y,z) |
|---|---|---|---|---|---|---|---|
| stg_00 | 3 / 5 | 32.8 | 88/0 (88/0) | 0/0 | 0/0 | 0/0  | 299, [-190.0, 170.0, 720.0] |
| stg_10 | 0 / 2 | 62.2 | 80/56 (80/56) | 23/0 | 0/0 | 0/0  | 299, [-317.0, 50.0, 97.0] |
| stg_20 | 5 / 6 | 16.2 | 112/8 (112/8) | 0/0 | 0/0 | 0/1 f99 P2 st31 50/+100 cm at (126,150,-358) | 299, [-400.0, 50.0, -50.0] |
| stg_30 | 4 / 6 | 27.5 | 128/0 (128/0) | 26/0 | 0/0 | 0/1 f1226 P1 st31 62/+30 cm at (-242,30,-235) | 299, [200.0, 50.0, 400.0] |
| stg_40 | 2 / 4 | 27.1 | 104/8 (104/8) | 88/0 | 0/0 | 0/0  | 299, [400.0, 50.0, -530.0] |
| stg_50 | 0 / 3 | 89.2 | 112/16 (112/16) | 140/0 | 0/0 | 1/0  | 299, [450.0, 50.0, 300.0] |
| stg_60 | 2 / 5 | 56.6 | 72/0 (72/0) | 26/0 | 0/0 | 0/1 f239 P1 st31 60/+33 cm at (-395,33,-135) | 299, [590.0, 170.0, -120.0] |
| stg_70 | 0 / 3 | 141.8 | 72/32 (72/32) | 60/0 | 0/0 | 2/5 f96 P2 st31 4/+65 cm at (-405,65,-758); f247 P1 st31 73/+65 cm at (-411,65,-178); f556 P2 st31 10/+65 cm at (-398,65,-23) | 299, [280.0, 50.0, 60.0] |
| stg_80 | 0 / 1 | 72.9 | 72/40 (72/40) | 30/0 | 0/0 | 0/0  | 299, [320.0, 50.0, -200.0] |
| stg_90 | 1 / 5 | 18.8 | 128/0 (128/0) | 82/0 | 0/0 | 0/1 f607 P1 st5 0/+100 cm at (-516,101,392) | 299, [200.0, 50.0, -300.0] |
| stg_a0 | 0 / 0 | None | 112/0 (112/0) | 98/0 | 0/0 | 0/0  | 299, [-14.1, 150.0, 414.1] |

### Frames per state id, all 78 comparable tapes (stg_a0 excluded), original frames (tapes) / remaster
| state | original | remaster |
|---|---|---|
| 0 | 243476 (78) | 266795 (78) |
| 2 | 528 (36) | 37 (12) |
| 4 | 365 (40) | 312 (40) |
| 5 | 14884 (45) | 13385 (44) |
| 6 | 1070 (44) | 814 (45) |
| 7 | 42 (2) | 0 (0) |
| 8 | 2687 (12) | 244 (1) |
| 10 | 25947 (63) | 24808 (62) |
| 11 | 13423 (21) | 14008 (21) |
| 13 | 2506 (12) | 357 (4) |
| 14 | 38 (6) | 282 (20) |
| 15 | 1163 (66) | 2977 (41) |
| 16 | 6004 (66) | 3094 (41) |
| 17 | 475 (8) | 0 (0) |
| 21 | 3175 (13) | 732 (2) |
| 23 | 9623 (21) | 11615 (21) |
| 24 | 1232 (38) | 1176 (31) |
| 27 | 26842 (67) | 11814 (40) |
| 28 | 3824 (24) | 2719 (21) |
| 29 | 2838 (24) | 1968 (21) |
| 31 | 18880 (29) | 21484 (44) |
| 32 | 3464 (26) | 5644 (42) |
| 34 | 88 (1) | 0 (0) |
| 35 | 816 (24) | 72 (2) |
| 36 | 39 (1) | 0 (0) |
| 37 | 222 (22) | 285 (24) |
| 38 | 975 (11) | 160 (6) |

## 10. New disc tapes this wave (fx-cov2): what the original does
- **pc_freeze** (Ryoma vs Falcon, Londo; BUG-65): P1's transform at f11 (130 rows) and Fusion k1/108 at f202 (flash =
  its fr-25 hold, f228-268). P2's UP (f30-89) and X (f90-93) during the transform did nothing (P2 motion frame 43 held
  f10-141, position unchanged); P2's run (DOWN f221-290) stood still f228-268 and moved on from f269. Round clock 99
  held to f188 (59 + 130 frames). Both recovery counters held f13-142 and f230-269. Objects: the floor gem appeared at
  f469 (gems_drop: 299) and chest 1 went at f535 (gems_drop 365): every stage timer +170 = 130 + 40. Freeze windows of
  every Fusion from the logs (the other fighter's counter + motion frame + health held, /tmp/ps-
  fx-cov2/fusion_freeze.json): 39-40 frames at a fixed offset per Fusion (Ryoma FX 28, FY 3; Falcon 68 / 32; Jack 23 /
  7; Kraken 17 / 16; Rouge 8 / 21; Valgas 22 / 35; Wang-Tang 33 / 3; Ayame 3; Galuda 28; Gunrock 68) = the first
  41-row hold in every Fusion's pc_moves.json rows (its 2nd..41st row).
- **turn_ryoma / turn_jack / turn2_ryoma** (Londo; BUG-58): 0 rows of state 7 in 8 starts from standing, 7 + 9 direction
  switches 3-20 frames into a run and 5 directions held from the @place frame. In a run the facing turns at once and
  the velocity swings over ~6 frames (turn_ryoma f880-889). State 7's trigger is something else (the two disc cases:
  right after a @place with the direction held, Jack; a run out of state 24, Ryoma).
- **turn3_ryoma** (Falcon vs Ryoma, stg10; BUG-58): P2 just placed facing 49152 + DOWN+LEFT = state 7 k0/21 13 rows >
  state 2 k0/28 > run; runs out of a jab's state 24 start in state 2 (k0/3 / k0/28) and never enter state 7. A state 7
  right after an @place may be a tape artifact (the placed angle vs the run code's own heading).
- **ledge_hang** (Jack vs Wang-Tang, stg20; BUG-63): from mash_s22's spot (-439, 100, 502), a running jump into the
  north wall (z 572.7): B at y 407-409 (the wall's top) = state 36 k2/207 20 rows > k2/208; UP+Y there = k1/71 37 rows;
  then k2/208 29 rows dropping to the floor. B at y 277 / 335 = the air action k1/53 > k1/54. Without B (v2): no catch.
  4 catches in 8 tries.
