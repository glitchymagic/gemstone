# Health recovery (BUG-14): the disc's rule, from 1ST_READ, scored on every logged frame and hit

fx-cov2, 2026-10-27. Checker: `tools/health_check.py [--json OUT]` (default: every `dumps/fidelity/o_*.bin` tape log +
the 48 `dumps/fidelity/cpu/cpu_*.bin` CPU-vs-CPU logs; the .bin captures already carry `+0x71D4..7` and `+0x720C..F`
per frame, the .jsonl rows only had the health).

## The fields (player struct, P1 0x0C7E40C4 / P2 0x0C7EB394)
| offset | type | what |
|---|---|---|
| +0x71D4 | s16 | health (240) |
| +0x71D6 | s16 | **recoverable ceiling**: the health climbs back up to it |
| +0x71D8 | s16 | the red "just lost" bar: drains 1 every other frame (0x0C7F307C & 1 == 0) down to +0x71D6 (display only) |
| +0x720E | u8 | the attacker's combo count (counts before the damage, RIP.md) |
| +0x720F | u8 | **recovery counter** |
Round start (0x0C0996C8): +0x71D4 = +0x71D6 = +0x71D8 = 240, +0x720F = 0.

## The rule (code)
**Every fight frame** (0x0C0555B6 -> 0x0C055566 for P1 then P2):
```
cnt = (cnt - 1) & 0xFF
if cnt == 0 and hp < ceil:  hp += 1; cnt = 40
if (frame & 1) == 0 and red > ceil:  red -= 1
```
(the counter is not reset when nothing is pending, so it wraps through 255 every 256 frames; a hit always sets it to 40.)

**A hit** (0x0C08E16C..0x0C08E2DE; r14 = the victim, +0xF8 = the attack record, d = the float damage after every
factor of 0x0C059718 / 0x0C08DFA4, min 1; `int(d)` is what the health loses):
```
if attacker.combo (+0x720E) == 1 and hp != ceil:  ceil = red = hp       # a NEW combo forfeits what is still pending
if record[4] == 0 and byte 0x0C7F4767 == 0:                             # an ordinary attack record (b4 type 0)
    hp -= int(d)                     (below 0: all three = -1, or = r13 (0?) when record[16] & 2)
    ceil -= int(d * 0.19999999f)     (the constant is 0x3E4CCCCC: 0.2 just under, so a whole 10.0 loses 1, 10.5 loses 2)
    ceil = max(ceil, hp)
    PC victim: gauge -= int(d / 240 * 1800)
else:                                                                     # b4 1 pole / air actions, 2 throws, 3 / 4 PC
    hp -= int(d)                                                          # moves, 5 thrown objects + items, 7 ...
    ceil = red = hp                  (nothing comes back, and nothing pending stays)
    PC victim: gauge -= int(d / 240 * 5520)
cnt = 40
```
0x0C7F4767 is 0 in every logged fight (an option byte next to 0x0C7F476B, the "PC victim x0.5" option); with it set
nothing would ever recover.

**When the tick does not run**: only in round phase 3 (fight), and not while the world stands still: a Power Change
transform (130 rows, the other fighter frozen too) or a Fusion's 40-frame flash (BUG-65, docs/BUGS.md). It does run
in hit-stop, reactions, lying, throws.

## Scored on the logs (tools/health_check.py, 96 logs: 48 tape logs + 48 CPU logs)
```
quiet fight-phase frames: 744,954; the tick rule exact on 700,111; not ticked = world freezes (transform 37,150,
  Fusion flash 7,190, other 496: the KO frame / the frames around the freezes' edges); other mismatches 7
hits: 2,133 (the counter set to 40 on 2,111; the rest are KOs and same-frame double hits)
  recoverable (ceiling above the health after the hit): 487
    the ceiling exact with the integer damage: 369; within the float damage's range: 487 / 487
    (116 hits had a fractional damage, e.g. Ryoma's 10 x 1.05 for one gem held = 10.5: 0.2 x 10.5 = 2.1 -> 2, not 1;
     one hit came on a frame whose recovery tick ran first)
  the combo rule: 163 recoverable first-of-combo hits with health still pending: 162 fit "ceil = hp first" (the 163rd
    is the same-frame tick), 9 would fit without it
  nothing back: 1,563 (by the attacker's record b4: 1 pole/air 136, 2 throws 72, 3/4 PC 279, 5 objects/items 7,
    PC attacker 645, unknown hit id 401 (throw victims k4, objects, items: the attacker's +0x100 is not the record))
```
PC victim's gauge on a hit (every log, hits on a fighter in Power Change with gauge left, the float damage's range):
d / 240 x 1800 on 29 of 30 recoverable hits, d / 240 x 5520 on 74 of 74 others (the remaster: 1800 for every hit).
b4 of the attacker's hit id, normal-form records only (pN0_hit.json): 446 recoverable hits are b4 0, 0 are b4 1-5;
17 "b4 0" hits that recovered nothing are items / thrown objects (hid 16 there is the object's record, type 5).

## The remaster today (fighter.gd receive_hit / _recover_tick, provisional)
`rec_left = 0 if the attacker is in Power Change or grabbing else int(dmg * 7 / 8)`, `rec_t = 40`, +1 every 40 frames.
Against the disc's pending amount after each hit (2,050 non-KO hits): the same after 1,461, more after 408 (pole moves
and air actions recover on the remaster, a new combo's first hit keeps the old pending amount on the disc but the
remaster drops it ... ), less after 181 (the remaster forgets the earlier hits of the same combo; a whole 10 recovers 9
on the disc, 8 here). The thrown-object rule (prop.gd rec_left = 0) matches.

## Exact change for the lead (fighter.gd; Rules.game_damage needs to hand out the float)
1. `Rules.game_damage_f(...) -> float` = today's game_damage without the final `int()` (game_damage = int(of it)).
2. Fighter: `rec_ceil := 240` (reset with hp at round start), `rec_cnt := 0` (u8), drop rec_left / rec_t.
3. receive_hit(dmg_f, rec_type, attacker):
   ```
   if attacker and attacker.combo_hits == 1 and hp != rec_ceil: rec_ceil = hp      # combo_hits counted before the damage
   hp = Rules.apply_damage(hp, int(dmg_f))
   if rec_type == 0: rec_ceil = maxi(hp, rec_ceil - int(float32(dmg_f) * 0.19999999))
   else: rec_ceil = hp
   rec_cnt = 40
   ```
   rec_type = the attack record's `type` (pN0_hit.json hits[id].type = b4; PC moves' records are 3 / 4, throws 2,
   objects / items 5); grab-throw damage events (_throw_tick) = type 2; prop.gd's thrown objects = type 5.
4. _recover_tick, once per fight-phase frame, skipped in a world freeze (fight.gd `_frozen_by`, BUG-65):
   ```
   rec_cnt = (rec_cnt - 1) & 0xFF
   if rec_cnt == 0 and hp > 0 and hp < rec_ceil: hp += 1; rec_cnt = 40
   ```
   (today it also runs outside phase 3: the disc's does not.)
   And the PC victim's gauge loss: d / 240 x 1800 on a recoverable hit, d / 240 x 5520 (0x45AC7FFF) on the others
   (receive_hit uses 1800 for every hit).
5. Optional HUD: the red bar = +0x71D8 (set to the health on a non-recoverable hit / a combo restart, drains 1 every
   other frame to the ceiling).
Retest: `tools/health_check.py` scores the disc; the remaster side = the hp columns of the tape diffs (atk_ground P2
230 > 231 at 68, 108, 148 = disc today; hits_down / dist_* / moves_* hp % after the change).
