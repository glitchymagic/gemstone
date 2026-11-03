extends SceneTree
## fx-reach: every attack / throw clip's joints b00-b18 per clip frame, in the model's own space (cm; +z = forward, the
## clip as captured, no pin), for tools/reach.py (the disc's sphere centres vs the clip's).
## Godot --headless --path game -s res://tests/reach_probe.gd -- OUT.jsonl CHAR[,CHAR...]
## One line per clip frame: {"ch", "pc", "c": clip, "f": clip frame, "j": [[ox, oy, oz, xx, xy, xz, yx, yy, yz, zx, zy, zz] x 19]}
## (origin cm, basis columns x / y / z mapping a cm offset in the joint's frame to cm in model space)
var n := 0

func _initialize() -> void:
	pass

func _process(_dt: float) -> bool:
	n += 1
	if n < 2: return false
	var a := OS.get_cmdline_user_args()
	var out := FileAccess.open(str(a[0]), FileAccess.WRITE)
	for ch in str(a[1]).split(","):
		var m := PSModel.create_for(ch, false)
		if m == null: continue
		root.add_child(m)
		for pc in m.forms.keys():
			var ap: AnimationPlayer = m.players[pc]
			(m.trees[pc] as AnimationTree).active = false
			for k in m.forms: (m.forms[k] as Node3D).visible = (k == pc)
			m.form = pc
			var sk := m.skeleton()
			var inst: Node3D = m.forms[pc]
			inst.position = Vector3.ZERO
			var bones := []
			for j in 19: bones.append(sk.find_bone("b%02d" % j))
			for clip in ap.get_animation_list():
				var cs := String(clip)
				if not (cs.contains("k1_") or cs.contains("k4_") or cs.contains("k3_")): continue
				var nf := int(round(ap.get_animation(clip).length * 60.0)) + 1
				for f in nf:
					ap.play(clip); ap.seek(f / 60.0, true, true)
					sk.force_update_all_bone_transforms()
					var rel := m.global_transform.affine_inverse() * sk.global_transform
					var js := []
					for bi in bones:
						if bi < 0: js.append([]); continue
						var t: Transform3D = rel * sk.get_bone_global_pose(bi)
						var o := t.origin * 100.0; var b := t.basis
						js.append([snappedf(o.x, 0.01), snappedf(o.y, 0.01), snappedf(o.z, 0.01),
							snappedf(b.x.x * 100.0, 0.0001), snappedf(b.x.y * 100.0, 0.0001), snappedf(b.x.z * 100.0, 0.0001),
							snappedf(b.y.x * 100.0, 0.0001), snappedf(b.y.y * 100.0, 0.0001), snappedf(b.y.z * 100.0, 0.0001),
							snappedf(b.z.x * 100.0, 0.0001), snappedf(b.z.y * 100.0, 0.0001), snappedf(b.z.z * 100.0, 0.0001)])
					out.store_line(JSON.stringify({"ch": ch, "pc": pc, "c": cs, "f": f, "j": js}))
		m.queue_free()
	out.close()
	print("REACH_PROBE done")
	quit()
	return true
