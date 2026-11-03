# The original's CPU (AI): how Power Stone's computer player works (BUG-24 groundwork)

Everything here is read out of 1ST_READ.BIN (loaded at 0x0C010000; addresses are 0x0C...) and checked against
CPU-vs-CPU logs of the disc in Flycast. Tools: `tools/cpu_ai.py` (tables + scripts -> `game/assets/fidelity/cpu_ai.json`,
`dis CHAR` prints a fighter's scripts), `tools/cpu_stats.py` (logs + statistics -> `game/assets/fidelity/cpu_stats.json`).

## 1. The short version

* The AI **only presses virtual buttons.** Each frame it rebuilds the player's input word `+0x2DC` out of the same
  logical bits a human's pad is remapped to (0x400 punch, 0x200 kick, 0x004 jump, 0x600 action = punch+kick,
  D-pad 0x10 up / 0x20 down / 0x40 left / 0x80 right, camera-relative). No state or motion is ever set by the AI
  module (no set_motion 0x0C09A808 call, no +0x71BA write); everything it does goes through the fighter code a human
  uses. So a port = the same pad bits into the remaster's (fidelity) fighter core.
* It is a **per-character script interpreter**: an interrupt dispatcher picks a *situation* (15 of them) by priority,
  a per-character table picks a *script* for that situation by CPU level band (level / 4) and `rand()`, and the
  script (u16 bytecode, 88 opcodes, 55 used) presses buttons, steers the stick toward a target, waits on states and
  branches on distance / heights / states / random numbers. 487 distinct scripts, 11,339 instructions, all exported.
* CPU strength = the global level byte 0x0C7F305C (9 at fight 1 ... 29-30 at Final Valgas; rank counter 0x0C7F305D / 8).
  It selects the script band (thresholds 4, 8, ... 32), the evade / tech chances (two 32-entry % tables) and, outside
  the AI, the CPU damage tables (CPU_ATK / CPU_DEF, `rules.gd`).
* Final Valgas has his own, separate hand-coded AI (0x0C08D5CE, section 9).
* **The port (game/scripts/cpu_game.gd) is the game's CPU** for every 1-on-1 fight since fx-cpu2 (10-27); status and the
  disc-vs-port numbers: sections 11 and 12.

## 2. Entry and per-frame flow

Per-frame battle update `0x0C092B8C` (both players, P1 then P2), per player:

```
mode = MV_OK (0x0C7F3050, one byte for both players; 0 = no input, 1 = round "Ready" (directions only), 2 = fight)
mode 0 : +0x2DC..+0x2E8 = 0
mode 1/2: if p+0x71ED (CPU flag) == 0: copy 36 B of pad 0x0C7F31F0 (+port) to p+0x2DC, remap 0x0C092908 (human)
          elif p+4 (character) == 10: 0x0C08D5CE(p)          Final Valgas AI
          else:                    0x0C04C24C(p)          the AI
mode 1 only: the four words &= 0xF4 (Final Valgas 0xF0): directions (+bit 2) only while "Ready"
if p+0x7241: the four words = 0 (input lock)
```

`0x0C04C24C(p)` (AI entry, normal fighters):

```
p+0x2E0 = p+0x2DC; p+0x2DC = 0                 previous / current
0x0C3673EE = p+3 (player index), 0x0C3673EF = p+4 (character)
0x0C04CFAC(p)          think: reset triggers, interrupt dispatcher, script selection (section 4)
0x0C04C9C6(p)          interpreter: run script ops until one yields (section 6)
p+0x2E4 = cur & ~prev (pressed), p+0x2E8 = prev & ~cur (released)
if byte 0x0C494D45: on-screen AI debug (strings "Kyori" distance, Timer, Lever, Mode, Hitdt, Mask, IntLv, Table,
                    Target, POS/TAR/EnP X Y Z, SET_W, NANDO = level 0x0C7F305C / rank 0x0C7F305D, MV_OK, RET)
```

The CPU flag is set to 1 for CPU sides at round init (0x0C0D3C76 / 0x0C0D4262; P1 +0x71ED frozen at 1 = AI drives P1).

### CPU-only branches outside the AI module (the game core treats a CPU slightly differently)
| where | what |
|---|---|
| 0x0C078668 (in 0x0C0784E4, a projectile / Drive launcher) | CPU: launch direction = angle to the opponent (0x0C09DB78); human: the heading +0x7248 |
| 0x0C095556, 0x0C09CC36 | per-character counters 0x0C7F2F60 / 0x0C7F2F8C bumped only for humans |
| 0x0C09B7E0, 0x0C09B8E4, 0x0C09B9BE, 0x0C09BA9C | human-only paths (table 0x0C339408 by player index) |
| 0x0C09FDF6 | human-only check of +0x7236 |
| 0x0C059718 / 0x0C08DFA4 | damage: CPU_ATK / CPU_DEF by level (documented in RIP.md) |

## 3. The AI work record: 0x0C366F40 + player index * 0x254

| off | size | meaning (debug label) |
|---|---|---|
| +0x00..+0x03 | u8 x4 | per-op scratch: +0 = phase of the running op, cleared by 0x0C04CDF2 whenever an op completes |
| +0x04 | u8 | Mode (activity class set by the interrupt, see table) |
| +0x06 | u16 | IntLv: priority of the running script (an interrupt with bit b fires only if IntLv < b) |
| +0x08 | u16 | Mask: enabled interrupt bits (default 0xFFFE; scripts MASK_ON / MASK_OFF) |
| +0x0C | u32 | script instruction pointer (saved ip; the global 0x0C3673E8 is the live one) |
| +0x14 | u16 | Timer: 600 at selection; 0 -> script abandoned (reset) |
| +0x16 | u16 | nesting base for IF skipping (0) |
| +0x18 | u16 | CNT (ops 77-79) |
| +0x1A | u16 | WAIT counter (op 60) |
| +0x1C | u16 | frames left of a timed op (JUMP / SIDESTEP ...) |
| +0x26 | s16 | REG: the script's value register (REG_* ops write, IF_* ops test) |
| +0x28 | u16 | Hitdt: opponent hit id (debug) |
| +0x2A | u16 | direction flag of a timed op (toward / away) |
| +0x2C | u16 | Table: script index last selected / called |
| +0x30 | u32 | last item seen (interrupt 2) |
| +0x38 | u16 | active (0 = select the default script this frame) |
| +0x3A/+0x3C/+0x3E/+0x40 | u16 | edge latches of interrupts 0x800 (tech), 0x800 (thrown), 0x1000 (zone), 4 (close) |
| +0x42 | u16 | last opponent hit id seen (interrupt 0x10) |
| +0x44/+0x46/+0x48/+0x4A | u16 | last own PC flag / opponent PC flag / own state / MV_OK (reset triggers) |
| +0x4C | u32 | last steering heading (0x1000 hysteresis of the move ops) |
| +0x50/+0x58 | f32 | own x / z this frame |
| +0x5C | u16 | stuck counter (frames walking / running with 0x0C04C078 < 5) |
| +0x60/+0x64/+0x68 | f32 | target position x y z |
| +0x6C | u32 | target object (player struct or stage object) |
| +0x70 | u16 | RET: call / interrupt stack depth |
| +0x74 + 12*d | f32 x3 | saved target positions; +0x164+4d saved targets; +0x1B4+4d saved ips; +0x204+2d IntLv; +0x22C+2d Mask |

## 4. Think 0x0C04CFAC: reset triggers, interrupts, the default

Reset (Timer = 600, active = 0, Mask = 1): MV_OK changed, own Power Change flag (+0x71F3) changed, opponent's PC
flag changed, own state became 27 (hit), Timer reached 0. Mask = 1 blocks every interrupt in that frame, so a reset
always falls through to the default script.

Then the interrupts, **in this order**; each needs `Mask & bit` and `IntLv < bit`; the first that fires pushes the
running context (0x0C04CCE0: ip, target, target pos, Mask, IntLv at depth RET; RET+1), sets active = 1, IntLv = bit,
Mode, and selects (situation, sub) (0x0C04CE3C). A script that ends in RET resumes the interrupted script; END drops
everything.

| bit | condition (p = me, o = opponent) | Mode | situation.sub |
|---|---|---|---|
| 0x1000 | own state in {34 pole catch, 26, 36, 39} | 0x30 | 13.0 |
| 0x1000 | zone code 0x0C09CD32(p) != 0 (2/3 ignored; 4-7 only when the opponent is on the matching side in z / x), rising edge (+0x3E) | 0x80 | 8.0 |
| 0x800 | 0x0C08E8AC(p): p[9]==1, p[10]==1, +0x71BC==2 and table 0x0C1507A8[+0x71DD] != 0 (a reaction that can be recovered), rising edge (+0x3A), then rand%100 < EVADE[level] | 0x10 | 11.0 |
| 0x800 | own state 29 (being thrown), rising edge (+0x3C), rand%100 < THROWN[level] | 0x10 | 11.0 |
| 0x400 | own state in {0, 2, 31, 5} and (a) an object in the player's near list (+0x2C0[i], count +0x2D8, kind +0x2B8[i]) whose top 0x0C02629E is between y+60 and y+440, or (b) 0x0C04CAFE: a type-2 kind 8/16 object in that list above me | 0x00 | 10.0 |
| 0x400 | (c) 0x0C04CB50: type-2 kind-12 object, unless it is within 300 cm and -100 <= dy < 100; target = it | 0x01 | 10.1 |
| 0x200 | own state 15 / 16 (down / get-up) | 0x90 | 12.0 |
| 0x200 | own state 13 | 0x91 | 12.1 |
| 0x100 | 0x0C04CB96: a live object not mine, kind 1/18 in sub-state 6-12 or kind 6 in 13-15 (thrown at me) | 0x90 | 9.0 |
| 0x80 | opponent state 36 or 34 (pole) | 0x70 | 7.0 |
| 0x40 | stuck counter > 60 and own state 2 / 31 | 0x60 | 6.0 |
| 0x20 | opponent state 15 (down) | 0x40 | 14.0 |
| 0x10 | opponent hit id (+0x100) changed and != 0; rand%100 < 100 (always, but a rand() is used) | 0x50 | 5.RESP[o char][hit id] |
| 0x08 | distance 0x0C04C028 < 300, -100 <= o.y-p.y < 100, opponent within +-45 deg of my heading (0x0C04BFD0 < 0x2000), opponent not down | 0x40 | 4.0 |
| 0x04 | distance < 300, -100 <= dy < 100, opponent not down, rising edge (+0x40) | 0x41 | 4.1 |
| 0x02 | 0x0C04CA6E: a new item (!= +0x30); REG = its kind | 0x31 | 3.1 |
| 0x02 | 0x0C04CA52: a type-2 object at +0x2C0[0]; REG = its kind | 0x30 | 3.0 |
| 0x02 | 0x0C04CA94; target = it, REG = its kind | 0x32 | 3.2 |
| default | active == 0: IntLv 1, Mask 0xFFFE (bit 2 cleared while carrying, +0x7236), Mode 0x10, Timer 600, RET 0 | 0x10 | 1.0 |

RESP = 0x0C32D6D0[char] -> u8[256]: sub 1 for opponent hit ids 18, 96-102, 104 (every fighter), else sub 0.
EVADE (0x0C32D768) = 30 31 32 33 34 35 36 37 38 39 40 42 44 46 48 50 60 65 70 75 80 85 90 91 ... 99 (% by level 0-31);
THROWN (0x0C32D7A8) = 10 11 ... 18 20 22 ... 60 70 80.

## 5. Script selection 0x0C04CE3C(p, situation, sub)

```
set  = own PC ? PC : (opponent PC ? oppPC : n)
sel  = SEL[set][char][situation][sub]      SEL n 0x0C32D64C, oppPC 0x0C32D6A4, PC 0x0C32D678 (u32[char])
list = n thresholds t[i]; band = first i with level < t[i]; then n lists (len, script indices); take band's list
idx  = list[(u32)(rand() / 32768.0f * 255.0f) % len]   (0x0C0DF940 = rand()*(1/32768), 0x0C0E6F24 = unsigned %)
Table (+0x2C) = idx; ip = SCR[set][char][situation][idx]   SCR n 0x0C32D5C8, oppPC 0x0C32D620, PC 0x0C32D5F4
```
Thresholds are 4, 8, ..., 32 (level / 4 bands) or a single 32 (one list for every level). Only 16 of the 630 lists
are banded, and in 9 of the 10 fighters' default lists every band holds the same script: the level really changes the
script only for Galuda (default, situations 3 / 4) and Gunrock in Power Change. Difficulty otherwise comes from the
EVADE / THROWN chances, the damage tables and the arcade fight index the scripts test (REG_FIGHT, 47 uses). Final Valgas (10) points
at Valgas's tables but never runs them. Situation 0's list is the per-character **library** used by CALL / GOTO.

## 6. The interpreter 0x0C04C9C6 and the opcodes

```
ip = work+0x0C; go = 1
while go and *ip != 0xFFFF: ip = work+0x0C; op = *ip++; HANDLER[op](p)      HANDLER = 0x0C32D7F8, LEN = 0x0C32D958
```
An op that completes stores the ip past itself into +0x0C, clears the scratch (0x0C04CDF2) and sets go = 1 (the next
op runs in the same frame); an op that waits leaves +0x0C alone and sets go = 0 (it runs again next frame). So
condition / register ops are free, and every frame ends on a pad-writing or waiting op. IF skipping (0x0C04DFDE)
counts nesting with the IF-type ops 29 30 31 32 33 59 and stops after the matching ELSE (8) or ENDIF (7).

Full table (name, length in words, handler, number of uses in all 487 scripts) = `tools/cpu_ai.py ops`. The used ones:

| op | name | meaning |
|---|---|---|
| 0 | END | active = 0, IntLv = 1, Mask = 1, stop (default script next frame) |
| 2 | PRESS b | wait for a frame whose previous pad (+0x2E0) is empty, hold b that frame; the next frame continues |
| 83 | PRESS_DIR b | as PRESS, then b + the direction to the target on the next frame (4 phases) |
| 86 | GRAB | a direction (opposite of the vector at +0x270, 0x0C050A12) 2 frames, the 2nd with 0x600 (action), 0x600 once more |
| 3 | JUMP n | jump (4) + direction to the target position (n > 0) / away (n < 0), held |n| frames, then one empty frame |
| 51 | WALK n | hold the direction to (n > 0) / away from (n < 0) the aimed target |n| frames, then go on |
| 67 | DASH n | empty frame, 1-frame tap, empty frame, then hold to / away from the aimed target |n| frames (running: hold at once) |
| 1 | KEEP_DIST d | steer to d +- 20 cm from the target |
| 4 | RUN_TO d | to d +- 20 cm of the target object (aimed); when not running and within 300 cm of the opponent it dashes first: empty frame, 1-frame tap, empty frame, then holds (a double tap = run) |
| 55 | APPROACH d | the same toward the target position (+0x60; dash whenever not running) |
| 56 | SIDESTEP n | side = rand%2; 2 empty frames, tap +-90 degrees to the aim, empty, hold n frames (a sideways dash) |
| 76 | MOVE_UNTIL_Y h | steer toward the target until own y >= h |
| 50 | MOVE50 n | phased approach (1 use) |
| 9 / 10 / 11 | GOTO s / CALL s / RET | library script s (situation 0 list); CALL pushes ip, target, pos, Mask, IntLv |
| 7 / 8 | ENDIF / ELSE | |
| 29 30 31 59 32 33 | IF_GT n, IF_LT n, IF_EQ n, IF_NE n, IF_NZ, IF_Z | on REG |
| 25 | RAND n | REG = (u32)(rand()/32768*255) % n |
| 19 | REG_DIST | REG = (int) horizontal distance to the opponent, cm |
| 20 / 21 | REG_OPP_DY / REG_OWN_DY | REG = (int)(o.y - p.y) / (int)(p.y - o.y) |
| 22 | REG_FIGHT | REG = arcade fight index (0x0C7F2E46 + 120 * player) |
| 57 / 74 | REG_OPP_ST / REG_OWN_ST | REG = opponent / own state |
| 58 | REG_CARRY | REG = own +0x7236 = the kind (1-16) of the object carried, 0 none (library 9 picks the throw / use script by kind) |
| 84 | REG_HELD | REG = kind of the held object (+0x71C8 -> +0x30C), 0 none |
| 78 / 77 / 79 | REG_CNT / CNT_SET n / CNT_CLR | the counter +0x18 |
| 75 | TIMER n | Timer = n |
| 63 / 64 | MASK_ON b / MASK_OFF b | |
| 45 | TARGET_OPP | target = opponent |
| 53 | TARGET_ORIGIN | target position (0, 0, 0) |
| 85 | TARGET_WAYPT | waypoint rand%4 of this stage (0x0C32DB90[stage byte 0x0C7F3051], 4 xyz points, e.g. Londo (400,0,-200) (400,0,500) (-400,0,-200) (400,0,900)) |
| 72 | TARGET_RANDOM | target position (-500 + 10 * (rand%100), 0, -500 + 10 * (rand%100)) cm (x first) |
| 73 | TARGET_STAGE | own y < 400: x > -z - 100 ? (x, 0, 300) : (-550, 0, z); y >= 400: x > -z - 100 ? (x, 0, -100) : (50, 0, z) (fixed constants: the climb-up point library 12 jumps from) |
| 44 | FIND_ITEM | best pick-up (kind 1/18, list *0x0C7E4078, filter 0x0C0AC55C) by 2*dist(me) - dist(opponent); REG = found |
| 62 / 70 / 71 | FIND_POLE / FIND_KIND6 / FIND_KIND7 | same scoring over kinds 5 / 6 (list *0x0C7E407C) / 7 |
| 42 / 46 / 80 | WAIT_IDLE / WAIT_FREE / WAIT_GROUND | until own state 0 / {0,2,31,5} / {0,2,31} |
| 81 / 87 | WAIT_OPP_FREE / WAIT_OPP_71BC | while opponent state in {27,24,15,16} / opponent +0x71BC == 2 |
| 82 | WAIT_7206 | until own +0x7206 > +0x7234: +0x7206 counts the attack presses the string handler 0x0C09468C has taken (reset in 0x0C097BB0), so a string presses again only once the last press was taken |
| 43 | WAIT_LAND | while above the target and falling |
| 60 | WAIT n | n frames |

**The first two arcade fights are scripted gentler.** Every default script (situation 1) except Gunrock's, Galuda's,
Kraken's and Valgas's starts `REG_FIGHT IF_EQ 0 CALL 19 / REG_FIGHT IF_EQ 1 CALL 20`: in fight 1 Falcon's library 19
waits 10 frames, MASK_OFF 0x99C (no evade 0x800, projectile 0x100, opponent-on-pole 0x80, counter 0x10 and close-range
8 / 4 interrupts), then only goes for items / objects (libraries 6-9) before END. REG_FIGHT is the human's arcade fight
index, so the CPU's behaviour depends on the fight number as well as on the level (cpu_stats.py freezes both).

Example (Falcon, library 0.1 = his punch string): `WAIT_GROUND PRESS 0x400 WAIT_7206 REG_OPP_ST IF_EQ 27 PRESS 0x400
WAIT_7206 REG_OPP_ST IF_EQ 27 ... RET`: the CPU only continues a string while the opponent is in hit state 27
(hit-confirm), pressing on the first frame the chain accepts. `tools/cpu_ai.py dis falcon` prints all of them.

## 7. Steering helpers
* Direction bits 0x0C050180(angle): `DIR[((angle - camera_yaw + 0xD000) & 0xFFFF) / 0x2000 & 7]`, camera yaw = u16
  0x0C7F31E0, DIR (0x0C32D7E8) = 0x80 0x90 0x10 0x50 0x40 0x60 0x20 0xA0: an 8-way digital stick relative to the
  camera, exactly like a human's D-pad.
* Angle to the target position 0x0C050068: atan(-dz/dx) (0x0C0DF360) + 0x8000 if dx < 0, + 0x4000 (game u16 angle,
  0 = +z, 0x4000 = +x; dx == 0 uses a tiny epsilon).
* Aim 0x0C04FED8: target pos = the target object's position; past 300 cm it leads by 10 frames of its velocity
  (+0x38 / +0x40).
* Distance to the target object 0x0C0500CA = sqrt(dx^2 + dz^2) minus a per-kind radius (0x0C32D6FC) for non-players.
* Steering hysteresis (ops 1, 4, 51, 55, 67, 76): keep the previous heading (+0x4C) while the new one is within
  0x1000 (22.5 deg).
* rand = the C rand 0x0C0DF920 (state 0x0C346A50, LCG * 0x41C64E6D + 0x3039, >> 16 & 0x7FFF), shared with the rest
  of the game: an exact port must consume it in the same order.

## 8. Checked against the disc
`tools/cpu_ai.py check LOGS` replays every script selection in the CPU-vs-CPU logs: (Mode, IntLv) -> situation.sub,
the level band and the PC set must give a script list that contains the logged Table (or a library script it calls in
the same frame). First logs: 1182 of 1182 selections consistent, so the dispatcher's mode / priority map, the band
thresholds and the tables decode right. The per-frame logs carry Mode / IntLv / Mask / script pointer / Table /
target / RET / pad of both AIs for a frame-by-frame diff of a port.

## 9. Final Valgas: 0x0C08D5CE (structure decoded 10-27; ported by fx-fv: section "Final Valgas port" at the end corrects
## the % helper, the health band and zone class 1 below)
Runs only while 0x0C0555C4() and p+0x10B == 0. Clears +0x2DC / +0x2E4 / +0x7204, then a 3-state machine
(jump table 0x0C338534: 0x0C08D492, 0x0C08D4E6, 0x0C08D594) on a 36-byte block at 0x0C439E38 + index * 36
(reset 0x0C08CAEA: +6 = 99, +4 = player), running a byte-coded command list (block +0x10; commands 0 / 1 / 2 ...,
table 0x0C3383CC, sub-handlers 0x0C338518). Its logged attack mix is in RIP.md (99>100 ...). What the code does
(fx-cpu2 read of /tmp/ps-fx-cpu/fv_c.txt + the disassembly):
* **zone class** 0x0C08CB8C(p): the opponent's angle off his facing > 0x4E38 (~110 deg, behind) and distance < 700 cm
  -> 4; else distance < 400 -> 0, < (a second constant next to 400 in the pool, not read) -> 1, < 900 -> 2, < 1500 -> 3,
  else 5. Distance 0x0C08CB4C = horizontal, opponent - self.
* **level bucket** 0x0C08CB26 = clamp(level - 20, 0, 11) >> 2 & 3 (levels 20-31 -> 0..2).
* **health band** 0x0C08CD18: (240 + own health - opponent health) through 0x0C0E6E5C -> block +8 (a change re-picks).
* **list choice** 0x0C08CC26: block +9 = zone class; a rand() index into the row (block +8 * 16) of table
  0x0C338A80[zone] picks the command list 0x0C338A68[zone][i] -> block +0x10.
* **interrupts** (0x0C08D056, only in state 0 / 2, each once per latch bit in block +0x1D, most by a % table through
  0x0C08CC90 = rand % 256 < table[health band]): opponent kind 6 (item) in state 33 -> list 0x0C338410 / 0x0C338412
  (after 4 uses); opponent state 13 -> % 0x0C150630 -> list 0x0C33844C[zone]; opponent state 23 (transform) with +10
  set -> % 0x0C15063C -> 0x0C338484[zone]; own health dropped while the zone is 5 (far) -> % 0x0C150648 -> a random
  list of 0x0C3384F4.
* **commands** (0x0C08D33C reads the list; block +5 = the running command, +0xC = its frame count): 0 = stand N frames
  (pad 0; N from 0x0C150654[level bucket][rand] when 0; ends early when the zone class changes; 0x0C08D0A6); 1 / 10 =
  steer N frames: the 8-way direction to the opponent from 0x0C1505F0 by angle (0x0C08CD7E), ends when the zone class
  drops to <= the one picked from 0x0C338504 (0x0C08D154); 2 = press pad word 0x0C3383CC[a] (as pressed and held), after
  N frames word 0x0C3383CC[b], until his state leaves 11 (the attack: he only attacks in state 11, RIP.md) (0x0C08D21A);
  3 = branch by % table 0x0C150774; 4 = a random wait (0x0C08D286: + 0x0C338514[health band] + 1); 6 = +0x7204 = 2
  until his state leaves 33 (0x0C08D2EE); 7 / 8 = block +0x1E on / off.
Next: read the tables named above out of 1ST_READ (u32 lists, byte command lists) and port it as CPUGame's Final Valgas
branch; fight.gd keeps cpu.gd's boss_attack for him until then.

## 10. Statistics of the original's CPU (CPU vs CPU, both sides the game's AI)
`tools/cpu_stats.py run u1 0` / `run u2 1` (5 pairs x levels 9 / 19 / 29 + Falcon vs Final Valgas, 18,000 frames each,
level frozen), `tools/cpu_stats.py stats` -> `game/assets/fidelity/cpu_stats.json`, per fighter and level:
attack starts per minute and the move mix (motion ids), spacing (mean / p10 / p50 / p90 cm), jumps / runs / grabs /
pick-ups / object throws per minute, carry share, gems gained / lost per minute, the share of time the AI targets an
object, Power Change count / timing / share, presses per minute, rounds (frames, damage dealt / taken, KO), and the
AI's own Mode / Table shares (`cpu_stats.py table`). The port against these numbers: section 12.

## 11. Port: game/scripts/cpu_game.gd (CPUGame) is the game's CPU (BUG-24, fx-cpu2 10-27)
**fight.gd uses CPUGame for every 1-on-1 CPU: Arcade, VS, the attract demo** (`Fight.cpu_level_for()`,
`cpu_fight_index()`). cpu.gd stays only where the original has nothing to port: Battle Royale / 2v2 (3-4 fighters; the
disc's AI is strictly 1-on-1: one opponent pointer, P1 / P2 work records) and Final Valgas (his own AI, section 9, is not
ported yet: cpu.gd's `boss_attack` with the logged chains drives him).

Tests: `tests/cpu_game_test.gd` (PS_TEST_CHARS, PS_STAGE, PS_CPU_LEVEL, PS_FIGHT, PS_FRAMES, PS_SEED, PS_TRACE=0|1 the
interpreter per frame, PS_TRACE_POS=1 positions / targets / wall contact every 30 frames, PS_CPU_LOG=rows for
cpu_stats.py, PS_MATCH=1 play to the match result); `tests/cpu_replay.gd` (section 12b).

**CPU level 0x0C7F305C** (`Fight.cpu_level_for`): arcade = Rules.ARCADE_CPU_LEVEL[fight] (9, 13, 17, 19, 22, 25, 27, 28,
29: the logged level at each fight's start); attract demo and everything else = 25 (measured in the attract demo,
Flycast u2: 0x0C7F305C = 25, rank 0x0C7F305D 200 -> 206 -> 207 while the demo plays; both arcade blocks' fight index 7).
VS: the disc's VS mode has no CPU option we found; the port uses the attract numbers there. The CPU damage tables
(CPU_ATK / CPU_DEF) now apply in the attract demo too (both sides CPU at 25).
**The rank counter moves during a fight** (Flycast u1, arcade fight 1 Ryoma vs Falcon, P1 under the game's AI, rank
logged every frame, /tmp/ps-fx-cpu2/rank.bin): starts at 72 (level 9); 28 steps in round 1: +1 on a
300-frame beat (240 / 540 / 840 / 1140 / 1440 frames after the fight starts, later 2510 / 2810 / 3110), +1 on 16 of the
27 attack starts of either side, +2 / +4 near hits (2082, 2173) and 2 more; it reached 104 (= 13 * 8, the next fight's start
level) 3295 frames into round 1 and stayed at 104 for the rest of the fight (round 2 flat). The writer is not found yet
(no literal-pool reference to 0x0C7F305D; it goes through a struct base): the port keeps the fight's start level for the
whole fight. FIDELITY: in fight 1 the original's CPU ends round 1 at level 13, the port's at 9.

**REG_FIGHT (op 22, 0x0C04EF6C)**: v = byte 0x0C7F3071 (0 or 3 -> 1), REG = byte 0x0C7F2E46 + (v - 1) * 120: the
arcade player's fight index (0x0C7F3071 = which pad plays the arcade), the same value for both AIs.

**Ported since wave 1** (world adapter in cpu_game.gd, `_w_*`; an arena may override any `ai_*` hook):
| original | remaster | evidence |
|---|---|---|
| object lists *0x0C7E4078.. (+2 type, +3 owner, +4 kind, +0x20 xyz, +0x30C item id, +0x30D sub-state) | Prop / Gem / poles by kind (table below) | RAM dumps of a Londo CPU fight, Flycast u1 (lon_0..6) |
| FIND_ITEM 44: kinds 1/18 | throwables at rest (Prop REST) | type 2 kind 1 = Londo's patio chairs / tables / bins / metal chair |
| op 62 (named FIND_POLE in cpu_ai.json): kind 5, list *0x0C7E407C | **the Power Stones** (Gem) | type 3 kind 5: 3 objects that fly when spilled; library 5 RUN_TO 0 = touch to take |
| FIND_KIND6 70 / FIND_KIND7 71 | none (items not in the remaster) | type 3 kind 6 = an item on the floor (+0x30C its id), type 2 kind 7 = the item chest (+0x30C = the item inside: 10, 1) |
| 0x100 incoming: kind 1/18 in sub-state 6-12, not mine | a Prop FLYING thrown by the other | |
| 0x02 (0x0C04CA52): +0x71C8 = the object in hand **or in reach**, type 2 -> 3.0, REG = its kind | the carried Prop, else a throwable at rest or a pole (kind 2) within 1.5 m | disc log falcon_ryoma_L9: 3.0 fires every 6 frames in the Ready phase while both stand still, both press punch on the first fight frame (3.0: kind 2 pole -> action within 300 cm; else opponent > 500 cm -> action = lift, else punch); lon_0: both in state 35 lifting, +0x7236 = 1; lon_3: +0x71C8 on a table at rest |
| REG_CARRY 58 (+0x7236) | 1 for a lifted stage object (library 9 -> library 14: throw it in range) | lon_0 |
| REG_HELD 84 (+0x71C8 -> +0x30C) | 0 (the item id; stage objects 0) | |
| zone code 0x0C09CD32 (interrupt 0x1000 -> situation 8: pinned against an object with the opponent on that side; Falcon's 8.0 GRABs him within 300 cm, or jumps + grabs when he is above within 800) | a Prop at rest within 1.5 m; side 4 / 6 (z) or 5 / 7 (x) by the larger axis | decompile: contact list +0x294, type 2, +0x30D == 0, side class > 3 (0x0C09CE6C, not read); 1.5 m = the reach of the lift (lon_0: a chair 143 cm away lifted in the first frames) |
| 0x400 (a): a contact object 60-440 cm above the feet -> 10.0 JUMP 6 | the measured floor raster 60 cm ahead: a floor 60-440 cm up, none walkable | |
| WAIT_7206 82 (u8 +0x7206 > s8 +0x7234, 0x0C050F80) | the core's chain window: gmo_f >= atk_open (no core attack: not state 10) | +0x7234 reset with +0x720A / +0x7236 (0x0C0A2080 and 3 more); its writer not read |
| WAIT_LAND 43 (0x0C05103C) | above the target position and falling (core vcm.y) | |
| MOVE50 50 (1 use), recoverable reactions 0x0C08E8AC (0x800 evade) | not ported (MOVE50 completes; the core has no recoverable reactions yet) | |
Also fixed on the way: `GameHits.key_of` and `Fight.tape_row` took Kraken's clip prefix "k0"/"k1" for the key, so none
of Kraken's motions found their hit steps (no game hits, no hit ids for the AI's counter interrupt 0x10) and his logged
motion ids were wrong.

## 12. Proof: the port against the disc (fx-cpu2, 10-27)

### 12a. Statistics (`tools/cpu_stats.py verdict`)
Same jobs as section 10 (15 pairs x levels 9 / 19 / 29 with the fight index the arcade pairs with each level: 0 / 3 / 7, on
P2's home stage, 18,000 frames, PS_SEED 1; Falcon vs Final Valgas left out: his AI is not ported):
`/tmp/ps-fx-cpu2/portstats.sh` -> `cpu_stats.py stats portlogs port_stats.json` -> `verdict`.
Verdict: PASS = within 25 % of the disc (0.5 /min for small rates, 0.05 for shares); FAIL is tagged **ai** (the AI's
own numbers), **core** (needs fighter-core mechanics not ported yet: items, throws, Power Change, reactions) or **out**
(outcomes of both; round frames are n/a: the port rows lack the clock / KO marks the reducer counts a round end by, see 12c). Totals: {'FAIL': 191, 'n/a': 21, 'PASS': 58}.

| number | PASS | FAIL | n/a |
|---|---|---|---|
| move mix overlap | 1 | 17 | 0 |
| attack starts /min | 5 | 13 | 0 |
| punch presses /min | 6 | 12 | 0 |
| kick presses /min | 2 | 15 | 1 |
| jump presses /min | 5 | 11 | 2 |
| jumps /min | 2 | 16 | 0 |
| runs /min | 4 | 14 | 0 |
| spacing p50 cm | 6 | 12 | 0 |
| object-target share | 5 | 13 | 0 |
| grabs /min | 6 | 12 | 0 |
| pick-ups /min | 2 | 16 | 0 |
| object throws /min | 4 | 14 | 0 |
| PC /min | 9 | 9 | 0 |
| damage dealt /min | 1 | 17 | 0 |
| round frames | 0 | 0 | 18 |

Where the AI spends its time (Mode shares, mean of the 18 fighter-levels, disc / port): default 0.325 / 0.240, zone 0.164 / 0.022, item_held/pole 0.110 / 0.363, close 0.104 / 0.100, down/projectile 0.086 / 0.077, counter 0.078 / 0.067, object_above 0.048 / 0.013, close_once 0.043 / 0.029, item_new 0.016 / 0.000, opp_pole 0.009 / 0.014, object_target 0.008 / 0.000, stuck 0.005 / 0.074. Reading:
* **stuck (situation 6)**: the port's fighters stop dead at floor steps the original climbs (the stuck counter counts
  frames running at < 5 cm/frame, 0x0C04C078). Probed: stg10 (260, -408) running +x/+z from the -33 cm floor onto 0;
  Londo (-645, -182) -25 / -50 -> 0; Londo (-59, -204) at y 0 where the measured raster has the fountain base at 55 cm:
  0 cm/frame for 500+ frames, `is_on_wall` true. The core's step-up (`_core_move`) casts against the remaster's
  collision, not the measured floor raster. A fighter-core fix (12e), not an AI one.
* **item held 0.363 vs 0.110, zone 0.022 vs 0.164**: with +0x71C8 read as the object in reach (section 11), 3.0 now
  fires next to every throwable and pole; on the disc a punch there starts an object move (both fighters k1/153 >
  k1/154 on the first fight frame, disc log falcon_ryoma_L9) that ends the contact, in the remaster it is a plain
  punch (BUG-26) and the fighter stays in reach, so 3.0 fires again. The zone code only knows throwables here (the
  disc's contact list also holds the stage's own pieces). Before the +0x71C8 change: item held 0.004, stuck 0.248.
* **counter (0x10)** needs the opponent's hit ids: fixed for Kraken in this pass (GameHits.key_of).
* attack / press rates and damage follow from the above plus the core gaps (BUG-15..21 strings / reactions /
  launches, BUG-25 Power Change, BUG-26 items): no row is tuned around them.

<details><summary>full table (270 rows)</summary>

| fighter | level | number | disc | port | verdict |
|---|---|---|---|---|---|
| falcon | 9 | move mix overlap | 1.00 | 0.11 | FAIL (core: the moves the core starts) |
| falcon | 9 | attack starts /min | 31.3 | 118.8 | FAIL (ai) |
| falcon | 9 | punch presses /min | 24.6 | 672.6 | FAIL (ai) |
| falcon | 9 | kick presses /min | 18.2 | 613.2 | FAIL (ai) |
| falcon | 9 | jump presses /min | 21.4 | None | n/a |
| falcon | 9 | jumps /min | 9.12 | 0.0 | FAIL (ai) |
| falcon | 9 | runs /min | 21.03 | 0.91 | FAIL (ai) |
| falcon | 9 | spacing p50 cm | 502.1 | 530.6 | PASS |
| falcon | 9 | object-target share | 0.441 | 0.002 | FAIL (ai) |
| falcon | 9 | grabs /min | 0.79 | 0.0 | FAIL (core) |
| falcon | 9 | pick-ups /min | 3.57 | 0.0 | FAIL (core) |
| falcon | 9 | object throws /min | 2.78 | 0.0 | FAIL (core) |
| falcon | 9 | PC /min | 0.79 | 0.0 | FAIL (core) |
| falcon | 9 | damage dealt /min | 246.0 | 10.9 | FAIL (out) |
| falcon | 9 | round frames | 3024.7 | None | n/a (no round ended) |
| ryoma | 9 | move mix overlap | 1.00 | 0.0 | FAIL (core: the moves the core starts) |
| ryoma | 9 | attack starts /min | 21.0 | 0.0 | FAIL (ai) |
| ryoma | 9 | punch presses /min | 22.2 | 33.3 | FAIL (ai) |
| ryoma | 9 | kick presses /min | 18.2 | 33.3 | FAIL (ai) |
| ryoma | 9 | jump presses /min | 24.2 | 33.0 | FAIL (ai) |
| ryoma | 9 | jumps /min | 9.12 | 33.33 | FAIL (ai) |
| ryoma | 9 | runs /min | 28.17 | 28.78 | PASS |
| ryoma | 9 | spacing p50 cm | 502.1 | 530.6 | PASS |
| ryoma | 9 | object-target share | 0.267 | 0.491 | FAIL (ai) |
| ryoma | 9 | grabs /min | 0.0 | 0.0 | PASS |
| ryoma | 9 | pick-ups /min | 3.57 | 0.0 | FAIL (core) |
| ryoma | 9 | object throws /min | 1.98 | 0.0 | FAIL (core) |
| ryoma | 9 | PC /min | 0.4 | 0.0 | PASS |
| ryoma | 9 | damage dealt /min | 125.0 | 0.0 | FAIL (out) |
| ryoma | 9 | round frames | 3024.7 | None | n/a (no round ended) |
| ryoma | 19 | move mix overlap | 1.00 | 0.47 | FAIL (core: the moves the core starts) |
| ryoma | 19 | attack starts /min | 25.2 | 14.8 | FAIL (ai) |
| ryoma | 19 | punch presses /min | 41.1 | 483.3 | FAIL (ai) |
| ryoma | 19 | kick presses /min | 41.7 | 470.5 | FAIL (ai) |
| ryoma | 19 | jump presses /min | 38.9 | 23.0 | FAIL (ai) |
| ryoma | 19 | jumps /min | 10.9 | 10.0 | PASS |
| ryoma | 19 | runs /min | 28.33 | 16.66 | FAIL (ai) |
| ryoma | 19 | spacing p50 cm | 461.6 | 601.4 | FAIL (ai) |
| ryoma | 19 | object-target share | 0.248 | 0.128 | FAIL (ai) |
| ryoma | 19 | grabs /min | 0.0 | 0.0 | PASS |
| ryoma | 19 | pick-ups /min | 2.49 | 0.61 | FAIL (core) |
| ryoma | 19 | object throws /min | 1.25 | 0.0 | FAIL (core) |
| ryoma | 19 | PC /min | 0.62 | 0.0 | FAIL (core) |
| ryoma | 19 | damage dealt /min | 139.2 | 10.3 | FAIL (out) |
| ryoma | 19 | round frames | 3854.3 | None | n/a (no round ended) |
| wangtang | 9 | move mix overlap | 1.00 | 0.0 | FAIL (core: the moves the core starts) |
| wangtang | 9 | attack starts /min | 31.4 | 0.0 | FAIL (ai) |
| wangtang | 9 | punch presses /min | 21.1 | 78.7 | FAIL (ai) |
| wangtang | 9 | kick presses /min | 16.2 | 78.7 | FAIL (ai) |
| wangtang | 9 | jump presses /min | 17.7 | 78.1 | FAIL (ai) |
| wangtang | 9 | jumps /min | 7.15 | 78.54 | FAIL (ai) |
| wangtang | 9 | runs /min | 30.79 | 0.2 | FAIL (ai) |
| wangtang | 9 | spacing p50 cm | 491.3 | 428.7 | PASS |
| wangtang | 9 | object-target share | 0.394 | 0.002 | FAIL (ai) |
| wangtang | 9 | grabs /min | 1.87 | 0.0 | FAIL (core) |
| wangtang | 9 | pick-ups /min | 1.56 | 0.0 | FAIL (core) |
| wangtang | 9 | object throws /min | 1.56 | 0.0 | FAIL (core) |
| wangtang | 9 | PC /min | 0.31 | 0.0 | PASS |
| wangtang | 9 | damage dealt /min | 168.9 | 0.0 | FAIL (out) |
| wangtang | 9 | round frames | 3858.3 | None | n/a (no round ended) |
| jack | 9 | move mix overlap | 1.00 | 0.08 | FAIL (core: the moves the core starts) |
| jack | 9 | attack starts /min | 28.0 | 221.3 | FAIL (ai) |
| jack | 9 | punch presses /min | 29.2 | 111.2 | FAIL (ai) |
| jack | 9 | kick presses /min | 20.8 | 0.8 | FAIL (ai) |
| jack | 9 | jump presses /min | 16.5 | 0.8 | FAIL (ai) |
| jack | 9 | jumps /min | 4.67 | 0.0 | FAIL (ai) |
| jack | 9 | runs /min | 20.84 | 2.22 | FAIL (ai) |
| jack | 9 | spacing p50 cm | 491.3 | 428.7 | PASS |
| jack | 9 | object-target share | 0.461 | 0.124 | FAIL (ai) |
| jack | 9 | grabs /min | 0.31 | 0.0 | PASS |
| jack | 9 | pick-ups /min | 1.87 | 0.0 | FAIL (core) |
| jack | 9 | object throws /min | 2.49 | 0.0 | FAIL (core) |
| jack | 9 | PC /min | 0.93 | 0.0 | FAIL (core) |
| jack | 9 | damage dealt /min | 190.3 | 0.0 | FAIL (out) |
| jack | 9 | round frames | 3858.3 | None | n/a (no round ended) |
| jack | 19 | move mix overlap | 1.00 | 0.36 | FAIL (core: the moves the core starts) |
| jack | 19 | attack starts /min | 35.3 | 43.3 | PASS |
| jack | 19 | punch presses /min | 33.7 | 87.3 | FAIL (ai) |
| jack | 19 | kick presses /min | 31.0 | 27.9 | PASS |
| jack | 19 | jump presses /min | 30.0 | 46.7 | FAIL (ai) |
| jack | 19 | jumps /min | 10.52 | 17.27 | FAIL (ai) |
| jack | 19 | runs /min | 27.89 | 68.47 | FAIL (ai) |
| jack | 19 | spacing p50 cm | 385.7 | 272.9 | FAIL (ai) |
| jack | 19 | object-target share | 0.509 | 0.579 | PASS |
| jack | 19 | grabs /min | 1.58 | 0.0 | FAIL (core) |
| jack | 19 | pick-ups /min | 1.58 | 0.61 | FAIL (core) |
| jack | 19 | object throws /min | 1.58 | 0.0 | FAIL (core) |
| jack | 19 | PC /min | 2.1 | 0.0 | FAIL (core) |
| jack | 19 | damage dealt /min | 263.6 | 67.0 | FAIL (out) |
| jack | 19 | round frames | 3420.5 | None | n/a (no round ended) |
| gunrock | 9 | move mix overlap | 1.00 | 0.33 | FAIL (core: the moves the core starts) |
| gunrock | 9 | attack starts /min | 45.1 | 38.2 | PASS |
| gunrock | 9 | punch presses /min | 31.3 | 51.2 | FAIL (ai) |
| gunrock | 9 | kick presses /min | 17.4 | 23.3 | FAIL (ai) |
| gunrock | 9 | jump presses /min | 23.4 | 34.5 | FAIL (ai) |
| gunrock | 9 | jumps /min | 5.21 | 13.33 | FAIL (ai) |
| gunrock | 9 | runs /min | 17.36 | 34.24 | FAIL (ai) |
| gunrock | 9 | spacing p50 cm | 625.4 | 350.1 | FAIL (ai) |
| gunrock | 9 | object-target share | 0.417 | 0.18 | FAIL (ai) |
| gunrock | 9 | grabs /min | 0.87 | 0.0 | FAIL (core) |
| gunrock | 9 | pick-ups /min | 1.74 | 1.82 | PASS |
| gunrock | 9 | object throws /min | 2.6 | 0.0 | FAIL (core) |
| gunrock | 9 | PC /min | 1.74 | 1.51 | PASS |
| gunrock | 9 | damage dealt /min | 423.6 | 124.8 | FAIL (out) |
| gunrock | 9 | round frames | 2073.5 | None | n/a (no round ended) |
| gunrock | 19 | move mix overlap | 1.00 | 0.39 | FAIL (core: the moves the core starts) |
| gunrock | 19 | attack starts /min | 27.1 | 20.0 | FAIL (ai) |
| gunrock | 19 | punch presses /min | 54.8 | 47.0 | PASS |
| gunrock | 19 | kick presses /min | 50.4 | 12.7 | FAIL (ai) |
| gunrock | 19 | jump presses /min | 28.0 | 18.8 | FAIL (ai) |
| gunrock | 19 | jumps /min | 10.27 | 6.67 | FAIL (ai) |
| gunrock | 19 | runs /min | 22.1 | 23.03 | PASS |
| gunrock | 19 | spacing p50 cm | 461.6 | 601.4 | FAIL (ai) |
| gunrock | 19 | object-target share | 0.397 | 0.433 | PASS |
| gunrock | 19 | grabs /min | 1.87 | 0.0 | FAIL (core) |
| gunrock | 19 | pick-ups /min | 2.8 | 0.3 | FAIL (core) |
| gunrock | 19 | object throws /min | 2.18 | 0.0 | FAIL (core) |
| gunrock | 19 | PC /min | 0.62 | 1.21 | FAIL (core) |
| gunrock | 19 | damage dealt /min | 216.1 | 87.0 | FAIL (out) |
| gunrock | 19 | round frames | 3854.3 | None | n/a (no round ended) |
| galuda | 9 | move mix overlap | 1.00 | 0.37 | FAIL (core: the moves the core starts) |
| galuda | 9 | attack starts /min | 20.8 | 50.0 | FAIL (ai) |
| galuda | 9 | punch presses /min | 73.8 | 70.9 | PASS |
| galuda | 9 | kick presses /min | 58.2 | 34.2 | FAIL (ai) |
| galuda | 9 | jump presses /min | 43.4 | 26.1 | FAIL (ai) |
| galuda | 9 | jumps /min | 3.47 | 14.85 | FAIL (ai) |
| galuda | 9 | runs /min | 19.1 | 47.57 | FAIL (ai) |
| galuda | 9 | spacing p50 cm | 625.4 | 350.1 | FAIL (ai) |
| galuda | 9 | object-target share | 0.435 | 0.438 | PASS |
| galuda | 9 | grabs /min | 0.0 | 0.0 | PASS |
| galuda | 9 | pick-ups /min | 9.55 | 6.06 | FAIL (core) |
| galuda | 9 | object throws /min | 0.87 | 0.0 | FAIL (core) |
| galuda | 9 | PC /min | 0.87 | 1.21 | PASS |
| galuda | 9 | damage dealt /min | 126.7 | 66.7 | FAIL (out) |
| galuda | 9 | round frames | 2073.5 | None | n/a (no round ended) |
| galuda | 19 | move mix overlap | 1.00 | 0.41 | FAIL (core: the moves the core starts) |
| galuda | 19 | attack starts /min | 30.5 | 51.2 | FAIL (ai) |
| galuda | 19 | punch presses /min | 57.5 | 59.7 | PASS |
| galuda | 19 | kick presses /min | 41.7 | 45.1 | PASS |
| galuda | 19 | jump presses /min | 35.3 | 27.3 | PASS |
| galuda | 19 | jumps /min | 12.93 | 10.91 | PASS |
| galuda | 19 | runs /min | 25.58 | 54.84 | FAIL (ai) |
| galuda | 19 | spacing p50 cm | 411.2 | 293.2 | FAIL (ai) |
| galuda | 19 | object-target share | 0.462 | 0.372 | PASS |
| galuda | 19 | grabs /min | 2.3 | 0.0 | FAIL (core) |
| galuda | 19 | pick-ups /min | 2.59 | 3.64 | FAIL (core) |
| galuda | 19 | object throws /min | 0.57 | 0.0 | FAIL (core) |
| galuda | 19 | PC /min | 0.86 | 0.61 | PASS |
| galuda | 19 | damage dealt /min | 162.4 | 71.5 | FAIL (out) |
| galuda | 19 | round frames | 4175.7 | None | n/a (no round ended) |
| ayame | 9 | move mix overlap | 1.00 | 0.27 | FAIL (core: the moves the core starts) |
| ayame | 9 | attack starts /min | 24.8 | 262.8 | FAIL (ai) |
| ayame | 9 | punch presses /min | 23.2 | 131.1 | FAIL (ai) |
| ayame | 9 | kick presses /min | 10.7 | None | n/a |
| ayame | 9 | jump presses /min | 19.1 | None | n/a |
| ayame | 9 | jumps /min | 8.77 | 0.0 | FAIL (ai) |
| ayame | 9 | runs /min | 14.1 | 0.81 | FAIL (ai) |
| ayame | 9 | spacing p50 cm | 585.9 | 406.6 | FAIL (ai) |
| ayame | 9 | object-target share | 0.471 | 0.008 | FAIL (ai) |
| ayame | 9 | grabs /min | 0.31 | 0.0 | PASS |
| ayame | 9 | pick-ups /min | 2.82 | 0.0 | FAIL (core) |
| ayame | 9 | object throws /min | 2.51 | 0.0 | FAIL (core) |
| ayame | 9 | PC /min | 1.25 | 0.0 | FAIL (core) |
| ayame | 9 | damage dealt /min | 197.1 | 0.0 | FAIL (out) |
| ayame | 9 | round frames | 3829.3 | None | n/a (no round ended) |
| ayame | 19 | move mix overlap | 1.00 | 0.4 | FAIL (core: the moves the core starts) |
| ayame | 19 | attack starts /min | 24.2 | 39.1 | FAIL (ai) |
| ayame | 19 | punch presses /min | 56.8 | 56.4 | PASS |
| ayame | 19 | kick presses /min | 44.2 | 24.5 | FAIL (ai) |
| ayame | 19 | jump presses /min | 32.1 | 38.8 | PASS |
| ayame | 19 | jumps /min | 10.0 | 17.57 | FAIL (ai) |
| ayame | 19 | runs /min | 26.84 | 59.69 | FAIL (ai) |
| ayame | 19 | spacing p50 cm | 385.7 | 272.9 | FAIL (ai) |
| ayame | 19 | object-target share | 0.497 | 0.544 | PASS |
| ayame | 19 | grabs /min | 1.05 | 0.0 | FAIL (core) |
| ayame | 19 | pick-ups /min | 0.53 | 0.3 | PASS |
| ayame | 19 | object throws /min | 0.0 | 0.0 | PASS |
| ayame | 19 | PC /min | 0.53 | 0.61 | PASS |
| ayame | 19 | damage dealt /min | 108.9 | 115.1 | PASS |
| ayame | 19 | round frames | 3420.5 | None | n/a (no round ended) |
| rouge | 9 | move mix overlap | 1.00 | 0.0 | FAIL (core: the moves the core starts) |
| rouge | 9 | attack starts /min | 17.2 | 0.0 | FAIL (ai) |
| rouge | 9 | punch presses /min | 23.5 | 78.9 | FAIL (ai) |
| rouge | 9 | kick presses /min | 15.7 | 78.9 | FAIL (ai) |
| rouge | 9 | jump presses /min | 32.3 | 78.3 | FAIL (ai) |
| rouge | 9 | jumps /min | 11.91 | 78.94 | FAIL (ai) |
| rouge | 9 | runs /min | 18.8 | 0.0 | FAIL (ai) |
| rouge | 9 | spacing p50 cm | 585.9 | 406.6 | FAIL (ai) |
| rouge | 9 | object-target share | 0.374 | 0.0 | FAIL (ai) |
| rouge | 9 | grabs /min | 1.25 | 0.0 | FAIL (core) |
| rouge | 9 | pick-ups /min | 2.82 | 0.0 | FAIL (core) |
| rouge | 9 | object throws /min | 1.88 | 0.0 | FAIL (core) |
| rouge | 9 | PC /min | 1.25 | 0.0 | FAIL (core) |
| rouge | 9 | damage dealt /min | 163.0 | 0.0 | FAIL (out) |
| rouge | 9 | round frames | 3829.3 | None | n/a (no round ended) |
| rouge | 19 | move mix overlap | 1.00 | 0.25 | FAIL (core: the moves the core starts) |
| rouge | 19 | attack starts /min | 20.8 | 25.0 | PASS |
| rouge | 19 | punch presses /min | 24.8 | 24.0 | PASS |
| rouge | 19 | kick presses /min | 30.0 | 20.6 | FAIL (ai) |
| rouge | 19 | jump presses /min | 26.0 | 31.9 | PASS |
| rouge | 19 | jumps /min | 6.93 | 8.69 | FAIL (ai) |
| rouge | 19 | runs /min | 23.68 | 61.4 | FAIL (ai) |
| rouge | 19 | spacing p50 cm | 371.0 | 377.6 | PASS |
| rouge | 19 | object-target share | 0.382 | 0.14 | FAIL (ai) |
| rouge | 19 | grabs /min | 1.16 | 0.0 | FAIL (core) |
| rouge | 19 | pick-ups /min | 0.58 | 3.84 | FAIL (core) |
| rouge | 19 | object throws /min | 0.0 | 0.0 | PASS |
| rouge | 19 | PC /min | 0.58 | 1.01 | PASS |
| rouge | 19 | damage dealt /min | 69.3 | 27.9 | FAIL (out) |
| rouge | 19 | round frames | 3116.0 | None | n/a (no round ended) |
| kraken | 9 | move mix overlap | 1.00 | 0.46 | FAIL (core: the moves the core starts) |
| kraken | 9 | attack starts /min | 33.9 | 17.9 | FAIL (ai) |
| kraken | 9 | punch presses /min | 20.0 | 179.1 | FAIL (ai) |
| kraken | 9 | kick presses /min | 22.3 | 170.0 | FAIL (ai) |
| kraken | 9 | jump presses /min | 30.6 | 15.5 | FAIL (ai) |
| kraken | 9 | jumps /min | 9.28 | 3.33 | FAIL (ai) |
| kraken | 9 | runs /min | 19.95 | 65.14 | FAIL (ai) |
| kraken | 9 | spacing p50 cm | 327.2 | 230.1 | FAIL (ai) |
| kraken | 9 | object-target share | 0.321 | 0.158 | FAIL (ai) |
| kraken | 9 | grabs /min | 1.86 | 0.0 | FAIL (core) |
| kraken | 9 | pick-ups /min | 1.39 | 2.42 | FAIL (core) |
| kraken | 9 | object throws /min | 0.46 | 0.0 | PASS |
| kraken | 9 | PC /min | 0.93 | 0.3 | FAIL (core) |
| kraken | 9 | damage dealt /min | 184.7 | 56.1 | FAIL (out) |
| kraken | 9 | round frames | 2586.0 | None | n/a (no round ended) |
| kraken | 19 | move mix overlap | 1.00 | 0.54 | PASS |
| kraken | 19 | attack starts /min | 42.8 | 49.1 | PASS |
| kraken | 19 | punch presses /min | 38.2 | 61.5 | FAIL (ai) |
| kraken | 19 | kick presses /min | 33.9 | 45.1 | FAIL (ai) |
| kraken | 19 | jump presses /min | 32.5 | 30.9 | PASS |
| kraken | 19 | jumps /min | 8.33 | 15.45 | FAIL (ai) |
| kraken | 19 | runs /min | 26.15 | 27.87 | PASS |
| kraken | 19 | spacing p50 cm | 411.2 | 293.2 | FAIL (ai) |
| kraken | 19 | object-target share | 0.378 | 0.141 | FAIL (ai) |
| kraken | 19 | grabs /min | 0.86 | 0.0 | FAIL (core) |
| kraken | 19 | pick-ups /min | 0.57 | 2.73 | FAIL (core) |
| kraken | 19 | object throws /min | 0.0 | 0.0 | PASS |
| kraken | 19 | PC /min | 1.44 | 1.82 | PASS |
| kraken | 19 | damage dealt /min | 177.9 | 101.2 | FAIL (out) |
| kraken | 19 | round frames | 4175.7 | None | n/a (no round ended) |
| valgas | 9 | move mix overlap | 1.00 | 0.49 | FAIL (core: the moves the core starts) |
| valgas | 9 | attack starts /min | 19.0 | 23.3 | PASS |
| valgas | 9 | punch presses /min | 17.2 | 174.8 | FAIL (ai) |
| valgas | 9 | kick presses /min | 19.5 | 177.8 | FAIL (ai) |
| valgas | 9 | jump presses /min | 26.0 | 33.3 | FAIL (ai) |
| valgas | 9 | jumps /min | 10.21 | 20.91 | FAIL (ai) |
| valgas | 9 | runs /min | 24.13 | 26.97 | PASS |
| valgas | 9 | spacing p50 cm | 327.2 | 230.1 | FAIL (ai) |
| valgas | 9 | object-target share | 0.414 | 0.135 | FAIL (ai) |
| valgas | 9 | grabs /min | 1.39 | 0.0 | FAIL (core) |
| valgas | 9 | pick-ups /min | 2.32 | 1.21 | FAIL (core) |
| valgas | 9 | object throws /min | 2.32 | 0.0 | FAIL (core) |
| valgas | 9 | PC /min | 0.93 | 0.91 | PASS |
| valgas | 9 | damage dealt /min | 308.6 | 87.3 | FAIL (out) |
| valgas | 9 | round frames | 2586.0 | None | n/a (no round ended) |
| valgas | 19 | move mix overlap | 1.00 | 0.23 | FAIL (core: the moves the core starts) |
| valgas | 19 | attack starts /min | 32.3 | 50.1 | FAIL (ai) |
| valgas | 19 | punch presses /min | 29.5 | 35.8 | PASS |
| valgas | 19 | kick presses /min | 26.6 | 19.2 | FAIL (ai) |
| valgas | 19 | jump presses /min | 29.5 | 35.1 | PASS |
| valgas | 19 | jumps /min | 9.82 | 13.94 | FAIL (ai) |
| valgas | 19 | runs /min | 25.42 | 55.75 | FAIL (ai) |
| valgas | 19 | spacing p50 cm | 371.0 | 377.6 | PASS |
| valgas | 19 | object-target share | 0.394 | 0.13 | FAIL (ai) |
| valgas | 19 | grabs /min | 0.0 | 0.0 | PASS |
| valgas | 19 | pick-ups /min | 1.73 | 2.42 | FAIL (core) |
| valgas | 19 | object throws /min | 1.73 | 0.0 | FAIL (core) |
| valgas | 19 | PC /min | 1.73 | 0.81 | FAIL (core) |
| valgas | 19 | damage dealt /min | 281.9 | 39.2 | FAIL (out) |
| valgas | 19 | round frames | 3116.0 | None | n/a (no round ended) |

</details>

### 12b. Same-start frame diff of the AI alone (`tests/cpu_replay.gd`)
The port's AI is fed the disc's logged world every frame (both fighters' position, velocity, facing, state, health,
Power Change, hit id; MV_OK, level; the C rand state of the previous frame), P1 then P2 as 0x0C092B8C runs them,
and its Mode / IntLv / Table and button bits (0x604) are compared with the next logged frame (directions are not: the
logs carry no camera yaw; stage objects are not in the logs either, so selections that need them cannot match).
Every log diverges on the first fight frame (frame ~350): the disc's CPUs stand next to a stage object there (Mode
0x30, interrupt 0x02 on +0x71C8) that the replay has no record of. Over whole logs (run before the +0x71C8 change; the
replay has no objects, so it is unaffected):

| log | side | frames | Mode/IntLv/Table equal | buttons equal | selections matched (all) | of them without objects | counter 0x50 | down / projectile 0x90 |
|---|---|---|---|---|---|---|---|---|
| ayame_rouge_L9 | ayame | 11787 | 29.2 % | 97.6 % | 274 / 626 | 274 / 417 | 4 / 5 | 8 / 19 |
| ayame_rouge_L9 | rouge | 11787 | 34.8 % | 96.4 % | 256 / 615 | 256 / 448 | 14 / 19 | 24 / 27 |
| falcon_gunrock_L29 | falcon | 15282 | 29.1 % | 94.4 % | 188 / 785 | 188 / 654 | 29 / 41 | 22 / 42 |
| falcon_gunrock_L29 | gunrock | 15282 | 22.6 % | 93.7 % | 223 / 1176 | 223 / 1031 | 42 / 57 | 24 / 64 |
| falcon_ryoma_L9 | falcon | 14413 | 14.9 % | 96.2 % | 266 / 779 | 265 / 532 | 6 / 13 | 29 / 38 |
| falcon_ryoma_L9 | ryoma | 14413 | 27.3 % | 97.5 % | 214 / 766 | 213 / 509 | 23 / 26 | 52 / 70 |
| falcon_wangtang_L19 | falcon | 12165 | 30.7 % | 94.7 % | 282 / 839 | 282 / 724 | 60 / 76 | 55 / 78 |
| falcon_wangtang_L19 | wangtang | 12165 | 31.5 % | 95.2 % | 153 / 546 | 150 / 458 | 28 / 45 | 18 / 47 |
| galuda_kraken_L19 | galuda | 12826 | 28.6 % | 93.2 % | 349 / 828 | 318 / 609 | 52 / 63 | 17 / 25 |
| galuda_kraken_L19 | kraken | 12826 | 38.7 % | 94.7 % | 216 / 579 | 216 / 445 | 25 / 33 | 28 / 39 |
| galuda_rouge_L29 | galuda | 11348 | 25.4 % | 92.0 % | 186 / 725 | 184 / 587 | 25 / 38 | 25 / 54 |
| galuda_rouge_L29 | rouge | 11348 | 33.4 % | 93.2 % | 96 / 451 | 95 / 357 | 37 / 44 | 9 / 19 |
| gunrock_galuda_L9 | gunrock | 14419 | 20.0 % | 95.2 % | 233 / 677 | 233 / 502 | 38 / 51 | 8 / 45 |
| gunrock_galuda_L9 | galuda | 14419 | 10.1 % | 95.5 % | 116 / 683 | 116 / 452 | 10 / 28 | 30 / 65 |
| jack_ayame_L19 | jack | 13138 | 23.9 % | 95.6 % | 143 / 530 | 141 / 397 | 33 / 46 | 21 / 40 |
| jack_ayame_L19 | ayame | 13138 | 26.2 % | 94.0 % | 223 / 906 | 220 / 698 | 39 / 56 | 62 / 95 |
| jack_valgas_L29 | jack | 8929 | 30.8 % | 94.6 % | 211 / 661 | 211 / 614 | 27 / 37 | 37 / 59 |
| jack_valgas_L29 | valgas | 8929 | 26.1 % | 95.5 % | 115 / 436 | 114 / 384 | 11 / 33 | 7 / 16 |
| kraken_valgas_L9 | kraken | 10237 | 37.9 % | 95.5 % | 179 / 420 | 178 / 339 | 30 / 35 | 32 / 48 |
| kraken_valgas_L9 | valgas | 10237 | 27.5 % | 94.7 % | 163 / 438 | 162 / 368 | 18 / 31 | 14 / 40 |
| rouge_valgas_L19 | rouge | 8562 | 39.0 % | 96.5 % | 134 / 390 | 134 / 329 | 34 / 43 | 21 / 46 |
| rouge_valgas_L19 | valgas | 8562 | 36.2 % | 96.2 % | 115 / 330 | 115 / 273 | 11 / 18 | 25 / 36 |
| ryoma_ayame_L29 | ryoma | 14468 | 43.1 % | 96.1 % | 393 / 858 | 391 / 751 | 60 / 72 | 53 / 82 |
| ryoma_ayame_L29 | ayame | 14468 | 27.2 % | 94.0 % | 288 / 1055 | 284 / 888 | 42 / 60 | 40 / 60 |
| ryoma_gunrock_L19 | ryoma | 11862 | 36.6 % | 96.8 % | 311 / 615 | 311 / 495 | 42 / 49 | 65 / 92 |
| ryoma_gunrock_L19 | gunrock | 11862 | 28.9 % | 95.6 % | 138 / 613 | 137 / 473 | 41 / 46 | 11 / 22 |
| wangtang_jack_L9 | wangtang | 11874 | 28.3 % | 98.2 % | 293 / 696 | 293 / 513 | 7 / 7 | 29 / 38 |
| wangtang_jack_L9 | jack | 11874 | 23.9 % | 97.6 % | 299 / 725 | 299 / 559 | 11 / 12 | 37 / 53 |
| wangtang_kraken_L29 | wangtang | 14938 | 37.1 % | 94.1 % | 266 / 931 | 266 / 776 | 40 / 55 | 44 / 64 |
| wangtang_kraken_L29 | kraken | 14938 | 39.9 % | 92.1 % | 386 / 1026 | 382 / 866 | 31 / 41 | 36 / 46 |

Selections the disc made in the object modes (0x30 / 0x31 / 0x32 / 0x80 / 0x00) are ~0 matched (no objects in the
logs); the counter (0x50) and down (0x90) selections, which only need the fighters, match most of the time; the
default (0x10) less, after the paths have parted. The C rand is shared with the rest of the game, so a selection made on
a different frame draws a different number: the replay re-reads the logged rand every frame.

### 12c. No stalls: seeded CPU-vs-CPU matches on all 11 stages (`stages.sh`: Falcon vs Ryoma, level 25, fight index 7,
PS_SEED 1, played to the result, max 26,000 frames)

| stage | result | rounds (how, P1 / P2 health) |
|---|---|---|
| stg00 | over | TIME 189/238, TIME 232/21, TIME 232/240 |
| stg10 | over | TIME 189/151, TIME 240/164 |
| stg20 | over | TIME 174/237, TIME 239/238, TIME 235/238 |
| stg30 | over | TIME 132/138, TIME 209/156, TIME 228/206 |
| stg40 | over | TIME 211/236, TIME 230/224, TIME 207/237 |
| stg50 | over | TIME 58/81, TIME 240/198, TIME 230/65 |
| stg60 | over | TIME 237/234, TIME 118/153, KO 124/0 |
| stg70 | over | TIME 193/197, TIME 124/127 |
| stg80 | over | TIME 222/181, TIME 199/180 |
| stg90 | over | TIME 223/72, TIME 212/115 |
| stga0 | NOT OVER | TIME 240/240, TIME 240/240, TIME 240/240, TIME 240/240 |

Verdict: **FAIL**: 1 KO in 30 rounds; the others run the 99 s clock out (the disc's CPU-vs-CPU rounds: 2,074 -
4,176 frames mean per pair, mostly KOs, section 10). stga0 (Final Valgas's arena) has no measured playable area /
floor raster (assets/fidelity has no stga0_area.json: fx-oom measured 10 stages): the fighters start in its -393 cm pit
and run into a 136 cm wall at (247, 1320) (StageCollision) that the ledge check (0x400) can't see without the raster; a
collision-ray fallback was tried and dropped (98 % of the time in JUMP 6: it measures the remaster's mesh, not the disc).
Same causes as 12a. The AI itself never freezes: every frame ends on a pad op or a wait (cpu_game_test PASS on all runs).

### 12d. Left (next wave)
1. Final Valgas's own AI (section 9: structure decoded, tables to read, needs pad-driven attacks in his core).
2. The in-fight rank ramp (section 11: measured, the writer of 0x0C7F305D not found).
3. The contact lists the AI reads (+0x294 / +0x2A9 classes, +0x2C0 / +0x2B8 kinds, the side classes of 0x0C09CE6C, the
   reach that sets +0x71C8): the port uses 1.5 m (lon_0's 143 cm lift) for all of them; MOVE50 (0x0C0517A8, 1 use);
   recoverable reactions 0x0C08E8AC (needs the core's).
4. Re-run 12a / 12c after the core's step-up, items, throws, reactions and Power Change land: the AI is not tuned around
   them.

### 12e. Requests for fighter.gd (the lead's)
1. **Step-up onto the measured floors**: `_core_move` steps up only where the remaster's collision ray finds a floor;
   the probes in 12a (stg10 (260, -408) -33 -> 0 cm, Londo (-645, -182) -25 -> 0, Londo (-59, -204) the 55 cm fountain
   base) stop fighters dead (`is_on_wall`, 0 cm/frame for 500+ frames) where the raster (Arena.floor_levels) has a floor
   within the 60 cm step: the CPU's stuck share is 0.074 (0.248 before the +0x71C8 change) vs the disc's 0.005.
2. **Pick-up reach**: `_try_pickup` takes props within 1.4 m; the disc's Falcon lifts the metal chair from 143 cm
   (lon_0: at (-340, -58), chair home (-469, 5), state 35 k2/219 10 frames into the fight).
3. When the attack port lands: the string handler's press counters (+0x7206 taken / +0x7234) so WAIT_7206 (op 82) can
   read them instead of the core's window (gmo_f >= atk_open).
4. Reactions: a "recoverable" flag per reaction (0x0C08E8AC: p[9] == 1, p[10] == 1, +0x71BC == 2, table 0x0C1507A8
   [+0x71DD] != 0) for the 0x800 evade interrupt.


## BUG-41: why the ported CPU lands so little damage (fx-cpu2, 10-27 02:45-03:10, master 35e21d4 merged)
Runs: `tests/cpu_game_test.gd PS_MATCH=1` on Londo, PS_SEED 1, 18,000 frames max, 3 pairs x level 9 (fight index 0) /
19 (fight index 3): falcon-ryoma, wangtang-jack, gunrock-galuda (`/tmp/ps-fx-cpu2/b41.sh`, analyser
`an41.py`: attack start = state into 10 / 11, hit = the opponent's health drops, distance at the start, Mode / Table
time shares, which Mode / Table started each attack). Disc: the cpu_stats logs of the same fighters / levels (P2's home
stage).

| | disc (10 fighter-levels) | port, +0x71C8 reach 1.5 m (fx-cpu2 merge) | port, carried object only | port, reach = the core's | **port, + gstate = gst (committed)** |
|---|---|---|---|---|---|
| damage dealt /min, mean of 12 sides | **184** (112 - 267) | 55 | 39 | 73 (4 - 156) | **77** (9 - 177) |
| hits landed per attack start | 0.45 - 1.29 (mean 0.73) | 0.02 - 0.26 | 0 - 0.59 | 0.01 - 0.44 | 0.04 - 0.41 |
| attack starts /min | 15 - 20 | 18 - 94 | 0 - 23 | 12 - 91 | 7 - 98 |
| distance at attack start, p50 cm | 244 - 543 | 223 - 396 | 200 - 511 | 211 - 415 | 267 - 458 |
| KO rounds | most | 0 of 13 | 1 of 12 | 2 of 12 | 4 of 12 |

Where the starts come from (Mode/Table before the start): disc 30/0 (an object in reach: k1/150 pole swing, k1/78 object
throw, k1/153 > 154 object move, k1/16), 80/0 (zone: k1/10, k1/16), 10/14 (library 14, throw the carried object: k2/225),
50/0 (counter), 90/0. Gaps, biggest first:
1. **+0x71C8 reach vs the core's reach (fixed in cpu_game.gd)**: the AI read objects up to 1.5 m as "in reach" (the disc's
   143-144 cm lift) but the core lifts within 1.4 m and catches poles within 1.1 m: Ryoma at Londo's P2 spawn
   (-340, -58) pressed action for 150+ frames at metal chair 32 (144 cm). Reading "in reach" only for the carried object
   instead made fight 1 (index 0: library 19 only goes for objects) fully passive: falcon-ryoma and wangtang-jack L9 0
   attacks, full-health TIME draws. Now "in reach" = what the core can act on (1.4 m props / 1.1 m poles): mean damage
   55 -> 73 /min, falcon-ryoma L9 146 / 111 (disc 267 / 112), hits per start 0.41 / 0.44.
2. **Punch next to an object (core)**: 3.0 with a stage object in reach and the opponent within 500 cm presses punch
   (Falcon's script 3.0); on the disc that punch is an object move (k1/153 > k1/154: 49 frames, the fighter travels
   ~200 cm, ~8 cm/frame, and the opponent was hit at frame 29 of k1/154 in cpu_falcon_ryoma_L9 frame 389), which ends the
   contact. The core plays a plain punch, the contact stays and 3.0 fires again: wangtang-jack L9 spent 51 % / 49 % in
   30/0 with 373 / 277 starts from it at a constant 373 cm (hits per start 0.08 / 0.05); final run: Wang-Tang L9 still
   56 % in 30/0, 98 starts /min, 0.04 hits per start. The biggest remaining gap.
2b. **State ids (fixed in cpu_game.gd)**: the merged core keeps the original's state id in `gst` in every state
   (reactions 27 / 24, thrower 28, thrown 29, KO 8, carry 35 > 0 ...), but gstate() still mapped the remaster's S-states:
   a fighter in S.DOWN with gst 27 (launched) read 15, so the hit-confirm of the strings (REG_OPP_ST IF_EQ 27 after
   WAIT_7206) stopped them after the first hit, and the opponent-down interrupt 0x20 fired on launches. Now gstate = gst.
3. **Counter cascade**: each whiffed punch arms a hit id, the other's 0x10 counter (situation 5: Falcon's 5.0 jump-kicks
   from 300-500 cm) answers it: falcon-ryoma L19 85 + 106 starts from 50/0 at 367 cm, 0.06 / 0.01 hits per start. Goes
   away with 2.
4. **Held at a ledge (core_ground)**: Falcon on Londo's raised floor at (250, 250, 700) cm sits in state 0 for 3,796 frames
   with the stick held (pad 0x10, APPROACH toward a TARGET_RANDOM point below): the core neither runs nor drops him (the
   disc walks off: state 14). Stuck share (Mode 0x60) 0.09 - 0.63 on 7 of 12 sides in the final run (wangtang-jack L9 P2 0.63; disc 0.005).
Not the cause (checked): waits on a state the core never reports (longest run on one wait op in 9,000 frames,
falcon-ryoma L19 / wangtang-jack L9: WAIT_GROUND 455-462 frames only across KO / win poses, 120+ in transform / down;
WAIT_7206 at most 9 frames, WAIT_FREE 65); attacks starting out of range (the port's p50 start distance 267-458 cm is
inside the disc's 244-543: the disc's long starts are throws / jump attacks).

Requests for fighter.gd (the lead's):
- **Pick-up reach**: `_try_pickup` -> `arena.nearest_prop(global_position, 1.45)` (or more): the disc lifts chair 32 from
  144 cm (lon_0, Falcon at (-340, -58), state 35 k2/219 ten frames into the fight). Then set cpu_game.gd PROP_REACH_M
  to the same value.
- **Punch with an object in reach**: on the ground, punch (X) with a throwable at rest within that reach starts k1/153
  (then k1/154, 49 frames, ~8 cm/frame travel, state 10) instead of the plain punch; with a pole within reach the
  swing k1/150 > 151 > 152 (disc 30/0 starts: k1/150 6x Falcon, 6x Wang-Tang). Expose the object as `reach_obj`
  (+0x71C8: the carried object, else the one a punch / action would act on) and flip cpu_game.gd REACH_FROM_CORE = true.
- **Ledges under core_ground**: idle (gst 0) with the stick held toward the edge of a raised floor must run and fall off
  (gst 31 -> 14) like the disc, not hold: Londo (250, 250, 700) cm, stick toward +z of the camera.

## BUG-41 replay (fx-cpu3, 10-27 05:07-, master ff61291)
**Checker**: `game/tests/cpu_world_replay.gd` (`PS_CPU_REPLAY=dumps/fidelity/cpu/cpu_X.jsonl`, stage = P2's home): every
logged disc frame puts the fighter where the disc had it (feet x/y/z, facing) on a real Arena of that stage and asks
cpu_game.gd's world hooks (0x400 (a) `_w_ai_object_overhead`, the 0x40 stuck counter, 0x1000 `_w_ai_zone`, 0x02
`_w_ai_item_held`); a predicate true while the disc could take that interrupt (Mask bit set, IntLv below) and did not =
false positive (fp), a disc selection of that Mode with the predicate false = miss; places on a 100 cm grid. Stage
objects stay at their home spots (the logs have no object lists). All 16 logs: `/tmp/ps-fx-cpu3/rall.sh`.

**0x40 stuck (Mode 0x60): the port's counter is the disc's.** 0x0C04C078 = the horizontal distance from the player's
+0x20 / +0x28 to the AI block's +0x50 / +0x58 (block 0x0C366F40 + 0x254 * index), sqrt 0x0C0DF340, truncated; counted
in state 2 / 31 while < 5 cm, fires at > 60 and resets on firing. On the disc's own motion (16 logs, ~190,000 frames):
**5 false frames and 1 miss in 47 disc 6.0 selections** (rule "> 61" misses 38, "reset on every selection" misses 47).
The disc gets stuck too (stg20 (-74, 50, -81), state 31, v -9.5, 61 frames -> 6.0 -> pad 0x20). So the port's 0x60 share
is where the remaster's fighters do not move. q41 on master ff61291 (falcon vs ryoma L9, Londo, 6000 f, seed 1):
**Falcon 60/0 0.641, Ryoma 60/0 0.614** (match NOT OVER). Where: Londo's stairs, Falcon 3,705 frames at (50, y 60, 570)
facing -z with velocity 0 in state 31 (running down from the 60 cm to the 30 cm step), Ryoma (-50 / -250, y 60, 550-590)
1,764 + 1,712 frames; the targets there are waypoints at y 167-193 (TARGET_RANDOM points up the stairs). The core stops
them: step fronts marked outside in the area raster. Probe (master arena.gd, `/tmp/ps-fx-cpu3/
stairs_probe.gd`): at x 0.50 / -0.50 / -2.09 m, `wall_at` is true for z 5.45-5.65 m at feet y 0.6 AND 0.3 while
`floor_levels` there is [0.6] (z 5.65) / [0.3] (z 5.45-5.60), walkable from either side; z 5.70+ and 5.35 are open. A
fighter on the 60 cm step running -z stops at z 5.70 (Falcon's 3,705 frames at (50, 60, 570)) (the lead's stairs work: `arena_stepcell_wip.gd`, q_step2: the
stairs cleared, Falcon 0x60 0.115 left at the 240 cm raised floor (350, 240, 690) facing -z, velocity -9.5, no
movement for 500+ frames = held at the ledge, request 3 below).

**0x400 (a) object above (Mode 0x00 -> 10.0 = `JUMP 6`, op 3 toward the target position, then RET)**: on q41 master
Ryoma 00/0 0.20: 224 frames at the fountain base (0, y 56, 100-150) **carrying** (k2/221 CARRY, gst 31) and pressing
jump + direction (pad 0x94 6 frames, 0 for 2-3, again): fighter.gd ignores jump while carrying (`not carry`), so he never
leaves the base, 0x400 fires again at once (q_step2: 893 frames there). On the disc a carrying fighter jumps: the 16
logs have k2/222 state 4 (319 frames) > k2/223 state 5 (4,476) > k2/224 state 6 (240), and the disc's fighters sit in
Mode 0x00 while carrying for 185 frames (109 in k2/223 state 5, 64 in k2/222 state 4). The rest of the 00 frames (300, y 0 -> 225, 600) are jumps
up onto the 240 cm floor that land (fine).
Predicate vs the disc (TRUE share 0.1-3.3 % of frames per side, the disc's 00 share 0.5-7 %): fp 3-249 frames and most
disc 10.0 selections missed (e.g. falcon_ryoma_L9 15 / 23, galuda_kraken_L19 45 / 51, wangtang_kraken_L29 44 / 68): the
raster test 60 cm along the facing is not the disc's contact list (+0x2C0 holds the pieces the fighter touches, and
(b) kind 8 / 16 objects). Contact-length sweep, 16 logs, 543 disc 10.0 selections (fp = frames, miss = selections):

| contact length (CONTACT_M) | 0 (under the feet) | 0.3 m | 0.45 m | **0.6 m (cpu_game.gd)** | 0.8 m |
|---|---|---|---|---|---|
| fp frames | 804 | 1,038 | 1,565 | 1,890 | 2,578 |
| missed disc selections | 527 | 447 | 395 | 357 | 340 |

Ring of 8 points around the feet (any direction) at 0.3 / 0.45 / 0.6 m: fp 5,618 / 6,857 / 7,854, missed 346 / 282 /
214. No length or shape wins both: the raster is the wrong test, not a wrong length; CONTACT_M stays 0.6 (forward).
Decode: **0x0C02629E(shape, piece)** = the touched collision piece's top: by shape type (r4 & 15: 0 / 1 / 2) it copies
16 / 20 / 24 bytes of the piece (0x0C0E6FDC / 0x0C0E6FE8) and returns piece +4 (base y) + piece +16 / +12 (height).
So (a) = "a collision primitive in the fighter's contact list (the pieces its body overlaps this frame, filled by the
collision code) with its top 60-440 cm above the feet", in any direction and in the air too (183 of the 543 disc
selections are in state 5). To score it right the replay needs the pieces (stage collision primitives of each
stgN0: their shape / base y / height / extent) or the logged list +0x2C0 / +0x2D8 (next step 2). The disc's 543
10.0 selections: own state 31 266, **5 (already airborne) 183**, 0 49, 2 45; carrying 59; the jump's top 70 / 330 /
423 cm above the start (p10 / p50 / p90); the floor it lands on vs the start: +60..+240 cm in 224, the same floor (0)
in 70, lower in 140 (the jump took it over an edge). It is a jump up onto / over a solid piece the fighter touches.

**0x1000 zone (Mode 0x80) and 0x02 item held (Mode 0x30)**: misses dominate (zone: nearly every disc 8.0 selection,
e.g. 28 / 28, 20 / 22; item held 46 / 57, 238 / 247): the disc's contact list holds the stage's own pieces (walls,
crates, the fountain) and the objects where they are at the time; the replay only has the props at home. Not a
port-only number: the replay needs the object lists (next steps).

### Requests for fighter.gd (the lead's), from the replay
1. **Jump while carrying**: ground states with a carried stage object and jump pressed -> k2/222 (state 4) > k2/223
   (state 5) > k2/224 (state 6), like the disc (16 logs: 319 / 4,476 / 240 frames). Today `not carry` blocks it, and the
   CPU's 10.0 JUMP 6 at Londo's fountain base (0, 56, 120) repeats for 224-893 frames per 6000.
2. **Carry walk = state 2**: the disc's k2/221 (carrying, moving) is state 2 (5,560 frames), k2/220 (carrying, still)
   state 0 (2,736); the core reports gst 31 / 32 for it (both count for the stuck counter, but 0x400 / 0x10 / scripts
   read the state).
3. **Ledge**: (350, 240, 690) on Londo, state 31, velocity (0, 0, -9.5), no movement for 500+ frames (q_step2): running
   off the raised floor must drop (state 31 falling, then 14), as fx-cpu2's item 4.

### Next steps (BUG-41 replay)
1. (done 05:23: no contact length / ring beats 0.6 m forward; CONTACT_M stays.) A piece-based 0x400 (a) once the stage
   collision primitives are exported (shape, base y, height, extent: 0x0C02629E's layout above).
2. Object lists in the disc logs (tools/cpu_stats.py: walk *0x0C7E4078.. +0x18 per frame: type / kind / x y z /
   sub-state, and the player's +0x2C0 / +0x2D8 / +0x2B8 contact list) so the replay can score 0x02 / 0x1000 / 0x400 (b)
   against the real objects (Flycast k1 / k2).
3. Arena (the lead's / fx-oom's): the Londo step-front band z 5.45-5.65 m that `wall_at` calls a wall (probe above).
4. After the lead's stairs + requests 1 / 3: q41 + the 6-pair re-measure (b41m.sh / an41.py) vs the disc's 184 dmg/min.

## Final Valgas port (fx-fv, 10-27): game/scripts/cpu_fv.gd is his own AI 0x0C08D5CE
Read out of the disassembly (`tools/ghidra/sh4dis.py 0x0C08CB26 1420`; the Ghidra C of /tmp/ps-
fx-cpu/fv_c.txt drops most FPU and division arguments), tables exported by `tools/fv_ai.py export` ->
`game/assets/fidelity/fv_ai.json` (`fv_ai.py dis` prints all 52 command lists in words). `cpu.gd` hands a boss to
`CPUFV` (PS_FV_OLD=1 = the old `_boss_tick` look-alike); `tests/cpu_fv_test.gd` plays him against the ported normal CPU.

**Per frame** (0x0C08D5CE, only while 0x0C0555C4 = round phase 3 and byte 0x0C7F302D == 0, and p+0x10B == 0): pad
+0x2DC, pressed +0x2E4 and +0x7204 cleared; the interrupts 0x0C08D050; then the block state +0 through 0x0C338534.
The block (36 bytes at 0x0C439E38 + player index * 36, reset 0x0C08CAEA by 0x0C08A6C0 when the CPU flag is set: all 0,
+6 = 99, +4 = player): +0 state (0 start list 0x0C33852C, 1 zone lists, 2 an interrupt's list), +1 sub-state (0 init,
1 fetch, 2 run), +2 command phase, +5 command (0 stand, 1 steer, 2 press, 3 random wait, 4 special) via 0x0C338518,
+6 previous command, +7 list index, +8 band, +9 zone the list was picked for, +0xA zone snapshot / steer stop class,
+0xB steer away, +0xC u16 frames, +0xE wait spread, +0x10 list pointer, +0x14 / +0x18 pad words, +0x1C uses of the
Ayame interrupt, +0x1D latches, +0x1E lock, +0x1F interrupt kind, +0x20 s16 his last health.

* **Fetch** (sub-state 1 -> 2, one frame with an empty pad): state 0 re-points the list at the start list when the band
  changes; state 1 picks a list on entry (0x0C08CC26) and again when the band changes or the zone class moved out of
  the one it was picked for (picked 0-3: zone > picked; 4: zone < 4; 5: zone < 5); then the reader 0x0C08D33C.
* **Reader** (bytes; words = (s8 hi << 8 | s8 lo) & 0xFFFF): `00 hi lo` stand, `01 hi lo` / `0A hi lo` steer toward /
  away, `02 a hi lo b` press PADW[a] then PADW[b] after N frames, `03` PCT[0x0C150774] -> state 1 else go on, `04 n m`
  random wait, `05` PCT[ZONE_PCT[zone]] (0x0C338540) -> state 1 else reset to state 0, `06` special, `07` / `08` lock on /
  off, `09` clear latches + lock, anything else reset. PADW (0x0C3383CC) = 0x400 0x200 0x410 0x004 0x014 0x404 0x204
  0x400 0x600.
* **Commands**: stand = pad 0 for N frames (N 0 -> STAND[level bucket][rnd 16] = 60-180), the first frame counts, ends
  early when the zone class changes; steer = the 8-way camera-relative pad toward / away (0x0C08CD7E: atan(dx / dz)
  + 0x8000 if dz < 0, minus the camera yaw, (+0x1000) / 0x2000; DIR 0x0C1505F0) for N frames (N 0 -> STEER[zone][rnd
  16] = 60-360), the first frame only picks the stop class THR[rnd 16] (0x0C338504: 1 x8, 0 x4, 2 x2, 3 x2) and ends
  when the zone class <= it; press = PADW[a] pressed + held on the first frame, PADW[b] on the frame N runs out (N 0 =
  never), done the first frame his state is not 11; random wait = n + rnd(m) + WAIT_ADD[band] (30 15 10 0) + 1 frames;
  special = +0x7204 = 2 for one frame, done once his state is not 33.
* **Helpers** (corrections to section 9): rnd(k) = (u32)(rand() / 32768 * 255) % k (k 0 -> 0, the rand is still drawn).
  % helper 0x0C08CC90 = rnd(32) < T[(level - 20) % 12] (C remainder) - the level, not the band. Band 0x0C08CD18 (not
  while locked) = max(TC[clock / 10], TH[(240 + own - opp health) / 24]) % 4, TC (0x0C3383F9 - k) = 3 3 2 2 2 1 1 0 0 0
  for 0-9 / 10-19 ... 90-99 s left, TH (0x0C3383FA + 20 - h) = 3 3 3 2 2 2 2 1 1 1 1 0 ... for h 0..20: the band rises
  (shorter waits, other rows) as the clock runs down or he falls behind. Zone class 0x0C08CB8C: the opponent more than
  0x271C (55 deg) off his facing (0x0C08A8AA: atan of opponent - him minus p+0x30) and nearer than 700 cm -> 4, else
  < 400 / 600 / 900 / 1500 cm -> 0 / 1 / 2 / 3, else 5. Level bucket = clamp(level - 20, 0, 11) >> 2.
* **Interrupts** (0x0C08D050: only unlocked and in his state 0 / 2, first match wins, each once per latch): opponent
  Ayame (character 6) in state 33 -> list 0x0C338410 (`06`, special) for the first 3 uses, then 0x0C338412 (not locked);
  opponent dizzy (state 13) -> PCT 0x0C150630 -> 0x0C33844C[zone] (locked); opponent in state 23 with +10 set (the
  change into Power Change; +10 not decoded, the port reads the remaster's transform / powered) -> PCT 0x0C15063C ->
  0x0C338484[zone] (locked); his health changed while the zone is 5 -> PCT 0x0C150648 -> 0x0C3384F4[rnd 4] (locked).
  The % tables are 20-28 / 32 at level 20-31 (zone lists 8-24 / 32).

### Final Valgas on the disc (tools/fv_log.py, Flycast fv1 / fv2, Falcon = the game's AI, level 29 frozen)
Way in: arcade as Falcon, fight 1 poked to row 6 index 7 with P2's health frozen at 0 until round phase 4 (poking it
every few frames instead KO'd Final Valgas too: the pokes ran into his fight), A through the story screens until P2's
character byte is 10, then the capture. **His fight is one round**: Falcon's KO -> phase 5 (273 frames) -> CONTINUE?;
his KO -> phase 5 (307) -> the ending (both logs). Logs: /tmp/ps-fx-fv/disc/ (2 rounds so far,
more running). `tools/fv_ai.py stats|attacks|verdict` reduce them.

| | disc L29_a | disc L29_b |
|---|---|---|
| round | 2294 frames, Falcon KO'd (FV 64 left) | 3467 frames, FV KO'd (Falcon 75 left) |
| attack starts /min | 7.8 | 11.4 |
| move mix (first motion) | k1/97 40 %, 99 20 %, 102 20 %, 3 20 % | k1/97 45 %, 102 27 %, 99 18 %, 3 9 % |
| opponent distance at attack start p10 / p50 / p90 cm | 304 / 932 / 1305 | 330 / 695 / 907 |
| frames between attacks p10 / p50 / p90 | 42 / 239 / 255 | 32 / 87 / 288 |
| damage dealt / taken per min | 380 / 231 | 178 / 236 |
| moves (state 2 starts) /min | 3.1 | 7.3 |

What his fighter code does with the pad (measured, `fv_ai.py attacks`): 0x404 -> k1/99 > 100, and the list's second
0x404 120 frames later -> > 101 or > 103 (1 each; the rule is in his attack code); 0x200 -> 97 > 98 (looped) > 104
(5 of 7; 2 hit out of it); 0x204 -> 102 (4); 0x004 -> 3, a second 0x004 20 frames later -> 3 > 17; 0x600 -> nothing.
Things the remaster's boss branch does not do (fighter.gd, the lead's; requests below): **he moves** - in state 2
(k0/1 / k0/2, the steer command's direction pad) he glides ~3.5-4.5 cm/frame (log b: (53, 65) -> (113, 195) ->
(345, 511) -> (142, 950)); **he reacts** to some hits: state 27 k2/0 for 60 frames, then state 5 k0/6 (11 frames),
others take damage with no reaction (state stays 0 / 11: 13 of 41 hits); his KO is state 27 k2/0 through phase 4,
then k0/6 and standing state 0 (his health comes back +1 per 40 frames after hits like everyone's: the game's
recoverable damage); **he throws**
(log a: Falcon in state 29 while he plays k4/1 > k4/3 > k4/5, k4/0 > k4/4: the KO).

### Final Valgas port status (10-27 03:45) and what to do next
Done (committed): the AI (cpu_fv.gd, every table from the BIN), the disc logger + reducers, the pad -> attack map for
the chains the remaster has (fv_attacks.json: 0x404 -> drive_p, 0x004 -> kick1), BUG-31's stall cause in stga0's
area data (the floor holes around his start point, tools/fv_area_fill.py), his fight = one round (fight.gd
_end_round). Before (master): every seeded Falcon vs Final Valgas match TIME, Falcon 'falling' in place at y -10 cm
in the hole for 7,000+ frames, Final Valgas at 232-240 health (rem_old seeds 1-5).
Next: (1) more disc rounds at 21 / 25 / 29 (disc_jobs.sh fv1 / fv2, 6600 frames each; levels 20-23 / 24-27 / 28-31
are his three level buckets) and `fv_ai.py verdict 'disc/cpu_*.jsonl' 'rem_new/rem_s*.jsonl'`; (2) his radius:
dump P2 +0x258 during his fight (fighter_radius.json has none); (3) a frame diff of the AI alone like cpu_replay.gd
(the logs carry his block as `fv` hex: +0 state, +1 sub, +2 phase, +5 command, +7 list index, +8 band, +9 zone,
+0xC frames, +0x10 list pointer); (4) the fighter.gd requests below.

### Requests for fighter.gd (the lead's boss branch), from the disc logs above
1. **Pad-driven attacks** (his state-0/2 pad -> state 11 chain): 0x404 -> k1/99 > 100, a second 0x404 during 100 ->
   101 or 103 (rule unknown: 1 / 1); 0x200 -> 97 > 98 (98 loops while ...) > 104; 0x204 -> 102; 0x004 -> 3, a second
   0x004 20 frames in -> 3 > 17; 0x600 -> nothing. Then cpu_fv.gd can hand the pad over (`input` already carries it;
   `attack_for` / fv_attacks.json is the stop-gap for the two chains the boss attacks have).
2. **He moves**: state 2 with the stick held (k0/1 / k0/2 while turning) glides him ~3.5-4.5 cm/frame toward the pad
   direction; today `_ground_control` zeroes his velocity and `_face_opponent` turns him at once (his zone class 4
   "opponent behind" can never fire).
3. **Reactions**: some hits put him in state 27 k2/0 (60 frames) > state 5 k0/6 (11) > 0, others only take health
   (13 of 41 logged hits; the class rule = REACT.md's records for his attacker's hits); his KO = 27 k2/0 through phase 4,
   then k0/6, standing (state 0) in phase 5. k2/0 / k0/6 are not in pa0.glb yet (capture: tools/add_clips.py).
4. **Throws**: he grabs (Falcon in state 29 while he plays k4/1 > 3 > 5, k4/0 > 4 = 48 + damage); 0x600 pressed
   next to the opponent is the likely trigger (1 logged press, no motion: out of reach).

### Port vs disc (03:47; 2 disc rounds; superseded by the 4-round table below)
`fv_ai.py check` on the disc logs: every state-1 list the disc ran is zone_lists[+9][+7] with +7 in rows[+9][band]
(34 / 34), every state-2 list an interrupt's (20 / 20), every stand / steer / wait frame count one the tables or lists
give (12 / 12, 13 / 13, 30 / 30): the tables, the band and the zone decode right.
Remaster runs: `rem_runs.sh` = tests/cpu_fv_test.gd, Falcon (CPUGame, L29, fight index 8) vs Final Valgas on stga0,
PS_SEED 1-10, PS_MATCH (logs /tmp/ps-fx-fv/rem_old = master's look-alike before the stga0 fill,
rem_new = this branch).

| number | disc min..max | before (master: cpu.gd boss_tick, holes) | after (cpu_fv.gd, filled, 1 round) |
|---|---|---|---|
| attack starts /min | 7.8..11.4 | 14.0 FAIL | 9.3 (5.4..15) PASS |
| opponent distance at attack start p50 cm | 695..932 | 241 FAIL | 212 (76..474) FAIL |
| frames between attacks p50 | 87..239 | 60 FAIL | 193 (33..380) PASS |
| damage dealt /min | 178..380 | 55 FAIL | 71 (0..206) FAIL |
| damage taken /min | 231..236 | 1.2 FAIL | 421 (20..887) FAIL |
| round frames | 2294..3467 | 6002 (TIME) FAIL | 2710 (978..6002) PASS |
| KO share | 1.0 | 0 / 10 rounds FAIL | 9 / 10 PASS |
| move mix k1/99 (99 > 100 ...) | 0.18..0.20 | 0.85 FAIL | 0.18 PASS |
| move mix k1/97 / 102 / 3 | 0.40-0.46 / 0.20-0.27 / 0.09-0.20 | 0 / 0 / 0.06 FAIL | 0 / 0 / 0.83 FAIL |
PASS 0 / 12 before, 5 / 11 after. Stalls (full-health TIME): 5 / 5 seeds before (Falcon 'falling' in the hole), 0 / 10
after (1 TIME round with 66 / 158 health). What is left is his fighter code (requests above): without the 0x200 /
0x204 chains (k1/97 > 98 > 104, 102 = 65-70 % of his disc attacks) he only has 99 > 100 and k1/3 (the 0x004 lists,
82 %); without moving / turning he never gets the zone-4 ("opponent behind") lists (9 of the disc's ~35 state-1 picks) and
fights at 2 m instead of 7-9 m, and he never reacts, so Falcon (CPUGame) wins 8 of 10 with 210-240 health left.

### Hits on Final Valgas (disc, 2 rounds; brief item 3)
Every health drop of his with Falcon's motion / hit id on the frame before and whether he went to state 27 k2/0 within
3 frames: Falcon's Power Change moves k1/99 (12 dmg: 2 of 6 react), k1/100 hit 117 / 118 (6 dmg: 7 of 10), k1/101 (8:
8 of 14), k1/159 hit 119 (6: 1 of 2), his landing kick k0/6 (12: 1 of 1); the object hits k2/245 / 246 hit 16 (14 dmg)
never (7 of 7 none, him in state 0 / 11) and a k2/112 contact once none. So he is knocked about (k2/0 60 frames > state
5 k0/6 11 > 0: no launch, no knock-down, the same 60-frame reaction for every class seen), but not by every hit: the
no-reaction ones come while he attacks (state 11), turns (2) or right after a reaction (state 0 / 5 within ~20 frames)
- consistent with an armour / reaction lock rather than a per-class rule; more rounds + REACT.md's record classes of
those hit ids would settle it. The remaster: damage only, never a reaction (fighter.gd `receive_hit` boss branch).

### Port vs disc with 4 disc rounds (03:52; L29 a-d; verdict = the remaster's mean inside the disc's min..max, each end
### widened 10 %, shares 0.02). `fv_ai.py check` on all 4: list picks 64 / 64, interrupt lists 24 / 24, frame counts
### 18 / 18, 22 / 22, 47 / 47. Mapping now also 0x004 -> k1/2 once (3 of 3: 3, 3 > 17, 2).

| number | disc a-d min..max | before (master) | port + stga0 fill + 1 round | + his radius 140 (rem_new2, seeds 1-4) |
|---|---|---|---|---|
| attack starts /min | 7.0..13.9 | 14.0 PASS | 9.3 PASS | 10.2 PASS |
| opponent distance at attack start p50 cm | 184..932 | 241 PASS | 212 PASS | 297 PASS |
| frames between attacks p50 | 34..239 | 60 PASS | 193 PASS | 164 PASS |
| damage dealt /min | 81..482 | 55 FAIL | 71 FAIL | 195 PASS |
| damage taken /min | 20..248 | 1.2 FAIL | 421 FAIL | 67 PASS |
| round frames | 1809..3467 | 6002 FAIL | 2710 PASS | 4680 FAIL |
| KO share | 1.0 | 0 FAIL | 0.9 PASS | 1.0 PASS |
| move mix k1/97 / 102 / 3 | 0.40-0.67 / 0.20-0.43 / 0-0.20 | FAIL | FAIL | FAIL |
| move mix k1/99 / 2 | 0-0.20 / 0-0.14 | 0.85 FAIL / PASS | PASS / PASS | PASS / PASS |
| PASS | | 5 / 12 | 6 / 12 | **8 / 12** |
Stalls: 5 / 5 seeds before (all TIME), 0 / 14 after (13 KO, 1 TIME at 66 / 158). Who wins: disc 2 / 4 rounds Final
Valgas; remaster with the radius 4 / 4 (111-203 left), without it Falcon 8 / 10. The fails left are the chains his
boss attacks lack (k1/97 > 98 > 104, 102: 65-100 % of the disc's starts) - fighter.gd request 1.

### fx-fv status at 03:52 (supersedes "port status" above) and the next steps
Committed on fx-fv: cpu_fv.gd (his AI, cpu.gd hands bosses to it; PS_FV_OLD=1 = the old look-alike), fv_ai.json /
fv_attacks.json (tables, measured pad -> chain map), tools/fv_log.py (disc logger), tools/fv_ai.py (export / dis /
stats / attacks / check / verdict), tools/fv_area_fill.py + the filled stga0_area.json (BUG-31), his radius 140 in
fighter_radius.json (BUG-33), his fight = one round (fight.gd, run_tests / cine_tests accept it), tests/cpu_fv_test.gd.
Numbers: verdict 5 / 12 -> 8 / 12 PASS, stalls 5 / 5 -> 0 / 14, list picks 64 / 64 against the disc.
Next (in order): (1) the fighter.gd requests above (pad-driven chains 97 > 98 > 104 / 102 / 3 > 17 / the 0x404
branch, moving + turning in state 2, the k2/0 reaction, throws): after them re-run `rem_runs.sh` + `fv_ai.py verdict`;
(2) disc rounds at levels 21 / 25 (`disc_jobs.sh fv1 "21:a 25:a"`: his level buckets 0 / 1, none logged yet; the
arcade always meets him at 29-30 = bucket 2); (3) the hit-reaction rule (armour while attacking / a lock after a
reaction?) from more rounds; (4) a per-frame replay of his AI on the logged world (like tests/cpu_replay.gd: the `fv`
hex in each disc row is his block); (5) the run_tests 'no gem / throwable out of the map' count in falcon vs
finalvalgas on Londo (3,498 frames in the first run of this branch: compare with PS_FV_OLD=1, /private/tmp/
ps-fx-fv/tests/).

### Final numbers at 04:05 (7 disc rounds: L29 a-f + L21 b; `fv_ai.py check` 141 / 141 list picks, 28 / 28 interrupt
### lists, frame counts 28 / 28, 42 / 42, 87 / 87)
Disc rounds: all 7 KOs, 1761-4063 frames; Final Valgas wins 3, Falcon 4. Pad -> chain (fv_attacks.json "disc"): 0x404
99 > 100 (> 103 x3 / > 101 x2 on the second press), 0x200 97 > 98 > 104 (18), 0x204 102 (15), 0x400 96 (3), 0x410
10 > 13 (1), 0x004 3 (2) / 3 > 17 (3) / 2 (1), 0x600 nothing (6).
Verdict (15 rows): **before 9 / 15 PASS** (fails: damage taken 1.2 /min, round 6002 frames TIME, KO share 0, mix 97 /
102 / 99), **port + fill + 1 round 12 / 15** (fails: mix 97 / 102 / 3), **+ radius 140: 11 / 15** (+ round frames 4680
vs 1761-4063: he wins 4 / 4 but slower). Stalls 5 / 5 -> 0 / 14. Every remaining fail is the boss attack set
(fighter.gd request 1). The `run_tests` falcon-vs-finalvalgas suite: 160 / 164 before the test fixes (2 = the one-round
match, fixed in a3e1172; 'no gem / throwable out of the map' 3,498 frames on Londo with the new AI, 0 with PS_FV_OLD=1:
open, an arena / gem case his new fights reach; the 2v2 out-of-map 4 frames at (-4.86, -0.33, 7.35) also with the old AI).

### Last update 04:07 (8 disc rounds: + L21 a; Flycast instances stopped)
`check`: 170 / 170 list picks, 32 / 32 interrupt lists. Verdict: before 10 / 15, port 13 / 15, + radius 12 / 15 (the
k1/97 share entered the disc's spread with L21's 0.235; fails left: mix 102 / 3, + round frames with the radius).
The 'gem / throwable out of the map' fail of run_tests falcon-vs-finalvalgas (Londo, a remaster-only pairing: he only
fights on stga0 on the disc): Londo's prop with home (287, 50, 375) ends at rest at (140, 0, 187) by frame 480 with
the new AI (cpu_fv_test PS_OOM_OBJ=1 PS_STAGE=stg00 PS_SEED=1); not looked into (props / his reach, not his AI). Base
suite on this branch: 164 / 164; Falcon vs Ryoma on stga0 (run_tests PS_STAGE=stga0): 164 / 164, 2 TIME rounds with
191 / 92 and 240 / 192 health (no full-health stall).

## Final Valgas fighter port (fx-fv2, 10-27 06:00-08:30, branch fx-fv2 from 2f8da7d)
His fighter code is read out of 1ST_READ (`tools/ghidra/sh4dis.py 0x0C08A6E4 4100`; Ghidra's C stops at
0x0C08A928) and ported as fighter.gd section "Final Valgas (fx-fv2)" (`_fv_tick`, hooked first in `tick`; `_fv_hit`
from `receive_hit`'s boss branch; `_fv_reset` in `reset_round`). cpu_fv.gd hands its pad words to it (`fv_pad` /
`fv_prs` = +0x2DC / +0x2E4) instead of calling `boss_attack`; `PS_FV_OLD=1` keeps the old path for "before" numbers.
* **Per frame** 0x0C08A6E4: x / z clamped to +-950 cm (his disc start point is that corner: stga0_area spawn (950, 950)),
  then the second presses (state 11, attack 6, phase 2, +0xEE 0, pressed & 4 and pad & 0x400 -> phase 3; attack 4,
  phase 1, +0xEC != 0, pressed & 4 -> +0xF0 = 1), then the state handler.
* **Attacks** = state 11 with +0x7223 (dispatcher 0x0C08A9A8, phase byte +0x0A, timers +0xEC / +0xEE / +0xF0; "end" =
  0x0C0980B0). Pad word -> attack measured on the disc (fv_attacks.json "disc"): 0x200 -> 2, 0x410 -> 3, 0x004 -> 4,
  0x404 -> 6, 0x204 -> 7, 0x400 -> 8 (0x014 -> 5 by elimination, never pressed in 8 rounds). Side test 0x0C08A842 =
  (angle to the opponent - heading +0x30) & 0xFFFF < 0x8000.
  2: k1/97 30 frames > k1/98 (rnd(3) + 1) x 30 > k1/104 to its end (logged 97 30 f x17, 98 30 / 60 / 90).
  3: k1/10 (side) | 6 > k1/13 | 9, -1 / -2 by how far off his heading the opponent is (+0x8E3 / +0x1000 bands).
  4: k1/3 (side) | 2 with +0xEC 45 | 40; a second jump press inside that = k1/17 | 16 when it runs out (logged 3 > 17 at 51).
  5: k1/5 (side) | 4 > k1/17 | 16.   6: k1/99 > k1/100 (+0xEC 46); a second 0x404 in those 46 frames = k1/101 (side) |
  103, or k1/100 again with the opponent within 10 deg (0x71C) of his heading.   7: k1/102.   8: k1/96.
  Motion end (+0x71AA) = clip frames + 2 (logged: 102 111 / 109, 104 34 / 32, 96 82 / 80, 13 34 / 32; 99 93 / 92).
  He never moves while attacking (every logged state-11 frame: position unchanged).
* **State 2** (a direction on the pad): heading turns 0.5 deg/frame toward the stick (0.496-0.503 measured), k0/1 when
  the stick is clockwise of it, k0/2 the other way (picked on entry; logged S - heading -63..-88 for k0/1, +71..+85 for
  k0/2), 4.00 cm/frame along the heading while the stick is within 90 deg (log b f910: 105 deg off, turned in place 119
  frames), none on the entry frame.
* **Reactions**: health only, except the round's first hit under 100 and its first at 50 or less: state 27 for 60
  frames, then state 5 k0/6 5 frames, then 0 (all 13 logged reactions of 8 rounds: 105>99 111>99 104>96 104>92 104>98
  101>96 102>96 / 55>49 53>45 56>50 55>43 54>48, from states 0, 2, 11 alike); KO = state 27 through the KO call.
* **Throws** (attacks 9 / 10, pad 0x600; not ported): k4/2 | 3 for 62-188 frames reaching 199-462 cm, caught = k4/0
  178 > k4/4 175-310 | k4/1 151 > k4/5 286, victim state 29 k4/48 > 51 | k4/49 > 52, 80 damage (120 > 40) or the KO
  (3 catches, 3 misses in 8 rounds). His k4/0-5 and k0/6 are now in pa0.glb (add_clips.py capture A z0, real motions);
  **k2/0 is not**: Motion Check's k2/0 for him is k2/118 frame for frame (an empty slot), archived in the scratch
  `_archive/`, so his reaction keeps the motion on display.
* **Not ported**: his projectiles / beams / shots (effect objects 0x0C062210 / 0x0C0C9834 / 0x0C0CA268 spawned from
  97/98/100/101/102/103/104/96; they land most of his damage, up to 11 m away: fvhits in the scratch); the remaster's
  reach test (BOSS_REACH) over the move row's window stands in for the motions without body spheres. Attack 1
  (k1/0|1|14|15) has no pad word in the logs.

### Numbers (fv_ai.py verdict, disc = 8 rounds, remaster = rem_runs.sh seeds, Falcon CPUGame L29 vs him on stga0)
Remaster after = /tmp/ps-fx-fv2/all8 (seeds 1-4, 6-8; 16 rows now that the disc set has k1/6):
| number | disc 8 rounds | fx-fv end (rem_new2, his old boss attacks) | fx-fv2 (his fighter code) |
|---|---|---|---|
| attack starts /min | 5.3..15.1 | 10.2 PASS | 15.5 PASS |
| opponent distance at attack start p50 cm | 184..932 | 297 PASS | 684 PASS |
| frames between attacks p50 | 34..331 | 164 PASS | 43 PASS |
| damage dealt /min | 13..482 | 195 PASS | 40 PASS |
| damage taken /min | 20..423 | 67 PASS | 5.3 FAIL |
| round frames / KO share | 1761..4063 / 1 | 4680 FAIL / 1 | 6000 TIME FAIL / 0 FAIL |
| move mix k1/97 / 102 / 99 / 3 / 96 | 0-0.67 / 0.2-0.67 / 0-0.33 / 0-0.2 / 0-0.2 | 0 / 0 FAIL / PASS / FAIL / - | 0.19 / 0.149 FAIL (seed 1 alone 0.23) / 0.37 / 0.07 / 0.19 PASS |
fx-fv's own verdict on rem_new2 with this disc set: PASS 12 / FAIL 3; fx-fv2: PASS 12 / FAIL 4 (all 9 move-mix rows but
102 pass now; 102 sits at 0.149 vs the disc's 0.2 lower bound). What fails is the damage exchange: every one of the 7
seeds is a TIME round (Falcon 125-228 left, him 227-240). He fights from 6-7 m as on the disc, but the remaster has
neither his effect objects (beams / shots: the disc's damage at 3-11 m) nor Falcon's (Power Missile etc.: the disc's
Falcon damaged him from range), so neither side lands much at the disc's distances; before, he stood in his corner and
Falcon walked into melee. Next (in order): (1) his effect objects (0x0C062210 / 0x0C0C9834 / 0x0C0CA268: positions,
speeds, the hit records 112 / 113 / 116 they carry) and the attacker-side projectile reach for Falcon's PC moves on
him; (2) the 0x600 throws (attacks 9 / 10 at 0x0C08BB84 / 0x0C08BF28: k4 clips are in the rig now; victim k4/48-52
not captured); (3) a real-fight capture of his k2/0 (capseg P2's skeleton in a disc fight at his first hit under 100);
(4) the brief's item 5 ('no gem / throwable out of the map' in falcon vs finalvalgas on Londo): gone on master and
here (see "fx-fv2 checks"); (5) run_tests in both looks: "fx-fv2 checks" below; his shots: "Final Valgas shots".

## Final Valgas shots (fx-fv2, 10-27 06:35-): his beams / shots / missiles on the disc, as data for fx-shot's PCShots
Disc logs: `tools/fv_shots.py log fv1|fv2 LEVEL NAME` = his fight as tools/fv_log.py takes it (boot_boss, both sides the
game's AI, level frozen) + the whole object pool 0x0C7D0980 (64 x 0x31C) every frame (`cap`, aligned with the rows:
P2's player object slot 1 = his +0x20 / +0x30 on every frame) + both players' object-hit fields (+0xF8 record, +0x71BD
hit id) + both model headings (+0x30). 4200 frames each (~7 min a log): L21 a b, L25 a b, L29 a-d in
/tmp/ps-fx-fv2/shots/ (1.7 GB with the pool frames). His objects = type 1, owner byte 1 (the
type-5 owner-1 slots are looks: no spheres, no hit id). `fv_shots.py objs NAME` lists them, `build` writes
game/assets/fidelity/fv_shots.json in fx-shot's pc_shots.json schema (fighters.finalvalgas[MOTION].shots = [{t, hid,
kind, rows: [[fwd, side, up] cm, heading - his (u16), spheres [[fwd, side, up, r]]]}] + fn / hit / log / f), keyed by his
motion (k1_098 ...: t = rows from that motion's first frame, because his attacks chain motions and the spawns follow
each motion's own rows / timers; frame = his feet on the motion's first frame, his heading +0x30 on the shot's first
frame; he never moves while attacking) and `table` prints this (8 logs: L21 a b, L25 a b, L29 a-d):

| motion | object (handler) | spawned at motion rows | n | life frames | speed cm/f | sphere r cm | hit id (base dmg) | landed |
|---|---|---|---|---|---|---|---|---|
| k1_096 | 0x0C0CB5D6 | 31 39 53 61 | 4 | 36..36 | 10 | - | none (a look) | 0 / 4 |
| k1_096 | 0x0C0CB86C | 39 61 | 2 | 36..36 | 10 | 100 | 115 (8) | 1 / 2 |
| k1_096 | 0x0C0CBA6E | 42 | 1 | 23..23 | 30.9 | 90..100 | 115 (8) | 1 / 1 |
| k1_096 | 0x0C0CBD88 | 53 | 1 | 70..70 | 0 | - | none (a look) | 0 / 1 |
| k1_096 | 0x0C0CBF1C | 31 53 | 4 | 21..34 | 5.23 | 2.3..113.3 | 116 (8) | 1 / 4 |
| k1_098 | 0x0C0CA67E | 1 3 5 | 41 | 139..299 | 5.34 | 2.2..45 | 114 (10) | 16 / 41 |
| k1_100 | 0x0C0C9B08 | 0 | 4 | 84..86 | 14 | - | none (a look) | 0 / 4 |
| k1_100 | 0x0C0CA198 | 0 1 2 3 4 5 6 8 9 10 11 12 ... | 88 | 3..67 | 14.6 | 45 | 112 (8) | 2 / 88 |
| k1_100 | 0x0C0CB344 | 9 19 24 29 44 49 54 59 64 | 9 | 19..19 | 0 | - | none (a look) | 0 / 9 |
| k1_100 | 0x0C0CB456 | 4 9 14 29 34 39 44 49 69 | 9 | 15..30 | 20 | 120 | 113 (8) | 2 / 9 |
| k1_101 | 0x0C0CA198 | 1 4 6 9 11 14 16 19 24 29 34 39 ... | 26 | 3..46 | 17.63 | 45 | 112 (8) | 0 / 26 |
| k1_101 | 0x0C0CB344 | 3 5 8 10 13 15 18 23 33 38 43 48 ... | 18 | 19..19 | 0 | - | none (a look) | 0 / 18 |
| k1_101 | 0x0C0CB456 | 3 8 10 13 15 18 20 23 33 38 43 53 ... | 18 | 15..30 | 20 | 120 | 113 (8) | 1 / 18 |
| k1_102 | 0x0C0CA67E | 12 22 32 | 105 | 138..345 | 8.5 | 2.2..45 | 114 (10) | 64 / 105 |
| k1_103 | 0x0C0CA198 | 2 3 7 12 13 17 22 23 27 28 32 33 ... | 33 | 4..41 | 16.82 | 45 | 112 (8) | 1 / 33 |
| k1_103 | 0x0C0CB344 | 1 2 6 7 11 12 16 17 21 26 27 31 ... | 29 | 19..149 | 0 | - | none (a look) | 0 / 29 |
| k1_103 | 0x0C0CB456 | 1 2 6 12 16 21 22 26 31 32 36 37 ... | 22 | 15..160 | 20 | 120 | 113 (8) | 0 / 22 |

Falcon's damage from him in the 8 logs by hit id (P1 +0x71BD): missiles 114 958, 113 32, 112 24, 115 24, 116 24, the
throw records 34 / 49 / 51 8 (8 or 10 a hit, 11 at level 21, 5 / 2 with the combo cut); fx-fv's 8 older logs add k1/3 / k1/17 body hits (29)
and the throws. None came from k1/99 / k1/100's body (pa0_hit's k1/99 steps arm hit 112 on frames 0-19).
* **Missiles** (handler 0x0C0CA67E, record 114, 10 dmg; spawned by 0x0C0CA268: k1/98 one at its rows 1 / 31 / 61 ...
  = the +0xEE timer of attack 2, k1/102 four to six at once on row 12, a second volley on row 32 in one log): they
  sit on his body (the object's +0x20 still, its sphere r 22.5 following his body) for 46-201 frames, staggered in a
  volley (47 52 53 59 63 69 73 in one), then leave backward and up (pitch 54 deg, 29 cm/frame falling by 1 a frame for
  20 frames: the same in every logged launch), then home at 20 cm/frame turning yaw (+0x30) 910 u16 (5 deg) and pitch
  5 deg a frame toward the opponent (3,196 of 3,198 flying frames), then dive at 51-56 cm/frame turning 145 u16 / 1 deg
  a frame once pointing almost straight down (fv_shots.json "homing" holds these numbers; flight steps measured on 4
  logs); 80 of 146 landed, 71-75 frames after the launch; on a hit (+0x144) or at the end the sphere grows 2.2 -> 45 cm over 20 frames in place (the blast). **Their
  path depends on where the opponent is**: the table's rows are one logged instance that landed (its dive ends where
  Falcon was in that log), so PCShots' fixed-path replay only hits a target standing there; the homing needs a mode in
  pc_shots.gd (fx-shot's: data above, not ported here).
* **k1/100 / k1/101 / k1/103 fireballs** (0x0C0CA198, record 112, 8 dmg, r 45): one every frame or every 5 frames while
  the motion runs, out at 107 cm/frame for a frame, then 14-24 cm/frame, 4-46 frames; with them on k1/101 / 103 the
  r-120 balls of 0x0C0CB456 (record 113 set after the spawn row, 20 cm/frame, 15-30 frames) and looks (0x0C0CB344,
  0x0C0C9B08). k1/100's beam aim (+0x7244 pitch toward the opponent, 10-60 deg, 0x0C08B282) bends them: replayed as
  logged.
* **k1/96** (attack 8): 0x0C0CB86C (record 115, r 100, 10 cm/frame, 36 frames from row 39) and the shockwave
  0x0C0CBF1C (record 116, r 2.3 -> 113 over 34 frames from row 31).
* **The 0x600 throws** start the same way: k4/2 | 3 spawns a grab object (0x0C062210) and the catch is that object
  touching the opponent (0x0C09C894) by row 62, then k4/0 > k4/4 | k4/1 > k4/5 with the victim set to k4/48 | 49 (state
  29); not in the table (no record: the catch is not a damage hit).
* **0x400** = attack 8 (k1/96) 3 of 5 presses, attack 1 (k1/0 | 1: 0x0C08AA2C, 14 | 15 with the opponent higher) 2 of 5
  (L29_c f320 at 190 cm, L29_f f262 at 527 cm): the choice is in his state-0 pad handler, not found yet (the port maps
  0x400 to 8).
**Hook-up** (fighter.gd "Final Valgas (fx-fv2)", live only with fx-shot's pc_shots.gd + shot_land / shot_hit on the
branch, loaded by path so this branch compiles alone): `_fv_shots()` joins fv_shots.json's finalvalgas entry into
PCShots' table in place, `tick()` every frame before his own, `begin(motion) + spawn(0)` on every k1 motion he sets,
`spawn(row)` on its later rows; motions with shots skip the reach stand-in. **Merge request for fx-shot's
`shot_hit`**: its boss branch must call `_fv_hit()` when `_fv_on()` (his 100 / 50 reactions; tested in the scratch
merge). Scratch merge fx-fv2 + fx-shot (/tmp/ps-fx-fv2/combo, uncommitted): cpu_fv_test seeds
1 / 2 / 3 run clean (no script errors), every round still TIME: Falcon left 29 / 228 / 154 (seed 1 alone 132 without
shots), him 216 / 232 / 221: the fixed-path missiles rarely meet a moving Falcon. Next: a homing mode in PCShots
(fx-shot) from the numbers above; Falcon's PC shots on him already run there.

### fx-fv2 checks (07:25): run_tests in both looks, against master 2f8da7d (scratch checkout, classic)
| suite | master 2f8da7d classic | fx-fv2 classic | fx-fv2 remaster (his HD rig rebuilt with k0/6 + k4/0-5, imported) |
|---|---|---|---|
| falcon vs finalvalgas (PS_TEST_CHARS) | 162 / 164: "P1 played attack clips" + 2v2 out of map (gunrock 14 frames) | 163 / 164: 2v2 out of map (the same 14 frames) | 163 / 164: the same |
| PS_STAGE=stga0 (falcon vs ryoma) | 163 / 164: free-for-all out of map (wangtang 7 frames) | 163 / 164: the same | 163 / 164: the same |
Both fails are master's own (Battle Royale rounds, no Final Valgas in them: brawl_tests drops bosses), same frames and
spots. The brief's item 5 ('no gem / throwable out of the map' in falcon vs finalvalgas) no longer fails, on master or
here. Unit checks 53 / 53. rem_runs (7 seeds, this branch alone): see "Numbers" above (12 / 16, every round TIME).
