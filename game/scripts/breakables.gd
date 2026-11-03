extends Node
## BUG-95: the original's breakable scenery and the piece it drops (docs/BRK.md, decoded from 1ST_READ, checked by
## tools/breakables.py check on every logged object log: 11/11 breaks, 9/9 hang timers, 297/297 fall rows, 7/7 hits).
## - Breakable = type-4 kind-15 object (handler 0x0C0B1C24), one per entry of game/assets/fidelity/breakables.json
##   (its collision box from round-start RAM; drawn by the stage layout part desc[2] + 10). Sub 0: 0x0C0AC600 looks in
##   the box's contact list for a fighter (+2 == 0) with the reaction machine on (+9 == 1) in class 22 (+0x71DD, the
##   wall splat); the contact = the collision pass's box-vs-fighter test 0x0C02180C (per axis: half + radius - |d| >= 0
##   in x and z, the y spans overlap; the fighter = radius r, centre feet + h, half height h). Found -> 0x0C0B1CA8
##   spawns the piece (owner = the other player), sub 1 = the breakable is freed (0x0C059330): gone until the round
##   resets the objects.
## - Piece = type-2 kind-15 object (handler 0x0C0B1D96): at the breakable's home (pushed to the stage wall like any
##   radius-0 body: Londo 735 -> 730), timer +0xEC = 70 + (u32)(rand() / 32768.0f * 255.0f) % 20 (the game's shared
##   rand), vy -2. Sub 0 hangs until the timer runs out (first fall frame = spawn + timer + 1), then 0x0C0A1E0A arms
##   hit id 32 (record 0x0C33AB08 + 32 * 20: class 3 tumble, base 32, type 7, no hit-stop). Sub 1: y += vy, vy -= 1
##   (cm/frame), its attack sphere (set 16: r 50 cm at the origin) hits each fighter once (+0x11C list) when he is
##   hittable; on the frame after it reaches the floor sub 2 (no hit, landing 0x0C0ACE56), then it is freed.
const UNIT := 0.01
const DATA := "res://assets/fidelity/breakables.json"
const PIECE_HID := 32                 # 0x0C33AB08 record the piece arms (logged in RAM: +0x100 = 32)
const PIECE_REC := "0320001807010100000000000004200003080200"
const OBJ_HID_BASE := 1000            # the record slot breakables.gd adds to the attacker's table for the reaction machine
const PIECE_R := 0.50                 # attack set 16: one sphere, r 50 cm, at the piece origin
static var _doc := {}

var arena: Node
var items: Array = []    # [{home: Vector3 cm, c: Vector3 cm, h: Vector3 cm, node: Node3D, shapes: Array, broken: bool}]
var pieces: Array = []   # [{node, base: Transform3D, home: Vector3 cm, pos: Vector3 cm, vy: float, t: int, sub: int,
						 #   landed: bool, owner: Fighter, toucher: Fighter, hit: Array}]
var _hittable := {}      # fighter -> can_be_hit() at the end of the previous tick (the original tests the state the
						 # frame starts with: the hit lands one frame after the get-up ends, 7 of 7 logged)
var log_events: Array = []   # [[event, frame, ...]] for tests / tools

static func data() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(DATA):
		_doc = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return _doc

func setup(a: Node) -> void:
	arena = a
	var st: Array = (data().get("stages", {}) as Dictionary).get(str(a.get("stage")), [])
	for b in st:
		var e := {"home": _v(b.home_cm), "c": _v(b.box_c_cm), "h": _v(b.box_h_cm), "node": null, "shapes": [], "broken": false}
		var want: Vector3 = _v(b.get("layout_pos_cm", b.home_cm)) * UNIT
		var best: Node3D = null; var bd := 0.05
		for n in a.get("scenery"):
			if int((n as Node3D).get_meta("part", -1)) != int(b.part): continue
			var d := (n as Node3D).position.distance_to(want)
			if d < bd: bd = d; best = n
		e.node = best
		if best and a.get("scenery_body"):   # its collision shapes: the ones built from this holder's meshes
			var org := []
			for mi in Mats._meshes(best): org.append((mi as MeshInstance3D).global_transform.origin)
			for cs in (a.get("scenery_body") as Node).get_children():
				if int(cs.get_meta("part", -1)) != int(b.part): continue
				for o in org:
					if (cs as Node3D).global_transform.origin.distance_to(o) < 0.001: e.shapes.append(cs); break
		items.append(e)

static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## Round start: the original rebuilds every object (logged: the broken ones are back the next round)
func reset() -> void:
	for p in pieces:
		if is_instance_valid(p.node): (p.node as Node).queue_free()
	pieces.clear()
	for e in items:
		e.broken = false
		if e.node: (e.node as Node3D).visible = true
		for cs in e.shapes: (cs as CollisionShape3D).disabled = false
	_hittable.clear()

func tick(frame := -1) -> void:
	var fs: Array = arena.get("fighters")
	_tick_pieces(fs, frame)
	_tick_breakables(fs, frame)
	for f in fs: _hittable[f] = (f as Fighter).can_be_hit()

func _tick_breakables(fs: Array, frame: int) -> void:
	for e in items:
		if e.broken: continue
		for f in fs:
			var ft := f as Fighter
			if not (ft.rx_on and ft.rx_phase == "splat"): continue   # class 22: k2/152 stuck / slide, k2/153
			if not _touches(ft, e): continue
			_break(e, ft, frame)
			break

func _touches(f: Fighter, e: Dictionary) -> bool:   # 0x0C02180C: box (centre c, half h) vs the fighter's cylinder
	var r := Fighter.body_radius(f.char_id) / UNIT
	var hh := float((data().get("body_half_height_cm", {}) as Dictionary).get(f.char_id, 75.0))
	var p := f.global_position / UNIT
	var c: Vector3 = e.c; var h: Vector3 = e.h
	if h.x + r - absf(c.x - p.x) < 0.0: return false
	if h.z + r - absf(c.z - p.z) < 0.0: return false
	return minf(c.y + h.y, p.y + 2.0 * hh) - maxf(c.y - h.y, p.y) >= 0.0

func _break(e: Dictionary, toucher: Fighter, frame: int) -> void:
	e.broken = true
	var owner: Fighter = toucher.last_hit_by if toucher.last_hit_by else toucher.opponent   # 1 - the toucher's owner
	var home: Vector3 = e.home
	var pos := home
	if arena.has_method("has_area") and arena.has_area():   # pushed out of the stage wall (radius 0: the area is
		var q: Vector3 = arena.clamp_point(home * UNIT, -Fighter.body_radius("falcon"))   # Falcon-referenced, r 30)
		pos = Vector3(q.x / UNIT, home.y, q.z / UNIT)
	var t := 70 + CPUGame.rnd(20)
	var node: Node3D = null
	if e.node:
		node = (e.node as Node3D).duplicate() as Node3D
		arena.add_child(node)
		(e.node as Node3D).visible = false
	for cs in e.shapes: (cs as CollisionShape3D).disabled = true
	var p := {"node": node, "base": (e.node as Node3D).transform if e.node else Transform3D(), "home": home, "pos": pos,
		"vy": -2.0, "t": t, "sub": 0, "landed": false, "owner": owner, "toucher": toucher, "hit": [], "new": true}
	pieces.append(p)
	_place(p)
	log_events.append(["break", frame, toucher.char_id, home, t])
	_dbg("break %s by %s home %s piece %s timer %d" % [toucher.char_id, owner.char_id if owner else "-", home, pos, t])

func _place(p: Dictionary) -> void:
	if p.node and is_instance_valid(p.node):
		var b: Transform3D = p.base
		(p.node as Node3D).transform = Transform3D(b.basis, b.origin + (Vector3(p.pos) - Vector3(p.home)) * UNIT)

func _floor_cm(p: Vector3) -> float:   # the floor the original has under the piece (multi-level stages), else 0
	var x := p.x * UNIT; var z := p.z * UNIT
	if arena.has_method("has_area") and arena.has_area():
		var lv: Array = arena.floor_levels(x, z)
		if not lv.is_empty():
			var fy: float = arena.floor_y_at(x, z, p.y * UNIT, 0.0)
			return maxf(fy, float(lv.min())) / UNIT
	var info: Dictionary = arena.get("info") if arena.get("info") is Dictionary else {}
	return float(info.get("floor_y", 0.0))

func _tick_pieces(fs: Array, frame: int) -> void:
	for p in pieces.duplicate():
		if p.new:   # spawned during the breakable's tick: its own handler runs from the next frame
			p.new = false
			continue
		match int(p.sub):
			0:
				p.t = int(p.t) - 1
				if int(p.t) <= 0: p.sub = 1   # 0x0C0A1E0A: hit id 32 armed, the hit list cleared
			1:
				p.pos = Vector3(p.pos) + Vector3(0, float(p.vy), 0)
				p.vy = float(p.vy) - 1.0
				if p.landed:   # +0x274 > 0: on the floor since last frame's collision pass
					p.sub = 2; p.vy = 0.0
					log_events.append(["land", frame])
					_dbg("land at %s" % Vector3(p.pos))
				var fl := _floor_cm(p.pos)
				if Vector3(p.pos).y <= fl:
					p.pos = Vector3(Vector3(p.pos).x, fl, Vector3(p.pos).z); p.landed = true
				_place(p)
				if int(p.sub) == 1: _hit_test(p, fs, frame)
			2:
				if is_instance_valid(p.node): (p.node as Node).queue_free()
				pieces.erase(p)

func _hit_test(p: Dictionary, fs: Array, frame: int) -> void:
	var c: Vector3 = Vector3(p.pos) * UNIT
	var owner: Fighter = p.owner
	for f in fs:
		var ft := f as Fighter
		if ft == owner or ft in p.hit: continue
		if owner and ft.team == owner.team and fs.size() > 2: continue   # 2v2: no friendly fire
		if not (ft.can_be_hit() and bool(_hittable.get(ft, false))): continue
		if not GameHits.overlap([[c, PIECE_R]], ft.body_spheres()): continue
		p.hit.append(ft)
		var dmg := Rules.game_damage(int(PIECE_REC.substr(2, 2).hex_to_int()), ft.defence(), 1,
			owner.gems if owner else 0, owner.powered if owner else false, ft.powered,
			owner.cpu_level if owner else -1, ft.cpu_level, 7)
		var hid := _arm_record(owner)
		# heading: 0x0C08D662 on the piece's velocity (vx = vz = 0 -> 0x4000 for every piece): the logged tumbles all
		# slide toward -x (moves_*: 700 -> 697.5 -> 695.1, z still), so the hit "comes from" +x of the victim
		ft.receive_hit(dmg, 9.0, true, ft.global_position + Vector3(0.5, 0, 0), owner, hid)
		if Fighter.CORE: ft.rec_ceil = ft.hp   # an object's damage never comes back (logged; HEALTH.md type 5)
		if owner: owner.stats.hits += 1; owner.stats.dmg_dealt += dmg
		log_events.append(["hit", frame, ft.char_id, dmg])
		_dbg("hit %s for %d piece y %.1f" % [ft.char_id, dmg, Vector3(p.pos).y])

## The reaction machine reads the hit record from the attacker's table (Fighter._rx_record); the piece's record comes
## from the object table 0x0C33AB08 instead, so it is added once at OBJ_HID_BASE + id in that table (request for the
## lead: a record argument on receive_hit / react_start, then this goes)
static func _arm_record(owner: Fighter) -> int:
	if owner == null: return -1
	Fighter._rx_tables()
	var recs: Dictionary = Fighter._rx.get("records", {})
	if not recs.has(owner.char_id): return -1
	var a: Array = recs[owner.char_id]
	var idx := OBJ_HID_BASE + PIECE_HID
	while a.size() <= idx: a.append("")
	a[idx] = PIECE_REC
	return idx

var _pf := 0
func _physics_process(_dt: float) -> void: _pf += 1
func _dbg(t: String) -> void:
	if OS.has_environment("PS_BRK_LOG"): print("BRK pf %d: %s" % [_pf, t])
