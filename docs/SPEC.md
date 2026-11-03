# Power Stone (1999, Capcom, Dreamcast / NAOMI) — 1:1 Rules Spec

Scope: the **original Power Stone** only (not Power Stone 2). Every fact below is tagged with its
source. Anything not found in the time available is marked **"measure from the disc later."**
This is a research spec for a private remaster, not a legal document — no legal commentary included.

## Sources used
- [S1] Wikipedia — Power Stone (video game): https://en.wikipedia.org/wiki/Power_Stone_(video_game)
- [S2] StrategyWiki — Power Stone/Gameplay: https://strategywiki.org/wiki/Power_Stone/Gameplay
- [S3] StrategyWiki — Power Stone/Moves: https://strategywiki.org/wiki/Power_Stone/Moves
- [S4] StrategyWiki — Power Stone (main/characters list): https://strategywiki.org/wiki/Power_Stone
- [S5] Power Stone Wiki (Fandom) — Edward Falcon: https://powerstone.fandom.com/wiki/Edward_Falcon
- [S6] Power Stone Wiki (Fandom) — Londo: https://powerstone.fandom.com/wiki/Londo
- [S7] Power Stone Wiki (Fandom) — Valgas: https://powerstone.fandom.com/wiki/Valgas
- [S8] Power Stone Wiki (Fandom) — Kraken: https://powerstone.fandom.com/wiki/Kraken
- [S9] Power Stone Wiki (Fandom) — Power Stone (video game) overview: https://powerstone.fandom.com/wiki/Power_Stone_(video_game)
- [S10] 32bits Substack — "Expansion hack: Power Stone, Power Stone 2 (Dreamcast)" (Motion Check / Hit Edit debug menu): https://32bits.substack.com/p/expansion-hack-power-stone-power
- [S11] Giant Bomb — Power Stone: https://giantbomb.com/wiki/Games/Power_Stone
- [S12] Fighters Generation — Power Stone: https://fightersgeneration.com/games/powerstone.html
- [S13] GamesAsylum — Power Stone Collection review (modes/VMU minigames): https://www.gamesasylum.com/?p=204
- [S14] WebSearch synthesis of fan-wiki Power Fusion descriptions for Falcon/Ryoma (cross-checked against S3, noted where it conflicts)

GameFAQs move-list FAQs for Power Stone (Dreamcast, game ID 197338) exist but blocked all automated
fetch attempts in this session (anti-bot "Request Blocked due to abuse from hosting service").
StrategyWiki's dedicated `/Characters`, `/Stages`, and `/Items` appendix pages are empty stubs as of
this session — content below comes from `/Gameplay`, `/Moves`, the main article, and the Fandom wiki
instead. **Anyone revisiting this spec should try GameFAQs again from a non-flagged IP/browser.**

---

## 1. Controls (Dreamcast)

Per StrategyWiki's control table [S2]:

| Input | Dreamcast button | PSP equivalent (Collection) | Function |
|---|---|---|---|
| Analog stick / D-pad | — | — | Move character in 360°; highlight menu items |
| Punch | X | Square | Punch; push or throw a held item |
| Kick | Y | Triangle | Kick; use/swing a held weapon |
| Jump | A | Cross | Jump |
| Punch + Kick (combined) | B | Circle | **Action button**: pick up a weapon/object; also the general "grab" near objects, poles, opponents |
| Power Fusion 1 | L or C | L | Punch + Jump (while transformed) |
| Power Fusion 2 | R or Z | R | Kick + Jump (while transformed) |
| Start | Start | Start | Pause/Resume |
| Camera (PSP only) | — | Select | Change camera angle |

Notes:
- Power Stone is a 3-action-button fighter at its core (Punch/X, Kick/Y, Jump/A); the DC's B button is
  a combined Punch+Kick press used contextually as the pick-up/grab/action button [S2][S11].
- Near a wall, pole, or an opponent, the action button (B / Punch+Kick) is what grabs/picks
  up rather than striking — exact grab-range and prompt behavior: **measure from the disc later.**
- Button layout for Power Fusion specials (L/R vs. Punch+Jump/Kick+Jump) is confirmed in [S2]; some fan
  summaries describe the same two Fusion moves as bound to "Attack+Jump" / "Action+Jump" instead [S14] —
  treat [S2]'s L/R + Punch+Jump/Kick+Jump mapping as primary and verify against the disc.

## 2. Movement

- Movement is free 360° analog movement around fully 3D arenas — "go-anywhere, grab-anything" is the
  game's own pitch [S1][S11].
- Characters can run/walk and jump freely around the arena while picking up items [S1].
- Double jump: at least Falcon is documented as able to double jump [S5]; whether this is universal to
  the whole cast or character-specific: **measure from the disc later.**
- Dash, wall jump/wall kick, pole swings, climbing, rope/ledge behavior: not confirmed in any source
  reached this session — **measure from the disc later** for all of these mechanics specifically.
- Walk/run speed values, exact jump height/arc: **measure from the disc later.**

## 3. Attacks

- Core attacks are simple single-button presses on Punch (X) or Kick (Y) rather than deep motion-input
  combo strings — "most attacks... can be executed with a simple press of the attack button" [per
  StrategyWiki summary, S2/S4]; "simplified commands for special and super moves" [S11][S12].
- Falcon's normal style is described as boxing punches combined with somersault kicks [S5].
- Dash attacks, jump attacks, and precise punch/kick strings per character are not enumerated by any
  source reached this session beyond the Power Drive/Fusion specials in §5 below —
  **measure from the disc later** for normal-move strings and juggle/combo routes.
- Grabbing and throwing opponents: the Punch+Kick action button is used to grab; exact throw mechanics,
  startup, and damage: **measure from the disc later.**
- Picking up / carrying / throwing / swinging objects: confirmed general mechanic — press the action
  button near a destructible/weapon object to pick it up, Punch to throw it, Kick to swing/use it as a
  weapon [S2]. Per-object exact behavior (swing arcs, durability, break conditions): **measure from the
  disc later.**
- Weapons obtained from item boxes include chairs, tables, bombs, bazookas/bazooka guns, flamethrowers,
  swords, and Molotov cocktails [S9][S11][S12].

## 4. Items

- Each stage is populated with destructible scenery (tables, chairs, lampposts, signs, etc.) that can be
  picked up and used as improvised weapons, plus item boxes/pickups that can contain actual weapons
  [S9][S12].
- Documented weapon/item categories across the game: bazooka, sword, hammer, bombs/Molotov cocktails,
  flamethrower, and healing/power-up consumables described as meat, cake, and apples; special items
  include a "Power Shield" and "Nyoi-bo" staff [S9].
- Per-stage item lists are not comprehensively documented in any source reached — the one stage with
  confirmed interactable detail is **Londo** (Edward Falcon's stage, a stand-in for London) [S6]:
  - Setting: a riverside city with a fountain and restaurants (named "Fiskerestaurant," "The Royal
    Restaurant," "Fish & Chips"); pigeons populate the area.
  - Destructible/throwable scenery: 2 lampposts, 1 bench, 1 garbage can, 2 plants, The Royal Restaurant
    billboard, 2 tables, 2 chairs, 2 wall billboards (non-respawning), 7 window plants (non-respawning).
  - No stage-exclusive weapon item is documented beyond the above; Falcon's own "main item" is noted
    elsewhere as a soccer ball [S5], but whether that's a Londo-stage item or a Falcon-specific gag
    prop: **measure from the disc later.**
- Full item list per other stage (Tong-An, Mahdad, Manches, Oedo, Mutsu, Dawnvolta, Dullstown,
  Skullhaven, Avalon Is.): **measure from the disc later.**
- Healing item specifics (HP restored, spawn rate): **measure from the disc later.**

## 5. Power Stones (gems)

- Power Stones are colored gems that appear in the arena during a match [S1][S9].
- Collecting **three** Power Stones triggers **Power Change**: the character transforms into a more
  powerful form [S1][S9][S4].
- While transformed, the character gains a power gauge; the transformed state lasts only until the gauge
  fully drains [S1][S9].
- While transformed and the gauge is up, the character can throw out lesser special moves, **or** spend
  the entire remaining gauge at once on one of two super/"Fusion" moves — generally one long-range
  attack and one grab/close-range or juggle-heavy attack [S1][S9][S11].
- The two special-move tiers are named consistently across sources as **Power Drive** (regular specials,
  available any time while carrying stones/transformed, lower cost) and **Power Fusion** (the two
  gauge-dump super moves, bound to Punch+Jump and Kick+Jump / L and R) [S2][S3].
- Exactly how/when Power Stones spawn (start of round vs. drip-fed, whether item boxes can also yield a
  stone) and what happens to a character's collected stones when they take a hit (e.g., Valgas's
  attacks are specifically noted to knock **two** Power Stones off a carrier at once [S7]) beyond that
  one data point: **measure from the disc later** for the general on-hit stone-drop rule and respawn
  timing.
- After a character's transformation ends (gauge empties or they're KO'd transformed), what happens to
  the stones (destroyed, dropped back into the arena, etc.): **measure from the disc later.**

### Power Drive / Power Fusion — full table (per [S3], StrategyWiki Moves page)

| Character | Power Drive (Punch) | Power Drive (Kick) | Power Fusion (Jump+Punch) | Power Fusion (Jump+Kick) |
|---|---|---|---|---|
| Edward Falcon | Power Missile | Power Hurricane | Power Explosion | Power Rocket |
| Ryoma | Raijinken | Iaizan | Midare Zantou | Tenchi Ryoudan |
| Ayame | Hana Shuriken | Ouka Gakure | Hyakka Ryouran | Ouka no Mai |
| Wang-Tang | Ryuugadan | Ryuu Taifuu | Dai Ryuu Gyoku | Muten Ryuubu |
| Rouge | Gouka no Toiki | Yume e no Izanai | Shakunetsu no Wana | Himitsu no Tengoku |
| Jack | Rolling Slash | Round Slash | Killer Dance | Misery Rain |
| Gunrock | Gun Gun Rock | Rock the Crash | Rock 'n' Roll | Earthquake |
| Galuda | Sabaki no Hikari | Tenkuu no Sakebi | Tenbatsu no Hikari | Tenkuu no Otakebi |

**Falcon, in full (cross-referenced [S3] + [S5]):**
- Power Drive / Punch — **Power Missile**: fires a homing missile from his arm.
- Power Drive / Kick — **Power Hurricane**: a spinning uppercut.
- Power Fusion / Jump+Punch — **Power Explosion**: fires several homing missiles in a spread.
- Power Fusion / Jump+Kick — **Power Rocket**: charges at the opponent repeatedly in succession; per
  [S5] this is "his most damaging Power Fusion throughout the entire game." (Note: a separate fan
  summary [S14] describes "Power Rocket" as the Attack+Jump move and "Power Explosion" as the
  Action+Jump move — the opposite button pairing from [S3]/[S5]. [S3] and the Falcon-specific page [S5]
  agree with each other and are treated as primary; confirm against the disc.)
- Power Change form: a red, android-like powered suit that can fire missiles and fly briefly via a back
  rocket; nicknamed "Red Whirlwind" (赤い疾風) [S5].

**Ryoma, in full ([S3], plus earlier cross-check [S14] which agrees on move identity though not on
exact button naming):**
- Power Drive / Punch — **Raijinken**: a quick slash at the nearest opponent, calling down a lightning
  strike where the sword hits; can be chained several times, with the final hit calling down multiple
  bolts [S14, consistent with S3's naming].
- Power Drive / Kick — **Iaizan** (named only in [S3]; effect not separately confirmed —
  **measure from the disc later**).
- Power Fusion / Jump+Punch — **Midare Zantou**: an extremely fast flurry of slashes that throws out
  many slow homing crescent projectiles [S14].
- Power Fusion / Jump+Kick — **Tenchi Ryoudan**: Ryoma ascends and repeatedly slashes anyone caught,
  then slams down in a lightning burst [S14].
- Power Change form: "Master Swordsman" per [S1]'s roster summary; visual details beyond the title —
  **measure from the disc later.**

Other 6 cast members: Power Drive/Fusion move **names** are in the table above per [S3]; per-move
**effect descriptions** beyond Falcon and Ryoma were not captured this session —
**measure from the disc later.**

## 6. Round rules

- A match is won when one character's life/health bar is fully depleted [S1].
- Round count (single round vs. best-of-N), match timer length, draw handling, time-over tiebreak rule,
  and any ring-out mechanic: **not confirmed** in any source reached this session —
  **measure from the disc later** for all of these.
- Health bar values, numeric damage per hit/weapon, and frame data: no FAQ with numbers was reachable
  this session (GameFAQs blocked; the 32bits debug-menu article [S10] confirms a **Hit Edit** tool
  exists in the game's own debug menu for editing hitboxes, but the article doesn't publish the
  underlying numbers) — **measure from the disc later** for all damage/health/timing numbers. The
  in-game debug menu itself (Motion Check + Hit Edit under Game Check, per [S10]) is the best lead for
  extracting ground-truth numbers directly from the disc.

## 7. Roster

Original 10-character roster (8 starting + 2 unlockable bosses) [S1][S4][S11]:

| US name | Japanese name | Home stage | Power Change form name |
|---|---|---|---|
| Edward Falcon | Edward Fokker (エドワード・フォッカー) [S5] | Londo | "Red Whirlwind" (赤い疾風) [S1][S5] |
| Wang-Tang | ワンタン [S1] | Tong-An | "Agile Dragon" [S1] |
| Ryoma | リョーマ [S1] | Mutsu | "Master Swordsman" [S1] |
| Ayame | あやめ [S1] | Oedo | "Cherry Blossom Dancer" [S1] |
| Rouge | ルージュ [S1] | Mahdad | "Scorching Beauty" [S1] |
| Jack | ジャック [S1] | Manches | "Mad Clown" [S1] |
| Gunrock | ガンロック [S1] | Dawnvolta | "Heavy Tank" [S1] |
| Galuda | ガルーダ [S1] | Dullstown | "Proud Eagle" [S1] |
| Kraken (boss, unlockable) | クラケン [S1] | Skullhaven (his pirate ship) [S8] | "Ghost Pirate" [S1]; spectral form with a skull head, a sharpened claw, and a mini-cannon replacing his gun [S8] |
| Valgas (final boss, unlockable) | バルガス [S1] | Avalon Is. [S1][S7] | Transforms into **Final Valgas** after defeat [S1][S7] |

Unlock conditions:
- **Kraken**: unlocked after clearing Arcade mode with all 8 standard characters [S8].
- **Valgas**: unlocked after clearing Arcade mode with Kraken [S7].

Boss fight notes:
- **Kraken**: penultimate boss, fought on his pirate ship (Skullhaven); slow but has long reach via his
  mechanical claw and gun; Power Drive moves "Skull Gun" (fires cannonballs) and "Skull Wire" (claw
  extends to snag and reel in the opponent); Power Fusion moves "Skull Vacuum" (head inflates and sucks
  opponents in) and "Skull Soul" (releases ghosts from his mouth) [S8].
- **Valgas**: final human-form boss on Avalon Is.; stronger than Gunrock, good defense, surprisingly
  quick for his size; most of his attacks knock **two** Power Stones off the opponent at once, and he
  prioritizes grabbing stones himself; moves include "PS Energy" (chest-beam), "Dynamite Kick"
  (launches 1 or 3 energy projectiles), "PS Energy Maximum" (bigger chest beam), "Meteor Chain"
  (full-range electrical burst) [S7].
- **Final Valgas**: after Valgas is defeated, the Power Stones overload him and he transforms into a
  giant monster for a final fight, per the game's ending narrative [S7]. Final Valgas's own moveset and
  whether it's a separate playable/fightable form with distinct mechanics: **measure from the disc
  later.**

## 8. Stage list

Ten stages, one per standard/boss character, confirmed by name from StrategyWiki's roster article
[S4][S1]:

| Stage | Associated character |
|---|---|
| Londo | Edward Falcon |
| Tong-An | Wang-Tang |
| Mahdad | Rouge |
| Manches | Jack |
| Oedo | Ayame |
| Mutsu | Ryoma |
| Dawnvolta | Gunrock |
| Dullstown | Galuda |
| Skullhaven | Kraken |
| Avalon Is. | Valgas |

Only **Londo** has confirmed interactable detail reached this session (see §4 above) — full
interactable/hazard lists for the other nine stages: **measure from the disc later.**

## 9. Modes

- **Arcade mode**: progress through fights to reach and unlock Kraken, then Valgas (see §7 unlock
  conditions). Exact fight count, opponent order/branching, and per-character endings were not
  confirmed by any source reached this session — **measure from the disc later.**
- **Versus mode**: confirmed to exist (human vs. human) [S4] — options/rules therein:
  **measure from the disc later.**
- **Options**: exists per standard Capcom DC conventions; specific contents not confirmed —
  **measure from the disc later.**
- **VMU minigames**: the Dreamcast version shipped with VMU minigames; the later *Power Stone
  Collection* (PSP) re-presents "the three VMU mini-games... on a faux Game & Watch LCD handheld" [S13],
  implying there are **three** VMU minigames tied to the original release. Their names/rules:
  **measure from the disc later.**
- Capcom Fighting Collection 2 (modern rerelease) unlocks Valgas via an "EX Settings → Secret
  Characters" toggle instead of the original unlock chain [S7] — not relevant to the original DC rules
  but noted in case the remaster's unlock flow gets compared against the wrong rerelease.
- No "Power Stone Collection"-specific unlockables beyond the VMU-minigame repackaging were confirmed
  for the *original* 1999 game — **measure from the disc later** if more are wanted.

## 10. Damage numbers / health / timings

No numeric health, damage-per-hit, frame data, or timer-length values were found in any source reached
in this session. GameFAQs (the most likely source for these) blocked all fetch attempts as automated
traffic. The strongest lead for ground-truth numbers is the game's own hidden debug menu — **Game
Check → Motion Check** (animation/pose testing) and **Game Check → Hit Edit** (hitbox viewing/editing)
— documented structurally (not numerically) in [S10]. Patches to enable this menu are said to be
available from SegaXtreme per [S10].

**Overall: measure from the disc later** for every number in this section — health totals, damage per
punch/kick/weapon/Power Drive/Power Fusion, startup/active/recovery frames, and timer length (if any).
