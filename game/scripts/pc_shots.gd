class_name PCShots
extends RefCounted
## fx-shot (docs/SHOTS.md): the Power Drive / Fusion shots. The original's move code (0x0C339070[char]) spawns them as
## type-1 objects in the object pool (0x0C7D0980 + slot * 0x31C, owner = the attacker); each carries its own attack
## spheres (+0x148, world x / y / z / r cm, r 0 = off) and a hit id (+0x100). Every frame the original tests those
## spheres against the fighters and an overlap is a hit: the victim's record = the owner's attack
## record of that hit id (victim +0xF8 / +0x71BD, logged), damage by the game's formula; the victim's reaction starts on
## his next frame (the pool runs after the players). A shot hits a victim once (+0x144), a victim takes one shot a
## frame. The table (game/assets/fidelity/pc_shots.json, tools/pc_shots.py build) holds every shot of every Drive /
## Fusion as the original logged it: its spawn row in the move, then per frame the object's position, heading and spheres in the attacker's frame (his feet on the move's first row, his heading on the shot's
## first frame). The remaster replays those rows and runs the same sphere test against the fighters' body spheres.
## Look (w8, tools/shot_look.py): each shot draws the disc's own effect-model parts where the disc's draw nodes put them,
## every frame (game/assets/fidelity/pc_shot_look.json: per table shot, per row [[part, X, Y, Z axes, T cm from the shot's
## position]] in the same attacker frame as the rows; parts = game/assets/ripped/effects/efN0_pPP.glb, common_pPPP.glb for the common bank).

const CM := 0.01
const LOOK_DIR := "res://assets/ripped/effects/"
static var _t := {}
static var _lk := {}
static var _glb := {}

static func _look(char_id: String, nm: String, i: int) -> Array:
	if _lk.is_empty() and FileAccess.file_exists("res://assets/fidelity/pc_shot_look.json"):
		_lk = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/pc_shot_look.json"))
	var f: Dictionary = (_lk.get("fighters", {}) as Dictionary).get(char_id, {})
	var m: Array = (f.get("moves", {}) as Dictionary).get(nm, [])
	return (m[i] as Dictionary).get("rows", []) if i < m.size() else []

static func _part(char_id: String, part: int) -> Node3D:
	var ef: String = ((_lk.get("fighters", {}) as Dictionary).get(char_id, {}) as Dictionary).get("ef", "")
	var path := LOOK_DIR + ("common_p%03d.glb" % (part - 1000) if part >= 1000 else "%s_p%02d.glb" % [ef, part])
	if not _glb.has(path):   # one template per part, its materials baked into its own meshes (a per-instance surface
		_glb[path] = null    # override logs "material is null" errors on the headless renderer)
		if ResourceLoader.exists(path):
			var t: Node3D = (load(path) as PackedScene).instantiate()
			t.scale = Vector3.ONE * CM
			_fx_mats(t)
			var ps := PackedScene.new()   # packed, not a live node: nothing left over at exit
			ps.pack(t)
			t.free()
			_glb[path] = ps
	return (_glb[path] as PackedScene).instantiate() if _glb[path] else null

## the effect parts' disc materials: the translucent list (glows: PCW intensity colour, face ARGB 0.75 / 1 / 1 / 1 on almost
## every effect part) unshaded, dst ONE (export_glb "_add") additive with src alpha x face alpha 0.75; the opaque list lit
static func _fx_mats(root: Node) -> void:
	for mi in Mats._meshes(root):
		var ms := (mi as MeshInstance3D).mesh.duplicate() as ArrayMesh
		for k in ms.get_surface_count():
			var src := ms.surface_get_material(k) as StandardMaterial3D
			if src == null: continue
			var m := src.duplicate() as StandardMaterial3D
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			var glow := src.resource_name.ends_with("_add") or src.resource_name.ends_with("_blend")
			if glow: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			else: m.roughness = 0.85   # the opaque list: solid things (Gunrock's boulders, Falcon's missiles), lit like the stage
			if src.resource_name.ends_with("_add"):
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.albedo_color = Color(1, 1, 1, 0.75)
			elif src.resource_name.ends_with("_blend"):
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.5
			ms.surface_set_material(k, m)
		(mi as MeshInstance3D).mesh = ms

static func _load() -> void:
	if _t.is_empty() and FileAccess.file_exists("res://assets/fidelity/pc_shots.json"):
		_t = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/pc_shots.json"))

## the shots of a Drive / Fusion (X / Y / AX / AY / FX / FY), [] when the original spawned none
static func shots_of(char_id: String, nm: String) -> Array:
	_load()
	var f: Dictionary = (_t.get("fighters", {}) as Dictionary).get(char_id, {})
	return (f.get(nm, {}) as Dictionary).get("shots", [])

static func has_shots(char_id: String, nm: String) -> bool:
	return not shots_of(char_id, nm).is_empty()

## the move's heading rule (pc_shots.py turns, the disc's pool +0x30 from a stale heading): {row, snap, rate, n};
## snap = face the opponent on that row, else n rows of `rate` (u16) toward him from that row; {} = no data
static func turn(char_id: String, nm: String) -> Dictionary:
	_load()
	var f: Dictionary = (_t.get("fighters", {}) as Dictionary).get(char_id, {})
	return (f.get(nm, {}) as Dictionary).get("turn", {})

var owner: Fighter
var live: Array = []      # {d: table shot, j: its row, org: Vector3 m, a: heading rad, hit: {victim id: true}}
var move := ""
var org := Vector3.ZERO
var spawned := 0          # stats: shots spawned / hits landed (tests)
var landed := 0

func _init(f: Fighter) -> void:
	owner = f

## the move's first row (the Drive's k1/16 / the Fusion's first): its shots are placed from here
func begin(nm: String) -> void:
	move = nm
	org = owner.global_position

## the attacker's move reached row `row`: the shots that start there appear (and are tested this frame)
func spawn(row: int) -> void:
	var all := shots_of(owner.char_id, move)
	for i in all.size():
		var d: Dictionary = all[i]
		if int(d.t) != row: continue
		var s := {"d": d, "j": 0, "org": org, "a": Fighter._ang(owner.facing), "hit": {}, "lk": _look(owner.char_id, move, i), "vis": []}
		live.append(s)
		spawned += 1
		_test(s)
		_draw(s)

## every frame before the attacker's own: the live shots move one row and test
func tick() -> void:
	if live.is_empty(): return
	if not CorePC.fight_on(owner):   # the round ended / restarts: the pool is cleared
		clear()
		return
	var keep := []
	for s in live:
		s.j += 1
		if s.j < (s.d.rows as Array).size():
			_test(s)
			_draw(s)
			keep.append(s)
		else:
			_undraw(s)
	live = keep

func clear() -> void:
	for s in live: _undraw(s)
	live = []

## the disc's parts of this row where its nodes put them ([] = nothing drawn: hide)
func _draw(s: Dictionary) -> void:
	var lk: Array = s.lk
	var ns: Array = lk[s.j] if s.j < lk.size() else []
	var vis: Array = s.vis
	var host := owner.get_parent()
	if host == null: return
	var f := Fighter._dir(float(s.a)); var sd := Vector3(f.z, 0, -f.x)
	for k in ns.size():
		var n: Array = ns[k]
		if k >= vis.size(): vis.append([-1, null])
		if int(vis[k][0]) != int(n[0]):
			if vis[k][1]: (vis[k][1] as Node).queue_free()
			var h := Node3D.new()
			var m := _part(owner.char_id, int(n[0]))
			if m: h.add_child(m)
			host.add_child(h)
			vis[k] = [int(n[0]), h]
		var ax := []
		for a in 3: ax.append(f * float(n[1 + 3 * a]) + sd * float(n[2 + 3 * a]) + Vector3.UP * float(n[3 + 3 * a]))
		var hn: Node3D = vis[k][1]
		if absf(Basis(ax[0], ax[1], ax[2]).determinant()) < 1e-9:   # a part scaled to nothing this frame
			hn.visible = false
			continue
		var sp: Array = (s.d.rows[s.j] as Array)[0]   # the part's offset is from the shot's own position this row
		hn.transform = Transform3D(Basis(ax[0], ax[1], ax[2]), _world(s, [float(sp[0]) + float(n[10]), float(sp[1]) + float(n[11]), float(sp[2]) + float(n[12])]))
		hn.visible = true
	for k in range(ns.size(), vis.size()):
		if vis[k][1]: (vis[k][1] as Node3D).visible = false

func _undraw(s: Dictionary) -> void:
	for v in s.vis:
		if v[1] and is_instance_valid(v[1]): (v[1] as Node).queue_free()
	s.vis = []

func _world(s: Dictionary, p: Array) -> Vector3:
	var f := Fighter._dir(float(s.a)); var sd := Vector3(f.z, 0, -f.x)
	return (s.org as Vector3) + (f * float(p[0]) + sd * float(p[1]) + Vector3.UP * float(p[2])) * CM

## world position of every live shot (tests / tools)
func positions() -> Array:
	var out := []
	for s in live: out.append(_world(s, (s.d.rows[s.j] as Array)[0]))
	return out

func _test(s: Dictionary) -> void:
	var r: Array = s.d.rows[s.j]
	var sp: Array = r[2]
	if sp.is_empty(): return
	var att := []
	for q in sp: att.append([_world(s, q), float(q[3]) * CM])
	for o in (owner.enemies if owner.enemies.size() > 0 else [owner.opponent]):
		var t: Fighter = o
		if t == null or (s.hit as Dictionary).has(t.get_instance_id()) or not t.can_be_hit(): continue
		if not GameHits.overlap(att, t.body_spheres()): continue
		if owner.shot_land(t, int(s.d.hid), _world(s, r[0]), float(s.a) + float(r[1]) / 65536.0 * TAU):
			s.hit[t.get_instance_id()] = true
			landed += 1
