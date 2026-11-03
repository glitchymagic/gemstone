# REACH: where the disc draws the body and where it hits (helper fx-reach, lane pstrailer2, 2026-10-27)

BUG-97 "drawn body / hit spheres ahead of the fighter". The fidelity core moves a fighter by the disc's logged travel and
plays the RAM-captured clip on top; the WIP travel pin (lead-w4 5581dcd) fixed near X for some fighters but lost far X
hits that land on the disc (Gunrock's far k1/16 at 234 cm). This pass measured the disc's own sphere centres and fixed
the drawing rule against them.

## 1. The disc's truth, per frame, in a real fight
tools/reachlog.py = tools/reflog.py's same-input tape run (both pads human) plus, per player and frame, the game's own
hit-test spheres straight from RAM: +0x148 the 4 attack spheres (f32 x, y, z, r world cm; r = 0 = not live), +0x188 the
12 body spheres, +0x330 the hip joint (part 0's world matrix, row 3). +0x101 / +0x102 = attack / body set.
All 10 moves_* tapes captured (Flycast instances re1 / re2, 3,516 frames each): /tmp/ps-fx-reach/disc.

What the spheres say:
- **Every sphere radius = the file radius x the joint matrix's scale.** The fight draws each fighter at its own joint
  scale; joint-to-joint distances disc / clip give the same number (Gunrock forearm-hand 27.08 / 22.56 cm = 1.200):

  | fighter | normal | Power Change |
  |---|---|---|
  | Falcon | 1.0 | 1.05 |
  | Ryoma | 1.0 | 1.04 |
  | Wang-Tang | 0.91 | 1.0 |
  | Jack | 1.135 | 1.4 |
  | Gunrock | 1.2 | 1.3 |
  | Galuda | 1.2 | 1.22 |
  | Ayame | 0.9 | 0.94 |
  | Rouge | 1.05 | 1.05 |
  | Kraken | 1.3 | 1.3 |
  | Valgas | 1.2 | 1.2 |

  Some moves scale single limbs further for a few frames (Gunrock's kick k1/25 foot x1.4, k1/24 x1.3): not modelled.
- The RAM-captured clips (tools/clips.py: local rotations + the RAM bone offsets, root = the hip's world position) keep
  the disc's hip height but the raw (unscaled) bone offsets. So the remaster drew Gunrock / Jack / Galuda / Kraken /
  Valgas / Rouge with limbs 5-30 % short and the feet hovering (ankle joints 37-47 cm above the floor vs 20-26 on the
  disc), Wang-Tang / Ayame 10 % long with the feet 5-8 cm in the floor, and every sphere radius at the file value.
- **The hip** (the disc's hip joint vs the clip's b00, both from the feet in the fighter's facing frame): clip frame =
  game frame - 1, minus the table travel the core already moved the fighter by (motions.json), is exact (0-3 cm) for
  every logged ground attack of all 10 fighters. Exceptions: the air attacks k1/10 / k1/12 (the clip's hip flies
  110-196 cm forward with Motion Check's jump travel; the disc keeps it over the feet) and a few long-travel moves whose
  table is not the clip's own travel (k1/74 for 7 fighters, Ryoma k1/26 / 27, Falcon / Gunrock k1/19, Ayame k1/22 / 29,
  Wang-Tang k1/26, Galuda k1/16): 20-64 cm.
- **Throws**: the thrower's hip = the k4 clip's hip minus the thrower path (throws.json), 0 cm median on all 10 grab
  attempts (Ryoma's k4/7 was drawn 42 cm off, Ayame 12 / p90 163).
- Hit frame: the remaster's tree showed clip frame gmo_f - 2 at the hit test (one frame late, cross-faded over the first
  4 frames): the disc shows clip frame g - 1 at its frame g.

## 2. The rule (code)
- psmodel.gd: `_apply_joint_scale` = b00's pose scale from game/assets/fidelity/body_scale.json (per form) -> limbs,
  meshes and sphere offsets at the disc's size; the hip (b00's own position) stays the clip's.
- game_hits.gd: a joint sphere's radius x the joint's scale (root spheres unscaled, as on the disc).
- psmodel.gd `core_frame(clip, g, table_pin)`: the core attack's pose = clip frame g - 1 exactly (state machine start +
  advance), the pin = the table travel, or the disc's own hip per game frame from game/assets/fidelity/hip_pin.json
  (the air attacks + the exceptions above, 33 clips); the tree's own advance waits that frame (what you see = what hits).
- fighter.gd (granted parts only): `_core_attack_tick` calls core_frame; `_motion()` = [gmo, gmo_f] while the core
  attack is on display; `_throw_rows` pins the thrower by the path; `react_start` stamps the physics frame and
  `_react_tick` holds row 0 on it (the lead's / fx-mv's hit-frame request: the disc shows state 27 with the motion
  unchanged on the hit frame).
- Tables come from the disc logs: `tools/reach.py export DISC CLIPS game/assets/fidelity moves_...` (CLIPS =
  game/tests/reach_probe.gd output: every attack / throw clip's joints per frame, keyed by form).

## 3. Proof (moves_* tapes, same input both sides)
Runtime joint error = disc live attack-sphere centre vs the remaster's joint as its hit test posed it (tape_run.gd
PS_REACH=1 log, same motion + game frame, each from its own feet): `tools/reach.py runtime`.

| tape | before (lead-w4 WIP pin) median / p90 cm | after |
|---|---|---|
| falcon | 9.8 / 87.1 | 4.4 / 7.0 |
| ryoma | 10.2 / 59.9 | 0.0 / 5.1 |
| wangtang | 11.2 / 57.3 | 0.0 / 21.1 |
| jack | 26.3 / 48.1 | 0.1 / 23.0 |
| gunrock | 29.4 / 77.4 | 0.1 / 33.0 |
| galuda | 12.1 / 53.1 | 0.0 / 16.2 |
| ayame | 11.0 / 60.0 | 0.0 / 19.9 |
| rouge | 16.8 / 48.1 | 0.0 / 2.8 |
| kraken | 25.8 / 77.6 | 0.0 / 16.0 |
| valgas | 15.6 / 50.3 | 0.0 / 3.3 |
| all 1,882 spheres | 18.4 / 57.1 | 0.0 / 21.9 |

Ankle joints above the feet, k1/16 frames 1-4 (cm), disc / before / after: Falcon 18.2 / 20.1 / 18.0, Ryoma 26.2 / 26.2
/ 24.6, Wang-Tang 19.8 / 14.5 / 19.8, Jack 28.4 / 42.6 / 28.2, Gunrock 22.0 / 38.9 / 21.8, Galuda 22.3 / 38.4 / 22.3,
Ayame 21.7 / 13.9 / 21.4, Rouge 20.3 / 37.2 / 20.4, Kraken 26.4 / 47.0 / 25.9, Valgas 25.8 / 39.5 / 25.2.

P2 damage per attempt (disc / no pin fid3 / WIP pin fid4 / fx-reach), the 6 non-PC attempts (near X, near Y, far X,
far Y, jump X/Y, grab): see section 4; sum of |damage - disc| over the 60 attempts 652 / 645 / 549, exact 21 / 21 / 26.

Hit frame (P2 state first divergence, fidelity_diff): dist_ryoma f28 -> f241, atk_ground f28 -> f173, hits_down f28 ->
f279, near_ryoma -> f173 (the disc's f28: state 27 with k0/0, k2/96 from f29, now the same). The next divergence on these
(P2 health f67, 230 vs 231) is the recovery tick, not reach.

## 4. What is left
- Per-frame limb scaling (Gunrock k1/24 / k1/25, Jack k1/10 / k1/4 joint error 21-111 cm): the disc scales single
  joints for a few frames; a per-clip joint-scale table from these logs would close it (not done).
- Near X still short on most fighters (Ryoma / Wang-Tang 39 > 10, Kraken 43 > 14, Valgas / Gunrock 45 > 16): the disc's
  extra 29-32 damage there is the breakable scenery piece (BUG-95), not reach.
- Power Change forms: the joint scale is applied (body_scale.json), the hip rule was only measured on normal forms (the
  PC hit sets don't map 1:1 in reach.py); PC rows (_pc_* = fx-shot's) not pinned. Clip-frame ankle check with the
  scale: every PC form lands at 18-25 cm (Jack 34).
- Non-attack clips (idle / run / jumps / reactions) keep the old drawing rule (hip from the clip, the PSModel root-motion
  pin); only their limb size changed.
