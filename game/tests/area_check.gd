extends SceneTree
## The remaster's stage collision against the original's measured playable area (assets/fidelity/STG_area.json):
## at every spot the original let the probe fighter (Falcon's centre) stand, a downward ray from 0.5 m over its feet
## (world + scenery collision) and a capsule of 26 cm (under Falcon's own radius) set on it.
##   Godot --headless --path game -s res://tests/area_check.gd -- STAGE OUT.json
## OUT: counts + the cells where the remaster has no floor at the original's level ("missing", throwables' footprints
## excluded: the original stands you on a table the remaster throws away) and where its collision blocks a capsule the
## original lets stand ("blocked").
var ar: Arena
var n := 0
var out_path := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = str(a[1]) if a.size() > 1 else "/tmp/area_check.json"
	ar = Arena.new(); ar.stage = str(a[0])

func _process(_d: float) -> bool:
	n += 1
	if n == 1: root.add_child(ar); ar.build(1)   # in the tree first (global transforms)
	if n < 4: return false   # collision shapes in the space
	var space := ar.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new(); cap.radius = 0.26; cap.height = Fighter.CAPSULE_H - 0.1
	var sq := PhysicsShapeQueryParameters3D.new(); sq.shape = cap; sq.collision_mask = 1
	var foot := []
	for p in ar.props:
		var bx := CamCheck.mesh_box(p as Node3D)
		foot.append(Rect2(bx.position.x - 0.3, bx.position.z - 0.3, bx.size.x + 0.6, bx.size.z + 0.6))
	var res := {"stage": ar.stage, "has_area": ar.has_area(), "cells": 0, "levels": 0, "ok": 0, "missing": [], "higher": [],
		"blocked": [], "prop_skip": 0, "surf": {}}
	# every spot the original let the probe fighter stand on (area "stand": x, z, feet y cm)
	for pt in ar.area.get("stand", []):
		var x := float(pt[0]) * Arena.UNIT; var z := float(pt[1]) * Arena.UNIT; var y := float(pt[2]) * Arena.UNIT
		res.levels += 1
		var skip := false
		for r in foot: if (r as Rect2).has_point(Vector2(x, z)): skip = true
		if skip: res.prop_skip += 1; continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, y + 0.5, z), Vector3(x, y - 0.6, z), 1))
		var hy: float = float(hit.position.y) if hit else -1e9
		if hit and (hit.collider == ar.world_body or hit.collider == ar.scenery_body):   # which disc surface / placed part
			var c := (hit.collider as Node).get_child(int(hit.shape)) as Node   # the remaster stands it on: agrees / too high / too low
			var mk := (String(c.get_meta("mesh", "?")) if hit.collider == ar.world_body else "part%s" % str(c.get_meta("part", "?"))) if c else "?"
			if not res.surf.has(mk): res.surf[mk] = [0, 0, 0]
			res.surf[mk][0 if absf(hy - y) <= 0.12 else (1 if hy > y else 2)] += 1
		if hit and absf(hy - y) <= 0.12: res.ok += 1
		elif hit and hy > y + 0.12: res.higher.append([pt[0], pt[1], pt[2], snappedf(hy / Arena.UNIT, 1)])
		else: res.missing.append([pt[0], pt[1], pt[2], snappedf(hy / Arena.UNIT, 1) if hit else null])
		var fy := maxf(y, hy) if hit and hy - y < 0.5 else y   # stand on whichever floor is there (a higher remaster floor = "higher", not a wall)
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(x, fy + 0.1 + cap.height * 0.5, z))
		var hits := space.intersect_shape(sq, 4)
		if not hits.is_empty():
			var who := "world"
			for h in hits:
				if h.collider == ar.scenery_body:
					var c := (h.collider as Node).get_child(int(h.shape)) as Node
					who = str(c.get_meta("part", "scenery")) if c else "scenery"
			res.blocked.append([pt[0], pt[1], pt[2], who])
	res.cells = ar.area.get("stand", []).size()
	# holes: 25 cm floor cells inside the area where nothing at all is under the original's floor (a gap in the disc
	# mesh: a fighter there stands on nothing)
	res["holes"] = []
	var fg: Dictionary = ar.area.get("floor", {})
	if not fg.is_empty():
		for i in int(fg.h):
			for j in int(fg.w):
				var x := (float(fg.x0) + j * float(fg.cell)) * Arena.UNIT; var z := (float(fg.z0) + i * float(fg.cell)) * Arena.UNIT
				if ar.sdf_at(x, z) < -0.2: continue   # the edge cells too: on_floor takes feet 7.7 cm out, a cell is 25 cm
				var ls := ar.floor_levels(x, z)
				if ls.is_empty(): continue
				var top: float = ls.max()
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, top + 0.5, z), Vector3(x, float(ls.min()) - 1.0, z), 1))
				if not hit: res.holes.append([snappedf(x / Arena.UNIT, 0.1), snappedf(z / Arena.UNIT, 0.1), snappedf(top / Arena.UNIT, 0.1)])
				# every lower level too, the way Arena._ray_down sees feet there (from 30 cm over them, straight down):
				# Galuda's ground floor under the 1.0 / 3.05 m tops the disc's fighters run under had no collision
				# and over the whole cell (its centre and 8 points 10 cm round it): the disc mesh's floor can end inside
				# a cell the original's floor fills (Galuda's north floor: a fighter 6 cm off the centre stood on nothing)
				for y in ls:
					if not hit and y >= top: continue
					var gap := false
					for ox in [-0.1, 0.0, 0.1]:
						for oz in [-0.1, 0.0, 0.1]:
							if space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x + ox, y + 0.3, z + oz), Vector3(x + ox, y - 40.0, z + oz), 1)).is_empty(): gap = true
					if gap: res.holes.append([snappedf(x / Arena.UNIT, 0.1), snappedf(z / Arena.UNIT, 0.1), snappedf(y / Arena.UNIT, 0.1)])
	# placed throwables (their RAM layout spots) and the round's gems / start points against the area
	res["props_out"] = []
	for p in ar.props:
		var pp := (p as Node3D).global_position
		if ar.out_of_map(pp + Vector3.UP * 0.1, CamCheck.OBJ_TOL): res.props_out.append([(p as Prop).part, snappedf(pp.x, 0.01), snappedf(pp.y, 0.01), snappedf(pp.z, 0.01), snappedf(ar.sdf_at(pp.x, pp.z), 0.01)])
	res["spawn_out"] = ar.spawn_points().filter(func(q): return ar.out_of_map(q)).size()
	# placed parts with collision: how much of each one's footprint the original lets a fighter stand on (stand spots
	# under its top per 25 cm cell): a part the original walks through has most of its footprint covered
	res["parts_cover"] = {}
	var stand: Array = ar.area.get("stand", [])
	for inst in ar.scenery:
		var part := int((inst as Node).get_meta("part", -1))
		if float(part) in ar.area.get("no_collide_parts", []): continue
		var bx := CamCheck.mesh_box(inst as Node3D)
		if bx.size.x * bx.size.z < 0.04: continue
		var cells := bx.size.x * bx.size.z / 0.0625
		var n := 0
		for pt in stand:
			var x := float(pt[0]) * Arena.UNIT; var z := float(pt[1]) * Arena.UNIT; var y := float(pt[2]) * Arena.UNIT
			if x > bx.position.x and x < bx.end.x and z > bx.position.z and z < bx.end.z and y < bx.end.y - 0.05: n += 1
		var k := str(part)
		if not res.parts_cover.has(k): res.parts_cover[k] = [0.0, 0]
		res.parts_cover[k][0] += cells; res.parts_cover[k][1] += n
	var f := FileAccess.open(out_path, FileAccess.WRITE); f.store_string(JSON.stringify(res)); f.close()
	print("AREA_CHECK %s area=%s stand=%d ok=%d missing=%d higher=%d blocked=%d holes=%d prop_skip=%d props_out=%s spawn_out=%d" % [ar.stage,
		str(res.has_area), res.cells, res.ok, res.missing.size(), res.higher.size(), res.blocked.size(), res.holes.size(), res.prop_skip,
		str(res.props_out), res.spawn_out])
	quit()
	return true
