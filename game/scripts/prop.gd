class_name Prop
extends Node3D
## A throwable stage object (the disc's own prop mesh). Pick up, carry overhead, throw;
## breaks on impact and comes back after a while (SPEC s3: pick up / carry / throw objects).

enum { REST, CARRIED, FLYING, BROKEN }

var part := 0
var home := Vector3.ZERO
var home_yaw := 0.0
var state := REST
var vel := Vector3.ZERO
var thrower: Fighter = null
var broken_t := 0.0
var visual: Node3D
var floor_y := 0.0

## The disc's property record per object (obj +0x314 -> 0x0C33BFD8 + 10 * index) and the per-fighter throw speeds
## (1ST_READ 0x0C33C05C + char * 24, 6 floats: carry throw byte7 == 0 / != 0, fling (k1/78, k1/154) byte7 == 0 / != 0):
## docs/OBJ.md 6b, game/assets/fidelity/obj_code.json (fx-obj: every stage's throwables matched to their layout parts
## from round-intro RAM dumps; 71 of 73 logged throws exact). Parts not matched use property 2.
static var _oc := {}
var stage_id := "stg00"

static func _code() -> Dictionary:
	if _oc.is_empty() and FileAccess.file_exists("res://assets/fidelity/obj_code.json"):
		_oc = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/obj_code.json"))
	return _oc

func property() -> int:
	var st: Dictionary = (_code().get("stage_throwables", {}) as Dictionary).get(stage_id, {})
	for t in st.get("throwables", []):
		if int(t.part) == part: return int(t.prop)
	return 2

## The hit's base damage: the object attack records 0x0C33AB08 (20 B, b1 = base) at index = property byte 0 (OBJ.md 6b:
## matches the logged 30-32 / 22-23 / 18 after the damage formula)
const HIT_BASE := {1: 32, 2: 24, 3: 40, 4: 48, 5: 32, 6: 32, 7: 32, 8: 32, 9: 24, 10: 24, 11: 40}
func hit_base() -> int:
	return int(HIT_BASE.get(property(), Rules.OBJECT_HIT_DMG))

func fly_cm(by_id: String, carried: bool) -> float:
	var sp: Dictionary = (_code().get("object_throws", {}) as Dictionary).get("speed_table", {})
	var row: Array = (sp.get("per_fighter", {}) as Dictionary).get(by_id, [])
	var b7: int = int((sp.get("byte7_by_prop", {}) as Dictionary).get(str(property()), 0))
	var col := (0 if carried else 2) + (1 if b7 != 0 else 0)
	if col < row.size(): return float(row[col])
	return (20.0 if b7 != 0 else 25.0) - (0.0 if carried else 5.0)

func setup(p_part: int, pos: Vector3, yaw: float, stg := "stg00", p_floor := 0.0) -> void:
	part = p_part; home = pos; home_yaw = yaw; floor_y = p_floor; stage_id = stg
	position = pos; rotation.y = yaw
	visual = Arena._load_prop_scene(part, stg)
	if visual: add_child(visual)

func pick_up(by: Fighter) -> void:
	state = CARRIED; thrower = by; fly_f = 0

func throw_from(by: Fighter, v: Vector3) -> void:
	state = FLYING; thrower = by; vel = v
	global_position = by.global_position + Vector3.UP * 1.6 + by.facing * 0.7

## The original's throw (fighter.gd core step 3a, logged): from a fixed point in front of the thrower, a straight line at
## the given speed (no gravity for FLY_STRAIGHT frames: provisional past the 8 logged ones), then 2 cm/frame^2.
const FLY_STRAIGHT := 30
const FLY_G := 2.0 * 0.01 * 3600.0     # 2 cm/frame^2 in m/s^2
## Respawn (docs/OBJ.md 6b, fx-obj's object log, 21 of 31 breaks; handler 0x0C0ADDDE): hidden on its home spot for 900
## frames, then it blinks for 90 (0x0C0E6E5C), then it is back at rest = 991 frames after the break (the record moves
## home 2 frames after the hit, which an earlier log read as the respawn). The disc's counter also pauses in game
## freezes (a 130-frame transform): not modelled.
const RESPAWN_HIDE_F := 900
const RESPAWN_F := 991
const BLINK_F := 4                     # frames per blink phase (the blink's own rate is not measured)
var fly_f := 0

func launch(by: Fighter, at: Vector3, v: Vector3) -> void:
	state = FLYING; thrower = by; vel = v; fly_f = 0
	global_position = at

func drop(at: Vector3) -> void:
	state = REST; thrower = null
	var ar := get_parent() as Arena
	if ar and ar.has_area():   # set down inside the original's playable area, on the floor under it
		var q := ar.clamp_point(at, 0.4)
		var fy := ar.floor_y_at(q.x, q.z, at.y, 0.3)
		if fy == -INF:   # in front of a raised block (its top over the carrier's feet): the nearest floor at or under
			# the feet (BUG-102: the home floor height put it inside / under the block, Londo part 25 at y 0 under 1.2)
			var best := INF
			for r in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]:
				for k in 16:
					var c: Vector3 = q + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * float(r)
					if not ar.inside(c.x, c.z, 0.4): continue
					var cy := ar.floor_y_at(c.x, c.z, at.y, 0.3)
					if cy > -INF and float(r) < best: best = float(r); q = Vector3(c.x, q.y, c.z); fy = cy
				if best < INF: break
		global_position = Vector3(q.x, fy if fy > -INF else floor_y, q.z)
		return
	global_position = Vector3(at.x, floor_y, at.z)

func tick(dt: float, arena: Arena) -> void:
	match state:
		FLYING:
			fly_f += 1
			if Fighter.CORE:
				if fly_f > FLY_STRAIGHT: vel.y -= FLY_G * dt
			else: vel.y -= 22.0 * dt
			global_position += vel * dt
			rotation.x += dt * 9.0
			for f in arena.fighters:
				if f == thrower or not f.can_be_hit(): continue
				if thrower and f.team == thrower.team: continue   # 2v2: no friendly fire
				if (f.global_position + Vector3.UP * 0.9).distance_to(global_position) < 1.0:
					# the game's item record (base 32, type 5) through its damage formula: the thrower's gems and CPU
					# level count, the victim's defence and Power Change too (6 logged object hits, tools/hitlog.py)
					var dmg := Rules.damage(hit_base(), thrower != null and thrower.powered, f.powered)
					if thrower:
						dmg = Rules.game_damage(hit_base(), f.defence(), 1, thrower.gems, thrower.powered,
							f.powered, thrower.cpu_level, f.cpu_level, 5)
					f.receive_hit(dmg, 9.0, true, global_position - vel.normalized(), thrower)
					if Fighter.CORE: f.rec_ceil = f.hp   # a thrown object (record type 5): its damage never comes back (HEALTH.md)
					if thrower: thrower.stats.hits += 1; thrower.stats.dmg_dealt += dmg
					_break(arena)
					return
			var fy := floor_y
			if arena.has_area():   # the floor the original has under it (multi-level stages), its walls round the area
				var lv := arena.floor_levels(global_position.x, global_position.z)
				if not lv.is_empty(): fy = maxf(arena.floor_y_at(global_position.x, global_position.z, global_position.y, 0.0), lv.min())
			if global_position.y <= fy or (arena.has_area() and not arena.inside(global_position.x, global_position.z, -0.3)):
				_break(arena)   # the floor, or the original's walls round the playable area
			elif arena.has_area() and not arena.inside(global_position.x, global_position.z) and not arena.on_floor(global_position + Vector3.UP * 0.1, 0.45):
				_break(arena)   # past the area's edge with no stage floor under it (Londo's back edge, z 6.3-6.6: the wall)
		BROKEN:
			broken_t += dt
			var bf := int(round(broken_t * 60.0))
			if bf >= 2 and position != home: position = home; rotation = Vector3(0, home_yaw, 0)
			if bf >= RESPAWN_HIDE_F: visible = (bf / BLINK_F) % 2 == 0
			if bf >= RESPAWN_F:
				state = REST; visible = true
				position = home; rotation = Vector3(0, home_yaw, 0)

func _break(arena: Arena) -> void:
	state = BROKEN; broken_t = 0.0; visible = false
	if arena.has_signal("gem_taken"):
		for f in arena.fighters:
			f.fx.emit("break", global_position)
			break
