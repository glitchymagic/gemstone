extends SceneTree
## Builds game/assets/fidelity/bone_boxes.json: for every fighter form on the disc (assets/ripped/pNk.glb, the disc's own
## meshes), per skeleton bone the box (bone space, cm) of the vertices that bone carries (rigid skin: the bone with the
## largest weight). The Power Change cinematic camera poses these boxes along the transform clip to keep the whole
## fighter (head, horns, feet) in frame (scripts/cinema.gd). Parts the game always hides are left out.
## Godot --headless --path game -s res://tests/bone_boxes.gd
const OUT := "res://assets/fidelity/bone_boxes.json"
var n := 0

func _process(_d: float) -> bool:
	n += 1
	if n < 2: return false
	var out := {}
	var ids := []
	for c in Roster.ALL:
		for id in (c.files as String).to_lower().split("/"):
			if not ids.has(id): ids.append(id)
	for id in ids:
		var path := "res://assets/ripped/%s.glb" % id
		if not ResourceLoader.exists(path): continue
		var hidden := []
		var cj := "res://assets/ripped/%s_clips.json" % id
		if FileAccess.file_exists(cj):
			var j = JSON.parse_string(FileAccess.get_file_as_string(cj))
			if j is Dictionary: hidden = j.get("hidden", [])
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
		var per := {}
		for x in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := x as MeshInstance3D
			if mi.mesh == null or mi.skin == null or hidden.has(String(mi.name)): continue
			if not (sk.global_transform.affine_inverse() * mi.global_transform).is_equal_approx(Transform3D.IDENTITY):
				push_error("%s %s: mesh not in skeleton space" % [id, mi.name]); quit(1); return true
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var bs = arr[Mesh.ARRAY_BONES]; var ws = arr[Mesh.ARRAY_WEIGHTS]
				if bs == null or ws == null or vs.is_empty(): continue
				var k := int(bs.size() / vs.size())
				for vi in vs.size():
					var best := 0; var bw := -1.0
					for jj in k:
						if float(ws[vi * k + jj]) > bw: bw = float(ws[vi * k + jj]); best = int(bs[vi * k + jj])
					var bone := mi.skin.get_bind_bone(best)
					var bn := String(sk.get_bone_name(bone)) if bone >= 0 else String(mi.skin.get_bind_name(best))
					var p: Vector3 = mi.skin.get_bind_pose(best) * vs[vi]
					per[bn] = (per[bn] as AABB).expand(p) if per.has(bn) else AABB(p, Vector3.ZERO)
		var o := {}
		for bn in per:
			var b: AABB = per[bn]
			o[bn] = [snappedf(b.position.x, 0.01), snappedf(b.position.y, 0.01), snappedf(b.position.z, 0.01),
				snappedf(b.size.x, 0.01), snappedf(b.size.y, 0.01), snappedf(b.size.z, 0.01)]
		out[id] = o
		inst.queue_free()
		print("%s: %d bones with geometry" % [id, o.size()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/fidelity"))
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, "", false))
	fa.close()
	print("wrote ", OUT, " (", out.size(), " forms)")
	quit(0)
	return true
