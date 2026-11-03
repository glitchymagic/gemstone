# Power Stone (DC, USA T1201N) — rip notes

Everything here was read off the owner's own disc copy (`_disc/`, gitignored). Tools in `tools/`.

## Disc
- GDI: 3 tracks. Track 3 (`Power Stone (USA) (Track 3).bin`, 1,185,760,800 bytes) is the high-density
  data track, raw 2352-byte sectors, starts at LBA 45000. Mode 1: 16-byte sync/header, 2048 data bytes.
- ISO9660 PVD at track sector 16. Directory extents use absolute LBAs: file offset = (LBA - 45000) * 2352 + 16.
- `tools/gdi_extract.py track3.bin 45000 rip/fs` → 303 files, 125.8 MB, flat root. `rip/inventory.tsv` lists LBA + size.

## File map (from names + the exe's file table at 1ST_READ.BIN 0x10C800, pointers at 0x170BD0, base 0x0C010000)
| Files | What |
|---|---|
| `Pn0.MDL` / `Pn1.MDL` | fighter n geometry: normal form / Power Change form |
| `Pnk_MODEL.BIN` | texture blob for a form + colour: P00/P02 = Falcon normal 1P/2P, P01/P03 = Falcon changed; P10/12/14/16 + P11/13/15/17 = Ryoma |
| `Pn0_MOT.MDT` | motions (big-endian int16 keyframes, see below) |
| `Pn0_HIT.BIN` | hit data (big-endian u16 index tables) — not decoded yet |
| `EFn0.MDL` + `EFn0_MODEL.BIN` | per-fighter effect models |
| `STGn0.MDL` + `STGn0_MODEL.BIN` | stage n geometry + textures (STG00 = Londo) |
| `*.ADX` | CRI ADX music/jingles (ST_00..0A stage themes, P_SELE select, OPEN, WIN, VS, ...) |
| `FOKER.BIN`, `RYOUM.BIN`, `COMMON.BIN`, `A_*.BIN`, `EV*.BIN`, `INST.BIN`, ... | `DTPK` Dreamcast sound banks (voices / SFX / announcer). tools/dtpk.py decodes the listed samples; NA.BIN = announcer; which sample plays when: the AICA channel log (tools/ref_londo.py snd, tools/sfx_extract.py). The sample table doesn't list every sample (COMMON has 8-bit PCM impacts between listed ones) |
| `FACEnn.BIN`, `LOGO.BIN`, `EYE.BIN`, `EFCT2D.BIN`, `ITEM_MODEL.BIN`, ... | compressed texture blobs (same compression as MODEL.BIN) |
| `1ST_READ.BIN` | executable (load 0x0C010000 / 0x8C010000); embeds common model banks at 0x171088 (gems, items, 3D HUD letters), 0x21CD80, 0x29D028 |

Fighter index (pass 3, verified in Motion Check + sound-bank order): P0 Falcon (FOKER), P1 Ryoma, P2 Wang-Tang, P3 Jack, P4 Gunrock (GANRO), P5 Galuda (GARUD), P6 Ayame,
P7 Rouge (RUJYU), P8 Kraken, P9 Valgas, PA final Valgas.

## .MDL geometry (all little-endian)
```
part*      u32 flag (1 = mesh, 0xFFFFFFFF = empty joint)  u32 kind  f32 sphere[4] (cx, cy, cz, r)
           material*   (while the next word is a PowerVR polygon PCW: top 3 bits = 4)
           u32 0  u32 vertex_count
material   u32 PCW  u32 ISP/TSP  u32 TSP  u32 TCW      (pre-built PowerVR TA header)
           f32 sphere[4]  u32 tex_index (0xFFFFFFFF = untextured)  u32 0
           f32 face_argb[4]  f32 offset_argb[4]  u32 0  u32 strip_bytes
           strip*
strip      u32 flags  u32 count     flags & 8 -> triangle list, count = triangles (3*count vertices)
                                    else triangle strip, count = vertices
vertex     f32 pos[3] f32 normal[3] f32 uv[2]                         (32 bytes)
         | u32 0x5Fxxxxxx (output-buffer offset)  i32 rel             (8 bytes)
           = repeat the vertex at (end of this 8-byte record + rel)
tail       texture table, 16 bytes each: u16 w, u16 h, u32 fmt, u32 RAM address (0x0CC0xxxx), u32 0
```
- Fighters: parts are in **local bone space** (limbs hang along -Y). Falcon P00 has 32 parts:
  0-21 body (5 empty joints: 4, 5, 8, 9, 12), 22/23 head variants, 24-31 hand poses (4 per hand).
- Stages: parts 0/1/3/38 are world-space (arena, buildings, water); the rest are local props
  (Londo: 16 fountain piece, 23/31 lamp posts, 25/26 patio tables, 28/30 chairs, 32 bench, 53/54 potted
  plants, 55 bin, 14 flower box, 10 pub sign, 40-43 splash, 56-58 pigeons, 59-98 breakage pieces).
- Units ≈ centimetres. Londo floor is y = 0, fountain centre at the origin, the plaza opens to -Z (canal side).
- Coordinates render correctly as a right-handed glTF with no axis flip (shop signs read the right way round).
- `tools/psmdl.py` parses it; `tools/export_obj.py` / `tools/export_glb.py` export (GLB embeds the PNGs).

## *_MODEL.BIN textures
```
u16 header (1)
token u16: kind = t >> 12, n = t & 0xFFF
  kind 1: next u16 repeated n times
  kind 0: n literal u16s follow
```
Output = the textures back to back, exactly the size the .MDL texture table implies (verified for P00, P10, STG00).
Texture `fmt`: high byte 1 = twiddled, 2 = twiddled+mipmaps, 3 = VQ, 4 = VQ+mipmaps; low byte
0 = ARGB1555, 1 = RGB565, 2 = ARGB4444. Standard PowerVR twiddle (Morton, y in the low bit), VQ = 2048-byte
codebook of 2x2 texels + index map; mip levels skipped with the usual VQ/twiddle mip offset tables.
`tools/pstex.py` decodes. Upscaled 4x with Real-ESRGAN x4plus_anime_6B (`tools/upscale.py`, wrap-padded so
tiling textures stay seamless); the decoded original is always the source.

## Motions: RAM motion capture (pass 2, the route that worked)
The MDT keyframes are not decoded; instead the game's own motion player is recorded out of RAM.
- **Debug menu:** `poke32 0x0C061B38 0x0C0D7108` (literal-pool pointer to the title-screen handler, swapped for the
  debug-menu function, per the 32bits article; the same addresses hold on the USA disc). Boot, poke, press START:
  TEST MENU appears. 9. GAME CHECK > 1. MOTION CHECK. Controls: UP/DOWN pick a field, LEFT/RIGHT change it, SHOT1 = A.
- **Motion Check RAM:** P1 block: player 0x0C49492C (0 Falcon, 1 Ryoma), metamor +1 (Power Change form), kind +2,
  cursor +3, motion number u32 0x0C49493C, playhead u16 0x0C494938 (frames since the motion started; stops on the
  last frame of one-shot motions). P2 block = +0x18. Poke motion = n-1 then press RIGHT: the motion restarts cleanly.
- **Motion table:** big-endian u16[512] at offset 0 of Pn0_MOT.MDT; non-zero = a real motion. Kind 0 = index < 256,
  kind 1 = index - 256. Empty slots play idle. Falcon: 25 kind-0 + 54 kind-1 (+ idle); Ryoma 24 + 69.
- **Kind 2 = shared bank** (not in the fighter's MDT): hit/knockdown/get-up reactions and object handling. Same
  rotations for every fighter (verified Falcon vs Ryoma bit-equal), root motion scaled per fighter (~1.12 Ryoma/Falcon).
- **Power Change forms** play bit-identical rotations (one MDT per fighter); root motion scaled (Falcon 1.05,
  Ryoma 0.948). Ryoma's PC model has 56 parts vs 47: body bones 0-18 shared, the extra parts hold constant local rotations.
- **Live motion in a real fight:** P1 fighter object = part-0 record - 0x40 (0x0C7E43C4); +0x6E98: u32 ptr x3 into the
  loaded MDT, u16 table value x2, ..., +0x6EA4 kind, +0x6EA5 motion number (0x0C7EB268/9). Logged per button in real
  arcade fights (tools: capseg of 0x0C7EB250:32):
  idle k0/0; jump k0/5 -> 6 -> land 9; run k0/25 (stop 26); punch k1/16 -> 17 -> 18; kick k1/24 -> 25 (close kick 59);
  air punch k1/10; air kick k1/12; grab k1/84; throw carried object k1/78; hit stagger k2/112; heavy k2/152;
  knocked down k2/153 -> lying k2/144 -> get-up k2/146 (face-down 145 -> 147); pick-up k2/219, carry k2/220,
  carry-run k2/221. Kind 3 = KO/lose. Kind 4 in Motion Check is mostly an empty-slot fallback (91-frame motion; real
  entries only 2, 3, 7, 49, 55, 64, 66); the kind-4 ids seen in fights (57-65 while next to the opponent) are most likely the
  thrower's synchronized throw-victim motions. Pole swings are not identified yet.
- **Capture:** tools/flycast_drive.lua `capseg name N A:L,...` appends, every vblank, each bone's 0xF0 bytes
  (world 4x4 at record-0x40 + the 0xB0 record) and the Motion Check vars. tools/mocap.py decodes; tools/clips.py cuts
  each motion at the playhead (one-shot) or at the exact pose repeat (loop; Ryoma's loops have an 8-frame lead-in)
  and converts to local quaternions L = W_bone * inverse(W_parent), root relative to the base transform
  (P1 at x = -70 facing +X, ANGLE 0x4000). Local translations equal the RAM bone offsets exactly (error 0.000).
- **Hidden parts** (alternate heads, hand poses, sword positions) get a zero-scale world matrix in Motion Check.
  In real fights the second head/hand variants also get matrices, so per-move hand shapes come from elsewhere (open).
- **Godot check:** the imported skinned GLB reproduces the RAM bone positions to 0.01 cm (tests/check_rig.gd).
- Older notes: the demo RAM pose is interpolated (motion blending), so it is not verbatim MDT keyframe data; the MDT
  header has more tables at 0x400/0x800; keyframes are big-endian int16 (frame 0 of the idle = 66 channels).

## Skeleton (solved)
- Each bone = 0xB0-byte node record: +0x00 u16 flag 1, byte +3 parent slot (relative to the form's part-0 record,
  0xFF root), +0x14/18/1C s32 rotation X/Y/Z (65536 = 360 deg, Euler XYZ row-vector), +0x2C f32 scale[3], +0x50 ptr to
  the part inside the loaded .MDL, +0x58 f32 bone offset[3]; world 4x4 row-vector matrix at record-0x40.
- Ryoma's sword/scabbard records use a second parent encoding (bytes +2/+3 = list, slot); tools/solve_parents.py
  finds the true parent as the one whose W_k * inverse(W_p) translation equals the part's own offset in every frame.
- The game edits some vertex floats of Ryoma's PC model in place after loading; find the MDL base by an unmodified
  chunk (tools/mocap.find_records tries 0x100, 0x40, 0x2000).

## Stage object layout (pass 2)
- Every placed stage object is a 0xA4-byte record (array at ~0x0C370A84 on Londo) holding a pointer to its part in
  the loaded STGn0.MDL; its 4x4 row-vector world matrix sits at pointer-0x4C, a flags word at pointer+8.
  tools/stage_layout.py reads them from a RAM dump taken DURING a fight on that stage -> game/assets/ripped/stg00_layout.json.
- Londo: 47 objects. Fountain centred at x 0, z 50 cm: basin 45 (y 0), water 52 (y -20), column 16 (y 149), ball 15
  (y 258), jets 20 x4 (y 120), spouts 50 x4, splash 43 x4; lamp posts 23 (440, -256) and 31 (-428, -256); patio
  furniture 24/25/26/28/30 at y 50; metal chair 32; plants 53/54; bin 55; pigeons 56-58 (3 groups); window flower
  boxes 14 x7 up on the buildings; pub signs 10/11; canal water 38 at (50, -250, -50). World parts 0/1/3 at the origin.
- Arcade mode as Falcon (fixed input timing) landed on Londo on 2 of 3 tries; the attract demo picks stages at random.

## Face / hand variants (pass 2)
- Fighter object bytes 0x0C7EB1CE / CF / D0 = head, right hand, left hand variant (Motion Check's head / R hand /
  L hand fields write the same bytes). In fights the game sets them per motion: hit reactions (kind 2 96, 99, 112,
  152, 153, 176, 178) = 1/1/1 (pained face, open hands); Falcon's air kick (k1 12) opens the right hand (2).
  Variant parts: Falcon 22-23 / 24-27 / 28-31; Ryoma 37-38 / 39-42 / 43-46; Ryoma PC 46-47 / 48-51 / 52-55.

## Flycast pitfalls
- flycast.emulator.saveState/loadState from a Lua vblank callback deadlocks the emulator (it calls
  gui_open_settings -> Emulator::stop on the emu thread). Never use them from the script.
- A second Flycast instance silently uses ~/.flycast/2 (empty config, no Lua). Kill hung instances with -9 first.
- The debug Stage Check screen renders black.

## Texture bug fixed in pass 2
- VQ + mipmap offsets were 6 bytes too long (0x155C instead of 0x1556 for 256x256): Londo's floor (STG00 t32, the
  only VQ+mip texture) decoded to noise. Correct offset = index bytes of all smaller levels (1x1 and 2x2 = 1 byte each).

## Audio
- `tools/adx_to_mp3.sh`: vgmstream-cli decodes ADX (no loop), ffmpeg trims at the disc loop end and encodes MP3
  (this ffmpeg has no libvorbis); `game/assets/audio/loops.json` = disc loop start in seconds (29 of 44 tracks loop).

## Pass 3: the game's code + logged Power Change fights
- **set_motion = FUN_0x0C09A808(player r4, kind r5, motion r6)**: writes kind/motion to player+0x71A4/5, looks the
  motion up in the loaded MDT (`kind*0x200 + motion*2`, big-endian u16), resets the playhead. 604 call sites in
  1ST_READ.BIN (tools/ghidra/sh4_motion_sites.py -> work/ghidra/motion_sites.tsv); Ghidra's all.c only reaches ~17 of
  them because every constant sits in an SH-4 literal pool. tools/ghidra/sh4dis.py (capstone 6) disassembles with the
  pool values inlined and `-x VALUE` finds the code that loads a constant; tools/ghidra/resolve_pool.py inlines pool
  constants into all.c functions. Per-fighter move code sits in blocks 0x0C063000-0x0C08C000 (one block per fighter,
  each with the same kind-3 set_motion pattern 6/0/1/7); normal strings (punch 16>17>18) are data-driven, not constants.
- **Player struct**: P1 0x0C7E40C4, P2 0x0C7EB394 (stride 0x72D0). +3 player slot, +0x710A/B/C face / R hand / L hand
  variant, +0x71A4 kind, +0x71A5 motion, +0x71BA state (0 idle, 4/5/6 jump start/air/land, 10 attack, 11 PC attack,
  15 lying, 16 get-up, 21 match end, 22 ready, 23 transform/revert, 27 hit, 29 thrown, 31/32 run/stop, 37 grab),
  +0x71BB previous state, +0x71D4 s16 health (240; +0x71D6/8 display copies), +0x71F3 Power Change flag,
  +0x7230 gem count, +0x7231 gem bitmask (1/2/4).
- **Forcing Power Change**: poke gems 3 + mask 7 (0x0C7EB2F4/5 for P1); the game's own check
  (0x0C08DA44: not powered, gems >= 3, health >= 0) starts the transform the next time the fighter is free.
  Freeze health with freeze16 on +0x71D4/6/8 so the CPU can't end the match. tools/arcade.py builds the whole run;
  flycast_drive.lua gained `until8 ADDR VAL [MAX]` (wait for the state byte) so inputs never land mid-hit.
- **MDT tables**: kind k's u16[256] table is at k*0x200 of Pn0_MOT.MDT (kinds 0-4). Kind 2 = shared bank indices
  (identical for every fighter). **Kind 3** = per-fighter system motions: 0 round intro, 1 ready, 2/3 win poses,
  5 lose (continue screen, 112-frame lead-in then a 90-frame loop), 8 transform (130 frames in a fight; the PC flag is set
  at +60), 9 revert (91), Jack also uses 11 (held through his PC). **Kind 4** = throw-victim motions taken from the
  THROWER's table (Falcon thrown by Jack played k4/57, which only exists in Jack's table): pole swings are not kind 4.
- **Falcon, logged**: punch 16>17>18, kick 24 (R hand 2), grab 84, run+punch = k1/16, run+kick = k1/24 (no separate dash
  clip), jump+P 10, jump+K 12 (R hand 2), Drive P k1/98 (L hand 2), Drive K k1/96 > 97 (held ~90 frames, hands 0/2/2),
  air Drive P k1/99, Fusion P+J k1/101 (~200 frames), Fusion K+J k1/101 > 100 > (159 > 100) x3-4 > k2/205.
  The pass-2 by-eye picks for win (k1/101) and transform (k1/170) were wrong.
- **Round end**: the KO'd fighter stays in k2/144 (lying); the winner plays k3/2 or k3/3 (state 21).
- Arcade as Falcon (fixed timing) faced Jack (his mansion stage) and then Rouge (her desert stage) this pass.
- **Ryoma, logged** (arcade, slot 7 on the select screen): punch 16>17>18, kick 24>25, run+P k1/16, jump P 10, jump K 12
  (L hand 1), transform k3/8, revert k3/9 > k3/10, Drive P k1/96, Drive K k1/105 > 110 > 111 > 112, air Drive P 99,
  air Drive K 106 > 107 > 110 > 111 > 112, Fusion P+J k1/108 (~300 frames), Fusion K+J k1/101 > 102 > 103 > 104.
  His kind-3 set is captured (Motion Check player 1): intro 106f, ready 119, win 2 (loop) / 3 (249), lose 5, transform 8 (149), revert 9 (39) > 10 (51).
- **Per-fighter code blocks** (each ends with its kind-3 6/0/1/7 calls): P0 Falcon 0x0C063000-0x0C068D50, P1 Ryoma
  -0x0C06C9xx, P2 -0x0C0717xx, P3 -0x0C0767xx, P4 -0x0C0794xx, P5 -0x0C07C5xx, P6 -0x0C07FCxx, P7 -0x0C0830xx,
  P8 -0x0C0875xx, P9 -0x0C089Bxx, PA (Final Valgas) -0x0C08C1xx. Cross-check: Falcon's block holds the only
  set_motion(1, 159) sites next to (1, 101) and (1, 100) = his logged Fusion K+J chain; Ryoma's block holds
  (1, 105/106/108/110) = his logged drives/fusion. Drives P/K, punches and transform go through data tables / variables.
- **Camera** (measured, Wang-Tang's dojo, 2400 frames): camera object 0x0C7F2664 (the third 0x72D0-sized object after
  P1/P2): +0x3C0 view matrix (row-vector, eye = -T * R^T), +0x400 camera world matrix (eye at +0x430), +0x448 eye-height
  cap (500 cm), +0x44C 1200, +0x450 eye, +0x474 desired target (= fighters' midpoint, y stepped per floor level),
  +0x480 smoothed target (closes 13.5% of the gap per frame), +0x3AC focal 640 px on 640x480 (41.1 deg vertical FOV).
  Yaw = fixed presets per stage area (dojo: 115 / 118.7 / 127.3 / 135 deg, switching by zone). Eye ~260 cm above the
  target, horizontal distance = 457 + 0.42 * |separation across view| + 0.90 * |separation along view| cm (RMS 136 cm on
  steady frames). The camera code itself was not located (it reaches these fields through a base pointer + 0x400).
  Implemented in game/scripts/fight.gd _update_camera (one yaw per stage; the per-zone yaw switches are not modelled).
  **Correction (2026-10-23 audit, Londo, 10,800 frames of the camera object + both fighters, tools/ref_londo.py cam ->
  dumps/cap/camL.bin, tools/cam_zones.py):** the target is the fighters' HIP midpoint (RAM positions are hip height,
  median difference 2 cm), not floor level; Londo uses yaw presets -135 (55% of frames) / -115 (31%) / -155 (2%) by area
  of the plaza, ~33 frames to turn (stg00_info.json cam_zones); the eye distance is stepped: 594 / 683 / 1195 cm for
  fighters < 3 / 3-7 / > 7 m apart (cam_levels), the eye ~0.36 x that above the target, capped at 500 cm. Now in
  game/scripts/fight_cam.gd (+ the remaster's fit / wall swing / scenery fades).
  **Second correction (2026-10-26, lane pstrailer2 fx-cam, ~43k fight frames per stage, all 11 stages, docs/fx-cam.md):**
  the desired target +0x474 is exactly the FEET (+0x020) midpoint + 100 cm (the hips only match it standing); +0x480
  closes 1/8 of the gap per frame in x/z and steps S.y in truncated whole cm; three yaw presets 20 deg apart on every
  stage (eased 10%/frame); the distance is continuous, not stepped (fidelity/<stg>_cam.json "dist"); +0x448 is the
  desired eye y = min(500 cm world, S.y + 0.279 x distance), eased 5%/frame. Final Valgas's arena uses another camera
  (yaw follows the boss-to-player line, eye up to 13 m). The round timer is u8 0x0C7F304D (99 down), not 0x0C7F2F28.
- **Ayame (P6, select slot 1)**: P60 45 parts / P61 39 parts; parts 23/25 (P60) and 22/25 (P61) have no node record
  (never drawn in Motion Check) -> hidden. solve_parents re-parents 31-34 to 30 (her fan pieces). Part 41 leaves its
  bone in many motions -> clips.py now stores per-bone translation tracks for any part whose local translation leaves
  its offset (`free` in the clip index; export_rig writes them as glTF translation channels). PC root scale 0.992,
  PC body rotations bit-equal to the normal form (remap_clips nbody 19 from a1k0_000). 126 motions (26 k0, 65 k1,
  22 shared k2, 12 k3). Logged (arcade vs Wang-Tang): punch 16 > 17 > 21, kick 24 > 25 > 29 (three kicks), close kick 59,
  run+P k1/16, jump P 10, jump K 12, transform k3/8, revert k3/9, win k3/2, Drive P k1/99, Drive K k1/97 (launches her
  into the air), air Drive P k1/101, Fusion P+J k1/103, Fusion K+J k1/105 > k0/26. Air Drive K: not seen yet.
- **Variant parts rule**: every form ends with 2 head variants (parent bone 4), 4 right-hand (parent 8), 4 left-hand
  (parent 12); make_clipmap derives the groups from that. Split parts for export = those 10 + hidden + record-less parts.
- **Wang-Tang (P2, select slot 2)**: P20 38 parts / P21 42; parts 20-26 have no node record (hidden). 133 motions.
  PC root scale 1.099, body rotations bit-equal (remapped). Logged (arcade vs Rouge): punch 16 > 17 > 18 > 19 (four hits),
  kick 24 > 25 > 26, run+P k1/16, run+K k1/24, jump P 10, jump K 12, transform k3/8 > k3/11, revert k3/9, win k3/2,
  Drive P k1/96, Drive K k1/99 > 100, air Drive P k1/103, air Drive K k1/99, Fusion P+J k1/101 > 102 > 111,
  Fusion K+J k1/106. Inputs are ignored for ~4 s after the round's ready state (FIGHT! banner): arcade.py waits 240 frames.
- tools/do_fighter.py N PREFIX boot|capture|build runs the whole mechanical pipeline for one fighter;
  tools/fighter_proof.py N id Name makes the side-by-side. psmodel.has_clip() = strictly mapped (clip_for falls back to idle).
- **Stages (pass 3)**: STGn0 = fighter n's home stage (dojo fight -> STG20, mansion fight -> STG30, Rouge fight -> STG70).
  tools/export_stage.py STGn0 ram.bin -> world GLB (textured parts < 10 with no placed record), one GLB per placed part,
  the RAM layout and stgN0_info.json (floor level, xz bounds of the floor-level world vertices). Spawns = the
  fighters' x/z (player +0x148/+0x150; y there is hip height, ~105 cm above the feet) at the round's ready state.
  Throwable/pole roles are only known for Londo so far; elsewhere every placed object is solid scenery.
  The 0xB0 node records of stage objects carry no gameplay type (flags 0x00010001 for chairs and signs alike).
- **Jack (P3, select slot 4)**: P30 45 parts / P31 54; 124 motions; PC root scale 1.233 (remapped). Logged (vs Rouge):
  kick 24 > 1, run+P k1/16, run+K k1/24, jump P k1/10 (a ~220-frame spin), jump K 12, own get-up k0/51 (face-down k0/52)
  instead of the shared k2/146, transform k3/8 > k3/11, revert k3/9, Drive P k1/96, Drive K k1/98, air Drive P k1/102,
  air Drive K k1/103, Fusion P+J k1/106 > 107 > 108, Fusion K+J k1/104. Punch string not seen (defaults 16/17/18 exist).
  Trick: freeze8 the CPU's state byte (P2 +0x71BA = 0x0C7F254E) to 15 (lying) to stop it interrupting the log.
- **Ryoma's sword**: none of his 128 Motion Check captures toggles a part's visibility (zero-scale matrix), and in fights
  the only per-motion selectors are face / R hand / L hand (0x0C7EB1CE-D0; 0x1CC/0x1CD hold 4, 0x1D1-3 stay 0). His extra
  sword/scabbard pieces (25, 26, 29, 33-36) are never shown in Motion Check: the game keeps the sword drawn, so the
  remaster does too (no invented sheathe).
- **HUD portraits**: FACE00..FACE10.BIN = the in-fight portrait + name banner per fighter index (00 holds FOKKER |
  FALCON side by side, 10 = Final Valgas). MODEL.BIN-style compression over twiddled ARGB4444, 128x128 (FACE00 256x128),
  stored upside-down; the portrait is the left 77 px of each 128-px cell (the rest holds other small art).
  tools/export_faces.py -> game/assets/ripped/ui/faceNN(_4x).png; hud.gd draws them in the corners.
- **Rouge (P7, select slot 6)**: P70 42 parts / P71 44; 125 motions; PC root scale 1.0. Logged (vs Wang-Tang? CPU pinned):
  punch 16 > 17, kick 24 > 25, run+P k1/78 (her own dash punch), run+K k1/24, jump P 10, jump K 12, transform k3/8,
  revert k3/9, Drive P k1/96 > 97 > 98, Drive K k1/100 > 101, air Drive P 99, air Drive K 102 > 101, Fusion P+J k1/105,
  Fusion K+J k1/103. Object throw not seen (left unmapped).
- **Chains (braids, ribbons)**: node records with flag 0x0101 form a second list (byte +3 = slot in that list; its first
  record's byte +3 = a body slot). Rouge 19-29 = her braid ending in the heart charm (19 hangs off bone 11), Wang-Tang 20-26,
  Ayame 23/25. They are simulated by the game every frame, so capturing them replays the original physics exactly.
  skel_from_ram/mocap now include them (flag & 0xFF == 1). Wang-Tang, Ayame and Rouge were first captured without them.
- **Variant probe** (do_fighter.py variants): freezing a face/hand selector byte in Motion Check shows which part each
  value draws; the game leaves stale matrices on variants it stops drawing, so those are not motion data. export_rig now
  gives every variant the default variant's pose.
- **Gunrock (P4, select slot 3)**: P40 35 parts / P41 29; 118 motions; PC root scale 1.083. Logged (vs Jack on STG30):
  punch k1/16, kick k1/24 (single presses; his strings were eaten by the round-start input lock, 17/18/25 unverified),
  run+P 16, run+K 24, jump P 10, jump K 12, transform k3/8, revert k3/9 > 10, Drive P k1/105, Drive K k1/144 > 100 > 101 > 103,
  air Drive P 104, air Drive K 100 > 101 > 103, Fusion P+J k1/96 > 97, Fusion K+J k1/144 > 100 > 99 > 100 > 101 > 102.
- **Galuda (P5, select slot 5)**: P50 34 parts / P51 31; 126 motions; PC root scale 1.017. Logged (vs Gunrock, CPU
  pinned): punch 16 > 18, kick 24 > 26, run+P 16, run+K 24, jump P 10, jump K 12, transform k3/8, revert k3/9,
  Drive P k1/96, Drive K 107 > 108 > 109, air Drive P 97, air Drive K 110 > 111 > 112, Fusion P+J 98 > 105,
  Fusion K+J 101 > 113 > 102.
- tools/test_all.sh: base suite + one CPU match per ripped fighter (all 41/41 at the end of wave 1).

## Pass 3, wave 3 (2026-10-22): bosses, poles, wall kick, translucency
- **Select cursor** = u16 0x0C7F2E54 (P1's arcade block). The 10-slot table at 1ST_READ 0x8C15261A is
  `8 0 6 2 4 3 5 7 1 9`: Kraken sits left of Falcon (cursor 0), Valgas right of Ryoma (cursor 9); locked slots are
  skipped by the cursor code only, so poking the cursor to 0 / 9 and pressing A starts an arcade run as Kraken / Valgas
  (the clear is not saved to the VMU, so the unlock never sticks). P1's MDT sits at 0x0C70F9D8 (P2's at 0x0C7C58A0).
- **Arcade progress**: per-player block at 0x0C7F2E45 + 120*player: +0 ladder row, +1 fight index (0-based). The code at
  0x0C0A43BA reads `table[row*9 + fight]` (table 0x8C1525BF). Poke +1 to 7 during fight 1 and win it: the next fight is
  Final Valgas (row[8] = 10). tools/ladder.py also missed fights: its dump waited for state 22, which Final Valgas's
  intro never sets (the round timer ran out first).
- **Kraken (P8)**, logged as P1: punch 16 > 19 > 18, kick 24 > 31, run+P 16, run+K 24, jump P 10, jump K 12,
  transform k3/8, revert k3/9, Drive P 100, Drive K 96 > 98, air Drive P 101, air Drive K 99 > 109, Fusion P+J
  107 > 108 > 106, Fusion K+J 102 > 103 > 104 > 105 > 106. Near the pinned, lying CPU his punch was k1/78 [0,1,0].
- **Valgas (P9)**, logged as P1: punch 18 > 16 > 17, kick 5 > 24, run+P 18, run+K 5, jump P 10, jump K 12, transform
  k3/8, revert k3/9, Drive P 96, Drive K 98, air Drive P 97, air Drive K 101, Fusion P+J 102 > 103, Fusion K+J 106 > 108.
  His hands change within most moves (fightlog.py sel = longest-held selector per motion).
- **Final Valgas (PA0)**, logged as the CPU (fightlog.py show fv_cpu2 2): never walks or jumps; every attack runs in
  state 11 (the Power Change attack state): 99 > 100 (x9), 99 > 100 > 101 (x2), 99 > 100 > 103, k1/2, k1/3, 4 > 16,
  16-105 idle frames between attacks; match-end pose k3/1. He has no gem slots on the HUD (the player still gets gems).
  Hit reactions / KO motion: not seen (no log), so the remaster gives him damage only and the shared knock-down on KO.
- **Poles**: the float at a stage record's part pointer - 4 is 1.4 for exactly the poles (Londo's lamp posts, the dojo's
  pillars, the ship's masts: 520-2480 tall, 20-50 wide); stage_layout.py writes `pole: true`. Valgas's stage has none.
- **Pole swing** (attract-demo CPU logs, 10 swings: Falcon x7, Wang-Tang, Ryoma, Rouge; dumps/cap/demo1 + demopos =
  P1/P2 x,y,z at player +0x148): a moving jump (k0/10) into a pole -> k2/211 (state 34, 2 frames, caught 0.8-0.9 m
  out) -> k1/150 (orbit 0.46-0.52 m out, ~75 degrees in 10 frames; Wang-Tang/Ryoma the full 18) -> k1/151 (snaps to the
  pole axis, flies 17.3 cm/frame out, 36 cm/frame up, 3.5 cm/frame^2 down, apex 1.9 m) -> k1/152 after a 22-27 frame
  flight, the normal landing k0/9 after a 33-36 frame one. tools/poleprobe.py (standing next to a pole and pressing
  buttons) never catches: the catch needs the jump to move into the pole.
- **Jumps**: standing jump k0/5 > 6 > 9; jump with a direction held k0/10 > 9 (poleprobe). Wall jump: k0/10 > k2/206
  (state 38, the wall kick, 8 frames) > k0/13 > k0/9. Other states seen in demos: 17 = k0/48 > 57 > 58 (a hop/vault,
  trigger unknown), 36 = k2/207, 24 = k2/157, 28/29 = throw / thrown (k4).
- **Kind-2 bank, added**: 206, 207, 210-218 captured from Motion Check for all 10 fighters (tools/add_clips.py capture,
  then build: merges the new clips into the built fighter, redoes the PC remap, re-exports; Falcon's and Ryoma's PC root
  scales 1.05 / 0.948 are read back from their pass-2 GLBs).
- **Translucency**: the strip material words are PowerVR TA words. PCW bits 24-26 = list type (0 opaque, 2
  translucent); TSP bits 31-29 / 28-26 = src / dst blend (4 SRC_ALPHA, 5 INV_SRC_ALPHA, 1 ONE). Stages use (0,1,0) and
  (2,4,5) and (2,4,1) = additive (light shafts, glows). export_glb names those materials `_add` / `_blend`; Mats makes
  `_add` additive + unshaded. `_blend` only where the texture's alpha is really partial (PowerVR sorts translucency per
  pixel, Godot per object; on/off alpha stays a cut-out).
- **Throwables outside Londo**: still unknown. No record field separates Londo's chairs/tables from fixed scenery
  (flags 0x10010001 mark list boundaries, not a type); the breakable ones own debris parts in the MDL (Londo 59-98)
  but that is not a throwable flag. Outside Londo every placed object stays solid scenery.

## Pass 4 (2026-10-22): the game's hit data, backgrounds, more throwables, the arcade row
- **Hit steps**: `Pn0_HIT.BIN` = u16 BE index[5 kinds][256 motions] (0 = none) + 8-byte steps from 0xA00:
  b0 -> player +0x102 (body sphere set), b1 -> +0x101 (attack sphere set), b2 = hit id (0 keep, 0xFF end) -> +0x100,
  b3 = the step's LAST motion frame (absolute). set_motion (0x0C09A808) copies index[kind][motion] to +0x71A0;
  0x0C09AEBC loads a step; the motion routine 0x0C09A910 counts frames in u16 +0x719E (+1 per frame from 0) and steps
  on once it passes b3 (0x0C09AC3A). 254 = until the motion ends. Logged (hdA): the jab arms hit 1 at frame 0 and has
  live spheres frames 5-8 exactly as the file says (b3 4, 8); 3340/3748 logged frames match, the rest are moves whose
  hit id the code arms itself (Falcon's Power Rocket flight k1/100 = 117/118/119, kept in pN0_hit.json code_hits).
- **Attack records**: 1ST_READ 0x0C338A98 = u32 per character -> 128 x 20 bytes; b1 = base damage (health 240,
  +0x71D4), b0 class, b4 type (2 = no defence/combo/bonus: throws 48-62; 3/4 = x1.2; 7 = no bonus), b12 reaction
  (6 = launches: 17 of 20 logged), b13/b14 -> victim +0x7211/+0x7212, b15 -> 0x0C08D644, b18 sound (99 = none).
  Objects: 0x0C338AC4 -> 14 generic records (base 10); items 0x0C33AB08 (thrown stage objects = base 32, type 5).
- **Damage** (0x0C059718 then 0x0C08DFA4): d = b1 x CPU_ATK[lvl] (attacker CPU, 0x0C32DF78) x defence[victim]
  (0x0C32E078: Falcon/Ryoma/Jack/Rouge 1.0, Wang-Tang/Ayame 1.05, Gunrock/Kraken 0.8, Galuda 0.9, Valgas 0.7, Final Valgas
  0.5) x combo[hits in a row] (0x0C32E0A4: 1-5 full, 6th 0.5, halving) / CPU_DEF[lvl] (victim CPU, 0x0C32DFF8); min 1;
  x1.05 / x1.1 attacker holding 1 / 2 gems, x1.2 attacker in Power Change; x0.5 victim in Power Change (arcade option
  0x0C7F476B = 1); int. Health -= d; gauge -= d / 240 x 1800. CPU level 0x0C7F305C = rank counter 0x0C7F305D / 8 (9 at
  fight 1, ~13/17/19/22/25/27/28, 29-30 at Final Valgas). The combo counter (attacker +0x720E) counts before the damage,
  resets when the victim's reaction ends, and never counts on Final Valgas (0x0C08D91A). Logged: 56/56 body hits, 6/6
  object hits and every throw exact (tools/hitlog.py hits).
- **Spheres**: PL block per character in 1ST_READ (0x0C11D7B0 + char*0x3200 = PLnn_DATA.BIN's first 0x3200 bytes,
  pointers 0x0C336660; slot table 0x0C7D08E0 + slot*64 built by 0x0C062CF4). +0x0000 attack sets (4 x [joint u8, flag,
  sphere u16]) -> player +0x148 (4 x x,y,z,r); +0x0640 body sets (12 x [joint, flag, sphere]) -> +0x188; +0x1900
  spheres (s16 x, y, z offset in the joint frame cm, s16 radius); joint 255 = the root. Builder 0x0C020680, lookup
  0x0C022952, counts 0x0C320034 (players 4 / 12). Body entry 0 is the push sphere (0x0C0209C6 tests only it). Body set
  per motion: the steps' b0, else (logged) stand/run 10 (3 coarse spheres), jumps 2, reactions 0, knocked down 5,
  lying 13, throws 12. Joints 0-18 are the same for every fighter and both forms (1 chest, 2 hips, 4 head, 7/11
  forearms, 8/12 hands, 14/17 shins, 15/18 feet). Geometry check: Falcon's jab hand sphere 102-104 cm ahead of the feet
  at 130 cm in the game (frames 6-8), the remaster's posed b12 103-105 / 130 (tests/hit_geom.gd).
- **Throws**: type-2 records 48-62 applied by the throw code: Falcon 49 + 49 + 48 (12 + 12 + 24) and 50 (48),
  Wang-Tang 50 (48). Kind 4 = throw motions (thrower k4/0, k4/2 state 28; thrown k4/49, k4/55 state 29).
- **Power gauge** (+0x71F4 s16): 2400 at the change, -1 per frame while free (paused in hit reactions), Drive -240,
  Fusion = the rest.
- **Background plane**: the PowerVR draws ISP_BACKGND_T's polygon where nothing covers the screen. Power Stone keeps it
  at tag 0 (ISP_BACKGND_T 0x01000000, skip 1) of the parameter buffer: 32-bit VRAM PARAM_BASE (0xA05F8020, toggles
  0x000000 / 0x400000) + 0, read from Lua as 0xA5000000 / 0xA5400000: ISP, TSP, TCW, then 3 vertices x, y, z, ARGB at
  (0,0), (640,0), (0,480), Gouraud-shaded as one plane over the screen. Londo 092A93 -> 568AE2 top to bottom, Jack's
  mansion 92A69A, the dojo nothing (alpha 0). tools/bgplane.py -> stgN0_info.json bg_rgb; Look.apply_background draws
  the same plane as a canvas layer (BG_CANVAS). Fog registers are the same on every stage (FOG_COL_RAM 101010).
- **The game's AI on P1**: freeze8 P1 +0x71ED = 1 during a fight and the game's CPU drives P1 too: CPU vs CPU on any
  stage (tools/stagefight.py ladder ROW TAG N,...). Ladder row 0 visits every stage but the dojo and Jack's mansion.
- **Arcade row**: rolled once per player when the select screen opens (0x0C0A4816): (u32)(rand()/32768*255) % 8 with
  the C rand at 0x0C0DF920 (state 0x0C346A50 from 1, never seeded); continues keep it; rows 8-9 never picked
  (docs/ARCADE-ROW.md, tools/arcade_row.py).
- **Tools**: hitdata.py (decode + export pN0_hit.json), hitlog.py (capture fields, hits vs formula, step timing),
  demolog.py (attract demo log), stagefight.py, throwables.py, bgplane.py, hitreport.py -> docs/HITS.md.
