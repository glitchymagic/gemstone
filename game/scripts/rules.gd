class_name Rules
extends RefCounted
## Fight rules, kept pure so the headless tests can check them. Numbers marked GAME come from the game's own code
## and tables (1ST_READ.BIN on the owner's disc, docs/RIP.md "Hit data"); PROVISIONAL ones are still the remaster's.

const MAX_HP := 240                  # GAME: health, player +0x71D4 (s16, 240 at round start)
const ROUND_TIME := 99.0             # GAME (logged): the round clock u8 0x0C7F304D starts at 99 and ends the round at 0
const GEMS_HELD_AT_START := 1        # GAME (logged): each fighter holds one stone at every round's first frame (+0x7230)
const ROUNDS_TO_WIN := 2             # PROVISIONAL best of 3
const GEMS_IN_PLAY := 3              # SPEC s5: three Power Stones -> Power Change
const GAUGE_MAX := 100.0
## GAME (logged, tools/hitlog.py on hdA): the Power gauge (player +0x71F4) starts at 2400 and loses 1 per frame while
## the fighter is free (paused in hit reactions), so a full gauge lasts 40 s; a Power Drive costs 240 (10%), a Fusion
## spends the rest, and damage taken costs dmg / 240 * 1800 (0x0C08E2BC). GAUGE_MAX 100 = the game's 2400.
const GAUGE_DRAIN := 100.0 / 40.0
const DRIVE_COST := 10.0
const GAUGE_PER_DAMAGE := 1800.0 / 240.0 / 2400.0 * 100.0
const FUSION_MIN := 30.0             # PROVISIONAL: Power Fusion dumps the whole gauge
const GETUP_INVULN := 1.0            # seconds of invincibility after getting up
const POWER_DAMAGE_MULT := 1.2       # GAME: attacker in Power Change (0x0C08E104, 0x0C08DFA4)
const POWER_DEFENSE_MULT := 0.5      # GAME: victim in Power Change (0x0C08E110 with the arcade option at 0x0C7F476B = 1)
const GEM_BONUS := [1.0, 1.05, 1.1]  # GAME: attacker holding 0 / 1 / 2 gems (0x0C08E10C / 0x0C08E108)
## GAME: damage scale by the attacker's hits in a row, counted after the hit (0x0C32E0A4): hits 1-5 full, the 6th
## half, then halving; hits on Final Valgas don't count (0x0C08D91A)
static var COMBO_SCALE: Array = DiscTables.list("combo_scale")   # from your 1ST_READ.BIN (importer/tables.py)
## GAME: the CPU's strength by level (0x0C7F305C = the rank counter 0x0C7F305D / 8): its hits x CPU_ATK[level]
## (0x0C32DF78), hits on it / CPU_DEF[level] (0x0C32DFF8)
static var CPU_ATK: Array = DiscTables.list("cpu_atk")   # from your 1ST_READ.BIN (importer/tables.py)
static var CPU_DEF: Array = DiscTables.list("cpu_def")   # from your 1ST_READ.BIN (importer/tables.py)
## MEASURED: the level at each arcade fight in real runs (30 RAM dumps, tools/hitlog.py): the game raises its rank
## counter as you play, so these are the logged averages, not a table from the code
const ARCADE_CPU_LEVEL := [9, 13, 17, 19, 22, 25, 27, 28, 29]

## Fallback attack table for moves the game's hit data doesn't cover with body spheres (projectiles, throws) and
## for fighters without hit data. Fighters with assets/ripped/pN0_hit.json hit with the game's own spheres, frames
## and attack records (GameHits, fighter._game_hit_update). dmg = base damage on the game's 240 scale (Falcon's
## records: every normal hit 12, Power Missile 24, Power Hurricane 12), t0/t1/t2 = startup / active end / total (s),
## reach/height/radius in metres from the attacker's feet, kb = knockback speed, down = knocks down.
## PROVISIONAL: t*, reach, h, r, kb, down (only the fallback path uses the geometry).
const ATTACKS := {
	"punch1": {"dmg": 12, "t0": 0.07, "t1": 0.14, "t2": 0.28, "reach": 0.8, "h": 1.2, "r": 0.55, "kb": 2.0, "down": false},
	"punch2": {"dmg": 12, "t0": 0.08, "t1": 0.15, "t2": 0.30, "reach": 0.85, "h": 1.2, "r": 0.55, "kb": 2.5, "down": false},
	"punch3": {"dmg": 12, "t0": 0.12, "t1": 0.22, "t2": 0.55, "reach": 0.95, "h": 1.1, "r": 0.65, "kb": 7.0, "down": true},
	"punch4": {"dmg": 12, "t0": 0.12, "t1": 0.22, "t2": 0.55, "reach": 0.95, "h": 1.1, "r": 0.65, "kb": 7.0, "down": true},
	"kick1": {"dmg": 12, "t0": 0.10, "t1": 0.18, "t2": 0.36, "reach": 0.95, "h": 0.8, "r": 0.6, "kb": 3.0, "down": false},
	"kick2": {"dmg": 12, "t0": 0.14, "t1": 0.24, "t2": 0.60, "reach": 1.05, "h": 0.9, "r": 0.65, "kb": 8.0, "down": true},
	"kick3": {"dmg": 12, "t0": 0.14, "t1": 0.24, "t2": 0.60, "reach": 1.05, "h": 0.9, "r": 0.65, "kb": 8.0, "down": true},
	"dash": {"dmg": 12, "t0": 0.10, "t1": 0.30, "t2": 0.65, "reach": 0.9, "h": 1.0, "r": 0.7, "kb": 9.0, "down": true},
	"air": {"dmg": 12, "t0": 0.06, "t1": 0.30, "t2": 0.40, "reach": 0.7, "h": 0.6, "r": 0.7, "kb": 6.0, "down": true},
	"throw": {"dmg": 48, "t0": 0.25, "t1": 0.30, "t2": 0.70, "reach": 0.7, "h": 1.0, "r": 0.7, "kb": 10.0, "down": true},
	"drive_p": {"dmg": 24, "t0": 0.15, "t1": 0.45, "t2": 0.70, "reach": 1.6, "h": 1.1, "r": 1.0, "kb": 9.0, "down": true},
	"drive_k": {"dmg": 12, "t0": 0.12, "t1": 0.40, "t2": 0.75, "reach": 1.2, "h": 1.2, "r": 1.1, "kb": 11.0, "down": true},
	"fusion1": {"dmg": 48, "t0": 0.40, "t1": 1.40, "t2": 2.00, "reach": 3.0, "h": 1.1, "r": 2.2, "kb": 13.0, "down": true},
	"fusion2": {"dmg": 48, "t0": 0.30, "t1": 1.60, "t2": 2.20, "reach": 1.8, "h": 1.2, "r": 1.6, "kb": 14.0, "down": true},
}
## GAME (partly): thrown stage objects hit with item attack records (1ST_READ 0x0C33AB08, types 5/6) whose base depends
## on the object kind: logged 24, 32 and 40 (hdA: 6 hits all 32; hlS on Londo: 24 and 40). Which object uses which
## record isn't decoded, so every prop uses 32, the most common one.
const OBJECT_HIT_DMG := 32
## GAME (logged): a throw applies type-2 attack records 48-62 (no defence / combo cut / bonus) in parts from the throw
## code; the logged totals (tools/hitlog.py, hdA + hlS): Falcon 49+49+48 = 12+12+24 and 50 = 48, Wang-Tang 50 = 48,
## Ayame 49x4 + 48 = 48, Kraken 50 = 48, Final Valgas 50x4 + 48 = 96. The remaster's throw is one hit of that total
## (ATTACKS.throw 48; THROW_TOTAL overrides); fighters not logged throwing use 48.
const THROW_TOTAL := {"finalvalgas": 96}
const OBJECT_SWING_DMG := 16         # PROVISIONAL (unused)

## Per-fighter move names (SPEC s5 table, StrategyWiki Moves).
const MOVE_NAMES := {
	"falcon": {"drive_p": "Power Missile", "drive_k": "Power Hurricane", "fusion1": "Power Explosion", "fusion2": "Power Rocket"},
	"ryoma": {"drive_p": "Raijinken", "drive_k": "Iaizan", "fusion1": "Midare Zantou", "fusion2": "Tenchi Ryoudan"},
	"ayame": {"drive_p": "Hana Shuriken", "drive_k": "Ouka Gakure", "fusion1": "Hyakka Ryouran", "fusion2": "Ouka no Mai"},
	"wangtang": {"drive_p": "Ryuugadan", "drive_k": "Ryuu Taifuu", "fusion1": "Dai Ryuu Gyoku", "fusion2": "Muten Ryuubu"},
	"rouge": {"drive_p": "Gouka no Toiki", "drive_k": "Yume e no Izanai", "fusion1": "Shakunetsu no Wana", "fusion2": "Himitsu no Tengoku"},
	"jack": {"drive_p": "Rolling Slash", "drive_k": "Round Slash", "fusion1": "Killer Dance", "fusion2": "Misery Rain"},
	"gunrock": {"drive_p": "Gun Gun Rock", "drive_k": "Rock the Crash", "fusion1": "Rock 'n' Roll", "fusion2": "Earthquake"},
	"galuda": {"drive_p": "Sabaki no Hikari", "drive_k": "Tenkuu no Sakebi", "fusion1": "Tenbatsu no Hikari", "fusion2": "Tenkuu no Otakebi"},
}

## GAME: the damage of one hit (0x0C059718 then 0x0C08DFA4), checked on 24 logged real hits (tools/hitlog.py hits)
## base = the attack record's damage byte; rtype 2 = records that skip defence and the combo cut (0x0C0597A0)
static func game_damage(base: int, victim_defence: float, combo_hits: int, attacker_gems: int, attacker_powered: bool,
		victim_powered: bool, atk_cpu_level := -1, vic_cpu_level := -1, rtype := 0) -> int:
	return int(game_damage_f(base, victim_defence, combo_hits, attacker_gems, attacker_powered, victim_powered,
		atk_cpu_level, vic_cpu_level, rtype))

## The same before the final int(): the health recovery ceiling takes int(d x 0.2) of the FLOAT damage (docs/HEALTH.md)
static func game_damage_f(base: int, victim_defence: float, combo_hits: int, attacker_gems: int, attacker_powered: bool,
		victim_powered: bool, atk_cpu_level := -1, vic_cpu_level := -1, rtype := 0) -> float:
	var d := float(base)
	if atk_cpu_level >= 0: d *= CPU_ATK[clampi(atk_cpu_level, 0, 31)]
	if rtype != 2: d *= victim_defence * COMBO_SCALE[clampi(combo_hits, 0, 15)]
	if vic_cpu_level >= 0: d /= CPU_DEF[clampi(vic_cpu_level, 0, 31)]
	d = maxf(d, 1.0)
	if rtype != 2 and rtype != 7:   # rtype 7 records get no gem / Power Change bonus (0x0C08E072)
		var m := 1.0
		if rtype == 3 or rtype == 4 or attacker_powered: m = POWER_DAMAGE_MULT
		if attacker_gems == 2: m = GEM_BONUS[2]
		elif attacker_gems == 1: m = GEM_BONUS[1]
		d *= m
	d = maxf(d, 1.0)
	if victim_powered: d *= POWER_DEFENSE_MULT
	if d > 0.0 and d < 1.0: d = 1.0
	return d

static func damage(base: int, attacker_powered: bool, victim_powered: bool) -> int:
	return game_damage(base, 1.0, 1, 0, attacker_powered, victim_powered)

static func apply_damage(hp: int, dmg: int) -> int:
	return maxi(0, hp - maxi(0, dmg))

## A knockdown hit makes the victim drop one carried gem (SPEC s5: stones are knocked out on hit;
## Valgas knocks out two). Changed fighters don't drop (their stones are spent on the change).
static func gems_dropped(carried: int, knockdown: bool, victim_powered: bool, attacker_is_valgas := false) -> int:
	if victim_powered or carried <= 0 or not knockdown: return 0
	return mini(carried, 2 if attacker_is_valgas else 1)

static func should_power_change(gems: int) -> bool:
	return gems >= GEMS_IN_PLAY

static func drain_gauge(gauge: float, dt: float) -> float:
	return maxf(0.0, gauge - GAUGE_DRAIN * dt)

static func can_fusion(gauge: float) -> bool:
	return gauge >= FUSION_MIN

static func can_drive(gauge: float) -> bool:
	return gauge >= DRIVE_COST

## Round result: 0 / 1 = winner index, -1 = draw.
static func round_winner(hp0: int, hp1: int) -> int:
	if hp0 <= 0 and hp1 <= 0: return -1
	if hp1 <= 0: return 0
	if hp0 <= 0: return 1
	if hp0 == hp1: return -1
	return 0 if hp0 > hp1 else 1

## Battle Royale round result: the only team with anyone standing; on time, the team with the most health left
## (KO'd fighters count 0); -1 = draw. hps[i] / teams[i] per fighter.
static func team_round_winner(hps: Array, teams: Array) -> int:
	var tot := {}
	for i in hps.size():
		var t := int(teams[i]) if i < teams.size() else i
		tot[t] = int(tot.get(t, 0)) + maxi(0, int(hps[i]))
	var alive := tot.keys().filter(func(t): return tot[t] > 0)
	if alive.size() == 1: return int(alive[0])
	if alive.is_empty(): return -1
	var best := -1; var bh := -1; var tie := false
	for t in alive:
		if tot[t] > bh: bh = tot[t]; best = int(t); tie = false
		elif tot[t] == bh: tie = true
	return -1 if tie else best

static func match_winner(wins: Array) -> int:
	for i in wins.size():
		if wins[i] >= ROUNDS_TO_WIN: return i
	return -1

## Cinematics/highlights were tuned on the remaster's old 1000-point health bar; this maps the game's damage onto it
static func dmg_1000(dmg: float) -> float:
	return dmg * 1000.0 / MAX_HP
