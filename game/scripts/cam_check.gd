class_name CamCheck
## What a player sees each frame, measured: is every fighter whole on screen (head / feet / sides cut, under the HUD),
## is anything between the camera and a fighter (stage walls, props, signs), how much of the frame is foreground clutter
## right in front of the lens, and do the two bodies sink into each other. Used by tests/match_movie.gd (PS_AUDIT=file:
## one JSON line per frame for tools/cam_audit.py) and by tests/cam_tests.gd (limits per match).

const HUD_TOP := 0.115   # the HUD's name / health / timer band, fraction of the screen height (hud.gd)
const GRID := Vector2i(16, 9)

## The game's body spheres for f (entries 1-11 on the posed skeleton) or a plain capsule when the model has none.
static func body(f: Fighter) -> Array:
	var s := f.body_spheres()
	if s.is_empty(): s = [[f.global_position + Vector3.UP * 0.9, 0.55]]
	return s

## Screen-space box of a fighter (fractions of the viewport): [min x, min y (top of head), max x, max y (feet)],
## or [] when the fighter is entirely behind the camera.
static func screen_box(cam: Camera3D, f: Fighter) -> Array:
	var vs := cam.get_viewport().get_visible_rect().size
	var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
	var any := false
	for s in body(f):
		var c: Vector3 = s[0]; var r: float = s[1]
		for d in [Vector3.UP, Vector3.DOWN, cam.global_basis.x, -cam.global_basis.x]:
			var p: Vector3 = c + d * r
			if cam.is_position_behind(p): continue
			var q := cam.unproject_position(p) / vs
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y)); hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			any = true
	return [lo.x, lo.y, hi.x, hi.y] if any else []

## The visible mesh, not just the game's spheres (a Power Change form's head and horns reach past them): per skin bone,
## the box of the vertices it carries (bone space, built once per mesh), its 8 corners posed in world space now.
static var _bone_boxes := {}   # mesh RID -> [[bind index, AABB in bone space], ...]

static func skin_points(f: Fighter) -> Array:
	var out := []
	if not (f.model is PSModel): return out
	var m := f.model as PSModel
	var inst: Node3D = m.forms.get(m.form)
	var sk := m.skeleton()
	if inst == null or sk == null: return out
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.skin == null: continue
		var bb := _boxes_of(mi)
		for it in bb:
			var bi: int = it[0]
			var bone := mi.skin.get_bind_bone(bi)
			if bone < 0: bone = sk.find_bone(mi.skin.get_bind_name(bi))
			if bone < 0: continue
			var xf := mi.global_transform * sk.get_bone_global_pose(bone)
			var box: AABB = it[1]
			for k in 8: out.append(xf * box.get_endpoint(k))
	return out

static func _boxes_of(mi: MeshInstance3D) -> Array:
	var key := mi.mesh.get_rid()
	if _bone_boxes.has(key): return _bone_boxes[key]
	var per := {}
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bs = arr[Mesh.ARRAY_BONES]; var ws = arr[Mesh.ARRAY_WEIGHTS]
		if bs == null or ws == null or vs.is_empty(): continue
		var k := int(bs.size() / vs.size())
		for vi in vs.size():
			var best := 0; var bw := -1.0
			for j in k:
				if float(ws[vi * k + j]) > bw: bw = float(ws[vi * k + j]); best = int(bs[vi * k + j])
			var p: Vector3 = mi.skin.get_bind_pose(best) * vs[vi]
			if per.has(best): per[best] = (per[best] as AABB).expand(p)
			else: per[best] = AABB(p, Vector3.ZERO)
	var out := []
	for b in per: out.append([b, per[b]])
	_bone_boxes[key] = out
	return out

## Screen box (fractions of the viewport) of world points: [min x, min y, max x, max y], [] if all behind the camera.
static func points_box(cam: Camera3D, pts: Array) -> Array:
	var vs := cam.get_viewport().get_visible_rect().size
	var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
	var any := false
	for p in pts:
		if cam.is_position_behind(p): continue
		var q := cam.unproject_position(p) / vs
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y)); hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		any = true
	return [lo.x, lo.y, hi.x, hi.y] if any else []

## Fraction of a fighter's body spheres hidden from the camera by the stage's own geometry (walls) or by a solid
## (not faded) stage object (its mesh box).
static func occluded(cam: Camera3D, f: Fighter, scenery: Array, ex: Array = []) -> float:
	var sp := body(f)
	var space := cam.get_world_3d().direct_space_state
	var e := cam.global_position
	var n := 0
	for s in sp:
		var c: Vector3 = s[0]; var r: float = s[1]
		var to := c - (c - e).normalized() * r
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(e, to, 1, ex))
		if hit or _box_hit(e, to, scenery) >= 0.0: n += 1
	return float(n) / sp.size()

## Fraction of a 16x9 grid of view rays that hit something closer than min(near_m, nearest fighter - 1 m): the stuff
## right in front of the lens (lamp posts, signs, wall corners).
static func foreground(cam: Camera3D, fighters: Array, scenery: Array, near_m := 3.0, ex: Array = []) -> float:
	var e := cam.global_position
	var dn := 1e9
	for f in fighters: dn = minf(dn, (f as Fighter).global_position.distance_to(e))
	var lim := minf(near_m, dn - 1.0)
	if lim <= 0.2: return 0.0
	var vs := cam.get_viewport().get_visible_rect().size
	var space := cam.get_world_3d().direct_space_state
	var n := 0
	for gy in GRID.y:
		for gx in GRID.x:
			var sp := Vector2((gx + 0.5) / GRID.x, (gy + 0.5) / GRID.y) * vs
			var dir := cam.project_ray_normal(sp)
			var to := e + dir * lim
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(e, to, 1, ex)) or _box_hit(e, to, scenery) >= 0.0: n += 1
	return float(n) / (GRID.x * GRID.y)

## Deepest overlap of two fighters' bodies in metres (0 = not touching).
static func overlap(a: Fighter, b: Fighter) -> float:
	var worst := 0.0
	for x in body(a):
		for y in body(b):
			worst = maxf(worst, float(x[1]) + float(y[1]) - (x[0] as Vector3).distance_to(y[0]))
	return worst

## Segment e->to against scenery boxes ([AABB, node] pairs, world space): index of the first box hit or -1.
static func _box_hit(e: Vector3, to: Vector3, scenery: Array) -> float:
	for i in scenery.size():
		var it: Array = scenery[i]
		var n: Node3D = it[1]
		if not n.is_visible_in_tree(): continue
		var bx: AABB = it[0]
		if bx.intersects_segment(e, to): return float(i)
	return -1.0

## Solid stage objects as [world AABB, node]: every placed object and throwable (pigeon-sized ones skipped), minus the
## ones the fight camera has faded out (scripts/scenery_fade.gd). Throwables' boxes are refreshed (they move).
static func scenery_boxes(fight: Fight) -> Array:
	var out := []
	if fight.fcam:
		for it in fight.fcam.fade.items:
			if float(it[3]) >= 0.5 or not is_instance_valid(it[0]): continue
			out.append([it[2] if it[2] != null else mesh_box(it[0]), it[0]])
		return out
	for n in fight.arena.scenery + fight.arena.props:
		var nd := n as Node3D
		if nd == null or not is_instance_valid(nd): continue
		var bx := mesh_box(nd)
		if bx.get_longest_axis_size() >= 0.35: out.append([bx, nd])
	return out

static func mesh_box(n: Node3D) -> AABB:
	var bx := AABB(); var first := true
	for mi in Mats._meshes(n):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		var b := m.global_transform * m.get_aabb()
		if first: bx = b; first = false
		else: bx = bx.merge(b)
	return bx

## Gems and throwables (resting or in flight) not over the stage's own floor inside the original's playable area. The
## area is where a fighter's centre may be, a fighter radius in from the walls: an object may sit up to OBJ_TOL past it
## (the RAM layout puts Londo's plants and chairs 13-37 cm past it, against the walls).
const OBJ_TOL := 0.45
static func objects_out(ar: Arena) -> int:
	var n := 0
	for g in ar.gems:
		if is_instance_valid(g) and ar.out_of_map((g as Node3D).global_position, OBJ_TOL):
			n += 1
			if _OOMO_DBG and not _oomo_seen.has(g):
				_oomo_seen[g] = true
				print("OOMO f%d gem %s pos %s" % [Engine.get_physics_frames(), g.name, str((g as Node3D).global_position.snapped(Vector3.ONE * 0.01))])
	for p in ar.props:
		var pr := p as Prop
		if pr == null or pr.state not in [Prop.REST, Prop.FLYING]: continue
		if pr.state == Prop.REST and pr.global_position.is_equal_approx(pr.home): continue   # where the original puts it
		ar._air = pr.state == Prop.FLYING   # a thrown / flung object is in the air: the air area (falls off ledges)
		var out := ar.out_of_map(pr.global_position + Vector3.UP * 0.1, OBJ_TOL)
		ar._air = false
		if pr.state == Prop.FLYING: out = ar.air_run(pr, out) >= 2   # in the air: from its 2nd frame out (as fighters)
		if out:
			n += 1
			if _OOMO_DBG and not _oomo_seen.has(pr):
				_oomo_seen[pr] = true
				print("OOMO f%d prop %s part %s state %d pos %s home %s" % [Engine.get_physics_frames(), pr.name, str(pr.get("part")), pr.state, str(pr.global_position.snapped(Vector3.ONE * 0.01)), str(pr.home.snapped(Vector3.ONE * 0.01))])
	return n
static var _OOMO_DBG := OS.has_environment("PS_OOMO_DEBUG")
static var _oomo_seen := {}

## One frame's numbers (PS_AUDIT lines; tools/cam_audit.py reads them).
static func frame(fight: Fight, n: int) -> Dictionary:
	var cam := fight.cam
	var sc := scenery_boxes(fight)
	var ex := [fight.arena.scenery_body.get_rid()] if fight.arena.scenery_body else []
	var out := {"f": n, "ph": fight.phase, "cine": fight.cinema.kind if fight.cinema else "",
		"cam": [snappedf(cam.global_position.x, 0.01), snappedf(cam.global_position.y, 0.01), snappedf(cam.global_position.z, 0.01)],
		"fov": snappedf(cam.fov, 0.1), "fg": snappedf(foreground(cam, fight.fighters, sc, 3.0, ex), 0.001), "p": []}
	var ar: Arena = fight.arena
	for f in fight.fighters:
		var fi := f as Fighter
		var clip := (fi.model as PSModel).current_clip() if fi.model is PSModel else ""
		out.p.append({"st": fi.state, "clip": clip, "hp": fi.hp, "oom": 1 if ar.fighter_out_of_map(fi, fight.cinema != null and fight.cinema.replaying()) else 0,
			"sd": snappedf(ar.sdf_at(fi.global_position.x, fi.global_position.z), 0.01),
			"pos": [snappedf(fi.global_position.x, 0.01), snappedf(fi.global_position.y, 0.01), snappedf(fi.global_position.z, 0.01)],
			"box": screen_box(cam, fi).map(func(v): return snappedf(v, 0.001)), "occ": snappedf(occluded(cam, fi, sc, ex), 0.01)})
	out["oomo"] = objects_out(ar)
	if fight.fighters.size() >= 2: out["ov"] = snappedf(overlap(fight.fighters[0], fight.fighters[1]), 0.001)
	if fight.fcam and fight.fcam.indoor:   # roofed stages: how much of the frame shows the empty outside
		out["void"] = snappedf(fight.fcam._void(cam.global_position, cam.global_position - cam.global_basis.z * 5.0,
			cam.get_world_3d().direct_space_state), 0.01)
	if fight.cinema and fight.cinema.kind != "":   # who the cinematic is about (the others may leave the frame)
		var cs := []
		for x in [fight.cinema.hero] + ([] if fight.cinema.kind in ["power", "win"] else [fight.cinema.foe]):
			if x: cs.append(fight.fighters.find(x))
		out["cs"] = cs
	if fight.fcam:
		out["fade"] = fight.fcam.fade.faded()
		out["cw"] = [snappedf(fight.fcam.yaw_off, 0.01), snappedf(fight.fcam.pull, 0.01), snappedf(fight.fcam.lift, 0.01), snappedf(fight.fcam.aim, 0.01), snappedf(fight.fcam.extra, 0.01)]
	return out
