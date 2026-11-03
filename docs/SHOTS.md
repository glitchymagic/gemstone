# Power Drive / Fusion shots (decoded from the disc, fx-shot)

fx-shot, 2026-10-27. The hits a Power Change move delivers away from the attacker's body are pool objects: the move
code (0x0C339070[char], PC.md) spawns them into the object pool and they hit on their own. The remaster had no such
objects, so most Drives did a fraction of the disc's damage (Ryoma's PC part 101 -> 42, Gunrock 132 -> 0, ...).
Tool: `tools/pc_shots.py` (tapes / log / build / check). Table: `game/assets/fidelity/pc_shots.json`. Port:
`game/scripts/pc_shots.gd` (PCShots) + fighter.gd section "PC shots (fx-shot)" and its hooks in the PC part.

## How it was logged
- Tapes `game/tests/tapes/shot_<fighter>.tape` (pc_shots.py tapes): the moves_<f> Power Change presses (Drive X, Y,
  air X, air Y, Fusion A+X; then 3 gems again + Fusion A+Y), each from a fresh placement at full health: part A = P2
  240 cm ahead (moves_ PC geometry; Falcon on Ryoma's stage like moves_falcon), part B = P2 farther (420 cm) and 150 cm
  to the side, part C = Fusion A+Y.
- Flycast (instances sh1 / sh2, pc_shots.py log): the reflog rows + the 64-slot object log (covlog) + the victims'
  record pointer +0xF8 and hit id +0x71BD every frame, and the WHOLE pool (0x0C7D0980, 64 x 0x31C) dumped every frame
  for 110-420 frames after each press -> `dumps/fidelity/shots/` (o_shot_<f>.{jsonl,obj.jsonl,hit.jsonl,meta.json},
  pool/<f>/<row>_<move>/NNNNN.bin; pool file i = log row press + 1 + i).
- **`@place` leaves the fighter's model heading stale on the disc**: it writes +0x7248 only, but the moves (their
  travel, their shots) use the player pool object's +0x30 (slot 0 = P1, 1 = P2). The v1 logs (archived in
  shots/_v1/) had P1 walking his Drive X along a heading left over from the transform's camera yaw. v2 tapes poke
  +0x30 with every place on the Flycast side (pc_shots.build_txt: `poke16 0x0C7D09B0` / `0x0C7D0CCC`). **Every
  fidelity tape that uses @place has this on the disc side** (the stale heading shows in moves_ / pc_ logs too).
- The v1 stale headings are what showed each move's own turn toward the opponent (below).

## The shot object (pool slot, 0x31C bytes; measured on the dumps)
| offset | what |
|---|---|
| +2 / +3 / +4 | type 1 (shot / effect with hits), owner (0 = P1), kind (per move: Ryoma Drive Y pillars k9 > k5 by distance) |
| +0x10 | per-frame handler (in the move code, e.g. Ryoma 0x0C0B8604 Drive X, 0x0C0B8F9A Fusion X) |
| +0x1C | the owner's player struct |
| +0x20 | x, y, z (cm) |
| +0x30 | heading (u16); homing shots turn it (+0x38 their speed, accelerating) |
| +0x100 | hit id (the owner's attack record: 0x0C338A98[char] + id x 20); +0x101 active (2 / 5, 0 after its hit) |
| +0x11C | the victim, after the hit |
| +0x144 | hits landed (never above 1 in any log: a shot hits once) |
| +0x148 | attack spheres, 16 bytes each: world x, y, z, r (cm); r = 0 = off. Ryoma X: 2 spheres r 48 at y + 160 / + 50, Drive Y pillars 2 x r 30 growing with the pillar, Fusion X petals 1 x r 35 |

The victim's +0xF8 / +0x71BD (logged per frame) confirm the record: every shot hit in the logs carries the shot's
+0x100 id (Ryoma: Drive X 114, Drive Y 120, air X 117, Fusion X 121, Fusion Y shot 124).

**0x0C08DEEC is not the shots' hit** (PC.md / REACT.md called it "object hit"): its 34 callers are in the move code
with r4 = a PLAYER (motion frame tests such as `+0x719E == 76 -> hit 51`) and it applies the record to that player's
+0x1C (the opponent): a throw / grab hit. The shots' hits behave like body hits (hit-stop from the record, launch from
the hip on the next frame).

## Rules (from the logs)
- **Spawn**: on a fixed row of the move (row 0 = the k1/16 frame / the Fusion's first), at a fixed offset in the
  attacker's frame: his feet on row 0, his model heading on the shot's first frame. Part A vs part B agree within
  0-10 cm for every non-homing shot (pc_shots.py check).
- **Path**: per frame in that frame, as logged (falling bolts, ground pillars, arcs). The table holds the logged rows;
  where part A's shot hit early and part B's same shot flew on, B's rows extend it.
- **Hit test**: the shot's live spheres (+0x148) against the fighters; port = GameHits.overlap against the victim's
  body spheres (the same body sets the body hits use).
- **Once per shot**, and **one shot hit per victim per frame** (Ryoma Drive Y: two pillars overlap P2 at row 30, the
  second hits at row 31).
- **Damage** = the record (rec[1], type rec[4]) through Rules.game_damage: type 3 / 4 records take the Power Change
  x1.2 (Ryoma: 8 -> 9, 7 -> 8, 12 -> 14), the attacker's combo cut applies (Ryoma Fusion X: 14 x5, then 7, 3, 1, ...).
  No recovery after them (the attacker is in PC).
- **Timing**: the hit frame shows the damage with the victim untouched (state 27, motion unchanged); his reaction
  starts on the NEXT frame (launch to the hip, then the record's hit-stop rec[2] - 2 rows: Drive X rec[2] 4 -> 2 held
  rows). The pool runs after the players. Port: damage at once, react_start from the victim's next tick.
- **Reaction side**: with the heading poked right (v2), P2 facing the attacker gets k2/96 (front), the same choice
  the remaster's react_start makes. v1's k2/128 came from P2's stale model heading.
- **Gems**: no gem dropped on any shot hit (all logged shot records have rec[16] & 0xC = 0); the port uses the body-hit
  rule (_spill_n by the record).
- **Turn toward the opponent** (v1 part B, stale heading -> the move's own turn; table `turn`): most ground Drives /
  Fusions face the opponent on row 1 (Wang-Tang X, Jack Fusion Y on row 2); Ryoma's Drive X turns 1820 (u16) a row for
  4 rows (from 0x91C7 it stops at 0x7557, not facing him); Kraken X / Y / Fusion Y turn 1225 / 142 / 1495 a row for
  7-9 rows; Falcon X and Fusion Y, Gunrock Y and Fusion Y, Rouge Fusion Y keep the heading; the air Drives keep it.
  Port: fighter._shot_turn on the PC rows (the travel follows the new heading, as the disc's does). Moves whose v1
  heading already pointed at P2 have no evidence and use the common rule (row 1 snap, marked `assumed`).

## Port (fx-shot) and numbers
- `PCShots` (game/scripts/pc_shots.gd), one per fighter (`Fighter.shots`): `begin` on the move's row 0 (origin = the
  feet), `spawn(row)` on every PC row (shots whose t = row appear in the fighter's current heading and are tested at
  once), `tick` first thing every frame (fighter._pc_frame): next row, sphere test against the enemies' body spheres.
  Hit -> `Fighter.shot_land` (record by hit id from react_code.json, Rules.game_damage via _hit_damage, combo count)
  -> victim `shot_hit` (damage, gauge drain, no recovery) and `_shot_react` on his next frame (gem rule, facing,
  react_start). The PC timeline's reach fallback (_check_hit) is off for moves that have shots (their disc hits ARE
  the shots); `_game_hit_update` (the motion's own body spheres) stays. `_shot_turn` applies the move's turn rule.
- Checker (`tools/pc_shots.py check`, 82 logged drives incl. the lead's moves_ object logs): part A 272 / 272 shots
  at their logged row, 0 cm (the table's source); part B (P2 elsewhere) every non-homing shot's spawn within 0-37 cm
  in the attacker's frame; 180 / 272 B shots spawn on the same row (Gunrock's rocks, Valgas' X / Fusion X bursts and
  the homing ones depend on the distance), mean path error 68.7 cm (homing shots dominate: Ryoma 106, Falcon 207,
  Galuda X 189 cm; fixed ones 0-10).
- Remaster runs (fidelity_run.py rem, master 2f8da7d snapshot vs this branch, same tapes; dmg = P2's damage):
  disc / before / after. shot_ part A per press, part C = Fusion Y.

| fighter | Drive X | Drive Y | air X | air Y | Fusion X | Fusion Y | part B (5 presses) | moves_ PC part | pc_ tape |
|---|---|---|---|---|---|---|---|---|---|
| ryoma | 9 / 0 / 9 | 24 / 14 / 16 | 11 / 0 / 12 | 0 / 0 / 0 | 85 / 14 / 91 | 102 / 27 / 18 | 115 / 14 / 32 | 101 / 69 / 51 | 220 / 14 / 69 |
| falcon | 38 / 28 / 38 | 0 / 0 / 0 | 0 / 0 / 38 | 0 / 0 / 0 | 104 / 14 / 0 | 170 / 14 / 14 | 55 / 14 / 38 | 104 / 42 / 52 | 241 / 42 / 52 |
| wangtang | 14 / 14 / 14 | 29 / 0 / 0 | 14 / 0 / 14 | 0 / 0 / 0 | 144 / 14 / 19 | 69 / 9 / 9 | 140 / 14 / 14 | 90 / 37 / 37 | 140 / 0 / 14 |
| jack | 26 / 4 / 4 | 38 / 0 / 0 | 22 / 0 / 0 | 38 / 0 / 0 | 120 / 0 / 0 | 122 / 16 / 99 | 69 / 0 / 0 | 97 / 20 / 103 | 133 / 0 / 0 |
| gunrock | 35 / 36 / 55 | 35 / 14 / 14 | 35 / 0 / 36 | 35 / 0 / 0 | 99 / 36 / 55 | 117 / 14 / 0 | 240 / 0 / 0 | 227 / 14 / 0 | 175 / 0 / 0 |
| galuda | 14 / 14 / 14 | 0 / 18 / 18 | 0 / 0 / 0 | 17 / 0 / 0 | 0 / 0 / 0 | 0 / 1 / 1 | 14 / 0 / 32 | 45 / 15 / 15 | 45 / 0 / 14 |
| ayame | 24 / 28 / 24 | 0 / 4 / 0 | 24 / 0 / 24 | 0 / 0 / 0 | 105 / 14 / 45 | 101 / 14 / 14 | 168 / 14 / 45 | 149 / 56 / 38 | 194 / 14 / 14 |
| rouge | 39 / 14 / 21 | 46 / 14 / 0 | 21 / 0 / 21 | 0 / 0 / 0 | 46 / 14 / 72 | 85 / 1 / 0 | 152 / 14 / 52 | 100 / 29 / 76 | 168 / 14 / 76 |
| kraken | 52 / 14 / 14 | 0 / 9 / 12 | 52 / 0 / 14 | 0 / 0 / 0 | 127 / 0 / 0 | 56 / 14 / 0 | 231 / 0 / 0 | 170 / 28 / 26 | 241 / 0 / 13 |
| valgas | 55 / 28 / 60 | 32 / 24 / 33 | 0 / 0 / 0 | 46 / 0 / 48 | 100 / 14 / 79 | 83 / 14 / 70 | 191 / 14 / 125 | 141 / 56 / 102 | 225 / 14 / 197 |

  Totals: shot_ tapes (all 14 parts x 10) disc 4035 / before 605 / after 1477; moves_ PC parts disc 1224 / before
  366 / after 500; pc_ tapes (P2 680 cm off) disc 1782 / before 98 / after 449. Exact (within 1) on the shot_ press
  parts: before 65 / 140, after 74 / 140 (the empty parts count on both). Exact matches now: Ryoma X 9, AX ~ (12 vs
  11), Falcon X 38, Wang-Tang X / AX 14, Galuda X 14, Ayame X / AX 24, Rouge AX 21, Valgas Y 33 vs 32.
- Why the rest still differ (not the shots' table: each one checked in the runs):
  - Gunrock: the remaster stands him at y 183 cm on Londo at (-180, -330) (the disc: 0) in every moves_ / shot_ part
    -> his shots start 183 cm up and miss (Drive X / air X land only from the reach of the old path).
  - Falcon (Ryoma's stage): the disc clamps the tape's place (-297, -30, -89) to (-265, 0, -68) (an area edge); the
    remaster keeps it -> P2 208 cm off on the disc vs 240 here; his Fusion X missiles (homing) then miss.
  - Homing shots (Open): Ryoma / Falcon / Wang-Tang / Ayame Fusion X, Galuda's Drives.
  - The victim after the first hit: the remaster's launch / reaction pose differs (Ryoma Drive Y: the second pillar
    meets P2 at 278 cm, 119 up on the disc; the remaster's body spheres in k2/96 frame 1 sit higher, fx-reach's travel
    pin), so follow-up shots miss (Drive Y 24 -> 16, Gunrock / Kraken multi-shot moves).
  - Moves whose hits are not type-1 shots: Jack's Drives (type-5 effects with no spheres + body hits), Kraken Fusion X,
    the Fusion Y body hits: the existing hit code.
  - Rouge Drive Y / Kraken Fusion Y / Gunrock Fusion Y lost the reach fallback's 14 (the disc's hits are their shots,
    which miss here for the reasons above).
- Base suite run_tests.gd: 164 / 164 in both looks (PS_LOOK=remaster and classic, 07:17), no new Godot errors (the
  runs show only the usual exit leaks). Unit-only: 53 / 53.

## Open
- **Homing shots** (tables replay part A's paths, P2 240 cm ahead; from elsewhere they fly to the logged spot): Ryoma /
  Falcon / Wang-Tang / Ayame Fusion X, Galuda's Drive X and air X (handlers 0x0C0B8F9A, 0x0C0B8430, 0x0C0BA090,
  0x0C0C1186, 0x0C0BDC20). **Ryoma's Fusion X petals are decoded** (0x0C0B8F9A, phase byte +8): phase 0 sets +0xEC 90
  (life), +0xEE 25 (straight frames), +0xF0 40; phase 1 every frame: while +0xF0 > 0 (--) and once +0xEE reaches 0
  (then held at 1): target = the opponent's joint matrix at player +0x300 (+0xDC0 in PC form; its translation = the
  hips, 107 cm over the feet standing), yaw +0x30 += clamp(atan2(dx, dz) - yaw, +-0x0AAA), pitch +0x2C +=
  clamp(atan2(-dy, horizontal) - pitch, +-0x071C), speed +0x44 += 0.27778; velocity +0x38/3C/40 = speed x (sin yaw,
  sin -pitch, cos yaw) (no cos-pitch factor); position += velocity; +0xEC 0 -> off (phase 2). So: 24 rows straight at
  15 cm/f, 16 homing rows, then straight. The yaw reproduces the log exactly (shot_ryoma part B, 16 rows); the pitch
  drifted a few cm a row against a feet+107 target. With the real target logged (`SHOT_JOINT=1 pc_shots.py log`:
  the +0x330 translation of both players' joint matrix, shots/_v3joint/o_shot_ryoma.joint.jsonl: the hips, y 120
  standing, 58 lying) a simulation of the rule above over all 42 petals of shot_ryoma still ends 58-68 cm mean off
  (one petal exact for 16 rows), so a piece is missing (the straight-phase length per petal / the order of the turn
  and the move): not ported; the table's fixed paths stay. Port it per handler once exact (the others use other
  constants: Galuda's clamps 0x0222).
- **Damage formula** (Rules.game_damage, not this lane): most shot records match (Ryoma 114: 8 -> 9, 120: 7 -> 8, 121:
  12 -> 14 and the combo cut), but 117 (Ryoma's air Drive X, hit after he landed) logs 11 where the formula gives 12,
  and his Fusion Y body record 122 logs 11 (formula 9).
- **Look** (w8 11-02, tools/shot_look.py, was: invisible): a shot object carries its draw nodes (+0x2DC count, +0x2E0..
  pointers to 0xA4-byte nodes in 0x0C36C000..: node - 0x54 = world matrix rows X / Y / Z / T in cm with the scale in it,
  node - 8 = the model part, in the attacker's EFn0.MDL (loaded whole, part table before it) or the common bank in
  1ST_READ 0x171088 (textures EFKY_MODEL.BIN; Ryoma's air Drive X = flipbook parts 68-71)). `SHOT_NODES=1 SHOT_TAG=_nd
  pc_shots.py log` re-logs a shot tape with that node region every frame (same tape, deterministic: same shots as the
  table's logs); shot_look.py build turns each table shot's nodes into its attacker frame per row
  (game/assets/fidelity/pc_shot_look.json), shot_look.py glb exports the parts used (game/assets/ripped/effects/,
  untracked disc data: run it after a fresh rip). PCShots draws them on the shot's rows, offset from the shot's own position
  (Valgas' Fusion Y lands on random spots: the unseeded rand), the translucent list unshaded (dst ONE = additive, src
  alpha x face alpha 0.75), the opaque list lit (Gunrock's boulders, Falcon's missiles, Kraken's bomb). Common-bank parts
  142-176 are the item meshes: ITEM_MODEL.BIN textures (Kraken's bomb = part 151), the rest EFKY. Checked against the
  disc's own frames (`SHOT_PICS=row,row SHOT_TAG=_pic pc_shots.py log`: Flycast screenshots on those tape rows): Ryoma's
  bolt, Gunrock's boulders, Kraken's bomb, Ayame's blades, Jack's beams, Valgas' Fusion bursts in place. Hidden
  (shot_look.HIDE): Valgas' 6 m Drive X sphere (EF90 part 0, opaque, tex 12) is a white / pink blast on the disc, a solid
  teal ball with the plain material: the disc colours some parts per frame (not decoded). Coverage: 222 of the table's
  shots carry nodes with parts. Ryoma: Drive X = the falling lightning bolt (part 0, 24 x 783
  cm), Drive Y = the slash wave + pillars, air Drives, Fusion X sparks. Not drawn yet: effects that are not type-1 shot
  objects (Fusion Y, the petals' own glow: their nodes have no part, a separate effect object draws them).
- Moves whose hits are not type-1 shots (Jack's Drive X: type-5 effects + body hits; the Fusion Y body hits) keep the
  existing hit code (_game_hit_update, else the reach fallback).
- **Jack's Drives (w6 11-02, measured on shots/o_shot_jack)**: Drive X is a burst of kind-5 effect objects from his hand
  (pool slots 34-56, ~8-30 cm/f forward at 100-130 cm up, stopping at a wall ~415 cm), and the disc hits P2 with
  record 112 every 5 frames for 4 (P2's +0xF8 0x0C330F08 = Jack's record 112, not an object: BUG-111), pushing him 60 -> 161 cm over 12
  frames. The remaster's shot tables hold type-1 shots only, so none of these exist in-game: Jack's PC damage disc /
  remaster: Drive X 26 / 4, Drive Y 38 / 0, air X 22 / 0, air Y 38 / 0, Fusion X 120 / 0, pc_jack 133 / 0. Port: add
  kind-5 paths to tools/pc_shots.py build, measure their hit reach from the hit frames (nearest kind-5 object to P2's
  hips), the 5-frame repeat, then decode the handler to confirm.
