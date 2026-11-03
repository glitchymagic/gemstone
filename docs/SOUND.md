# SOUND: the original's sound cues (BUG-36 / H-8)

Bar: every sound a player hears comes from the disc and starts on the frame the disc starts it. Before this pass the
remaster played 2 effects (`se_hit`, `se_hit_heavy` on every hit) + 6 announcer lines; jumps, landings, steps, swings,
voices, pick-ups, throws, knockdowns, Power Change were silent.

## Method (measured, not eyeballed)
1. **Disc logs** (`tools/sndlog.py`, Flycast instances via `tools/fcinst.py`):
   - `run INST TAPE,..`: the fidelity tapes (`game/tests/tapes/`) played with both fighters human (`tools/reflog.py`
     boot/play: P2's home stage, rand state 1, start on round phase 3). Same per-frame reflog rows as the fidelity pass.
   - `cpu INST P1:P2,..`: CPU vs CPU on P2's home stage (both CPU flags held at 1, healths held at 240 so a hit is a
     one-frame dip, clock held at 99), 3600 frames: every stage's own bank, gems, objects, every fighter as a victim.
   - The sound chip: a Lua watcher generated per run and hot-loaded with the driver's `lua` command in the same vblank
     as `tapelog`/`tape` (so watcher frame k = log row k) reads the 64 AICA channels' +0x00 (KYONB / PCMS / SA high) and
     +0x04 (SA low) every vblank and writes a line when one changes, with LSA +0x08, LEA +0x0C, OCT/FNS +0x18,
     DISDL/DIPAN +0x24, TL +0x28. 128 reads a frame: Flycast stays at full speed (a capseg of all registers would not).
   - After the run: sound RAM (2 MB at 0x00800000).
2. **Bank placement** (`tools/sndmap.py`): every DTPK file on the disc is searched in that run's sound RAM by 64-byte
   chunks of its sample area; a base is kept only if >= 97% of the whole sample area matches byte for byte (stage banks
   share samples, so partial matches are rejected). The header is not used (the driver patches it).
3. **Key-on** = a channel whose KYONB goes 0 -> 1, or whose SA changes while keyed. Sample = (bank, index) when SA is a
   listed start in the bank's sample table, else (bank, +offset) (the tables don't list every sample: COMMON's 8-bit
   impacts). Pitch = 44100 * 2^OCT * (1 + FNS/1024); level dB = -0.375 * TL - 3 * (15 - DISDL).
4. **Cues** (`tools/sndcues.py build` -> `game/assets/fidelity/sfx_map.json`, `cut` -> untracked `game/assets/audio/se/`):
   key-ons show up on the SAME vblank as the motion / state change that causes them (landing: state 6 + k0/9 f0 and the
   landing sample in one row), so each key-on is explained by one of
   - **motion**: a fighter's motion (kind, id) reaching motion frame F (+0x71A4/5, +0x719E; P-prefixed in the Power
     Change form). Kept when the sample keys on at >= 50% of that motion frame's entries in the logs (an entry = the
     first frame showing that kind/id/frame). Samples under 50% that together cover >= 50% = the game's random pick
     (weights kept). Kind 2 is the shared motion bank: one cue set `_k2` for every fighter, voices in it as `SELF_nnn`
     (the fighter's own bank, same index on every bank: checked on Falcon's and Ryoma's banks).
   - **impact**: shared samples on a health-drop frame (or the next), by the attack record's sound byte rec[0x12]
     (records = `react_code.json`, the attacker's hit id +0x100 on the hit frame or up to 3 frames before; 99 = none).
     These are never motion cues (each tape lands its hits on fixed motion frames, which would make whiffs sound).
     Hits with no record (Drives / Fusions = effect objects, throws) by the attacker's motion (`hit`), else `_any`.
   - **hurt**: the victim's own voice 0-4 frames after his health drops: by rec[4], played `_delay` = 2 frames after.
   - **event gem**: a gem count going up by one (CPU runs).
5. **Remaster** (`game/scripts/sfx_map.gd`, class SfxMap): one node per fight, `tick(fighters, tape_f)` once per physics
   frame from `fight.gd` (where the tape log row is written: it sees the state that row shows). Reads from outside only:
   the model's clip key + clip position (game frame = clip frame + 1, `Fighter._motion`; `gmo_f` for core attacks), hp,
   `rx_rec` (the record the reaction machine is running), `last_hit_by`, `arena.gem_taken`. Every motion frame reached
   since the last tick is cued (a new motion from its frame 0), so the clip's missing frame 0 still sounds. Stage
   samples (STG0N_) play only on stage stgN0 and are weighed against that stage's entries (`ns`). `PS_SFX_LOG=path`
   writes one line per started sample. fight.gd diff: 3 lines + the old per-hit `se_hit`/`se_hit_heavy` skipped when
   the map is loaded. The announcer stays with the round flow (fight.gd): NA bank key-ons are not cues.
6. **Proof** (`tools/sndproof.py rm NAME..` runs the remaster tape with the log, `run NAME..` compares): a disc key-on
   matches a remaster start of the same sample at the same tape frame (exact) or within +-3 frames. "same-motion" = the
   subset where the remaster shows the cue's fighter in the same motion (kind, id) on that frame, i.e. what the sound
   module is responsible for; the rest differ because the remaster's motion timing differs (gameplay, docs/FIDELITY.md).

## Bank map (sound RAM, byte offset from 0x00800000)
COMMON 0x10000 · NA (announcer) 0x80CF8 · P1's fighter bank 0x101C7C · P2's fighter bank right after it · the stage's
bank after that (Ryoma vs Falcon on Londo: RYOUM 0x101C7C, FOKER 0x1566F4, STG00 0x1A1E20; Falcon vs Ryoma on stg10:
FOKER 0x101C7C, RYOUM 0x14D3A8, STG01 0x1A1E20). Stage stgN0 loads **STG0N.BIN** (stg10 -> STG01, not STG10).
Fighter banks: FOKER Falcon, RYOUM Ryoma, WANG Wang-Tang, JACK Jack, GANRO Gunrock, GARUD Galuda, AYAME Ayame,
RUJYU Rouge, KRAKN Kraken, VAR_1 Valgas, VAR_2 Final Valgas. Key-ons at 0x1DBE00 / 0x1DFE40 (no bank) = the music
stream (ADX ring buffer), not effects.
Stage banks do NOT share an index layout: Londo's body fall is STG00 #5, the same bytes are STG01 #6; Londo lands on
STG00 #0, Ryoma's stage on STG01 #0 or #1 (a different sample). So a stage's sounds come only from logs ON that stage.

## Coverage (action -> sample; full table: sfx_map.json)
| action | motion@frame: samples (key-ons / entries) | fighters with a logged cue |
|---|---|---|
| jump (standing / moving) | k0_006@0: COMMON_006 165/196, COMMON_031 2/196, STG04_006 1/12; k0_006@18: COMMON_027 1/85, STG03_001 1/2, STG07_003 1/6; k0_010@0: COMMON_006 102/102, COMMON_017 1/102, COMMON_018 1/102; k0_010@36: STG04_003 1/8, STG05_001 1/1, STG09_001 1/6; k0_010@45: STG03_002 1/2; k0_010@51: STG00_002 1/1, STG03_002 1/2 | 10: ayame, falcon, galuda, gunrock, jack, kraken, rouge, ryoma, valgas, wangtang |
| landing | k0_009@0: COMMON_006 1/265, COMMON_007 1/265, COMMON_019 1/265 | 10: ayame, falcon, galuda, gunrock, jack, kraken, rouge, ryoma, valgas, wangtang |
| run steps | k0_025@9: COMMON_006 3/416, COMMON_007 1/416, COMMON_019 2/416; k0_025@10: COMMON_006 5/400, COMMON_007 1/400, COMMON_017 3/400; k0_025@27: COMMON_007 2/205, COMMON_017 1/205, COMMON_018 2/205; k0_025@28: COMMON_001 1/197, COMMON_006 2/197, COMMON_049 1/197 | 9: ayame, falcon, galuda, gunrock, kraken, rouge, ryoma, valgas, wangtang |
| stop | k0_026@0: COMMON_006 1/270, COMMON_007 1/270, COMMON_018 1/270; k0_026@13: STG04_002 1/2 | 5: ayame, gunrock, rouge, ryoma, wangtang |
| wall kick | k0_013@0: COMMON_006 1/9, COMMON_018 9/9; k0_013@4: STG05_002 1/1; k0_013@17: STG01_000 1/1; k0_013@23: STG09_000 1/1; k0_013@31: STG08_000 1/2; k0_013@42: COMMON_027 1/1 | 6: ayame, galuda, kraken, rouge, ryoma, valgas |
| pole catch / swing | k1_150@4: STG02_001 1/5, STG05_000 1/1; k1_150@8: COMMON_007 1/15, STG04_001 1/2; k1_150@9: STG06_003 1/2; k1_151@1: COMMON_006 1/16, COMMON_007 8/16, STG05_002 1/1; k1_151@4: STG06_007 1/2; k1_151@11: STG05_001 1/1 | 7: ayame, galuda, gunrock, jack, kraken, rouge, wangtang |
| punch chain (swing + voice) | (per fighter only) | 10: ayame, falcon, galuda, gunrock, jack, kraken, rouge, ryoma, valgas, wangtang |
| kick | (per fighter only) | 10: ayame, falcon, galuda, gunrock, jack, kraken, rouge, ryoma, valgas, wangtang |
| grab | k1_084@0: STG04_002 1/1, STG08_001 1/4; k1_084@3: STG07_002 1/1; k1_084@8: STG08_002 1/2; k1_084@16: STG04_002 1/1 | 4: ayame, falcon, gunrock, kraken |
| object throw | k1_078@8: COMMON_043 12/13, STG02_003 1/1; k1_078@10: STG04_002 1/2; k1_078@16: STG04_+0x10704 1/2; k1_078@17: STG01_000 1/2; k1_078@26: STG04_002 1/2; k1_078@31: COMMON_018 1/12, STG08_002 1/1 | 6: falcon, gunrock, rouge, ryoma, valgas, wangtang |
| pick-up / carry | k2_219@0: COMMON_006 1/31, COMMON_017 31/31, COMMON_019 1/31; k2_219@3: STG01_006 1/2, STG06_007 1/7, STG08_001 1/3; k2_219@17: STG01_002 1/2, STG04_+0x10704 2/14; k2_220@29: STG01_002 1/2 | 0:  |
| knocked down (fall, voice) | k2_152@0: STG00_005 44/43, STG01_006 9/9, STG02_006 7/7; k2_152@1: COMMON_006 2/100, COMMON_053 1/100, SELF_011 12/100; k2_152@40: STG03_002 1/2; k2_099@0: COMMON_019 1/41, COMMON_028 1/41, COMMON_029 1/41; k2_099@3: COMMON_006 1/44, COMMON_028 2/44, COMMON_053 1/44; k2_099@25: COMMON_053 1/39, STG02_001 1/2, STG05_001 1/2 | 0:  |
| get-up | k2_146@1: COMMON_027 1/86, COMMON_028 1/86, STG02_003 1/2; k2_146@8: STG02_003 1/2, STG05_001 1/4 | 0:  |
| Power Change / revert | k3_008@0: COMMON_029 33/33; k3_009@1: COMMON_029 23/24, STG00_005 1/12; k3_009@2: STG05_003 1/2; k3_009@4: COMMON_007 1/24, COMMON_028 24/24, STG00_005 1/12; k3_009@7: COMMON_028 24/24, STG02_003 1/1; k3_009@9: STG05_003 1/2 | 10: ayame, falcon, galuda, gunrock, jack, kraken, rouge, ryoma, valgas, wangtang |
| intro / win poses | k3_002@0: STG00_010 1/1; k3_003@0: STG00_010 1/1 | 2: ayame, ryoma |
| hit impact by attack record rec[0x12] | 0: COMMON_+0x10588 8/8; 1: COMMON_+0xC36E 8/25; 2: COMMON_+0x7FD0 39/44; 3: COMMON_+0x4502 23/32, COMMON_048 9/32; 4: COMMON_+0x1C3BE 8/8; 5: COMMON_+0x19588 23/23; 6: COMMON_+0x1592A 72/74; 7: COMMON_047 4/4; 8: COMMON_039 10/10; 9: COMMON_007 7/20, COMMON_040 17/20; 10: COMMON_041 59/63; 99: COMMON_016 1/2 | all (records) |
| hurt voice (own bank, +2 f) | rec[4]=0: {'10': 35, '11': 44, '12': 33, '14': 1} of 116; rec[4]=1: {'10': 11, '11': 6, '12': 8, '2': 1, '9': 3} of 32; rec[4]=2: {'10': 1, '11': 7, '12': 15, '14': 1} of 27; rec[4]=3: {'10': 20, '11': 26, '12': 41, '9': 13} of 102; rec[4]=4: {'10': 3, '11': 6, '12': 21} of 31; rec[4]=5: {'10': 1, '11': 3, '9': 1} of 5; rec[4]=_any: {'10': 140, '11': 136, '12': 179, '13': 3, '14': 2, '2': 1, '25': 1, '3': 1, '34': 1, '9': 26} of 559 | all (same index) |
| event gem | COMMON_027 51/89 | all |
| event gem_drop | COMMON_+0x10588 2/94, COMMON_+0x4502 3/94, COMMON_028 193/94, COMMON_048 5/94 | all |
| event ko | COMMON_020 20/10 | all |
| event ko_voice | SELF_002 10/10 (+90 f) | all |

Per fighter (motion cues / own-bank samples cued): Falcon 154 / 22, Ryoma 147 / 20, Wang-Tang 135 / 15, Jack 118 / 17,
Gunrock 105 / 12, Galuda 84 / 11, Ayame 123 / 14, Rouge 112 / 19, Kraken 127 / 15, Valgas 110 / 16 (each fighter's own
bank: attack yells on the motion frame, Power Change line on k3/8 frame 0, intro / win lines), shared kind 2 `_k2` 196,
pooled basic moves `_all` 127. 264 disc samples cut (untracked game/assets/audio/se/, `tools/sndcues.py cut`).
Logs: 17 tapes (move_basic, atk_ground, atk_move, items_londo, gems_pc, pole_wall, hits_down, moves_ for all 10
fighters) + CPU vs CPU 3600 frames on stg00..stg90 (10 stages): 27 runs, 5738 effect key-ons (announcer excluded),
**87.6% explained** by a cue / impact / hurt voice / event.

Rule notes (numbers = key-ons / entries in the logs):
- Hit impacts are per attack record, not per fighter: rec[0x12] 0 -> COMMON +0x10588, 1 -> +0xC36E, 2 -> +0x7FD0,
  3 -> +0x4502 (+ #48), 4 -> +0x1C3BE, 5 -> +0x19588, 6 -> +0x1592A, 7 -> #47, 8 -> #39, 9 -> #40, 10 -> #41, 99 none
  (+offsets = 8-bit PCM samples the bank's table does not list; cut by the key-on's SA + LEA).
- Hurt voice = the victim's own bank #10 / #11 / #12, 2 frames after the health drops (checked on Falcon's and Ryoma's
  banks: the same indices), rec[4] 4 -> #12 (21 of 23); 83% of hits voice one.
- Knocked down: body fall = the stage's own sample on k2/152 frame 0 (Londo STG00 #5 37/37, stg10 STG01 #6, stg20
  STG02 #6 ...), the faller's own #12 on frame 1 (56/66).
- Gem pick-up COMMON #27 (31 of 53 gem gains in CPU runs), a gem knocked out = COMMON #28 on two channels (138 / 70),
  Power Change = COMMON #29 on k3/8 frame 0 (25/25) + the fighter's line, revert k3/9 = COMMON #29 then #28 on frames
  4 and 7, pick-up and pole catch = COMMON #17 on k2/219 / k2/211 frame 0, wall kick = COMMON #18 (k2/206 frame 8,
  k0/13 frame 0), grab = COMMON #16 on k1/84 frame 11, object throw = COMMON #43 on k1/78 frame 8, jump = COMMON #6 on
  k0/6 or k0/10 frame 0, swing whoosh = COMMON #7 on each attack's active frame.
- The KO call (round phase 3 -> 4): COMMON #20 on two channels + the announcer's NA #13 ("K-O!", whisper), the KO'd
  fighter's own #2 90 frames later (10/10).

## Not mapped (and why)
- **Timer events no fighter causes**: COMMON #53 at tape frames 324 and 924 in almost every tape, #19 at 653 / 713 /
  773, #50 at 835 (the same frames whatever the fighters do: rand state 1 at the tape start makes them deterministic):
  stage / item-drop events of the original that the remaster has no counterpart for yet (85 + 56 + 23 key-ons).
- **Objects** (thrown chairs / barrels landing, breaking, item boxes): keyed by the object, which the reflog rows don't
  carry; the remaster simulates objects in prop.gd (see the request below). Some land on a motion frame and are cued
  (object throw #43); the rest stay silent.
- **Stage-specific steps / landings on a second surface** (STG01 #1, STG03 #2, STG08 #2 ...): position dependent (two
  floor materials on one stage); cued only where they repeat on a motion frame.
- **Final Valgas** (VAR_2 / STG0A): the only way in was poking the arcade index, and that fight kept Ayame's banks in
  sound RAM (the models were his): not logged. He gets the pooled / shared cues, no own voices.
- **Announcer** (NA): left to fight.gd's round flow. Finding for the lead: the KO call on the disc is NA **#13** in 10
  of 10 KOs logged; fight.gd's `vo_ko` is NA #12 (tools/sfx_extract.py PICK). NA #16 "Oh no!" plays when a gem is
  knocked out of a fighter (26 of its 26 key-ons are on a gem-drop frame); fight.gd says it on big hits with a 3 s
  cooldown instead. Other lines (#10 "Yeah!" 76, #27 "Wow!", #6, #18 ...) not attributed yet. Not changed here: the
  announcer belongs to fight.gd's round flow (request below).
- **The music stream** (key-ons at 0x1DBE00 / 0x1DFE40): Power Change switches the music on the disc; not effects.
- Random picks: where the disc picks one of several samples (hurt voices, some steps) the remaster picks with the
  same weights from its own seeded RNG: the same KIND of sound on the same frame, not always the same sample.

## Requests for fight.gd's round flow (lead / its owner)
- `vo_ko`: NA #13 instead of #12 (tools/sfx_extract.py PICK 'NA' 12 -> 13), 10 of 10 logged KO calls.
- `vo_ohno` ("Oh no!", NA #16): on a gem knocked out of a fighter (gem count down), not on every big hit.

## Requests for fighter.gd (lead)
None needed for what is mapped: everything is read from outside. Would help: a `sfx(kind)` signal (or a public var)
for object events the remaster already simulates in prop.gd (`_break`, thrown object hitting a wall / the floor), so
object sounds can be cued on the frame the remaster breaks / lands an object (now unmapped: the disc's object sounds
are keyed by the object, which the reflog rows don't carry).

## Proof (17 tapes, disc key-ons vs the samples the remaster starts, same tape frames; announcer excluded)
```
tape              disc  exact    +-3  extra | same-motion  exact    +-3
move_basic          57  38.6%  50.9%     29 |          33  66.7%  81.8%
atk_ground          72  27.8%  33.3%     44 |          28  64.3%  78.6%
atk_move            33  60.6%  69.7%     12 |          22  90.9%  90.9%
items_londo         22  36.4%  54.5%      6 |           8  75.0% 100.0%
gems_pc            136   0.0%   1.5%     17 |           0   0.0%   0.0%
pole_wall           12   8.3%  33.3%     12 |           2  50.0% 100.0%
hits_down           48  16.7%  25.0%     19 |           7  71.4% 100.0%
moves_falcon       129  17.1%  23.3%     66 |          31  67.7%  77.4%
moves_ryoma        159  15.1%  20.1%     71 |          35  65.7%  74.3%
moves_wangtang     154  31.8%  37.7%     55 |          63  76.2%  84.1%
moves_jack         151   8.6%  17.9%     46 |          28  46.4%  78.6%
moves_gunrock      149  17.4%  23.5%     47 |          32  81.2%  93.8%
moves_galuda       122  13.9%  23.0%     49 |          32  46.9%  65.6%
moves_ayame        148  33.1%  37.8%     51 |          53  86.8%  90.6%
moves_rouge        190  13.2%  17.4%     53 |          39  64.1%  74.4%
moves_kraken       153  17.6%  25.5%     62 |          51  47.1%  64.7%
moves_valgas       163  13.5%  21.5%     51 |          37  59.5%  78.4%
ALL               1898  18.6%  25.2%    690 |         501  66.9%  80.0%
```
- Before this pass the remaster had 2 effect samples (se_hit = COMMON +0xC36E, se_hit_heavy = COMMON #28) on every hit:
  at most 7.1% of these 1898 disc key-ons are even one of those two samples (upper bound of the old match).
- Now: 18.6% of the disc's key-ons start the same sample on the same frame, 25.2% within 3 frames (690 remaster
  starts unmatched). Where the remaster plays the same motion as the disc on that frame (501 key-ons), 66.9% exact /
  80.0% within 3 frames: the low overall share is the remaster's motion timing (it does a different move or the same
  one some frames apart: e.g. gems_pc, where its P1 never Power Changes so 0 of 136 line up), which is gameplay
  (docs/FIDELITY.md), not the sound map. Inside the same-motion subset the misses are random picks (the hurt voice is
  one of 3 lines on the disc too), clip frames off by one where the remaster's clip starts a frame late, and cues seen
  once.
- Most of the +1-frame impacts are gameplay: the remaster's health drops land one frame after the disc's for the same
  tape (atk_ground disc 28 / 201 / 501 / 1014 vs remaster 29 / 202 / 502 / 1015; hits_down 28 / 591 / 599 vs 29 / 591 /
  600); the sound starts on the remaster's own hit frame.
- Base suite with the hook in: 164/164 in Remaster and in Classic.

## Status (10-27 04:05, fx-snd) and next steps
- Done: tools/sndlog.py (tapes + CPU vs CPU per stage), sndmap.py (banks), sndcues.py (cues, cut, table),
  sndproof.py (proof); game/scripts/sfx_map.gd + 3 lines in fight.gd (+ the old per-hit samples / big-hit "Oh no!"
  skipped when the map is loaded); game/assets/fidelity/sfx_map.json from 27 disc runs; 268 samples cut.
- After a merge: run `tools/sndcues.py cut` and `Godot --headless --path game --import` (the samples are untracked),
  and `tools/sfx_extract.py` for vo_ko (now NA #13).
- Next: (1) object sounds (needs the prop.gd signal below), (2) the timer events (#53 / #19 / #50: find what the
  original drops at tape frames 324 / 924 / 653..), (3) Final Valgas's own bank (a real arcade run to fight 9, not a
  poked index), (4) more logs for kinds seen once (each new run: `tools/sndlog.py run|cpu ...` then `build`, `cut`).
