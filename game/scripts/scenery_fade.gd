class_name SceneryFade
extends RefCounted
## Stage objects that get between the lens and a fighter (lamp posts, wall signs, menu boards, tables, the fountain
## column) or sit right in front of the lens fade to a ghost and come back once the view is clear: what modern 3D
## fighters do. World walls never fade (the fight camera swings round them instead, scripts/fight_cam.gd).
## Works in both looks: GeometryInstance3D.transparency (stage_pbr writes no ALPHA, so it takes the instance value).

const GHOST := 0.82        # transparency of a faded object (0 = solid)
const FADE_IN := 9.0       # per second toward faded
const FADE_OUT := 3.0      # per second back to solid
const NEAR_M := 1.7        # anything this close to the lens fades
const BIG := 0.10          # ... or in front of the fighters and covering this much of the screen

var items: Array = []      # [node, meshes, box (static scenery) or null (moves), fade 0..1, part]

func setup(arena: Arena) -> void:
	items.clear()
	for n in arena.scenery:
		var nd := n as Node3D
		var ms := Mats._meshes(nd)
		if ms.is_empty(): continue
		var bx := CamCheck.mesh_box(nd)
		if bx.get_longest_axis_size() < 0.35: continue   # pigeons, cups: never in the way
		items.append([nd, ms, bx, 0.0, int(nd.get_meta("part", -1))])
	for p in arena.props:
		var ms2 := Mats._meshes(p as Node3D)
		if not ms2.is_empty(): items.append([p, ms2, null, 0.0, int((p as Prop).part)])

## points = what must stay visible (fighter head / chest / hips / knees / feet, world space)
func update(cam: Camera3D, points: Array, near_fighter: float, dt: float) -> void:
	if items.is_empty(): return
	var e := cam.global_position
	var fwd := -cam.global_basis.z
	var vs := cam.get_viewport().get_visible_rect().size if cam.is_inside_tree() else Vector2(1920, 1080)
	for it in items:
		var nd: Node3D = it[0]
		if not is_instance_valid(nd): continue
		var bx: AABB = it[2] if it[2] != null else CamCheck.mesh_box(nd)
		var want := 0.0
		var gone := false   # right at the lens: all the way out (a ghost that close is a blurred pane over the shot)
		if nd.is_visible_in_tree():
			var g := bx.grow(0.06)
			for p in points:
				if g.intersects_segment(e, p): want = 1.0; break
			var c := _closest(bx, e)
			var dc := c.distance_to(e)
			if dc < NEAR_M and (c - e).dot(fwd) > -0.2: want = 1.0; gone = dc < 1.0
			elif want == 0.0 and dc < near_fighter - 1.0 and _screen_cover(cam, bx, vs) > BIG: want = 1.0
		if gone: want = 1.25
		var f: float = it[3]
		f = move_toward(f, want, dt * (FADE_IN if want > f else FADE_OUT))
		if f != it[3]:
			it[3] = f
			var tr := smoothstep(0.0, 1.0, f) * GHOST + maxf(0.0, f - 1.0) * 0.72   # 1.25 -> fully out
			for m in it[1]: (m as GeometryInstance3D).transparency = minf(tr, 1.0)

func faded() -> Array:   # [part, fade] of every object not fully solid (tests, audit)
	var out := []
	for it in items: if float(it[3]) > 0.01: out.append([it[4], snappedf(float(it[3]), 0.01)])
	return out

static func _closest(bx: AABB, p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, bx.position.x, bx.end.x), clampf(p.y, bx.position.y, bx.end.y), clampf(p.z, bx.position.z, bx.end.z))

## Fraction of the screen the box covers (its projected corners' rectangle, clipped to the screen).
static func _screen_cover(cam: Camera3D, bx: AABB, vs: Vector2) -> float:
	var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
	var n := 0
	for i in 8:
		var p := bx.get_endpoint(i)
		if cam.is_position_behind(p): continue
		var q := cam.unproject_position(p) / vs
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y)); hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		n += 1
	if n == 0: return 0.0
	lo = lo.clamp(Vector2.ZERO, Vector2.ONE); hi = hi.clamp(Vector2.ZERO, Vector2.ONE)
	return maxf(0.0, hi.x - lo.x) * maxf(0.0, hi.y - lo.y)
