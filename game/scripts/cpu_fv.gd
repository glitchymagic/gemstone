class_name CPUFV
extends RefCounted
## Final Valgas's OWN AI, ported from 1ST_READ.BIN 0x0C08D5CE (docs/CPU.md "Final Valgas port"; tables =
## assets/fidelity/fv_ai.json, tools/fv_ai.py). Same interface as cpu.gd / cpu_game.gd (input: PInput,
## tick(dt, cam_basis)). The normal fighters' script interpreter (CPUGame) never runs for him.
## Per frame (only in the fight phase, 0x0C0555C4 = round phase 3): the pad words +0x2DC / +0x2E4 and +0x7204 are
## cleared, the interrupts 0x0C08D050 may switch to an interrupt list, then the block's state (0 = the start list,
## 1 = the zone lists, 2 = an interrupt list) fetches a command (one frame) or runs it (stand / steer / press / random
## wait / special). The block is the game's 36 bytes at 0x0C439E38 + player index * 36 (reset 0x0C08CAEA).
## The pad he presses goes to his fighter like a human's would; his attacks start from the pressed word through
## `attack_for` (the disc's pad word -> motion chain, measured: fv_ai.json "attacks"), because the remaster's boss core
## (fighter.gd boss branch) takes named attacks (boss_attack), not pad words.

static var D := {}

static func load_data() -> bool:
	if not D.is_empty(): return true
	var p := "res://assets/fidelity/fv_ai.json"
	if not FileAccess.file_exists(p): return false
	D = JSON.parse_string(FileAccess.get_file_as_string(p))
	return not D.is_empty()

var me
var arena
var input := PInput.new()
var level := 29                # 0x0C7F305C
var ok := false
var fight = null               # the Fight node: round clock (u8 0x0C7F304D) and phase
var cam_yaw := 0               # 0x0C7F31E0

# ---- the block (0x0C439E38 + index * 36) ----
var st := 0          # +0x00 0 start list, 1 zone lists, 2 interrupt list
var sub := 0         # +0x01 0 init, 1 fetch, 2 run the command
var ph := 0          # +0x02 phase of the running command
var cmd := 0         # +0x05 0 stand, 1 steer, 2 press, 3 random wait, 4 special
var prevcmd := 99    # +0x06
var li := 0          # +0x07 list index picked in the zone row
var band := 0        # +0x08 max(TC[clock / 10], TH[(240 + own - opp health) / 24]) % 4
var zone_at := 0     # +0x09 zone class the list was picked for
var zsnap := 0       # +0x0A zone at a stand's start / steer's stop class
var away := 0        # +0x0B steer direction (0 toward, 1 away)
var n := 0           # +0x0C u16 frame count
var m := 0           # +0x0E random-wait spread
var lst := ""        # +0x10 command list (address key)
var lpos := 0        #       read position in it
var wa := 0          # +0x14 first pad word of a press
var wb := 0          # +0x18 pad word pressed after n frames
var item_n := 0      # +0x1C uses of the opponent-state-33 interrupt
var latch := 0       # +0x1D interrupt latches (1 / 2 / 4 / 8)
var lock := 0        # +0x1E no interrupts, no band re-pick
var ikind := 0       # +0x1F which interrupt started the list
var last_hp := 0     # +0x20
var pad := 0         # +0x2DC
var pressed := 0     # +0x2E4
var special := 0     # +0x7204
var round_seen := -1
var trace := false

func _init(p_me, p_arena, p_level := 29) -> void:
	me = p_me; arena = p_arena; level = p_level
	ok = load_data()
	if me != null and me.get_parent() != null and "timer" in me.get_parent(): fight = me.get_parent()
	reset()

func reset() -> void:   # 0x0C08CAEA: memset 0, +6 = 99, +4 = player, +5 = 0
	st = 0; sub = 0; ph = 0; cmd = 0; prevcmd = 99; li = 0; band = 0; zone_at = 0; zsnap = 0; away = 0; n = 0; m = 0
	lst = ""; lpos = 0; wa = 0; wb = 0; item_n = 0; latch = 0; lock = 0; ikind = 0; last_hp = 0

func opp(): return me.opponent

func _core() -> bool:   # his own fighter code runs (fighter.gd _fv_on)
	return me != null and me.has_method("_fv_on") and bool(me._fv_on())

# ------------------------------------------------------------------------------------------------ world
func _clock() -> int:   # u8 0x0C7F304D: seconds left, 99 at the start
	if fight == null: return 99
	return clampi(int(ceil(float(fight.timer) - 0.0001)), 0, 99)

func _hp(f) -> int: return int(f.hp) if f != null else 0

func _fighting() -> bool:   # 0x0C0555C4: round phase 3 (and 0x0C7F302D == 0)
	if fight == null or not ("phase" in fight): return true
	return fight.phase == Fight.R.FIGHT

func _st(f) -> int: return CPUGame.gstate(f)

func _in_attack() -> bool:   # his state 11 (every attack of his runs in it)
	if "ai_st" in me: return int(me.ai_st) == 11
	if _core(): return int(me.gst) == 11
	return me.state == Fighter.S.ATTACK

func _idle() -> bool:   # his state 0 / 2
	if "ai_st" in me: return int(me.ai_st) in [0, 2]
	if _core(): return int(me.gst) in [0, 2]
	return me.state == Fighter.S.IDLE

func _dist() -> float:   # 0x0C08CB4C: horizontal, cm
	var a: Vector3 = CPUGame.pos_cm(me); var b: Vector3 = CPUGame.pos_cm(opp())
	return Vector2(b.x - a.x, b.z - a.z).length()

func _facing_u16() -> int:   # p+0x30 (his model yaw; the remaster's facing vector)
	if "ai_ang" in me: return int(me.ai_ang)
	if _core(): return Fighter._u16(float(me.fv_h))
	var f: Vector3 = me.facing
	return int(round(atan2(f.x, f.z) / TAU * 65536.0)) & 0xFFFF

func _atan_u16(dx: float, dz: float) -> int:   # 0x0C0DF360 on dx / dz, + 0x8000 when dz < 0 (dz 0 -> 1e-4)
	if dz == 0.0: dz = 0.0001
	var a := int(round(atan(dx / dz) / TAU * 65536.0))
	if dz < 0.0: a += 0x8000
	return a & 0xFFFF

## 0x0C08CB8C: the zone class. Opponent off his facing by more than 0x271C (55 deg) and nearer than 700 -> 4, else by
## distance < 400 / 600 / 900 / 1500 -> 0 / 1 / 2 / 3, else 5.
func zone() -> int:
	var a: Vector3 = CPUGame.pos_cm(me); var b: Vector3 = CPUGame.pos_cm(opp())
	var off := (_atan_u16(b.x - a.x, b.z - a.z) - _facing_u16()) & 0xFFFF
	var d := _dist()
	if ((off + int(D.behind_angle[0])) & 0xFFFF) > int(D.behind_angle[1]):
		if d < float(D.behind_cm): return 4
	else:
		var zc: Array = D.zone_cm
		for i in 4:
			if d < float(zc[i]): return i
	return 5

func _bucket() -> int:   # 0x0C08CB26
	return (clampi(level - 20, 0, 11) >> 2) & 3

## 0x0C08CC90: (rand % 32) < T[(level - 20) % 12] (C remainder: negative below level 20; the export keeps the 11
## bytes in front of each table for those)
func _pct(t: Array) -> bool:
	var r := CPUGame.rnd(32)
	return r < int(t[(level - 20) % 12 + 11])   # GDScript int % truncates like C

static func _rnd(k: int) -> int: return CPUGame.rnd(k)   # (u32)(rand / 32768 * 255) % k, k 0 -> 0 (rand used)

## 0x0C08CD18: the health band (only while not locked); true when it changed
func _band() -> bool:
	if lock != 0: return false
	var c := _clock()
	var r6: int = int(D.tc[clampi(c / 10, 0, 9)])
	var h := int((240 + _hp(me) - _hp(opp())) / 24.0)
	var r5: int = int(D.th[clampi(h, 0, 20)])
	var old := band
	band = posmod(maxi(r6, r5), 4)
	return band != old

## 0x0C08CC26: pick a list for the zone: row[band * 16 + rnd 16] -> zone_lists[zone][that]
func _choose() -> void:
	zone_at = zone()
	var row: Array = D.rows[zone_at][band]
	li = int(row[_rnd(16)])
	lst = str(D.zone_lists[zone_at][li]); lpos = 0

func _dir_pad() -> int:   # 0x0C08CD7E: the 8-way pad word toward (away 0) / away from (1) the opponent, camera-relative
	var a: Vector3 = CPUGame.pos_cm(me); var b: Vector3 = CPUGame.pos_cm(opp())
	var ang := (_atan_u16(b.x - a.x, b.z - a.z) - cam_yaw) & 0xFFFF
	var sec := int(((ang + 0x1000) & 0xFFFF) / 0x2000) & 7
	return int(D.dir[away][sec])

# ------------------------------------------------------------------------------------------------ interrupts
func _go_list(kind: int, key: String, locked: bool) -> void:
	st = 2; sub = 0; ph = 0; ikind = kind
	if locked: lock = 1
	lst = key; lpos = 0

func _interrupts() -> void:   # 0x0C08D050
	if lock != 0 or not _idle(): return
	var o = opp()
	var ost := _st(o)
	if (latch & 1) == 0 and str(o.char_id) == "ayame" and ost == 33:   # 0x0C08CE30
		latch |= 1; item_n += 1
		_go_list(0, str(D.item[0] if item_n < 4 else D.item[1]), false)
		return
	if (latch & 2) == 0 and ost == 13:   # 0x0C08CE90: opponent dizzy
		latch |= 2
		if _pct(D.pct_opp13): _go_list(1, str(D.opp13[zone()]), true); return
		return
	if (latch & 4) == 0 and ost == 23 and _opp_changing_up(o):   # 0x0C08CF10: opponent transforming (+10 set)
		latch |= 4
		if _pct(D.pct_opp23): _go_list(2, str(D.opp23[zone()]), true); return
		return
	var old := last_hp   # 0x0C08CF86: his health changed while the opponent is far (zone 5)
	last_hp = _hp(me)
	if (latch & 8) == 0 and zone() == 5 and old != _hp(me):
		latch |= 8
		if _pct(D.pct_far_hit):
			st = 2; sub = 0; ph = 0; ikind = 3; lock = 1
			lst = str(D.far_hit[_rnd(4)]); lpos = 0

## opponent +10 != 0 during state 23: the change INTO Power Change (FIDELITY: +10 not decoded; the remaster's
## transform state is the change in, the revert is its own)
func _opp_changing_up(o) -> bool:
	if "ai_b10" in o: return int(o.ai_b10) != 0
	return bool(o.powered) or o.state == Fighter.S.TRANSFORM

# ------------------------------------------------------------------------------------------------ the list reader
func _b(k: int) -> int:   # signed byte k of the running list
	var a: Array = D.lists[lst]
	var v := int(a[k]) if k < a.size() else 0xFF
	return v - 256 if v > 127 else v

func _w16(hi: int, lo: int) -> int: return ((hi << 8) | (lo & 0xFFFFFFFF)) & 0xFFFF

## 0x0C08D33C: read commands until one yields (stand / steer / press / random wait / special, a state switch or a reset)
func _read() -> void:
	while true:
		var c := _b(lpos)
		match c:
			0, 1, 10:
				n = _w16(_b(lpos + 1), _b(lpos + 2)); lpos += 3
				prevcmd = cmd
				if c == 0: cmd = 0
				else: away = 0 if c == 1 else 1; cmd = 1
				ph = 0; return
			2:
				wa = int(D.padw[_b(lpos + 1)]); n = _w16(_b(lpos + 2), _b(lpos + 3)); wb = int(D.padw[_b(lpos + 4)])
				lpos += 5; prevcmd = cmd; cmd = 2; ph = 0; return
			3:
				lpos += 1
				if _pct(D.pct_maybe): st = 1; sub = 0; ph = 0; return
			4:
				n = _b(lpos + 1) & 0xFFFF; m = _b(lpos + 2); lpos += 3; prevcmd = cmd; cmd = 3; ph = 0; return
			5:
				lpos += 1
				if _pct(D.pct_zone[zone_at]): st = 1; sub = 0; ph = 0; return
				_reset_state(); return
			6:
				lpos += 1; prevcmd = cmd; cmd = 4; ph = 0; return
			7: lpos += 1; lock = 1
			8: lpos += 1; lock = 0
			9: lpos += 1; latch = 0; lock = 0
			_:
				lpos += 1; _reset_state(); return

func _reset_state() -> void:
	st = 0; sub = 0; ph = 0; latch = 0; lock = 0

# ------------------------------------------------------------------------------------------------ the commands
func _s16(v: int) -> int: return v - 0x10000 if v >= 0x8000 else v

func _run_cmd() -> void:   # 0x0C338518[cmd]
	match cmd:
		0:   # 0x0C08D0A6 stand
			if ph == 0:
				pad = 0; ph = 1
				if n == 0: n = int(D.stand_n[_bucket()][_rnd(16)])
				zsnap = zone()
			elif ph != 1: return
			n = (n - 1) & 0xFFFF
			if n == 0 or zsnap != zone(): sub = 1
		1:   # 0x0C08D154 steer
			if ph == 0:
				ph = 1
				if n == 0: n = int(D.steer_n[zone()][_rnd(16)])
				zsnap = int(D.thr[_rnd(16)])
			elif ph == 1:
				n = (n - 1) & 0xFFFF
				if n == 0 or zsnap >= zone(): sub = 1
				else: pad = _dir_pad()
		2:   # 0x0C08D21A press
			if ph == 0:
				ph = 1; pressed = wa; pad = wa
			elif ph == 1:
				if n != 0:
					n = (n - 1) & 0xFFFF
					if n == 0: pressed = wb; pad = wb
				if not _in_attack(): sub = 1
		3:   # 0x0C08D286 random wait
			if ph == 0:
				ph = 1
				n = (n + _rnd(m) + int(D.wait_add[band]) + 1) & 0xFFFF
			elif ph == 1:
				n = (n - 1) & 0xFFFF
				if n == 0: sub = 1
		4:   # 0x0C08D2EE special: +0x7204 = 2, until his state leaves 33
			if ph == 0:
				ph = 1; special = 2
			elif ph == 1 and _st(me) != 33:
				sub = 1

## 0x0C08D492 / 0x0C08D4E6 / 0x0C08D594 by st
func _step() -> void:
	match st:
		0:
			if sub == 0: sub = 1; lst = str(D.start); lpos = 0
			elif sub == 2: _run_cmd(); return
			elif sub != 1: return
			sub += 1
			if _band(): lst = str(D.start); lpos = 0
			_read()
		1:
			if sub == 0: sub = 1; _choose()
			elif sub == 2: _run_cmd(); return
			elif sub != 1: return
			sub += 1
			if _band(): _choose()
			var z := zone()
			var keep := false
			if zone_at == 4: keep = z >= 4
			elif zone_at == 5: keep = z >= 5
			else: keep = zone_at >= z
			if not keep: _choose()
			_read()
		2:
			if sub == 0: sub = 1
			elif sub == 2: _run_cmd(); return
			elif sub != 1: return
			sub += 1
			_read()

# ------------------------------------------------------------------------------------------------ the frame
func tick(_dt: float, cam_basis: Basis) -> void:
	pad = 0; pressed = 0; special = 0
	if not ok or me == null or opp() == null: input.set_state(Vector2.ZERO, {}); return
	cam_yaw = int(round(atan2(cam_basis.z.x, cam_basis.z.z) / TAU * 65536.0)) & 0xFFFF
	if me.cpu_level >= 0: level = me.cpu_level
	if fight != null and "round_no" in fight and int(fight.round_no) != round_seen:
		round_seen = int(fight.round_no); reset()
	if _fighting():
		_interrupts()
		_step()
	_emit()

func _emit() -> void:
	var mv := Vector2(float((pad & 0x80) != 0) - float((pad & 0x40) != 0), float((pad & 0x20) != 0) - float((pad & 0x10) != 0))
	var now := {}
	if pad & 0x600 == 0x600: now["action"] = true
	else:
		now["punch"] = pad & 0x400 != 0
		now["kick"] = pad & 0x200 != 0
	now["jump"] = pad & 0x4 != 0
	input.set_state(mv.limit_length(1.0), now)
	if _core():   # his fighter code (fighter.gd "Final Valgas (fx-fv2)") takes the pad words themselves
		me.fv_pad = pad; me.fv_prs = pressed
		return
	if pressed != 0 and me.has_method("boss_attack"):
		var a := attack_for(pressed)
		if a != "": me.boss_attack(a)

## His fighter code's answer to a pressed pad word in state 0 (measured on the disc: fv_ai.json "attacks" = pad word
## -> the remaster's attack name for the motion chain that followed; FIDELITY: belongs in his core, fighter.gd)
func attack_for(w: int) -> String:
	var t: Dictionary = D.get("attacks", {})
	return str(t.get(str(w), ""))
