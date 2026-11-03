# Breakable scenery and the falling piece (BUG-95): decoded spec

Lane pstrailer2, helper fx-brk, 2026-10-27. Source: 1ST_READ disassembly (tools/ghidra/sh4dis.py), two Flycast RAM
dumps taken mid-piece (moves_jack tape, instance bk1: the piece hanging and falling), the 47 round-start RAM dumps of
fx-cov (every stage), checked on every object log (dumps/fidelity/o_*.obj.jsonl) by `tools/breakables.py check`.
Data: game/assets/fidelity/breakables.json (`tools/breakables.py export`). Port: game/scripts/breakables.gd (hooks
marked `fx-brk hook` in arena.gd: build, tick, clear_gems = round reset).

## The breakable (type 4, kind 15, handler 0x0C0B1C24)
- Per stage (round-start RAM, object list `*(0x0C7E4080)` linked by +0x18): Londo 7, stg10 3, stg20 1, stg40 2,
  stg50 5, stg60 4; none on stg30 / 70 / 80 / 90 / a0. Collision shape +0x248 = 2 (axis box): +0x24C centre x, y, z,
  +0x258 half extents (Londo: 74 x 350 x 70 cm, centre 350 cm below the object's home, i.e. the box reaches from the
  sign down to the plaza). Body set +0x102 = 42 (one 40 cm sphere): it is never "hit" by attacks.
- Drawn by the stage layout: part = stage descriptor (+0x308) byte 2 + 10 (Londo's 7 = part 14 = the wall signs; stg10
  21 / 22 / 35, stg20 30, stg40 13 / 32, stg50 18-21 / 40, stg60 34 / 35 / 38 / 39). breakables.json `layout_index` =
  the layout record that draws it (stg50 18-21 hang at (-600, 395, z) while their objects sit at (-500, 60, z)).
- Sub 0 (+8): `0x0C0AC600(obj)` = the first entry of the object's contact list (+0x294, count +0x2A8) that is a fighter
  (+2 == 0) with the reaction machine on (+9 == 1) and reaction class +0x71DD == 22 (the wall splat: k2/152 stuck /
  sliding, k2/153). The contact list is filled by the collision pass (0x0C025D10 family, pair test by shape); box vs
  fighter = 0x0C02180C: overlap_x = half_x + r - |dx|, overlap_z = half_z + r - |dz|, overlap_y = the y spans
  (fighter: feet .. feet + 2h, h = his +0x25C half height) -> contact when none is negative. Fighter r / h (cm):
  Ryoma 40 / 70, Falcon 30 / 75, Wang-Tang 27.3 / 68.25, Jack 34.05 / 85.12, Gunrock 60 / 90, Galuda 48 / 96, Ayame
  31.5 / 63, Rouge 31.5 / 78.75, Kraken 52 / 84.5, Valgas 50.4 / 90, Final Valgas 140 / 165.
  Found -> `0x0C0B1CA8(obj, 1 - toucher+3)` spawns the piece, sub 1 -> `0x0C059330` frees the breakable. It is gone for
  the rest of the round (no respawn timer); the round start rebuilds every object (logged: all back after round end).
- Why the fighter 413 cm below triggers it: the box reaches down to the floor; the splat puts him against the wall
  face inside the box's x / z span.

## The piece (type 2, kind 15, owner = the other player, handler 0x0C0B1D96)
- Spawn (0x0C0B1CA8): new object (2, 1, 0) via 0x0C059132; +3 owner, +4 = 15, +5 = 25, +6 = 5, +0x10 handler,
  +0x20 position = the breakable's home, +0x2C / +0x50 (1, 1, 1) copied, +0x308 descriptor, +0x101 = 16 (attack set),
  +0x102 = 43 (no body spheres), model 0x0C06233A(+0x2E0, 0x0C664958, desc[2]) = the same stage mesh. Shape 0
  (sphere) radius 0: the collision pass pushes it out of the stage wall like any body (Londo: home x 735 -> 730 on
  its first frame, the wall face).
- **Timer** +0xEC = 70 + (u32)(rand() / 32768.0f * 255.0f) % 20 (rand = the game's C rand 0x0C0DF920, the state
  every system shares; the piece takes the first call of its frame). +0x3C (vy) = -2.0.
  Checked: 9 of 9 logged pieces, first fall frame = spawn frame + timer + 1 (timers 81-88).
- Sub 0: --timer; at 0 -> sub 1 and `0x0C0A1E0A(obj, 32)`: +0x100 = hit id **32**, +0xF4 = record 0x0C33AB08 + 32*20
  = `03 20 00 18 07 01 01 00 00 00 00 00 00 04 20 00 03 08 02 00`: class 3 (tumble), base 32, hit-stop 0, type 7 (no
  gem / Power Change bonus, no combo count), level 0, elevation 4, direction byte 0x20 (object flag), no wall splat;
  the 10-entry hit list +0x11C cleared (one hit per fighter).
- Sub 1: y += vy; vy -= 1.0 (cm/frame^2 = 1); if +0x274 > 0 (on the floor since the last collision pass) -> sub 2,
  vy 0, +0x105 = 1, +0xEC = 60, landing 0x0C0ACE56. 297 of 297 logged fall rows exact (538 - (2n + n(n-1)/2), on
  the floor on the 32nd row from Londo's signs).
- Sub 2: freed (0x0C059330) the next frame (logged: on the floor 2 rows, then gone).
- **Hit**: attack set 16 of the object sphere table (0x0C7D08E0 index 4 -> sets 0x0C13FDB0, 2 entries per set;
  spheres 0x0C1411B0) = one sphere, **r 50 cm at the piece's origin**, against the fighter's body spheres while the
  piece is in sub 1 (the landing frame included). The victim must be hittable at the start of the frame: all 7
  logged hits land one frame after the victim's get-up (state 16) ends, whatever the piece's height then (133, 43,
  43, 133, 0, 0, 0 cm); Ayame's tape: the get-up ended on the landing frame -> no hit. Damage 32 on every logged hit
  (Jack held a gem: type 7 has no gem bonus). Reaction: class 3 tumble k2/112 (> k2/115 bounce > lying) through the
  object-hit init (+10 = 2: no hit-stop, no side / class remap, no gem drop). Knockback heading 0x0C08D662 on the
  piece's velocity: vx = vz = 0 -> 0x4000 for every piece (the logged tumbles slide toward -x).
- Not decoded / not logged: whether the piece can hit its owner (the port skips the owner, as thrown objects do),
  what 0x0C0ACE56 draws (landing dust / sound), Power Change body sizes.

## Port (game/scripts/breakables.gd)
Arena.build -> setup (the scenery holder of each breakable + its collision shapes), Arena.tick -> tick (after the
fighters: the piece appears on the splat's first frame, as logged), Arena.clear_gems (every round reset) -> reset.
Break = the holder hidden + its collision off, the piece = a duplicate of the same disc mesh moved by (piece - home);
the hang uses CPUGame.rnd(20) (the shared C rand). Hit = GameHits.overlap(piece sphere 50 cm, Fighter.body_spheres())
-> Rules.game_damage(32, ..., type 7) -> Fighter.receive_hit(..., owner, hid) with the record added to the owner's
table at 1000 + 32 (see "Requests").

## Requests for the lead (fighter.gd)
1. An object-record path into the reaction machine: `receive_hit(..., rec := PackedByteArray())` /
   `react_start(attacker, hid, from, rec)` using the given 20-byte record instead of `_rx_record(attacker, hid)`, and
   the object-hit init (+10 = 2: rx_freeze 0, no side / class remap). breakables.gd now writes the record into
   `Fighter._rx.records[owner][1032]` so react_start finds it (works, but it is a workaround).

## Air throws (BUG-98, part B): what is decoded, what is not
- **State 28 has one entry for hit-grabs**: `0x0C0A2712(p, k4 motion)` (thrower: +9 = 2, +0xA/B = 0, +0x7243 = 10,
  +0x7248 = +0x30 unless state 37, +0x71BB = old state, **+0x71BA = 28**, set_motion k4; victim (+0x1C): +9 = 3,
  +0xA-D = 0, +0x71BA = 29 ...). The only other way into state 28 is the pending action 9 of 0x0C09EA80 (the ground
  counter-grab of an attacking opponent, lead's BUG-98 note: the opponent must stand, +0x71BC == 0, so air throws never
  come from there). Callers of 0x0C0A2712 = the per-character move code (table 0x0C339070): Ryoma 0x0C069BE6, Wang-Tang
  0x0C06EC0C, Galuda 0x0C07AF22 / AFFA / B0A4 / BDCA, Ayame 0x0C07F994, Rouge 0x0C0829F2, Kraken 0x0C085B0E (Falcon,
  Jack, Gunrock, Valgas have no literal call: they reach it through shared code, not traced).
- **The gate** (Ryoma's handler 0x0C069B70, the same shape at the other sites), every frame of the move:
  attacker +0x108 != 0 and `0x0C09C894(p) == 1` (= the opponent is in the attacker's hit list +0x11C (count +0x144) and
  +0x108 == 1) and the opponent is not Final Valgas (+4 != 10) and (the opponent is in Power Change (+0x71F1) or his
  sub-step +9 == 1) -> +0x108 = 0, 0x0C0A2712(p, 3) (Ryoma: k4/3). No distance test anywhere on this path: whether it
  fires depends on what put the opponent into the hit list.
- **Measured** (`tools/airgrab_check.py`, every air punch = state 10 entered with k1/10, 22 o_* tapes + 48 CPU logs):
  21 throws, **all on row 1** (the punch's 2nd frame), none later; 18 air punches landed a normal hit later (rows 5-22,
  the punch's attack set 2) without a throw. k1/10's first hit step (rows 0..4-6, every fighter) arms hit 17 with
  **attack set 0 = no spheres**, so the row-1 contact is not the punch's spheres: the hit list must be filled by
  another test on the press frame. Per fighter (throw / hit without throw / miss): Ayame 2/3/17, Falcon 2/2/22,
  Final Valgas 1/0/5, Galuda 2/2/31, Gunrock 3/1/37, Jack 1/2/19, Kraken 2/4/29, Rouge 0/1/20, Ryoma 4/2/28,
  Valgas 2/1/10, Wang-Tang 2/0/21.
- **The hit list writer** (found): 0x0C0207CA(attacker, victim), the collision pass's hit test: victim +0xFC == 0
  (not hit yet) and +0x106 == 0, owners differ (or one is the stage), victim not already in the attacker's list
  (0x0C0207A2), then **0x0C02343C** = every attack sphere of the attacker (+0x148, 4 for players, 16 B each, built from
  the attack set +0x101) against the victim's body spheres +0x188 entries 1..11 (0x0C023328) -> victim appended to
  +0x11C (count +0x144, max 10), victim +0xFC = attacker. So the air throw IS a sphere contact, on row 1.
- **Not decoded (next step)**: what the attacker's +0x148 spheres are on k1/10 rows 0-1, where the hit step's attack
  set is 0 (empty in every fighter's PL block): stale spheres of the previous motion (the jump) or a builder rule for
  set 0. One Flycast RAM dump on a logged throw's row 0 / 1 (cpu_ryoma_ayame_L29 f784, cpu_wangtang_kraken_L29 f11432:
  replay the CPU fight to that frame, or a moves-style tape with both fighters jumping and P1 air-punching) answers
  it; then port: on row 1 of k1/10, those spheres vs the opponent's body spheres + the gate above -> Fighter's
  hit-grab path with hitgrabs.json (Ryoma k4/3, ...). `tools/airgrab_check.py` scores any candidate rule.
