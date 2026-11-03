# OBJ: the original's object / pole / wall / ledge machines (fx-obj, 10-27)

Decoded from 1ST_READ (SH-4 disassembly `tools/ghidra/sh4dis.py`, Ghidra `all_resolved.c`), measured on the disc's own
48 CPU-vs-CPU logs (`dumps/fidelity/cpu/cpu_*.jsonl`) and a Flycast object log (section 6). Rules + constants:
`game/assets/fidelity/obj_code.json`. Checker: `tools/obj_check.py score` (replays every rule on the 48 logs; the scores
below are its output). Units: cm, cm/frame, frames (60 Hz); headings u16, 0 = +z, 0x4000 = +x; `+0x30` = the player's
move/aim heading (the model faces it), `+0x7248` = the stick/jump direction.

Machinery every section uses:
- **set_state** `0x0C0A2E26(p, state, sub)`: per-state init table `0x0C339490[state](p, sub)`, per-frame handler table
  `0x0C3390D4[state](p)`. State 10 (attack) keeps `sub` in **+0x721F = the attack kind**; the per-fighter state-10
  init (Falcon 0x0C067944, one per fighter, all call the same shared inits) switches on it: 0/2 ground / run string,
  1/3 air, **5 = throw the carried object, 6 = object punch, 7 = pole swing**, 11/12 = turn / off-a-side attacks,
  13 Power Change turn, 15 item use.
- **+0x71BC** = 2 while airborne (0 on the floor). **+0x274 > 0** = floor contact this frame (0x0C09E7B8 clears
  +0x71BC; 0x0C09E7D2 = "no floor").
- **+0x71C8** = the object I touch (or hold); **obj +0x310[player idx]** = "touching this player" (0x0C0AC6A2).
  Object kind tests `0x0C0AC780(obj, q, idx)`: q 1 = pole (touching + kind 2), 2 = kind 3 (-> state 26), 7 = kind 1
  throwable, 11 = kind 4 (-> state 41), 6 = kind 1 or 6.
- Pad bits (the AI's virtual pad = a human's): 0x400 punch, 0x200 kick, 0x004 jump, 0xF0 stick. **The ACTION input**
  (0x0C0A22D6) = punch pressed while kick is held or kick pressed while punch is held (pad 0x600).

## 1. POLES (state 34 > state 10 kind 7: k2/211 > k1/150 > k1/151 > k1/152)

**Catch** (air handler, states 4/5, 0x0C093EE8): airborne + the ACTION input + `+0x71C8` = a pole (kind-2 object)
touching me. The air handler tries, in this order: 0x0C0A2490 (carried-object throw), 0x0C09FF0C -> state 36,
0x0C0A00E4 -> 39, **0x0C09FE68 -> state 34 (pole)**, 0x0C09FEBA -> 26 (kind 3), 0x0C0A01EC -> 41 (kind 4),
0x0C09E470 -> state 10 kind 4. No button = no catch (matches poleprobe.py: standing still never catches).
**State-34 init 0x0C0A0370**: +0x71BC = 2, +0x721C = 0; `+0x30 = heading(feet -> pole axis)`; position snapped to
**10 cm short of the pole axis along +0x30** (`x = pole.x - sin(h)*10, z = pole.z - cos(h)*10`, const 0x0C0A04B8);
y clamped into the pole's height range (0x0C02649A bottom/top of pole and fighter); all velocity / acceleration 0;
motion **k2/211** (+0xEC 15); sub 1 = k2/212 (the hang loop). Logged: the pole's collision then pushes the body
back out, so the k2/211 rows sit **42-62 cm from the axis (p50 45)**; the swing sets +0x2D9 = 2 every frame (the
pole stops colliding) and k1/150 sits on the axis. Reach: on the row before the catch the fighter was **47-150 cm
from the axis (p10 67, p50 94, p90 141, 83 catches)**, i.e. the catch fires when the body touches the pole during
that frame's move.
**State-34 handler 0x0C0968A0** (every frame while hanging):
- jump (0x004) -> let go: state 5 sub 0 (the jump direction +0x7248 = the stick + camera yaw, else +0x30 +- 0x4000);
- **punch or kick pressed (0x600) with +0x721C == 0 -> set_state(10, 7) = the swing** (+0x721E = 1 for kick);
- ACTION + a class-10 contact -> state 39; else the hang sub-machine (+0x0A).
**Swing init 0x0C064152**: +0x2D9 = 2, **k1/150**, **+0xEC = 10 frames**, snap onto the pole axis (0.1 cm short along
+0x30, 0x0C0A022E). **Ryoma and Wang-Tang** (own handler 0x0C069AA6 / 0x0C069ADC): +0x30 = heading to the opponent
already at the press, k1/150 runs its whole clip (**18 f**), then the same launch (heading to the opponent again, axis
snap, solver(35, -3.5)). **Kraken** (own handler 0x0C0848CC): +0xEC 8, **solver(8.0, -0.75)** (consts 0x0C0849DC/E0),
attack set 66 armed by 0x0C0A1D88 at the launch.
**Launch 0x0C06428A** (+0xEC reaches 0): +0x71BC = 2, **+0x30 = heading to the opponent**, then the solver
**0x0C0641A0(vy0, g)** and k1/151 (+0xEC 2):
- vy0 = **35**, g = **-3.5** (Galuda 45 / -2.8; consts 0x0C064418..24);
- D = `*0x0C494D1C` = the fighters' horizontal distance (computed before this frame's player updates) **+100 for
  Gunrock**; **if D < 200 and vy0 > 20: vy0 /= 2** (17.5: the falcon_ryoma_L9 f8855 short hop); D clamped to [1, 800];
- t = -vy0/g; H = (vy0 t - g t^2) / 2; **T = t + sqrt(2 (H + |y - opp.y|) / -g)**;
- velocity = **D/T along +0x30** horizontally, vy0 up, accel g (+0x48). The flight is NOT the remaster's orbit + fixed
  17.3 cm/f out: it is a ballistic hop that lands on the opponent.
**Landing 0x0C064448** (falling, floor contact): Gunrock = camera shake (0x0C0DC18E(30, 20)) + k1/152; Galuda = turn
180 + k1/152; everyone else: if the swing connected (+0x108 and 0x0C09C894) -> turn 180 (not Wang-Tang) + the normal
landing state 6 (k0/9) (Rouge: k1/152); missed -> turn 180 (not Wang-Tang) + **k1/152** (+0xEC 35; logged 16-50 f).
The swing's hit = the k1/151 attack set (attack set 6 / hid 66, HITS.md).

Score (obj_check.py on the 48 logs):
| rule | score |
|---|---|
| catch: airborne before k2/211 | 84/84 |
| catch: ACTION (0x600) on the catch frame | 72/84 (12 = the AI's press landed 1 frame early, pad 0x50 on the row) |
| k1/150 starts on a punch/kick press | 83/83 |
| k1/150 holds still on the pole axis | 83/83 |
| k1/150 10 f (Ryoma / Wang-Tang 18 f) | 80/81 (59/81 without the per-fighter rule) |
| launch vy0 35 / 17.5 (Galuda 45 / 22.5, Kraken 8) | 81/81 |
| horizontal speed = D/T within 2 % | 81/81 |
| aimed at the opponent within 1 deg | 76/81 |
| gravity 3.5 (Galuda 2.8, Kraken 0.75), per flight frame outside hit-stop | 1488/1503 |
| k1/152 then idle | 44/44 |

**Port (fighter.gd, lead)** - replace `_try_pole` / `_pole_update`'s orbit model:
1. Catch only from the air (gst 4/5 or a reaction flight) on the ACTION press (punch + kick, `ic.is_pressed("action")`)
   with a pole within reach (keep `arena.nearest_pole`, reach = the body touching the pole; the disc logs put the
   fighter 10 cm from the axis right after the catch): gst 34, k2/211, heading = toward the pole axis, position =
   axis - 10 cm along it, y clamped to the pole, velocity 0. No button pressed = keep hanging (k2/212 loop).
2. While hanging: jump = drop off (gst 5, stick direction); punch or kick = the swing.
3. Swing: gst 10, k1/150 on the axis for 10 frames (Ryoma / Wang-Tang 18), then heading = toward the opponent and the
   solver above (D = horizontal distance to the opponent, +100 cm Gunrock, vy0 halved under 200 cm, clamp 800),
   k1/151 with vy0 up, g down (-3.5, Galuda -2.8) per frame, D/T horizontal, until floor contact.
4. Landing: missed = turn 180 (not Wang-Tang) + k1/152 then idle; connected = turn 180 + the normal landing k0/9;
   Gunrock shakes the camera. Kraken: vy0 8, g -0.75 (a slow floating hop, never halved).

## 2. WALL KICK (state 38: k2/206 > k0/13)

**Trigger** (air handler 0x0C093FB8 -> **0x0C0A0C4C**): nothing held (0x0C09C6B8 == 0), **+0x721A == 0 (one wall
kick per airtime)**, jump pressed this frame, stick held (any direction), and **0x0C09CD32 returns a side class 4..7**
= I touch a stage wall OR an object at rest (type 2, +0x30D 0, obj +0x2D9 != 2) on that side -> set_state(38, side).
**Init 0x0C0A0984**: +0x71BC = 2, +0x721A += 1, velocity 0, **k2/206**, **+0xEC = 8**, `+0x30 = (side - 4) * 0x4000`
(an axis heading into the wall).
**Handler 0x0C0971CE**: punch/kick pressed (0x0C09E768) -> +0x30 += 0x8000, set_state(10, 1) = an air attack off the
wall (logged k1/10 14x, k1/16 6x); else after 8 frames -> +0x30 += 0x8000 (away from the wall) and set_state(5, 3).
**Kick-off** (state-5 init sub 3, 0x0C09F250 -> 0x0C09E39C): k0/13; per-fighter movement table **0x0C339540 + char *
0x98 + PC * 0x4C** (19 floats): **vy = +40 (25.0 for all)**, gravity = **+24 (Falcon/Ryoma/Wang-Tang/Galuda/Ayame/F.Valgas
2.0, Jack 1.08, Gunrock 1.15, Rouge 1.3, Kraken 1.2, Valgas 2.1)**, horizontal = **+44 (2.0 cm/f) along +0x30**, then
the normal air control of state 5 (the stick adds up to ~6-9 cm/f, logged). Same table: +16 standing jump vy 35.5
(Wang-Tang/Ayame 40, Jack 27, Gunrock 25.8, Rouge 30, Kraken 27, Valgas 37), +28 moving-jump speed 10.5, +56 run
speed (9.5; Wang-Tang/Ayame 10.5, Jack/Rouge 10, Gunrock 8.5, Kraken 9).

| rule | score |
|---|---|
| from the air (state 4/5) or a reaction flight | 79/79 |
| jump + stick on the kick frame | 73/79 (6 = Final Valgas logs, pad not his) |
| frozen through k2/206 | 79/79 |
| k2/206 8 f before k0/13 | 57/57 |
| kick-off vy 25 | 57/57 |
| gravity = table +24 | 57/57 |
| no stick: 2.0 cm/f straight off the wall | 10/10 |
| punch/kick during k2/206 -> air attack | 14/21 (7 = k1/16, the ground punch kind: the AI pressed on the landing frame) |

**Port**: the remaster's wall jump (`WALL_JUMP_OUT` 6.5 m/s + 0.95 x jump) is wrong: freeze 8 frames in k2/206
(velocity 0, facing the wall), then face away and launch vy 25 cm/f (table +40), the fighter's wall gravity (+24),
2.0 cm/f out + normal air control; once per airtime (reset on landing); objects at rest count as walls; punch/kick
during the freeze = an air attack facing away.

## 2b. AIR ACTION (BUG-27: k1/53 > k1/54, state 10 kind 4)
Last entry of the air ACTION list (section 1): **0x0C09E470** = at least **150 cm above the floor below**
(`y >= +0x2D4 + 150`) and the opponent NOT airborne -> set_state(10, 4). Shared init **0x0C06384A**: k1/53,
horizontal velocity 0, **vy 20, gravity -2.8** (consts 0x0C063898 / 9C); per-fighter handlers change it (logged,
63 uses, every fighter but Gunrock):
| fighter | k1/53: vy0, frames | k1/54 dive vy (straight down, horizontal 0) |
|---|---|---|
| Falcon / Rouge / Ayame | 20, 14 f | -15 |
| Ryoma | 20, 14 f | -25 |
| Kraken | 20, 10 f | -15 |
| Valgas / Galuda | 40, 10 f | -20 |
| Wang-Tang | 0, 10 f | -8 |
| Jack | 0, 11-14 f | -10 |
Horizontal 0 through k1/53 63/63; then k1/54 (11-18 f, the dive until the floor) > k1/56 / k1/55 / k1/146 (landing
variants). **Port**: in the air, the ACTION press with no pole / object / wall in reach and >= 150 cm of air below
(opponent on the ground) = this dive (the remaster has no move there, BUG-27).

## 3. OBJECT PUNCH (state 10 kind 6: k1/153 > k1/154 vault, k1/78, k1/59)

**Select** (state-10 init 0x0C0A1AC0, at 0x0C0A1BF0): a ground punch/kick (kind 0/2) that starts a string (chain
entry byte 0 == 0), not in Power Change, `+0x71C8` = a **kind-1 throwable at rest** (+0x30D 0) touching me:
punch -> always set_state(10, 6); kick -> only if `|heading(feet -> object) - +0x30| <= 60 deg` (0x2AAA).
**Init 0x0C063EAC**: kick -> **k1/59** (+0xEC 13: kick the object); punch: `d = heading to the opponent (0x0C09DB78) -
heading(feet -> object)`:
- **|d| >= 90 deg** (the object is behind me): `+0x30 = heading to the opponent + 0x8000` (turn to the object),
  **k1/153 (10 f, no horizontal move, gravity continues) then k1/154 (49 f) moving 4.0816 cm/f along +0x30**
  (const 0x0C0640EC); on k1/154 frame 6 the object is sent back over the fighter at the opponent (6b); then free
  (0x0C0A2080, idle k0/0);
- **|d| < 90 deg**: `+0x30 = heading to the opponent`, **k1/78** (33 f, +0xEC 8): the object is flung at the opponent
  (section 6 measures the object's flight).

| rule | score |
|---|---|
| k1/153 10 f | 90/90 |
| no horizontal move in k1/153 | 90/90 |
| k1/154 49 f (or a hit) | 85/88 |
| k1/154 velocity 4.0816 away from the opponent (per frame, 0.05) | 3572/3913 (heading from both fighters' positions on the k1/153 row; the rest: the opponent moving fast that frame, a few degrees off) |
| ends in idle k0/0 | 85/88 |
| k1/78 33 f / no move | 58/59, 59/59 |
| k1/59 33 f | 2/2 |

**Port**: in `_core_attack`, before the normal punch / kick: if the core's pick-up reach finds a light throwable at
rest touching the fighter (BUG-41's "object in reach", 1.45 m) and this press starts a string (not a follow-up, not
in Power Change): punch -> compare the heading to the opponent with the heading to the object:
- < 90 deg: face the opponent, k1/78 33 f in place; on its frame 8 the object leaves level along that heading at the
  fling speed (6b) and flies until it hits a fighter (damage 6b) or anything else (break -> respawn 900 + 90 f);
- >= 90 deg: face the object (= away from the opponent), k1/153 10 f in place, then k1/154 49 f moving 4.08 cm/f
  along that facing; on k1/154 frame 6 the object flies level toward the opponent (heading to him at that frame);
kick within 60 deg of the object = k1/59 33 f (the object's kick flight not logged yet).
Code of the releases: k1/78 handler 0x0C063FD4 (+0xEC 8 -> effect 9 + release 0x0C0633C0: still touching + kind 1
-> object set_state 0x0C0ABE44(obj, 10, idx) + sound 35); k1/59 handler 0x0C064016 (+0xEC 13 -> 0x0C063318, the kick
release); k1/153 > k1/154 handler 0x0C064056 (sub 0: k1/153 to its end, then k1/154 with +0xEC 6 and the 4.08
cm/f move; sub 1: the release at +0xEC 0 = sub 11). The flight speeds come from the object's own sub-state inits
(0x0C0ABE44 -> sub 10 / 11 / 8), not decoded: use the measured 15 / 20 / 25 / 30. This is BUG-41's biggest gap
(Wang-Tang whiffing next to objects); the CPU's 3.0 rule (CPU.md) then stops refiring because the object is gone.

## 4. CARRY THROWS / LIFTS (from the logs)
- **Pick-up chooser 0x0C0A19DC** (0x0C0A2490, on the floor, the touched object +0x71C8): a floor item (kind 6)
  unless its id (+0x30C) is 15 / 16 / 17; **at rest (+0x30D 0) and kind 1 or 6 -> state 35** = pick-up k2/219
  (17-18 f: 163/239 18 f, 76 17 f) > carry k2/220 idle / k2/221 walk / k2/222 > k2/223 jump-carry; **kind 1 NOT at
  rest (flying / dropped) -> state 25 = CATCH it**: init 0x0C0A1844: k2/226 (19 f, 15/15 logged, > k2/220),
  +0x71BC 0, **+0x30 = heading to the opponent**, object -> sub 5 (carried), +0x7236 = 1 (the logged ~6.5 cm/f is
  the run that led into it). So k2/226 is catching an object out of the air, not a heavy lift.
- **Weight** = property byte 6 (`0x0C33BFD8 + 10 * obj+0x314`): 0 anyone, 1 not Jack / Ayame / Rouge, 2 only
  Gunrock / Galuda / Valgas; Power Change lifts anything (filters 0x0C0AC55C / 0x0C0ABF64). Only property 4 has 2
  (Wang-Tang's dojo part 21, below); all Londo objects are 0.
- **Dropped (sub 4)** = the carrier was hit (state 27) or let go in the air (16 logged in lonA-C): 1 frame owned by
  the carrier, then owner 2, starting **180 cm above the carrier's feet** (the overhead hold), **vy +10, gravity 2**,
  horizontal **5.0 cm/f** slowing ~0.5 % a frame, 39-65 f until the floor -> rest **where it lands** (no respawn;
  13/16) or break if it hits something (sub 2, 2/16).
- throw = kind 5 (0x0C063CB2): on the floor **k1/60 36 f** (17/19); **airborne (+0x71BC 2) k2/225** (~42 f) with a
  velocity set from +0x30, then the landing k0/9 (157/159). k1/78 is the punch-next-to-an-object throw (section 3),
  not the carry throw.

## 5. LEDGES (state 14) and run-offs
No edge stop exists: floor contact is re-tested every frame (+0x274). Idle / walk-stop with no floor under the feet
(idle handler 0x0C093812 -> 0x0C093840) -> **set_state(14, 0)**: k0/6, horizontal velocity 0, gravity 2 cm/f^2 from
vy 0, land -> state 6 (8/8 logged). A runner (state 31) whose floor ends keeps running while it falls (390 logged
run-offs, all state 31). **Port**: the remaster's step code must never block a move because the floor ahead is LOWER
(BUG-41: Falcon held 3,796 frames at Londo (250, 250, 700)): drop-offs are free, only rises above the step-up height
block; idle / stop over air -> gst 14 straight down.

## 6. Object records + the object log (Flycast o1)
Lists `*(0x0C7E4078 + 4*(type-2))`, linked by +0x18, records 0x31C bytes: +2 type, +3 owner (0/1 player, 2 stage),
+4 kind, +0x10 handler, +0x20 x,y,z, +0x2D9/+0x2DA flags, +0x308 stage descriptor, +0x30C item id, +0x30D sub-state
(0 rest, 3/5 carried, 6-12 flying), +0x310 u8[2] touching player 0/1, +0x314 property index. Londo (a RAM dump in a
CPU fight): type 2 = 9 throwables (kind 1), 2 poles (kind 2, the lamps at (440, 0, -256) / (-428, 0, -256)), 2 kind-4
objects high up (y 487 / 660: state 41), 2 kind-8 at the fountain, the item chest (kind 7, +0x30C 9 = the item);
type 3 = the 3 Power Stones; type 4 kind 15 = 7 breakables; type 6 = an item on the floor (+0x30C its id).
Object log: `tools/obj_log.py INST P1 P2 FRAMES NAME OBJS` (CPU vs CPU, level 19, the 17 Londo objects above every frame; lonA / lonB / lonC in /tmp/ps-fx-obj/logs),
decode with `obj_check.py objlog`.

### 6b. What the objects do (object log lonA: Ryoma P1 vs Falcon P2, Londo, level 19, 12,000 frames, 9 throwables)
Throwable sub-states (+0x30D, handler 0x0C0AE034 switch, 13 entries): **0 rest** (owner 2) / **5 carried** (owner =
player) / **10 flung by k1/78** / **11 flung by k1/154** / **8 thrown from the carry** / **4 dropped** (the carrier
was hit: 1 frame owner = player, then 44-47 f falling as owner 2, then rest) / **2 break** (1 frame, on any hit or
wall) / **3 respawn wait**.
- **k1/78** (punch, object toward the opponent): the object leaves on **k1/78 frame 8**, flies **straight and level
  (vy 0) along +0x30 = the heading to the opponent at 15 / 20 / 25 cm/f** until it hits something (11 of 11).
- **k1/153 > k1/154** (punch, object behind me): the fighter turns AWAY from the opponent (toward the object) and on
  **k1/154 frame 6 the object flies back over him toward the opponent**, level, at 20 / 25 cm/f (9 of 9); the
  fighter keeps backing off at 4.08 cm/f for the rest of k1/154. It is an over-the-head object attack, not a vault.
- **Carry throw** (k2/225 in the air, release on frame 15; k1/60 on the floor): the object flies **3D-aimed at the
  opponent** (vy included, e.g. -21.65 from 350 cm above), 20 / 25 / 30 cm/f (17 of 17).
- **Speed** = the thrower's row of the throw-speed table below (decoded), column by throw kind and property byte 7.
- **Respawn (sub 3, 0x0C0ADDDE)**: hidden at its home spot for **900 frames** (+0xEC counts to 0x384), then **blinks
  for 90 frames** (0x0C0E6E5C), then back at rest = **991 frames after the break** (21 of 31 breaks; the others 1031 /
  1121 / 1161: the counter pauses while 0x0C0555DC is set = a game freeze, e.g. a 130-f Power Change transform; a
  round end resets every object). The remaster respawns 2 frames after the break (BUG-26 note): wrong, it must stay
  away 900 f + blink 90 f.
- **Londo's throwables** (exact match of the object homes to `stg00_layout.json` parts; property = obj +0x314):
| layout part | home x, y, z (obj +0x20) | property | stage descriptor (obj +0x308) | object record |
|---|---|---|---|---|
| 24 | 591, 50, 145 | 2 | 0x0C33B570 | 0x0C7D47B0 |
| 25 | 448, 50, 350 | 1 | 0x0C33B57D | 0x0C7D4ACC |
| 26 | 224, 50, 501 | 1 | 0x0C33B58A | 0x0C7D4DE8 |
| 28 | 287, 50, 375 | 10 | 0x0C33B597 | 0x0C7D5104 |
| 30 | 461, 50, 519 | 10 | 0x0C33B5A4 | 0x0C7D5420 |
| 32 | -469, 25, 5 | 3 | 0x0C33B5BE | 0x0C7D5A58 |
| 53 | -645, 0, 456 | 2 | 0x0C33B5F2 | 0x0C7D66C8 |
| 54 | -513, 50, 456 | 2 | 0x0C33B5FF | 0x0C7D69E4 |
| 55 | -576, 25, 878 | 2 | 0x0C33B60C | 0x0C7D6D00 |
- **Every stage's throwables** (a RAM dump of each stage at the round intro, Flycast o1 / o2, CPU vs CPU at the home
  stage; object home = +0x20 matched to the nearest `stgN0_layout.json` part, exact (0-2 cm) unless listed:
  stg10 part 15 23 cm, stg20 19 35 cm, stg40 22 / 38 / 39 / 40 22-103 cm (stacked crates at y 50 / 150: check by
  hand), stg60 43 12 cm, 64 107 cm). Kind-1 objects at rest; property -> base damage / speed / weight above:
| stage | throwables (layout part: property, weight) | not in stgN0_info "throwable" (the disc throws them) | poles (part) |
|---|---|---|---|
| stg10 | 11: 1, 12: 1, 14: 7, 15: 1, 33: 1, 37: 11 | 11, 12, 33 | 23, 24 |
| stg20 | 11: 2, 12: 2, 13: 2, 14: 2, 15: 2, 16: 2, 17: 2, 18: 2, 19: 1, 20: 1, 21: 4 (w2), 25: 5 | 21, 25 | 22, 23, 24 |
| stg30 | 20: 1, 21: 1 | 21 | 19 |
| stg40 | 22: 1, 23: 1, 33: 1, 34: 1, 35: 1, 39: 1, 37: 1, 38: 1, 39: 1, 40: 1 | - | 20, 21 |
| stg50 | 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 26: 9, 27: 9, 28: 9, 29: 9 | 11, 12, 13, 14, 15 | 31, 32 |
| stg60 | 11: 1, 12: 1, 13: 1, 43: 1, 44: 1, 64: 12 | 11, 13, 43, 44, 64 | 15, 16, 46 |
| stg70 | 11: 7, 14: 7, 15: 7, 16: 7 | 11, 14 | 17, 18, 19 |
| stg80 | 11: 1, 12: 1, 13: 1, 14: 1 | - | 18, 19 |
| stg90 | 10: 1, 11: 1, 13: 1 | 13 | - |
  The "not in stgN0_info throwable" column = objects the disc lets you lift that the remaster builds as scenery.
  Full rows (homes, match distance): obj_code.json `stage_throwables`.
- **Release geometry and speed** (lonA + lonB, 50 releases):
| release | start position | direction | speed cm/f (property 1 / 3 \| 2 / 10) |
|---|---|---|---|
| k1/78 frame 8 (sub 10) | **where the object lies** (it is touched, not in the hand: 6-190 cm ahead / aside of the feet), at its own rest height (obj y unchanged) | level, along the thrower's +0x30 (heading to the opponent) | Ryoma / Wang-Tang 15 \| 20, Falcon 20 \| 25, Gunrock - \| 35 |
| k1/154 frame 6 (sub 11) | where the object lies, its rest height | level, along +0x30 + 180 deg (= toward the opponent) | Falcon 20 \| 25, Wang-Tang 15 \| 20 |
| carry throw (k2/225 frame 15 / k1/60, sub 8) | **50 cm forward, 80 cm up, 0 side** of the thrower's feet in the +0x30 frame (Gunrock 60 forward, 96 up) | 3D, straight at the opponent's hip (aim point 95-120 cm above his feet, p50 ~105: his +0x148 hip) | Ryoma / Wang-Tang 20 \| 25, Falcon 25 \| 30, Gunrock 35 \| 40 |
  **Decoded: the per-fighter throw-speed table 1ST_READ 0x0C33C05C + char * 24** (6 floats, read by the object's
  sub-state inits, sub 10 at 0x0C0ADB5C: column +12 if property byte 7 != 0 else +8): columns = carry throw (byte 7
  0 / 1), fling k1/78 + k1/154 (byte 7 0 / 1), 2 more (kick? not tied). Property byte 7: 1 for properties 1, 3, 4,
  5, 7, 8, 11, 12; 0 for 2, 6, 9, 10.
  | fighter | carry (b7 0 / 1) | fling (b7 0 / 1) | cols 4 / 5 |
  |---|---|---|---|
  | Falcon | 30 / 25 | 25 / 20 | 30 / 25 |
  | Ryoma | 25 / 20 | 20 / 15 | 20 / 15 |
  | Wang-Tang | 25 / 20 | 20 / 15 | 25 / 20 |
  | Jack | 20 / 15 | 15 / 10 | 20 / 15 |
  | Gunrock | 40 / 35 | 35 / 30 | 30 / 25 |
  | Galuda | 35 / 30 | 30 / 25 | 35 / 30 |
  | Ayame | 20 / 15 | 15 / 10 | 25 / 20 |
  | Rouge | 20 / 15 | 15 / 10 | 20 / 15 |
  | Kraken | 30 / 25 | 25 / 20 | 25 / 20 |
  | Valgas | 40 / 35 | 35 / 30 | 40 / 35 |
  `obj_check.py objscore`: 71 of 73 logged releases (lonA + lonB + lonC) match their cell exactly; the 2 others = a
  fling that fell off a ledge (20.1 incl. its vy) and one that hit on its first frame.
- lonB (Gunrock P1 vs Falcon): carry-throw release on k2/225 f15 11/11, aimed 10/11, k1/78 f8 1/1, k1/154 f6 2/2.
- Score (`obj_check.py objscore lonA.bin lonA.meta.json`): k1/78 release on frame 8 11/11, k1/154 release on frame 6
  9/9, carry-throw release on k2/225 frame 15 17/17, fling level 18/19 and along the thrower's +0x30 19/19, speeds
  multiples of 5 cm/f 35/36, carry throw aimed at the opponent 16/17, respawn 991 f (or + a freeze) 31/33 (the 2
  others were cut by the round end, which resets every object).
- **Damage** (health drop of the fighter hit, Falcon as the victim at CPU level 19, 11 hits of 38 breaks; the rest
  broke on walls / the floor): property 1 = 30 / 32 / 30, property 10 = 23 / 22 / 23 / 22, property 2 = 23,
  property 3 = 18 (victim mid-attack); the victim goes to k2/112 (tumble) or k2/173. The fling (k1/78, sub 10) and
  the carry throw (sub 8) hit equally hard.
- **Base damage (for Rules.game_damage)**: the hit uses the object/item attack records **1ST_READ 0x0C33AB08**
  (20 B like the fighters': b0 class, b1 base damage of 240, b2 hit-stop) at the index in **property byte 0**:
  property 1 -> record 19 = **base 32** (measured 30-32), properties 2 / 10 -> record 17 = **base 24** (22-23),
  property 3 -> record 21 = base 40 (the one logged hit, 18, landed on an attacking victim), property 4 -> 23 = 48,
  5 -> 25 = 32, 6 -> 33 = 32, 11 -> 21 = 40. Bytes 1-5 (0x0A-0x0C = records 10-12 base 24 / 12 / 24, 7 / 8 = 12 / 40,
  0x10-0x14 = 24-40) are other hit cases (kicked / rolling / dropped?) not tied yet. Full table: obj_code.json
  `object_damage`.

## 6c. Items / weapons (measured on the 48 logs; code not decoded yet)
Every item is held with one of 4 shared kind-2 motion families, picked by the item (floor item = type-6 record,
+0x30C = its id; the chest = type-2 kind 7, +0x30C = the item inside; Londo's chest held id 9). Pick-up = state 35;
holding rides the normal states (0 idle, 2 walk, 31 run, 32 stop, 4/5/6 jump) with the family's motions; use =
state 10 kind 15 (`+0x721F` = 15 when the held class != 1, state-10 init 0x0C0A1B1A).
| family | pick-up (st 35) | idle / walk / run / stop | jump 4 / 5 / 6 | use on the floor (st 10) | use in the air | logged |
|---|---|---|---|---|---|---|
| A (lonA: item ids 0 and 2) | k2/195 24-25 f | 194 / 196 / 202 > 203 / 204 | 198 / 199 / 200 | k2/197 (40-53 f) | k2/201 (24-38 f) | 24 pick-ups, 9 + 16 uses |
| B | k2/229 24-25 f | 230 / 231 / - / - | 232 / 233 / - | k2/235 36 f | k2/236 21 f | 9 / 6 + 2 |
| C | k2/237 23-25 f | 238 / 239 / - / - | 240 / 241 / 242 | k2/243 52 f, k2/245 31 f | k2/244 18-40 f, k2/246 31 f | 12 / 12 + 13 |
| D | k2/247 19-20 f | 248 / - / - / - | 250 / 251 / 252 | k2/253 | k2/254 43 f | 3 / 3 |
Also seen: k2/207 (2 f) > k2/208 = states 41 / 36 (the hang on a kind-4 object / a class-9 contact, entered from a
jump on the ACTION input, section 1's air list), k2/205 (29 f, states 10 / 11) after k1/100 / k1/12.

## 6d. Overhead grabs from the air ACTION list (states 36 / 41, logged; inits 0x0C0A07E4 / 0x0C0A0B78 not read)
- **State 36** (0x0C09FF0C: a class-9 contact above, return 1 / 2 = sub 0 / 2), 11 logged: **k2/207 2 f** (or 20 f
  + k2/208 hold 47 f) at the grab height, then **k1/162 26 f** in place, **k1/163** (13-24 f: up ~130-150 cm, then
  down), then a drop attack **k1/171 22 f** / k1/170 36-37 f / k1/164 40 f, and the landing. Entered at y 267-440
  on the ACTION press (pad 0x600 11/11).
- **State 41** (0x0C0A01EC: a kind-4 object touching, e.g. Londo's two at y 487 / 660), 3 logged: k2/207 20 f
  holding, then k0/8 falling 35-37 f to the floor, landing k0/9.

## 7. Not done yet (next steps, in order)
1. Columns 4 / 5 of the throw-speed table (the k1/59 kick flight?), the object's flight end rules (wall break,
   floor landing of a carry throw).
2. Object damage bytes 1-5 of the property record (which hit uses which record), and Rules.game_damage on the bases.
3. Items: map +0x30C item id -> family A-D and each use's projectile / damage / ammo (object log of the type-6 slot
   + the type-5 shots it spawns: lonA's slots 0x0C7D7654 / 0x0C7D7970 carry them; kind-15 handlers per family).
4. The pole hang sub-machine (+0x0A, k2/212), k1/156 > k1/157 (24 logged, from runs), states 26 / 39 (kind-3 /
   class-10 contacts), the inits of states 36 / 41 (0x0C0A07E4 / 0x0C0A0B78).

## 8. fighter.gd requests (lead), by player impact
1. **Object punch** (section 3 port): punch / kick next to a light throwable at rest = k1/78 fling (object level at
   15-35 cm/f from frame 8) / k1/153 > k1/154 over-the-head fling (object from k1/154 frame 6, fighter backs off
   4.08 cm/f) / k1/59. Evidence: 90 + 59 + 2 logged, release frames 11/11 + 9/9 in the object log. Fixes BUG-41's
   biggest AI gap (3.0 refiring next to objects) and BUG-26.
2. **Poles** (section 1 port): ACTION catch in the air, punch/kick swing, k1/150 10 f (Ryoma / Wang-Tang 18) on the
   axis, the D/T solver flight at the opponent (81/81 logged launches within 2 %), landing rules. Replaces the orbit
   model (POLE_OUT 17.3 / POLE_UP 36 / sweep).
3. **Wall kick** (section 2 port): 8-f freeze, vy 25, 2.0 out + air control, per-fighter gravity (+24), once per
   airtime, objects at rest count (57/57 logged kick-offs). Replaces WALL_JUMP_OUT 6.5 m/s.
4. **Object respawn**: hidden 900 f + blink 90 f (991 f), not 2 frames; object speed = the 0x0C33C05C table (6b).
5. **Ledges**: never block a move because the floor ahead is lower; idle/stop over air -> gst 14 straight down.
6. **Air ACTION dive** k1/53 > k1/54 (section 2b) for BUG-27.
