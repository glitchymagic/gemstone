class_name Arena
extends Node3D
## Londo, from the disc's STG00.MDL: world geometry (parts 0/1/3/38) is visible and is the
## collision mesh; local-space props (tables, chairs, plants, bins, lamps) are placed on the plaza.
## Prop placement comes from the game's own RAM (assets/ripped/stg00_layout.json, tools/stage_layout.py: every stage
## object's world matrix read during a real fight on Londo). The PROPS table below is only the no-layout fallback.

signal gem_taken(f: Fighter)

const RIP := "res://assets/ripped/"
const FIDELITY := "res://assets/fidelity/"   # measured on the original (Flycast), tracked
const UNIT := 0.01
const BOUNDS_LAYER := 4   # collision layer of the original's invisible walls: fighters collide with it, camera rays don't
const BOUNDS := Rect2(-7.7, -3.6, 15.1, 10.3)   # plaza walkable area in metres (x, z)
const FOUNTAIN_R := 1.95
const FOUNTAIN_C := Vector3(0, 0, 0.5)   # fountain centre (disc: x 0, z 50 cm), from the RAM layout

## [prop part, x, z, yaw deg, throwable]  (disc units, from the plaza top view)
const PROPS := [
	[16, 0, 0, 0, false],          # fountain centre piece
	[23, -440, -330, 0, false],    # lamp posts (pole swings)
	[31, 690, -330, 0, false],
	[23, -440, 560, 0, false],
	[25, 420, 470, 0, true],       # patio tables with umbrellas
	[25, 560, 170, 30, true],
	[28, 300, 470, 90, true],      # chairs
	[28, 540, 470, -90, true],
	[28, 560, 50, 0, true],
	[32, -300, -250, 45, true],    # metal chair
	[53, -420, 250, 0, true],   # potted plants
	[53, -420, 100, 0, true],
	[55, 700, 600, 0, true],       # trash can
	[14, 200, 640, 0, true],       # flower box
	[55, -250, 620, 0, true],
]

var stage := "stg00"     # STGn0 of the disc: stg00 Londo, stg20 Wang-Tang's dojo, stg30 Jack's mansion, ...
var info := {}            # stgN0_info.json (tools/export_stage.py): world parts, floor, bounds, spawns, camera yaw
var bounds := BOUNDS
var poles: Array[Vector3] = []
var props: Array = []
var scenery: Array = []   # every placed non-throwable stage object (holder nodes; part id in meta "part")
var no_collide: Array = []   # the ones without collision that still block the view (Londo's wall signs)
var world_body: StaticBody3D      # the stage's own geometry (walls, floors)
var scenery_body: StaticBody3D    # placed objects' collision (same layer)
var bounds_body: StaticBody3D     # the original's invisible walls (BOUNDS_LAYER: fighters only, never the camera)
var gems: Array = []
var fighters: Array = []
var has_assets := false
var rng := RandomNumberGenerator.new()
var brk: Node = null   # fx-brk hook: breakable scenery + falling pieces (scripts/breakables.gd, BUG-95)

func build(seed_val := 1) -> void:
	rng.seed = seed_val
	if stage != "stg00" and not ResourceLoader.exists(RIP + stage + "_world.glb"): stage = "stg00"
	if FileAccess.file_exists(RIP + stage + "_info.json"):
		info = JSON.parse_string(FileAccess.get_file_as_string(RIP + stage + "_info.json"))
	_load_area()
	if stage != "stg00" and info.has("bounds_cm"):
		var b: Array = info.bounds_cm
		bounds = Rect2(float(b[0]) * UNIT, float(b[1]) * UNIT, (float(b[2]) - float(b[0])) * UNIT, (float(b[3]) - float(b[1])) * UNIT)
	var world_path := RIP + stage + "_world.glb"
	var body := StaticBody3D.new(); body.name = "StageCollision"; body.collision_layer = 1
	add_child(body)
	world_body = body
	if ResourceLoader.exists(world_path):
		has_assets = true
		var w: Node3D = (load(world_path) as PackedScene).instantiate()
		w.scale = Vector3.ONE * UNIT
		add_child(w)
		Mats.stage_mats(w)
		var skip: Array = area.get("no_collide_world", [])   # disc surfaces the original's floors / walls don't follow
		for mi in Mats._meshes(w):   # one collision shape per surface (material), so single surfaces can be left out
			var mesh := (mi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var key := "%s:%d" % [String(w.get_path_to(mi)), si]
				if key in skip: continue
				var arr := mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ix = arr[Mesh.ARRAY_INDEX]
				var faces := PackedVector3Array()
				if ix is PackedInt32Array and (ix as PackedInt32Array).size() > 0:
					for k in (ix as PackedInt32Array): faces.append(vs[k])
				else: faces = vs
				if faces.size() < 3: continue
				var shape := ConcavePolygonShape3D.new(); shape.set_faces(faces)
				var cs := CollisionShape3D.new(); cs.shape = shape
				cs.set_meta("mesh", key)
				body.add_child(cs)
				cs.global_transform = (mi as MeshInstance3D).global_transform
	if has_area():
		_build_bounds()   # the original's walls where it stops you; no floor anywhere the stage has none
	else:
		# no area data (or no stage files): an invisible floor so headless runs have ground (collision only, never drawn)
		var fl := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(40, 1, 40)
		fl.shape = bx; fl.position = Vector3(0, -0.52 if has_assets else -0.5, 0)
		if stage != "stg00": fl.position.y += float(info.get("floor_y", 0.0)) * UNIT - 0.3
		body.add_child(fl)
	if has_assets and FileAccess.file_exists(RIP + stage + "_layout.json"):
		_build_layout(body)
		brk = preload("res://scripts/breakables.gd").new(); brk.name = "Breakables"; add_child(brk); brk.setup(self)   # fx-brk hook
		return
	for p in PROPS:
		var pos := Vector3(p[1] * UNIT, 0, p[2] * UNIT)
		if p[0] in [23, 31]: poles.append(pos)
		if p[4]:
			var prop := Prop.new()
			prop.setup(int(p[0]), pos, deg_to_rad(p[3]))
			add_child(prop)
			props.append(prop)
		elif has_assets:
			var inst := _load_prop_scene(int(p[0]))
			if inst:
				inst.position = pos; inst.rotation.y = deg_to_rad(p[3])
				add_child(inst)
	if not has_assets:
		# headless/no-asset runs still get the real fountain + lamp layout as invisible colliders
		_add_cylinder(FOUNTAIN_C, FOUNTAIN_R, 0.5)

const THROWABLE := [24, 25, 26, 28, 30, 32, 53, 54, 55]     # patio tables/chairs, plants, bin
const NO_COLLIDE := [20, 38, 43, 50, 52, 56, 57, 58, 14, 10, 11]   # water, jets, splash, pigeons, wall-mounted
const WALL_MOUNTED := [14, 10, 11]

func _build_layout(body: StaticBody3D) -> void:
	var lay = JSON.parse_string(FileAccess.get_file_as_string(RIP + stage + "_layout.json"))
	var londo := stage == "stg00"
	# throwables: Londo's from pass 2; elsewhere the objects that moved between real fight dumps of the stage (the game's
	# fighters picked them up / threw them) + identical-mesh siblings (stgN0_info.json "throwable"); the rest is scenery
	var throwable: Array = []   # JSON numbers are floats: `11 in [11.0]` is false in GDScript (every stage but Londo had
	for t in info.get("throwable", THROWABLE if londo else []): throwable.append(int(t))   # its throwables built as walls)
	var floor_m := 0.0 if londo else float(info.get("floor_y", 0.0)) * UNIT
	# placed objects collide like the world (layer 1) but in their own body, so the camera can tell a lamp post
	# (fades, scripts/scenery_fade.gd) from a wall (the camera goes round it, scripts/fight_cam.gd)
	scenery_body = StaticBody3D.new(); scenery_body.name = "SceneryCollision"; scenery_body.collision_layer = 1
	add_child(scenery_body)
	for d in lay:
		var part := int(d.part)
		var m: Array = d.M
		# row-vector matrix (disc cm) -> Godot transform (metres)
		var b := Basis(Vector3(m[0][0], m[0][1], m[0][2]), Vector3(m[1][0], m[1][1], m[1][2]), Vector3(m[2][0], m[2][1], m[2][2]))
		var pos := Vector3(m[3][0], m[3][1], m[3][2]) * UNIT
		if d.get("pole", false): poles.append(Vector3(pos.x, 0, pos.z))   # the game's pole tag (record float 1.4)
		if part in throwable:
			var prop := Prop.new()
			prop.setup(part, pos, atan2(-float(m[0][2]), float(m[0][0])), stage, floor_m)
			add_child(prop)
			props.append(prop)
			continue
		var inst := _load_prop_scene(part, stage)
		if inst == null: continue
		inst.transform = Transform3D(b, pos)
		inst.set_meta("part", part)
		add_child(inst)
		scenery.append(inst)
		if londo and part in NO_COLLIDE:
			if part in WALL_MOUNTED: no_collide.append(inst)
			continue
		if float(part) in area.get("no_collide_parts", []): continue   # a surface the original stands nobody on (measured)
		for mi in Mats._meshes(inst):
			var cs := CollisionShape3D.new(); cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
			cs.set_meta("part", part)
			scenery_body.add_child(cs)
			cs.global_transform = (mi as MeshInstance3D).global_transform

func _add_cylinder(pos: Vector3, r: float, h: float) -> void:
	var b := StaticBody3D.new(); var cs := CollisionShape3D.new(); var c := CylinderShape3D.new()
	c.radius = r; c.height = h; cs.shape = c; b.add_child(cs); b.position = pos + Vector3.UP * h * 0.5
	add_child(b)

static func _load_prop_scene(part: int, stg := "stg00") -> Node3D:
	var path := RIP + stg + "_prop%d.glb" % part
	if not ResourceLoader.exists(path): return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	var holder := Node3D.new()
	n.scale = Vector3.ONE * UNIT
	holder.add_child(n)
	Mats.stage_mats(n)
	return holder

const CEIL_OVER_FLOOR := 4.5   # m over the stage's highest floor of the original: nobody gets higher (see clamp_fighter)
const NO_FLOOR_TOL := 0.35   # feet this far from every floor of the original (centre and 25 cm round it) = not a floor
var _last_pos := {}
var _still := {}

func clamp_fighter(f: Fighter) -> void:
	if not has_area():
		var p := f.global_position
		p.x = clampf(p.x, bounds.position.x, bounds.end.x)
		p.z = clampf(p.z, bounds.position.y, bounds.end.y)
		if p.y < float(info.get("floor_y", 0.0)) * UNIT - 3.0:
			p = random_floor_point(); f.velocity = Vector3.ZERO
		f.global_position = p
		return
	if f.collision_mask & BOUNDS_LAYER == 0: f.collision_mask |= BOUNDS_LAYER   # the walls below stop fighters only
	# the original moves a fighter straight back inside its playable area (logged: placed past a wall, it is out on
	# the next frame), every height, every state; the reach is per fighter (its collision radius against Falcon's)
	var m := fighter_margin(f.char_id)
	var p := f.global_position
	var air := not f.grounded()
	_run = not air and f.gst in STAIR_GST   # a runner / walker crosses the stairs' face bands (BUG-107)
	var s := air_sdf_at(p.x, p.z) if air else sdf_at(p.x, p.z)
	var fd := Vector3(f.facing.x, 0, f.facing.z)
	# stepping off a lower floor's edge (core_ground's drop rule, BUG-100): not pushed back onto the floor being left
	var stepping := not air and f.gst in [2, 31] and fd.length() > 0.01 and _drop_edge(p, p, fd.normalized(), m)   # a runner / walker only
	if s < m and not stepping:
		var q := air_clamp_point(p, m) if air else clamp_point(p, m)
		var push := Vector3(q.x - p.x, 0, q.z - p.z)
		if push.length() > 1e-5:
			var n := push.normalized()
			var vn := f.velocity.dot(n)
			if vn < 0.0: f.velocity -= n * vn   # no speed into the wall
		p = q
	_run = false
	# in the air (or on the ground, below) over a column with no floor at all (no level of the original, no stage mesh straight down or just
	# inside the edge): the air area holds the disc fighters' logged flight cells, but a launch clamped against a wall
	# there fell through into the sea (stg80 FFA: Wang-Tang launched across the ship stopped at (5.22, 2.12) against the
	# 1 m platform's side, fell to y -2.7, 11 frames out): onto the nearest spot of the walkable area, falling on
	# The same on the ground: a 10 cm area cell at the edge with no floor under it in either game (stg70 FFA: Falcon run
	# into (-1.3, 1.0, 3.88), sdf +0.01, no level, no mesh within 30 cm, pinned there 100 frames): onto the nearest spot
	# with the original's floor (as a top the original lacks)
	if is_inside_tree() and _void_under(p):
		var q := clamp_point(p, m) if air else p
		if _void_under(q): q = _off_top(q, m)
		var push := Vector3(q.x - p.x, 0, q.z - p.z)
		if push.length() > 1e-5:
			var n := push.normalized()
			var vn := f.velocity.dot(n)
			if vn < 0.0: f.velocity -= n * vn
		p.x = q.x; p.z = q.z
	# feet inside a block (every floor of the original here is over them: a 2D area holds the block's top, so the
	# push-back above can't see its sides): out sideways to the nearest spot with a floor at or under the feet, the way
	# the original's walls keep any body out of a block (body pushes, throws and launches don't go through core_ground:
	# Dawnvolta FFA, Ayame launched to (-2.26, -0.36, 5.61) under a 4.3 m top, lifted onto it 14 frames later)
	p = _solid_guard(f, p, m, air)
	# feet never under the original's floor: with nothing of the stage under them (fallen through the disc mesh, e.g.
	# a pole release inside a pillar), up onto the floor the original has there (at most its step-up above, as when
	# a fighter runs onto the fountain base: y 0 -> 55 in one frame, logged)
	if is_inside_tree() and not _ray_down(p):
		var g := floor_y_at(p.x, p.z, p.y)
		if g <= p.y - 0.02:   # pushed down through a floor (fighters piled on each other): the lowest one above, 2.5 m at most
			for y in floor_levels(p.x, p.z):
				if y > p.y and y < p.y + 2.5 and (g <= p.y - 0.02 or y < g): g = y
		if g > p.y - 0.02:
			p.y = g + 0.01
			if f.velocity.y < 0.0: f.velocity.y = 0.0
	# standing (or stuck) on something the original has no floor at: the tops of shelves / walls / masts the disc draws
	# but its collision never lets anyone stand on (seed 1 on Jack's stage: Falcon wall-kicking 100 s on a 7.2 m top;
	# the original's floors there are 0-100 cm): down onto the original's floor under the feet
	# standing on another fighter's head (an air kick landing on him: the remaster's capsules collide, the original's
	# push spheres keep bodies apart, nobody stands on anyone): off him sideways, then it falls
	var under: Fighter = null   # the fighter under the feet: from the last move's contacts, or straight down (a state
	for i in f.get_slide_collision_count():   # that doesn't move keeps no contacts)
		var c := f.get_slide_collision(i)
		if c.get_collider() is Fighter and c.get_collider() != f and c.get_normal().y > 0.6: under = c.get_collider(); break
	if under == null and is_inside_tree():
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			p + Vector3.UP * 0.1, p + Vector3.DOWN * 0.2, 2, [f.get_rid()]))
		if not hit.is_empty() and hit.collider is Fighter: under = hit.collider
	for o in ([under] if under != null else []):
		if true:
			var d := Vector3(p.x - (o as Fighter).global_position.x, 0, p.z - (o as Fighter).global_position.z)
			if d.length() < 0.01: d = Vector3(f.facing.z, 0, -f.facing.x)
			var need := Fighter.CAPSULE_R * 2.0 + 0.14   # clear of his capsule's rounded top
			var op := (o as Fighter).global_position
			var g := _grad(op.x, op.z)   # at the area's edge: inward
			var dirs := [d.normalized(), -d.normalized()]
			if g.length() > 1e-6: dirs.append(Vector3(g.x, 0, g.y).normalized())
			dirs += [Vector3(d.z, 0, -d.x).normalized(), Vector3(-d.z, 0, d.x).normalized()]
			for dv in dirs:
				var q: Vector3 = op + dv * maxf(need, d.length() + 0.05)
				if sdf_at(q.x, q.z) >= m: p.x = q.x; p.z = q.z; break
			f.velocity.y = minf(f.velocity.y, 0.0)
			break
	# never above where the original's physics can take anyone: a pole release from the stage's highest floor rises
	# 1.85 m over a 2.6 m hang (36 cm/f up, 3.5 cm/f^2); the remaster's pole swings reached 17-24 m (fighter.gd)
	var ceil_y := area_floor_max + CEIL_OVER_FLOOR
	if p.y > ceil_y and not f.powered:   # (Power Change forms fly: not measured)
		p.y = ceil_y; f.velocity.y = minf(f.velocity.y, 0.0)
	if is_inside_tree():
		var lp: Vector3 = _last_pos.get(f, p)
		var still: int = (_still.get(f, 0) + 1) if absf(lp.y - p.y) < 0.005 else 0   # held at one height (a wall-kick
		_still[f] = still; _last_pos[f] = p                                            # loop wedged on a top jitters in x/z)
		var stuck := still > 30 and f.state in [Fighter.S.IDLE, Fighter.S.RUN, Fighter.S.JUMP, Fighter.S.DOWN, Fighter.S.GETUP]
		if (_grounded(f) or stuck) and not _orig_floor_near(p):
			var below := -INF
			for y in floor_levels(p.x, p.z):
				if y < p.y and y > below: below = y
			if below > -INF:
				# off the top sideways (never down into it: a solid the remaster has and the original not would push
				# the fighter back up every frame; a lying fighter then never got up) to the nearest spot whose ground
				# is the original's floor; it falls from there
				var q := _off_top(p, m)
				if q != p: p = q; f.velocity = Vector3(0, minf(f.velocity.y, 0.0), 0); _still[f] = 0
			else:
				# inside a block's footprint under its top (the remaster's mesh lets you in where the original has a
				# 50 cm planter top): onto the top when a run would step up onto it (<= step_up), else out sideways to
				# where the original's floor is at the feet (Londo's terrace pushes a fighter out, steptest)
				var above := INF
				for y in floor_levels(p.x, p.z):
					if y > p.y and y < above: above = y
				var q := p
				var top_ok := false   # only onto a top the remaster has too (else it would drop back every frame)
				if above <= p.y + step_up + 0.01:
					var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
						Vector3(p.x, above + 0.3, p.z), Vector3(p.x, above - 0.1, p.z), 1))
					top_ok = not hit.is_empty() and absf(float(hit.position.y) - above) < 0.1
				if top_ok: q = Vector3(p.x, above + 0.01, p.z)
				else: q = _out_of_block(p, m)
				if q != p: p = q; f.velocity = Vector3(0, minf(f.velocity.y, 0.0), 0); _still[f] = 0
	if p.y < area_floor_min - 3.0:   # below every floor of the stage (nothing the original allows): back on the nearest floor
		var c := clamp_point(p, maxf(m, 0.3))
		var fy := floor_y_at(c.x, c.z)
		p = Vector3(c.x, (fy if fy > -INF else spawn_floor_y()) + 0.05, c.z); f.velocity = Vector3.ZERO
	f.global_position = p

## A point on the stage's floor, away from its edges: inside the original's area, on a floor it settles fighters on,
## the start points' level first (gems, respawns); Londo's fountain kept clear.
func random_floor_point(margin := 0.8) -> Vector3:
	if has_area():
		var y0 := spawn_floor_y()
		for i in 80:
			var k: String = _lev_keys[rng.randi() % _lev_keys.size()]
			var ij := k.split(",")
			var x := (_lx0 + (float(ij[1]) + rng.randf()) * _lc) * UNIT
			var z := (_lz0 + (float(ij[0]) + rng.randf()) * _lc) * UNIT
			if sdf_at(x, z) < margin: continue
			var ys := floor_levels(x, z)
			if ys.is_empty(): continue
			var best := INF
			for y in ys: if absf(float(y) - y0) < absf(best - y0): best = float(y)
			if absf(best - y0) > 0.6 and i < 60: continue   # the start floor first (gems on ledges stall CPUs)
			if stage == "stg00" and Vector2(x - FOUNTAIN_C.x, z - FOUNTAIN_C.z).length() < FOUNTAIN_R + 0.6: continue
			var over := false   # another floor of the original right over it: under an overhang or at a block's foot
			for y in ys: if float(y) > best + 0.05 and float(y) < best + 2.2: over = true
			if over: continue
			var q := Vector3(x, best + 0.05, z)
			if is_inside_tree() and out_of_map(q): continue   # the remaster's own floor under it too
			return q
		var sp := spawn_points()
		return Vector3(sp[0].x, y0 + 0.05, sp[0].z)
	for i in 40:
		var p := Vector3(rng.randf_range(bounds.position.x + 0.8, bounds.end.x - 0.8), float(info.get("floor_y", 0.0)) * UNIT + 0.05,
			rng.randf_range(bounds.position.y + 0.8, bounds.end.y - 0.8))
		if stage != "stg00" or Vector2(p.x - FOUNTAIN_C.x, p.z - FOUNTAIN_C.z).length() > FOUNTAIN_R + 0.6: return p
	return Vector3(3, 0.05, 2)

func nearest_prop(pos: Vector3, max_d: float) -> Node3D:
	var best: Node3D = null; var bd := max_d
	for p in props:
		if p.state != Prop.REST: continue
		if has_area() and not inside(p.global_position.x, p.global_position.z, -0.45): continue   # up on a ledge outside the area
		var d: float = (p.global_position - pos).length()
		if d < bd: bd = d; best = p
	return best

func nearest_pole(pos: Vector3, max_d: float):
	for p in poles:
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < max_d: return p
	return null

func scatter_gems(n: int) -> void:   # Battle Royale (a Pass-5 extra): the remaster's own drop
	for i in n:
		_spawn_gem(random_floor_point() + Vector3.UP * 6.0, Vector3.ZERO).legacy = true

func spill_gems(from: Vector3, n: int) -> void:   # Battle Royale / old callers: the remaster's own spill
	for i in n:
		var a := rng.randf() * TAU
		_spawn_gem(from + Vector3.UP * 1.2, Vector3(cos(a) * 4.0, 7.0, sin(a) * 4.0)).legacy = true

## The disc's gems in a 1-on-1 (docs/ITEMS.md 1-4, game/assets/fidelity/item_code.json, fx-item): 3 drop spots per stage
## (1ST_READ 0x0C33CA80); every round each fighter holds one stone and the third colour is queued; the drop clock counts
## fight frames: 0 a chest, 299 the queued gem, 599 a chest, then every 300 frames while a spot is free: a queued gem if
## any, else a chest (chests / items are not in the remaster yet: those drops are skipped, their timing kept). A drop goes
## to the free spot farthest from both fighters (sum of the distances). The Power Change start queues all 3 colours.
const DROP_FIRST := 299
const DROP_EVERY := 300
var drop_spots: Array = []
var gem_queue: Array = []
var drop_f := -1
var _drop_wait := 0
const DROP_CHEST2 := 599
var items: Items = null   # fx-item2 hook: the chests / items (game/scripts/items.gd)

func _load_drop_spots() -> void:
	drop_spots = []
	var path := FIDELITY + "item_code.json"
	if not FileAccess.file_exists(path): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		for sp in (d.get("drop_spots", {}) as Dictionary).get(stage, []):
			drop_spots.append(Vector3(float(sp[0]), float(sp[1]), float(sp[2])) * UNIT)

func gem_round_start(queue: Array) -> void:
	if drop_spots.is_empty(): _load_drop_spots()
	gem_queue = queue.duplicate(); drop_f = 0; _drop_wait = 0
	if items == null: items = Items.new(); items.name = "Items"; items.arena = self; add_child(items)   # fx-item2 hook
	items.round_start()

func queue_gems(colours: Array) -> void:
	for c in colours:
		if not gem_queue.has(c): gem_queue.append(c)

func _drop_tick() -> void:
	if drop_f < 0 or drop_spots.is_empty(): return
	drop_f += 1
	if items and drop_f == 1: items.drop_chest(_free_spot(), 1)   # fx-item2 hook: chest 1 on fight frame 0
	if items and drop_f == DROP_CHEST2: items.drop_chest(_free_spot())   # fx-item2 hook: chest 2
	if drop_f == DROP_FIRST: _drop_gem(); return
	if drop_f <= DROP_CHEST2: return
	if _free_spot() >= 0: _drop_wait += 1   # phase 4: 300 frames with at least one free spot, then the next drop
	if _drop_wait >= DROP_EVERY:
		_drop_wait = 0
		_drop_gem()   # a queued gem, else a chest's turn (not in the remaster yet)

func _drop_gem() -> void:
	var free := _free_spot()
	if gem_queue.is_empty() and free >= 0 and items: items.drop_chest(free); return   # fx-item2 hook: no gem queued = a chest
	if gem_queue.is_empty() or free < 0: return
	var g := _spawn_gem(drop_spots[free] + Vector3.UP * 0.09, Vector3.ZERO)
	g.spot = free; g.color_idx = int(gem_queue.pop_front())

func _free_spot() -> int:
	var best := -1; var bd := -1.0
	for i in drop_spots.size():
		var used := false
		for g in gems:
			if is_instance_valid(g) and (g as Gem).spot == i: used = true; break
		if used or (items and items.spot_used(i)): continue   # fx-item2 hook: a chest / floor item on it
		var d := 0.0
		for f in fighters: d += (drop_spots[i] as Vector3).distance_to(f.global_position)
		if d > bd: bd = d; best = i
	return best

## A gem knocked out of the victim (0x0C08E980): from 1 m up and 1 m toward the attacker, 0.20 m/f that way + vy 0.30;
## the 2nd of a 2-gem hit goes the opposite way
func spill_from(victim: Fighter, toward: Vector3, n: int) -> void:
	var h := Vector3(toward.x, 0, toward.z)
	h = h.normalized() if h.length() > 0.001 else -victim.facing
	for k in n:
		var d := h if k == 0 else -h
		var at := victim.global_position + Vector3.UP * 1.0 + d * 1.0
		if has_area() and not inside(at.x, at.z, 0.1): at = clamp_point(at, 0.1)   # a victim at the edge: start inside the walls (BUG-102, stga0 gems at x 9)
		var g := _spawn_gem(at, d * Gem.HOP_VY + Vector3.UP * 0.30)
		g.spot = -1
		g.color_idx = _free_colour()

func _free_colour() -> int:
	for c in 3:
		var held := 0
		for g in gems:
			if is_instance_valid(g) and (g as Gem).color_idx == c: held += 1
		if held == 0 and not gem_queue.has(c): return c
	return gems.size() % 3

func clear_gems() -> void:
	for g in gems: g.queue_free()
	gems.clear()
	gem_queue = []; drop_f = -1
	if items: items.clear()   # fx-item2 hook
	if brk: brk.reset()   # fx-brk hook: the round start rebuilds the objects

func _spawn_gem(pos: Vector3, vel: Vector3) -> Gem:
	var g := Gem.new()
	g.color_idx = gems.size() % 3
	add_child(g)
	g.global_position = pos; g.vel = vel
	gems.append(g)
	return g

func tick(dt: float) -> void:
	_drop_tick()
	if items: items.tick()   # fx-item2 hook
	for g in gems.duplicate():
		g.tick(dt, self)
		if g.gone():   # unattended 990 frames: gone, its colour queued again
			gems.erase(g); queue_gems([g.color_idx]); g.queue_free()
			continue
		if not g.takeable(): continue
		for f in fighters:
			# the original's pick-up rule (0x0C09CB20, docs/PC.md): gauge 0, under 3 gems, not in PC, not Final Valgas
			if not f.can_take_gem() or f.state in [Fighter.S.DOWN, Fighter.S.KO, Fighter.S.TRANSFORM]: continue
			if (f.global_position + Vector3.UP * 0.6).distance_to(g.global_position) < 0.95:
				gems.erase(g); g.queue_free()
				f.pick_gem()
				gem_taken.emit(f)
				break
	if has_area() and is_inside_tree():
		for f in fighters:
			var fp: Vector3 = (f as Fighter).global_position
			var q := _solid_guard(f, fp, fighter_margin(f.char_id), not f.grounded())
			if q != fp: f.global_position = q
	for p in props:
		p.tick(dt, self)
		var pr := p as Prop
		if pr and pr.state == Prop.REST and has_area() and is_inside_tree() and _prop_seen.get(pr, Vector3.INF) != pr.global_position:
			_settle_prop(pr)
			_prop_seen[pr] = pr.global_position

	if brk: brk.tick()   # fx-brk hook

## A throwable set down (Prop.drop: the area clamp + the original's floor under it) where the stage has no floor of its
## own (Londo's fountain column: a carried plant put down at (0.13, 0, 0.61), 293 frames out in the ryoma / wangtang /
## kraken suites): onto the nearest spot (rings of 10 cm up to 2 m) with the original's floor at most 30 cm over it and
## the remaster's under it. Its home spot (the original's placement) is never moved.
var _prop_seen := {}
func _settle_prop(pr: Prop) -> void:
	var p := pr.global_position
	if p.is_equal_approx(pr.home) or not out_of_map(p + Vector3.UP * 0.1, CamCheck.OBJ_TOL): return
	for ring in range(1, 21):
		for k in 16:
			var a := TAU * k / 16.0
			var q := Vector3(p.x + cos(a) * ring * 0.1, p.y, p.z + sin(a) * ring * 0.1)
			if sdf_at(q.x, q.z) < 0.4: continue
			var fy := floor_y_at(q.x, q.z, p.y, 0.3)
			if fy == -INF: continue
			var c := Vector3(q.x, fy, q.z)
			if _in_solid(c) or out_of_map(c + Vector3.UP * 0.1, CamCheck.OBJ_TOL): continue
			pr.global_position = c
			return

func gems_in_play() -> int:
	var n := gems.size()
	for f in fighters: n += f.gems
	return n

func spawn_points() -> Array:   # round-start x/z read from RAM at the ready state (Londo: pass-1 points)
	if area.has("spawn"):   # the original's round-start feet (logged at the first free frame of the probe fight)
		var a: Array = area.spawn
		return [Vector3(float(a[0][0]), float(a[0][1]) + 5.0, float(a[0][2])) * UNIT,
			Vector3(float(a[1][0]), float(a[1][1]) + 5.0, float(a[1][2])) * UNIT]
	if info.has("spawn_cm"):
		var sp: Array = info.spawn_cm
		var y := float(info.get("floor_y", 0.0)) * UNIT + 1.2
		return [Vector3(float(sp[0][0]) * UNIT, y, float(sp[0][1]) * UNIT), Vector3(float(sp[1][0]) * UNIT, y, float(sp[1][1]) * UNIT)]
	if stage != "stg00":
		var c := bounds.get_center()
		var y2 := float(info.get("floor_y", 0.0)) * UNIT + 1.2
		return [Vector3(c.x - 2.5, y2, c.y), Vector3(c.x + 2.5, y2, c.y)]
	return [Vector3(-3.2, 0.1, 2.6), Vector3(3.4, 0.1, 2.6)]

## Battle Royale starts: the stage's two real start points, then the same pair turned a quarter round its midpoint and
## mirrored across the stage centre, keeping only points on this stage's floor and apart from the others; teammates
## (2v2) take neighbouring points.
func spawn_points_n(n: int, teams: Array = []) -> Array:
	var sp := spawn_points()
	if n <= 2: return sp.slice(0, n)
	var c: Vector3 = (sp[0] + sp[1]) * 0.5
	var d: Vector3 = sp[1] - sp[0]; d.y = 0
	var perp := Vector3(-d.z, 0, d.x) * 0.5
	var bc := area_center() if has_area() else bounds.get_center()
	var cands := [c + perp, c - perp]
	for p in [sp[0], sp[1]]: cands.append(Vector3(2.0 * bc.x - p.x, p.y, p.z)); cands.append(Vector3(p.x, p.y, 2.0 * bc.y - p.z))
	for i in 80: cands.append(random_floor_point() + Vector3.UP * 1.2)
	var out: Array = [sp[0], sp[1]]
	var fy := float(info.get("floor_y", 0.0)) * UNIT
	if is_inside_tree(): fy = ground_y(sp[0])   # the real start points' own floor level (multi-deck stages)
	if has_area(): fy = spawn_floor_y()
	for q in cands:
		if out.size() >= n: break
		var p: Vector3 = q
		if has_area():
			if sdf_at(p.x, p.z) < 0.8: p = clamp_point(p, 0.8)
			if sdf_at(p.x, p.z) < 0.75: continue   # no room there (a narrow corner of the area)
		else:
			p.x = clampf(p.x, bounds.position.x + 0.8, bounds.end.x - 0.8)
			p.z = clampf(p.z, bounds.position.y + 0.8, bounds.end.y - 0.8)
		var gy := ground_y(p)
		if has_area():   # the original's floor there (the remaster's mesh can be another height, or a block's inside)
			gy = -INF
			for y in floor_levels(p.x, p.z):
				if absf(y - fy) < absf(gy - fy): gy = y
			if gy == -INF or _in_solid(Vector3(p.x, gy, p.z)): continue
			var over := false
			for y in floor_levels(p.x, p.z): if y > gy + 0.05 and y < gy + 2.2: over = true
			if over: continue
			if is_inside_tree() and out_of_map(Vector3(p.x, gy + 0.05, p.z)): continue
		if absf(gy - fy) > (0.6 if cands.find(q) < 6 else 1.5): continue   # another level (a deck, a pit, the canal, a roof)
		if stage == "stg00" and Vector2(p.x - FOUNTAIN_C.x, p.z - FOUNTAIN_C.z).length() < FOUNTAIN_R + 0.6: continue
		var ok := true
		for o in out: if Vector2(o.x - p.x, o.z - p.z).length() < 2.0: ok = false
		if ok: out.append(Vector3(p.x, gy + (0.05 if has_area() else 1.2), p.z))
	while out.size() < n: out.append(random_floor_point() + Vector3.UP * 1.2)
	if teams.size() >= 4 and int(teams[0]) == int(teams[1]):   # 2v2 given as [0, 0, 1, 1]: pair up by distance
		var a0: Vector3 = out[0]
		var rest := out.slice(1)
		rest.sort_custom(func(x, y): return a0.distance_to(x) < a0.distance_to(y))
		out = [a0, rest[0], rest[1], rest[2]]
	return out

func camera_yaw() -> float:   # Godot yaw for the fight camera: the original's preset (atan2 of eye - target) - 180
	return deg_to_rad(float(info.get("cam_yaw_deg", 180.0)) - 180.0)

func ground_y(p: Vector3) -> float:   # top of the stage collision under p (multi-level stages); Londo's plaza is y 0
	var floor := float(info.get("floor_y", 0.0)) * UNIT
	if not is_inside_tree(): return floor
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 30.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if hit else floor

## ---- The original's playable area (assets/fidelity/stgN0_area.json, tools/stage_area.py) ----
## Measured in Flycast: a fighter placed on a 50 cm lattice (flood-filled from the round's start points, refined to
## 25 cm at every edge) either settles where it was put or the game's own collision moves it; the file holds the signed
## distance (cm, + inside) to the edge of where the reference fighter's centre (Falcon) can be, the floor levels it
## settles on per 50 cm cell, and the edge contours. Bigger fighters stop further in (fighter_radius.json).
var area := {}
var area_floor_min := -1e9
var area_floor_max := 1e9
var _sdf := PackedByteArray()
var _sdfa := PackedByteArray()   # sdf_air (tools/area_logs.py): + the cells the disc's fighters crossed in the air
var _sdfar := PackedByteArray()  # sdf_air_stairs: the air area + the same bands (the out-of-map check only)
var _sdfr := PackedByteArray()   # sdf_stairs (tools/area_stairs.py, BUG-107): + stair-face bands, for runners / walkers only
var _sx0 := 0.0
var _sz0 := 0.0
var _sc := 10.0
var _sw := 0
var _sh := 0
var _lev := {}
var _lev_keys: Array = []
var _lx0 := 0.0
var _lz0 := 0.0
var _lc := 50.0
var _fl := PackedByteArray()   # floor raster: per 25 cm cell up to _fn levels (cm, int16, -32768 = none)
var _fx0 := 0.0
var _fz0 := 0.0
var _fc := 25.0
var _fw := 0
var _fh := 0
var _fn := 4
## The original lifts a fighter onto any floor at most this far above its feet in one frame (running onto Londo's
## 55 cm fountain base, logged); anything higher is a wall at that height (measured: docs/fx-oom.md, area "step_up_cm").
var step_up := 0.65
static var _radius := {}

func _load_area() -> void:
	var path := FIDELITY + stage + "_area.json"
	if not FileAccess.file_exists(path): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary: return
	area = d
	var g: Dictionary = d.sdf
	_sx0 = float(g.x0); _sz0 = float(g.z0); _sc = float(g.cell); _sw = int(g.w); _sh = int(g.h)
	_sdf = Marshalls.base64_to_raw(String(g.i16))
	_sdfa = Marshalls.base64_to_raw(String(d.sdf_air)) if d.has("sdf_air") else _sdf
	if _sdfa.size() != _sdf.size(): _sdfa = _sdf
	_sdfr = Marshalls.base64_to_raw(String(d.sdf_stairs)) if d.has("sdf_stairs") else _sdf
	if _sdfr.size() != _sdf.size(): _sdfr = _sdf
	_sdfar = Marshalls.base64_to_raw(String(d.sdf_air_stairs)) if d.has("sdf_air_stairs") else _sdfa
	if _sdfar.size() != _sdf.size(): _sdfar = _sdfa
	var l: Dictionary = d.levels
	_lx0 = float(l.x0); _lz0 = float(l.z0); _lc = float(l.cell); _lev = l.cells
	_lev_keys = _lev.keys()
	area_floor_min = float(d.floor_min) * UNIT; area_floor_max = float(d.floor_max) * UNIT
	if d.has("floor"):
		var fg: Dictionary = d.floor
		_fx0 = float(fg.x0); _fz0 = float(fg.z0); _fc = float(fg.cell); _fw = int(fg.w); _fh = int(fg.h); _fn = int(fg.n)
		_fl = Marshalls.base64_to_raw(String(fg.i16))
	if d.has("step_up_cm"): step_up = float(d.step_up_cm) * UNIT
	if _radius.is_empty() and FileAccess.file_exists(FIDELITY + "fighter_radius.json"):
		_radius = JSON.parse_string(FileAccess.get_file_as_string(FIDELITY + "fighter_radius.json"))

func has_area() -> bool:   # the stage's files are here (has_assets) and its measured area loaded
	return has_assets and _sw > 0 and _sdf.size() == _sw * _sh * 2

## How much further in than Falcon this fighter stops (m): the original's per-fighter collision radius difference.
func fighter_margin(char_id: String) -> float:
	var r: Dictionary = _radius.get("delta_cm", {})
	return float(r.get(char_id, 0.0)) * UNIT

var _air := false   # sdf_at reads sdf_air while set (air_sdf / clamp of a fighter off the ground)
var _run := false   # sdf_at reads sdf_stairs while set (a runner / walker on the ground: core_ground, clamp_fighter)
# on his own feet on the stairs: walk / run, and the stop slide / jump crouch a run turns into there (the state changes after
# the frame's move: the check would read the plain area on that frame; core_ground moves them out next frame)
const STAIR_GST := [2, 4, 31, 32]

func _s(i: int, j: int) -> float:
	return float(((_sdfar if _run else _sdfa) if _air else (_sdfr if _run else _sdf)).decode_s16((i * _sw + j) * 2))

## Signed distance (m) from (x, z) to the edge of the original's playable area, + inside (Falcon's centre).
func sdf_at(x: float, z: float) -> float:
	if not (is_finite(x) and is_finite(z)): return -1e9   # a NaN / INF position is nowhere (it recursed below forever: H-9)
	if not has_area():
		return minf(minf(x - bounds.position.x, bounds.end.x - x), minf(z - bounds.position.y, bounds.end.y - z))
	var u := (x / UNIT - _sx0) / _sc; var v := (z / UNIT - _sz0) / _sc
	var j := floori(u); var i := floori(v)
	if i < 0 or j < 0 or i >= _sh - 1 or j >= _sw - 1:   # off the raster: everything there is outside
		# (read the clamped cell directly: going back through metres let rounding put v at -1e-15 -> i = -1 -> recurse
		# for ever, w9 stg70 ladder-size detour searches at the raster's edge)
		var cu := clampf(u, 0.0, _sw - 1.001); var cv := clampf(v, 0.0, _sh - 1.001)
		var cj := floori(cu); var ci := floori(cv)
		var a0 := lerpf(_s(ci, cj), _s(ci, cj + 1), cu - cj); var b0 := lerpf(_s(ci + 1, cj), _s(ci + 1, cj + 1), cu - cj)
		return lerpf(a0, b0, cv - ci) * UNIT - Vector2(u - cu, v - cv).length() * _sc * UNIT
	var fu := u - j; var fv := v - i
	var a := lerpf(_s(i, j), _s(i, j + 1), fu); var b := lerpf(_s(i + 1, j), _s(i + 1, j + 1), fu)
	return lerpf(a, b, fv) * UNIT

## The same for a fighter off the ground: the area plus every cell the disc's fighters crossed in the air (falls off a
## ledge, launches; tools/area_logs.py). A walker never gets these (a launch line over a fence is not a way through it).
func air_sdf_at(x: float, z: float) -> float:
	_air = true
	var s := sdf_at(x, z)
	_air = false
	return s

func air_clamp_point(p: Vector3, margin := 0.0) -> Vector3:
	_air = true
	var q := clamp_point(p, margin)
	_air = false
	return q

func inside(x: float, z: float, margin := 0.0) -> bool:
	return sdf_at(x, z) >= margin

func _grad(x: float, z: float) -> Vector2:
	var h := _sc * UNIT
	return Vector2(sdf_at(x + h, z) - sdf_at(x - h, z), sdf_at(x, z + h) - sdf_at(x, z - h))

## p moved (x/z only) onto the nearest point at least `margin` m inside the original's playable area.
func clamp_point(p: Vector3, margin := 0.0) -> Vector3:
	if not has_area():
		return Vector3(clampf(p.x, bounds.position.x + margin, bounds.end.x - margin), p.y,
			clampf(p.z, bounds.position.y + margin, bounds.end.y - margin))
	var q := p
	for k in 12:
		var s := sdf_at(q.x, q.z)
		if s >= margin: return q
		var g := _grad(q.x, q.z)
		if g.length() < 1e-6: break
		var step := (margin - s) + 0.004
		q += Vector3(g.x, 0, g.y).normalized() * step
	if sdf_at(q.x, q.z) >= margin - 0.01: return q
	var sp := spawn_points()   # a flat spot of the SDF far outside: walk back towards the start points
	var c: Vector3 = (sp[0] + sp[1]) * 0.5
	for k in 64:
		q = q.lerp(Vector3(c.x, q.y, c.z), 0.08)
		if sdf_at(q.x, q.z) >= margin: return q
	return Vector3(c.x, p.y, c.z)

## The floor heights (m) the original settles a fighter's centre on at (x, z), lowest first: the 25 cm floor raster
## (every lattice point probed), else the coarser 50 cm cells.
func floor_levels(x: float, z: float) -> Array:
	var out: Array = []
	if _fw > 0:
		var j := roundi((x / UNIT - _fx0) / _fc); var i := roundi((z / UNIT - _fz0) / _fc)
		if i >= 0 and j >= 0 and i < _fh and j < _fw:
			for k in _fn:
				var v := _fl.decode_s16(((i * _fw + j) * _fn + k) * 2)
				if v != -32768: out.append(float(v) * UNIT)
		return out
	var key := "%d,%d" % [floori((z / UNIT - _lz0) / _lc), floori((x / UNIT - _lx0) / _lc)]
	for y in _lev.get(key, []): out.append(float(y) * UNIT)
	return out

## The game's ground under (x, z) for feet at from_y: the highest floor of the original at most `step` above the feet
## (default: the step-up limit; 0 = only floors at or below), -INF when there is none (a wall at that height, or
## nothing); without from_y the highest floor there. Stage collision ray as the fallback where nothing was measured.
func floor_y_at(x: float, z: float, from_y := INF, step := -1.0) -> float:
	var st := step_up if step < 0.0 else step
	var ls := floor_levels(x, z)
	var best := -INF
	for y in ls:
		if y <= from_y + st and y > best: best = y
	if best > -INF or not ls.is_empty(): return best
	if not has_area(): return ground_y(Vector3(x, (from_y if from_y < INF else 1.0), z))
	return -INF

## A wall of the original at (x, z) for feet at y: outside the playable area, or every floor there is more than the
## step-up limit above the feet. For any movement code: test the next position, slide / stop when true.
func wall_at(x: float, z: float, y: float, char_id := "falcon") -> bool:
	if sdf_at(x, z) < fighter_margin(char_id): return true
	return floor_y_at(x, z, y) == -INF

## A floor of the original here, but every one more than the step-up over the feet: the side of a block / raised floor
## (outside the area is the edge clamp's business, not this)
func wall_block(p: Vector3) -> bool:
	if not has_area() or floor_levels(p.x, p.z).is_empty(): return false
	return floor_y_at(p.x, p.z, p.y) == -INF

## Remaster-only unstick for the CPU (cpu_game.gd DETOUR_AFTER): a runner the disc's own AI has left pinned against a
## wall (it steers straight at its goal: Ryoma 7 s in the pocket behind the slanted wall at (7, 8) on Final Valgas's
## stage, w9) gets a waypoint round it. Breadth-first over the measured area (DETOUR_CELL grid, inside by the fighter's
## margin + 15 cm, a step at most step_up up or any drop down), from the feet to the cell nearest the goal; the waypoint
## is the farthest path cell the fighter can run to in a straight line. null: no way round, or nothing in the way.
const DETOUR_CELL := 0.25
const DETOUR_MAX := 6000   # cells searched (a 19 x 19 m window at 25 cm)
func ai_detour(f: Fighter, goal: Vector3) -> Variant:
	if not has_area(): return null
	var mg := fighter_margin(f.char_id) + 0.15
	var p := f.global_position
	if _line_clear(p, goal, mg): return null
	var c := DETOUR_CELL
	var k0 := Vector2i(roundi(p.x / c), roundi(p.z / c))
	var kg := Vector2i(roundi(goal.x / c), roundi(goal.z / c))
	var prev := {k0: k0}
	var lvl := {k0: p.y}
	var q: Array[Vector2i] = [k0]
	var qi := 0
	var best := k0; var bd := (k0 - kg).length_squared()
	var lo := minf(mg, sdf_at(p.x, p.z) - 0.02)   # pinned at an edge the feet are inside the margin: the first metre may be too
	while qi < q.size() and qi < DETOUR_MAX:
		var k := q[qi]; qi += 1
		var d2 := (k - kg).length_squared()
		if d2 < bd: bd = d2; best = k
		if d2 <= 4: break
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var n: Vector2i = k + o
			if prev.has(n): continue
			var x := n.x * c; var z := n.y * c
			if sdf_at(x, z) < (mg if (n - k0).length_squared() > 16 else lo): continue
			var y := floor_y_at(x, z, float(lvl[k]))
			if y == -INF: continue
			prev[n] = k; lvl[n] = y
			q.append(n)
	if best == k0: return null
	var path: Array[Vector2i] = []
	var k := best
	while k != k0: path.push_front(k); k = prev[k]
	var way := Vector3(path[0].x * c, p.y, path[0].y * c)
	for n in path:   # the farthest cell along the path still in a straight line from the feet
		var w := Vector3(n.x * c, float(lvl[n]), n.y * c)
		if _line_clear(p, w, mg): way = w
		else: break
	return way

func _line_clear(a: Vector3, b: Vector3, mg: float) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := maxi(1, ceili(d.length() / 0.1))
	var y := a.y
	var lo := minf(mg, sdf_at(a.x, a.z) - 0.02)   # a fighter pressed to the wall starts inside the margin: not deeper
	for i in range(1, n + 1):
		var t := float(i) / n
		var x := a.x + d.x * t; var z := a.z + d.y * t
		var sd := sdf_at(x, z)
		if sd < lo: return false
		if sd >= mg: lo = mg
		var fy := floor_y_at(x, z, y)
		if fy == -INF: return false
		y = fy
	return true

## The original's push-out: (x, z) back inside the playable area for this fighter (its radius against Falcon's).
func push_out(p: Vector3, char_id := "falcon") -> Vector3:
	return clamp_point(p, fighter_margin(char_id))

## ---- core_ground: the original's ground + walls for a fighter that moves itself (the fidelity core) ----
## Measured in Flycast (docs/fx-oom.md "Step-up", tools/area_probe.py samples; game/assets/fidelity/ground_samples.json
## holds the cases tests/ground_check.gd replays):
const LIFT := 0.10           # feet up to 10 cm under a floor are lifted onto it (placed 5 / 10 cm into Londo's terrace)
const LEDGE_MIN := 0.15      # rises / drops up to 15 cm between 25 cm floor cells are followed (no stage has a slope: the
                             # only 1-15 cm differences in the rasters are seams on Dawnvolta and Rouge's stage)
const LEDGE_REACH := 0.20    # a run is held with Falcon's centre 18-22 cm short of the floor raster's step (7 run tests)
const LEDGE_HOLD_F := 4      # ... for 4 frames, then the feet are on the upper floor and the run goes on (50-65 cm)
const HOP_HOLD_F := 5        # dojo 50 -> 150 cm: held 5 frames in the run, then state 17 for HOP_F frames, then placed
const HOP_F := 6             # HOP_IN further on, on the upper floor, running
const HOP_IN := 0.50
const HOP := {"stg20": [[50, 150]]}   # (lower, upper) cm of the ledges the original hops (only these were measured to)

func _floor_near(x: float, z: float, top: float) -> float:
	var g := floor_y_at(x, z, top, 0.0)
	if g > -INF or not floor_levels(x, z).is_empty(): return g
	for o in [Vector2(0.25, 0), Vector2(-0.25, 0), Vector2(0, 0.25), Vector2(0, -0.25)]:   # a raster hole at an edge
		var h := floor_y_at(x + o.x, z + o.y, top, 0.0)
		if h > g: g = h
	return g

## The floor a body rests on: under its centre, or (moving) under the front of its body: just after a step-up the
## original's centre is still up to 17 cm short of the raster's step (run tests) while the feet are on the upper floor.
func _support(c: Vector3, reach: Vector3, top: float) -> float:
	var g := _floor_near(c.x, c.z, top)
	if reach != Vector3.ZERO: g = maxf(g, _floor_near(c.x + reach.x, c.z + reach.z, top))
	return g

func _level_near(x: float, z: float, y: float, tol: float) -> bool:
	for v in floor_levels(x, z):
		if absf(v - y) <= tol: return true
	return false

func _hop_ok(lo: float, hi: float) -> bool:
	for pr in HOP.get(stage, []):
		if absf(lo - float(pr[0]) * UNIT) < 0.05 and absf(hi - float(pr[1]) * UNIT) < 0.05: return true
	return false

## The original's ground and walls for feet that moved prev -> feet this frame (metres, feet = the game's +0x020).
## Call it every frame after the core's own move (instead of trusting the remaster's mesh: Londo's fountain base is
## 55.0 cm in the original, 62.8 in the disc mesh) and take back `pos`. Returns:
##   pos       Vector3  feet corrected: pushed back inside the original's area (its wall push, this fighter's radius),
##                      held at a ledge (x/z = prev), snapped onto the floor when grounded
##   floor     float    the original's floor under pos for these feet (the highest level at most LIFT over the feet
##                      this frame); -INF = none (outside every floor: never after the push)
##   grounded  bool     the feet are on `floor` (pos.y == floor): land / stay grounded; false = in the air (ran off an
##                      edge: the original keeps the run state and falls at 2 cm/f^2; from idle it is state 14)
##   wall      bool     pushed by the area's edge or stopped by a ledge; normal = the push's x/z direction (unit, into
##                      the area): drop the velocity component against it
##   ledge     float    rise (m) of the floor in front of a grounded fighter moving sideways (0 = none) and ledge_kind:
##                      "step" (<= step_up 65 cm): hold LEDGE_HOLD_F frames, then call again with climb = true (the
##                      feet go up onto it and the move continues); "hop" (HOP pairs): hold HOP_HOLD_F frames, play
##                      state 17 for HOP_F frames, then climb = true (placed HOP_IN further on, on the upper floor);
##                      "wall": the run stops there (91 cm Dawnvolta, 100 cm ship, 120 cm Ayame's)
## Airborne feet that move into a block higher than LIFT over them are held at prev x/z (wall).
## The original never stops a fighter at a DROP (OBJ.md 5: floor contact is re-tested every frame; 390 / 390 logged
## run-offs kept running as they fell): the probes mark a raised floor's face band "outside" (a fighter placed there is
## moved), so the area alone held runners on Londo's 240 cm floor edge and pulled knocked-back fighters back over it
## (fx-cpu3, test_all ff61291). A cell at most DROP_BAND outside the area, over a floor at least LEDGE_MIN below the
## feet (here or just ahead) and with no floor at the feet's height or a wall above, is the drop: no push-back. The
## outer void (no floor) and walls between floors at one height stay walls.
const DROP_BAND := 0.8
const BAND_LOOK := 0.25   # m: how far past the reach core_ground looks across a floorless face band for a step
func _drop_edge(p: Vector3, prev: Vector3, dir: Vector3, m: float, runner := true) -> bool:
	if sdf_at(p.x, p.z) < m - DROP_BAND: return false
	var lower := false
	for q in [p, p + dir * 0.3]:
		for y in floor_levels(q.x, q.z):
			# a floor at this height AHEAD: a real wall (a fence). Under the feet it is the floor being left: the 25 cm
			# raster cell still holds it inside the step's 20 cm face band (Londo's 60 > 30 cm step at z 5.6: CPU runners
			# held there 600 frames, BUG-100). Runners / walkers only: an attack's travel doesn't fall (it stood in the band)
			if (q != p or not runner) and y >= prev.y - LEDGE_MIN and y <= prev.y + step_up + 0.005: return false
			if y > prev.y + step_up: return false                                       # a block / wall above
			if y < prev.y - LEDGE_MIN: lower = true
	return lower

## Airborne feet over a raised floor's face band with that floor's top just under them: the band is outside in the
## area (a fighter placed on the face is moved), but once the feet are over the top the air move onto it is free (OBJ.md
## 5; fx-cpu4 10-27: Gunrock's jump at Londo's 240 cm floor was held at z 6.29 from y 2.63 up, landed on the face's
## edge over a cell with only the plaza's floor and ran there 500+ frames). Here: a floor under the feet at p (the face's
## foot) and, just ahead, a higher floor at most 60 cm under the feet. A wall cell (no floor) never opens.
func _over_top(p: Vector3, dir: Vector3, fy: float) -> bool:
	if dir == Vector3.ZERO: return false
	var here := -INF
	for y in floor_levels(p.x, p.z):
		if y <= fy + 0.005 and y > here: here = y
	if here == -INF: return false
	for d in [0.15, 0.3]:
		var q: Vector3 = p + dir * d
		for y in floor_levels(q.x, q.z):
			if y <= fy + 0.005 and y >= fy - 0.6 and y > here + LEDGE_MIN: return true
	return false

const MAX_LIFT := 1.6   # m: the most the original lifts a fighter put inside a block onto its top (the dojo's 150 cm terrace)
## The move along a wall that blocked mv (BUG-100): mv turned toward the wall's tangent by the smallest of 15..75 deg
## that is free, at |mv| x cos(turn) (= the projection onto a straight wall); ZERO when nothing is free (a corner).
func _wall_slide(prev: Vector3, mv: Vector3, base: float, on0: bool, m: float) -> Vector3:
	var lim := base + (LEDGE_MIN if on0 else LIFT)
	for deg in [15, 30, 45, 60, 75]:
		for sg in [1.0, -1.0]:
			var th: float = deg_to_rad(float(deg)) * float(sg)
			var t := mv.normalized().rotated(Vector3.UP, th)
			var c := prev + t * (mv.length() * cos(th))
			if sdf_at(c.x, c.z) < m: continue
			var a := c + t * (LEDGE_REACH + 0.03)
			var la := floor_levels(a.x, a.z)
			var free := la.is_empty()   # as core_ground: blocked only when no floor there is at / under the limit
			for y in la:
				if y <= maxf(lim, prev.y + LIFT): free = true; break
			if free: return c - prev
	return Vector3.ZERO


func core_ground(feet: Vector3, prev: Vector3, char_id := "falcon", climb := false, runner := true) -> Dictionary:
	var r := {"pos": feet, "floor": -INF, "grounded": false, "wall": false, "normal": Vector3.ZERO, "ledge": 0.0, "ledge_kind": ""}
	if not has_area():   # no measured data for this stage: the stage collision under the feet
		var gy := ground_y(feet)
		r.floor = gy
		if feet.y <= gy + 0.02: r.pos = Vector3(feet.x, gy, feet.z); r.grounded = true
		return r
	var m := fighter_margin(char_id)
	var p := feet
	var mv := Vector3(feet.x - prev.x, 0, feet.z - prev.z)
	var dir := mv.normalized() if mv.length() > 1e-4 else Vector3.ZERO
	# +3 cm: past the raster's midpoint between the two 25 cm cells. Not the fighter's radius: the disc's big fighters step
	# up at the same spot as Falcon (o_stg_40 Gunrock, radius 60: centre in the step's cell on the step frame, 8.5 cm
	# across; the old + radius held him 53 cm short and the climb then put him 55-65 cm on in one frame: BUG-52)
	var reach := dir * (LEDGE_REACH + 0.03)
	var airborne := absf(feet.y - prev.y) > 0.0005   # moving up or down: the air area (falls off ledges, launches)
	_run = runner and not airborne   # a runner / walker crosses the stairs' face bands (BUG-107)
	if (air_sdf_at(p.x, p.z) if airborne else sdf_at(p.x, p.z)) < m and not _drop_edge(p, prev, dir, m, runner) \
			and not (airborne and _over_top(p, dir, feet.y)):   # the original's push-back: straight back inside, the next frame (logged)
		var q := air_clamp_point(p, m) if airborne else clamp_point(p, m)
		var n := Vector3(q.x - p.x, 0, q.z - p.z)
		if n.length() > 1e-5: r.normal = n.normalized()
		p.x = q.x; p.z = q.z; r.wall = true
	var g0 := _support(prev, reach, prev.y + LIFT)
	var on0 := g0 > -INF and absf(prev.y - g0) <= 0.02
	var base := g0 if on0 else prev.y
	if dir != Vector3.ZERO:
		var a := p + reach
		var la := floor_levels(a.x, a.z)
		# a step whose face band is wider than the reach (Londo's back stairs 90 > 120 > 150 cm: 40-50 cm with no floor
		# in the raster, a fighter can't be placed on a face): look on across it for the next floor, so a runner meets
		# the step there instead of being clamped at its foot forever (CPU runners after the 120 cm gem spot, w7 BUG-107)
		var ext := 0.0
		while on0 and la.is_empty() and ext < BAND_LOOK - 1e-4:
			ext += 0.05
			var a2: Vector3 = p + reach + dir * ext
			var l2 := floor_levels(a2.x, a2.z)
			if l2.is_empty(): continue
			for y in l2:   # only a step up from this floor counts (a wall / the same floor beyond: as before)
				if y > g0 + LEDGE_MIN and y <= g0 + step_up + 0.005: la = l2; a = a2
			break
		var lim := base + (LEDGE_MIN if on0 else LIFT)
		var same := la.is_empty(); var up := INF
		for y in la:
			if y <= maxf(lim, p.y + LIFT): same = true
			elif y < up: up = y
		if not same and up < INF:
			var kind := "wall"
			if on0:
				r.ledge = up - g0
				if up - g0 <= step_up + 0.005: kind = "step"
				elif _hop_ok(g0, up): kind = "hop"
			r.ledge_kind = kind if on0 else ""
			if climb and kind != "wall":
				# onto the upper floor: the centre crosses the step's face (where a fighter can't be placed, so it is
				# outside the area raster) onto the first spot with that floor
				p = Vector3(prev.x, up, prev.z) + dir * (HOP_IN if kind == "hop" else mv.length())
				# (a floor within 5 cm of the step's top, not that exact level: the next 25 cm cells of one top differ by a
				# cm or two, and an exact match ran the search on: BUG-52, runners put 55-80 cm on in the step's frame;
				# the original climbs at run speed, stg_70 f553 +65 cm up, 10 cm across)
				for k in 12:
					if _level_near(p.x, p.z, up, 0.05) and sdf_at(p.x, p.z) >= m: break
					p += dir * 0.05
				r.wall = false; r.normal = Vector3.ZERO
			else:
				p.x = prev.x; p.z = prev.z
				if kind == "wall":
					r.wall = true; r.normal = -dir
					# the disc slides a runner along a wall at the run speed x cos(angle to the wall) (its run logs: 4,770
					# frames at 45 deg off the facing at 6.7 of 9.5 cm/f); holding him dead made CPU runners stand in place
					# against a building for 300-600 frames (BUG-100). A held step / hop ledge stays held.
					var sl := _wall_slide(prev, mv, base, on0, m)
					if sl != Vector3.ZERO: p.x = prev.x + sl.x; p.z = prev.z + sl.z
	# a floorless cell only the stairs' face bands hold inside (sdf_stairs) is a step face to run across, so a floor lies
	# ahead along the run; the band's side past the steps has none (Kraken slid sideways off the top of Londo's back stairs
	# into (0.38, 0.9, 6.5): no floor, 26 frames out, w9)
	if _run and dir != Vector3.ZERO and not r.wall and floor_levels(p.x, p.z).is_empty():
		_run = false
		var plain := sdf_at(p.x, p.z)
		_run = true
		if plain < m:
			var ahead := false
			for k in range(1, 15):
				var q := p + dir * (0.05 * k)
				if not floor_levels(q.x, q.z).is_empty(): ahead = true; break
			if not ahead:
				p.x = prev.x; p.z = prev.z
				r.wall = true; r.normal = -dir
	var top := maxf(prev.y, p.y) + LIFT
	if on0: top = maxf(top, g0 + LEDGE_MIN)
	var g := _support(p, reach, top)
	if g == -INF:   # inside a block (only by a teleport / push / hop: moves are held at ledges): the original lifts a
		# fighter put inside a collision volume onto its top (Londo's fountain base from 40 cm under it, the dojo's
		# 150 cm terrace from 150 cm under; tools/area_probe.py records that top as the cell's floor)
		var above := INF
		for y in floor_levels(p.x, p.z):
			if y > top and y < above: above = y
		# a wall top far above (Ryoma's 7.3 m walls: fx-cov BUG-51; the disc stops a runner in the corner there): a fighter
		# moving on his own steps up at most step_up, one put / pushed inside a block is lifted at most MAX_LIFT
		var lim := (step_up + 0.005) if mv.length() > 1e-4 and absf(feet.y - prev.y) < 0.001 else MAX_LIFT
		if above < INF and above - prev.y > lim:
			p.x = prev.x; p.z = prev.z                       # the original never lifts that far: a wall, stay put
			r.wall = true; r.normal = -dir if dir != Vector3.ZERO else Vector3.ZERO
			g = _support(p, Vector3.ZERO, maxf(prev.y, p.y) + LIFT)
			if g == -INF and _in_solid(p):   # the spot held is inside the block too (an air kick's travel carried Ryoma
				# into a 2.2 m block's cell on Ayame's stage, then he sank through y 0 for good, w9 stg60 (-4.13, 0.81)):
				# out sideways to the nearest spot with a floor at the feet, as clamp_fighter's _solid_guard does
				var q := _out_of_solid(p, m, airborne, 60)
				if q != p:
					p.x = q.x; p.z = q.z
					g = _support(p, Vector3.ZERO, maxf(prev.y, p.y) + LIFT)
		elif above < INF: g = above; p.y = minf(p.y, above)
	r.floor = g
	var rising: bool = feet.y > prev.y + 0.001 and not (climb and r.ledge_kind != "" and r.ledge_kind != "wall")
	if g > -INF and not rising and (p.y <= g + 0.02 or (on0 and absf(g - g0) <= LEDGE_MIN)):
		p.y = g; r.grounded = true
	r.pos = p
	_run = false
	return r

## The level of the round's start points (the stage's main floor).
func spawn_floor_y() -> float:
	if area.has("spawn"): return float(area.spawn[0][1]) * UNIT
	return float(info.get("floor_y", 0.0)) * UNIT

func area_center() -> Vector2:
	if area.has("spawn"):
		var a: Array = area.spawn
		return Vector2(float(a[0][0]) + float(a[1][0]), float(a[0][2]) + float(a[1][2])) * 0.5 * UNIT
	return bounds.get_center()

## Feet on the stage's own floor: inside the original's playable area and a downward ray from the feet hits stage
## geometry (world, scenery or a measured floor patch; never the invisible walls).
func on_floor(pos: Vector3, tol := 0.05) -> bool:
	if not inside(pos.x, pos.z, -tol - maxf(0.0, -min_margin())): return false
	if not is_inside_tree() or _ray_down(pos): return true
	# at the area's edge the disc mesh's floor can stop a few cm short of the original's edge (a pole swing out over it)
	if sdf_at(pos.x, pos.z) < 0.35:
		var g := _grad(pos.x, pos.z)
		if g.length() > 1e-6:
			var n := Vector3(g.x, 0, g.y).normalized()
			for d in [0.15, 0.3]:
				if _ray_down(pos + n * d): return true
	return false

## Nothing to land on under pos: no floor of the original there and no stage mesh straight down (nor 15 / 30 cm inward
## at the area's edge, where the disc mesh can stop a few cm short: as on_floor)
func _void_under(pos: Vector3) -> bool:
	if not floor_levels(pos.x, pos.z).is_empty() or _ray_down(pos): return false
	var g := _grad(pos.x, pos.z)
	if g.length() > 1e-6:
		var n := Vector3(g.x, 0, g.y).normalized()
		for d in [0.15, 0.3]:
			if _ray_down(pos + n * d): return false
	return true

## Stage geometry (world, scenery, floor patches) under pos: the ray straight down, or one of four 6 cm to the side
## (a seam where two disc meshes meet is not a hole).
func _ray_down(pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for o in [Vector3.ZERO, Vector3(0.06, 0, 0), Vector3(-0.06, 0, 0), Vector3(0, 0, 0.06), Vector3(0, 0, -0.06)]:
		var q := PhysicsRayQueryParameters3D.create(pos + o + Vector3.UP * 0.3, pos + o + Vector3.DOWN * 40.0, 1)
		if not space.intersect_ray(q).is_empty(): return true
	return false

## Out of the map: feet not over the stage's own floor inside the original's area, or (grounded = standing on
## something) no floor of the original within NO_FLOOR_TOL of the feet there (a top the original never lets anyone on).
func out_of_map(pos: Vector3, tol := 0.05, grounded := false) -> bool:
	if not on_floor(pos, tol): return true
	return grounded and has_area() and not _orig_floor_near(pos)

## Standing on a top the original doesn't have: the nearest spot (rings of 10 cm up to 2.5 m, the way there clear at
## knee and chest height) inside the area whose ground (the remaster's collision straight down) is the original's floor.
func _off_top(p: Vector3, margin: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	for pass_ in 2:   # the second pass when every way off is blocked (a statue on the fountain's centre piece)
		for ring in range(1, 26):
			var q := _off_top_ring(space, p, margin, ring * 0.1, pass_ == 0)
			if q != p: return q
	return p

func _off_top_ring(space: PhysicsDirectSpaceState3D, p: Vector3, margin: float, rr: float, clear_way: bool) -> Vector3:
	if true:
		for k in 16:
			var a := TAU * k / 16.0
			var q := Vector3(p.x + cos(a) * rr, p.y, p.z + sin(a) * rr)
			if sdf_at(q.x, q.z) < margin: continue
			var blocked := false
			for h in ([0.4, 1.2] if clear_way else []):
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * h, q + Vector3.UP * h, 1)).is_empty(): blocked = true
			if blocked: continue
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 0.3, q + Vector3.DOWN * 40.0, 1))
			if hit.is_empty(): continue
			var g := Vector3(q.x, float(hit.position.y), q.z)
			if _orig_floor_near(g): return q
	return p

## The nearest spot (rings of 10 cm up to 2 m) inside the area with a floor of the original within NO_FLOOR_TOL
## of the feet: where the original pushes a fighter put inside a block; p when there is none.
func _out_of_block(p: Vector3, margin: float) -> Vector3:
	for ring in range(1, 21):
		var rr := ring * 0.1
		for k in 16:
			var a := TAU * k / 16.0
			var q := Vector3(p.x + cos(a) * rr, p.y, p.z + sin(a) * rr)
			if sdf_at(q.x, q.z) < margin: continue
			for y in floor_levels(q.x, q.z):
				if absf(y - p.y) <= NO_FLOOR_TOL: return Vector3(q.x, y + 0.01, q.z)
	return p

## The inside-a-block guard (clamp_fighter, and once more in tick after every fighter and the body pushes: a throw's
## release or a placement can end a frame inside a block, Londo's base suite FFA: Ayame at y 0 inside the 55 cm
## fountain base for a frame after a throw). -> the corrected feet.
func _solid_guard(f: Fighter, p: Vector3, m: float, air: bool) -> Vector3:
	if not (f.held_by or f.state in [Fighter.S.POLE, Fighter.S.GRAB]) and _in_solid(p):
		var above := INF
		for y in _levels_here(p.x, p.z): above = minf(above, y)
		var q := p
		if above - p.y <= SOLID_LIFT:   # just under the top: onto it (the original lifts a fighter put up to 40 cm
			p.y = above                 # under Londo's fountain base onto it, probe)
			if f.velocity.y < 0.0: f.velocity.y = 0.0
			q = p
		else:
			q = _out_of_solid(p, m, air, 60)
			if q == p:   # no floor at the feet anywhere near: under the stage (fell through a floor; BUG-60, Falcon on
				p.y = above   # Londo at y -3.42 under the -50 street): back onto the floor over the feet
				if f.velocity.y < 0.0: f.velocity.y = 0.0
				q = p
		if q != p:
			var push := Vector3(q.x - p.x, 0, q.z - p.z)
			var n := push.normalized()
			var vn := f.velocity.dot(n)
			if vn < 0.0: f.velocity -= n * vn
			if q.y > p.y and f.velocity.y < 0.0: f.velocity.y = 0.0
			p = q
	return p

## Feet inside a solid of the original: floors measured here and every one more than LIFT over the feet. -> p, or the
## nearest spot (rings of 5 cm up to 1.5 m) inside the area with a floor at most LIFT over the feet (on it or above it).
const SOLID_LIFT := 0.40
## The floor levels at (x, z), or at a raster hole (an edge cell the probe never stood on) its four 25 cm neighbours'.
func _levels_here(x: float, z: float) -> Array:
	var ls := floor_levels(x, z)
	if not ls.is_empty(): return ls
	for o in [Vector2(0.25, 0), Vector2(-0.25, 0), Vector2(0, 0.25), Vector2(0, -0.25)]:
		for y in floor_levels(x + o.x, z + o.y):
			if not ls.has(y): ls.append(y)
	return ls

func _in_solid(p: Vector3) -> bool:
	var ls := _levels_here(p.x, p.z)
	if ls.is_empty(): return false
	for y in ls:
		if y <= p.y + LIFT: return false
	return true

func _out_of_solid(p: Vector3, margin: float, air := false, rings := 30) -> Vector3:
	if not _in_solid(p): return p
	for ring in range(1, rings + 1):
		var rr := ring * 0.05
		for k in 16:
			var a := TAU * k / 16.0
			var q := Vector3(p.x + cos(a) * rr, p.y, p.z + sin(a) * rr)
			if (air_sdf_at(q.x, q.z) if air else sdf_at(q.x, q.z)) < margin: continue
			var best := -INF   # the highest floor there at most SOLID_LIFT over the feet: onto it (a body knocked under
			for y in floor_levels(q.x, q.z):   # the ship's deck edge goes up onto the deck beside it, not the mast top)
				if y <= p.y + SOLID_LIFT and y > best: best = y
			if best > -INF: return Vector3(q.x, maxf(p.y, best), q.z)
	return p

## Standing / lying on something (is_on_floor after its last move), not held up on purpose: a pole hang, a grab or
## throw, or the Power Change (its states don't move the body, so is_on_floor is the last move's).
static func _grounded(f: Fighter) -> bool:   # the fighter core's own ground state (a capsule resting on another
	# fighter's head reads is_on_floor, but the core's feet are in the air there: the original has no floor on a head)
	return f.grounded() and f.state not in [Fighter.S.POLE, Fighter.S.GRAB, Fighter.S.TRANSFORM]

## out_of_map for a fighter (the checks in cam_check / run_tests / brawl_tests): grounded where it really stands; during
## the instant replay the fighters are posed from recorded frames (checked live) and is_on_floor is stale.
## Off the ground, one frame out is how the original works too (its push-back puts a fighter back inside on the next
## frame, logged): an airborne fighter counts from his 2nd frame in a row out (a launch past a lamp post's footprint).
var _oom_run := {}
## Consecutive frames `who` (a flying object) has been out, counted once per physics frame
func air_run(who: Object, out: bool) -> int:
	var fr := Engine.get_physics_frames()
	var st: Array = _oom_run.get(who, [-1, 0])
	if int(st[0]) != fr:
		st = [fr, (int(st[1]) + 1) if out and int(st[0]) == fr - 1 else (1 if out else 0)]
		_oom_run[who] = st
	return int(st[1])
func fighter_out_of_map(f: Fighter, replaying := false) -> bool:
	# on a pole the original itself puts the fighter 10 cm from the axis (k2/211 / 212) and on it (k1/150): inside the
	# pole's footprint, which the area raster leaves out (docs/OBJ.md 1); the hop (k1/151) is checked as usual
	if f.state == Fighter.S.POLE and f.pole_sub <= 1: return false
	# the state-41 hang (fx-mv): the disc puts the feet under the kind-4 object itself (x, z onto it, 3 of 3 logged), which
	# the area raster leaves out like a pole's footprint; the hop off it is checked as usual
	if f.gst == 41 and f.mv_i == 0: return false
	# on a hoppable box's top (the disc's state 17 and standing on it): the box is the floor (fx-mv 6)
	if f.gst == 17: return false   # the hop onto / along a box (the disc's state 17, fx-mv 6): the box is the floor, its drop the disc's
	# (or just over it: a body frozen in a hit's hit-stop 14 cm over a stg10 crate, BUG-105 FFA w8)
	if f.has_method("on_hop_box") and f.on_hop_box(40.0): return false
	# a runner / walker stepping off onto a lower floor: the centre crosses the step's face band for a frame or two (the
	# disc's own drop, core_ground / clamp_fighter's drop rule, BUG-100)
	# (and any fighter there at a real floor's height: the jump's take-off frame right after, an attack begun at the edge)
	if f.grounded():
		var fd := Vector3(f.facing.x, 0, f.facing.z)
		var gp := f.global_position
		var at_floor := f.gst in [2, 31]
		var hv := Vector3(f.velocity.x, 0, f.velocity.z)
		# the floor under the feet, or the one just left: inside a step's face band the raster has none (Londo's 2.4 m
		# ledge: a runner 3 frames into the band starts an attack there, BUG-105 2v2 n1657)
		var behind := [gp, gp - fd.normalized() * 0.3] if fd.length() > 0.01 else [gp]   # (a take-off frame has v 0)
		if hv.length() > 0.01: behind.append(gp - hv.normalized() * 0.3)
		for q in behind:
			for y in floor_levels(q.x, q.z):
				if absf(y - gp.y) <= 0.02: at_floor = true
		for d in [fd, hv]:   # the way it faces or moves
			if at_floor and d.length() > 0.01 and _drop_edge(gp, gp, d.normalized(), fighter_margin(f.char_id)): return false
	var g := _grounded(f)
	_air = not f.grounded()   # off the ground: the air area (tools/area_logs.py)
	# a stair-face band (BUG-107: sdf_stairs / sdf_air_stairs) always has the steps under it: whoever is over one (a runner,
	# an attack or a jump begun there, a body knocked down on the stairs: Londo FFA, Ayame lying 8 frames at (-4.58, 0.9,
	# 6.38)) is on the map. (The clamp reads it for runners / walkers only.)
	_run = true
	var o := out_of_map(f.global_position, 0.05, g and not replaying and _rests_on_something(f))
	var air := _air
	_air = false; _run = false
	var fr := Engine.get_physics_frames()
	var st: Array = _oom_run.get(f, [-1, 0])
	if int(st[0]) != fr:
		st = [fr, (int(st[1]) + 1) if o and int(st[0]) == fr - 1 else (1 if o else 0)]
		_oom_run[f] = st
	return o and (not air or int(st[1]) >= 2)

## Stage geometry right under the feet now: is_on_floor is the last move's, and clamp_fighter may have
## moved the fighter since (off a head / a top), so the check looks again.
func _rests_on_something(f: Fighter) -> bool:
	if not is_inside_tree(): return true
	var p := f.global_position
	# stage only (layer 1): a fighter on another's head (2v2 / Battle Royale, BUG-99) is over the stage's floor, which
	# the plain area check covers; "a top the original lacks" is about stage tops
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.1, p + Vector3.DOWN * 0.15, 1, [f.get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _orig_floor_near(p: Vector3) -> bool:
	var any := false
	for o in [Vector2.ZERO, Vector2(0.25, 0), Vector2(-0.25, 0), Vector2(0, 0.25), Vector2(0, -0.25)]:
		for y in floor_levels(p.x + o.x, p.z + o.y):
			any = true
			if absf(y - p.y) <= NO_FLOOR_TOL: return true
	return not any

func min_margin() -> float:
	var m := 0.0
	for k in _radius.get("delta_cm", {}): m = minf(m, float(_radius.delta_cm[k]) * UNIT)
	return m

## Invisible walls (collision only, never drawn) on the edge contours, set out by the fighter capsule's radius so a
## capsule's centre stops exactly where the original stops Falcon's (smaller fighters: by their own radius), from below
## the lowest floor to well over the highest. Layer BOUNDS_LAYER: fighters only (clamp_fighter adds it to their mask),
## so the camera's rays and the ground rays never see them. Plus floor patches where the original has a floor and the
## disc mesh the remaster collides with has none (area "patches": 50 cm cells, top at the measured level).
func _build_bounds() -> void:
	bounds_body = StaticBody3D.new(); bounds_body.name = "AreaBounds"
	bounds_body.collision_layer = BOUNDS_LAYER; bounds_body.collision_mask = 0
	add_child(bounds_body)
	var off := Fighter.CAPSULE_R + maxf(0.0, -min_margin())
	var th := 0.5
	var y0 := area_floor_min - 6.0; var y1 := area_floor_max + 16.0
	for c in area.get("walls", area.get("contours", [])):
		var pts: Array = c
		for k in pts.size() - 1:
			var a := Vector2(float(pts[k][0]), float(pts[k][1])) * UNIT
			var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][1])) * UNIT
			var d := b - a; var L := d.length()
			if L < 0.01: continue
			var t := d / L; var n := Vector2(-t.y, t.x)
			var mid := (a + b) * 0.5
			if sdf_at(mid.x + n.x * 0.12, mid.y + n.y * 0.12) > sdf_at(mid.x - n.x * 0.12, mid.y - n.y * 0.12): n = -n   # n: out of the area
			var ctr := mid + n * (off + th * 0.5)
			# never a wall inside the original's area: boxes offset across the contour's small notches (raster steps,
			# thin posts) land back inside it, where they stopped fighters early and wedged them between invisible
			# walls in mid-air for good (docs/HUNT.md H-2); the SDF clamp (clamp_fighter) still holds the edge there
			var phantom := false
			for ua in [-0.5, 0.0, 0.5]:
				for ub in [-0.5, 0.0, 0.5]:
					var q: Vector2 = ctr + t * (L + 0.12) * ua + n * th * ub
					if sdf_at(q.x, q.y) > 0.05: phantom = true
			if phantom: continue
			var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
			bx.size = Vector3(L + 0.12, y1 - y0, th)
			cs.shape = bx
			cs.position = Vector3(ctr.x, (y0 + y1) * 0.5, ctr.y)
			cs.rotation.y = -atan2(t.y, t.x)
			bounds_body.add_child(cs)
	for pt in area.get("patches", []):   # [x cm, z cm, top y cm, size cm]
		var cs := CollisionShape3D.new(); var bx := BoxShape3D.new()
		var sz := float(pt[3]) * UNIT
		bx.size = Vector3(sz, 0.4, sz); cs.shape = bx
		cs.position = Vector3(float(pt[0]) * UNIT, float(pt[2]) * UNIT - 0.2, float(pt[1]) * UNIT)
		world_body.add_child(cs)
