extends SceneTree
## Attack-sphere reach of a motion: Godot --headless --path game -s res://tests/sphere_probe.gd -- CHAR CLIP F0 F1 HITFILE (p30)
## prints, per game frame f (clip frame f - 1), each attack-set sphere's centre (forward = +z of the model, cm) and radius
var m: PSModel
var n := 0
func _initialize() -> void:
	m = PSModel.create_for(OS.get_cmdline_user_args()[0], false)
	root.add_child(m)

func _process(_dt: float) -> bool:
	n += 1
	if n < 3: return false
	var a := OS.get_cmdline_user_args()
	var ap: AnimationPlayer = m.players[false]
	(m.trees[false] as AnimationTree).active = false
	var clip: String = a[1]
	var key := GameHits.key_of(clip)
	var gh := GameHits.load_for(a[4] if a.size() > 4 else "p30")
	var sk := m.skeleton()
	for f in range(int(a[2]), int(a[3]) + 1):
		ap.play(clip); ap.seek(maxf(0.0, f - 1) / 60.0, true, true)
		sk.force_update_all_bone_transforms()
		var st := gh.at(key, f)
		var sp := gh.world_spheres(gh.atk_sets, int(st.aset), sk, m, 0) if int(st.aset) > 0 else []
		var txt := ""
		for s in sp:
			var c: Vector3 = s[0]
			txt += " (fwd %.0f up %.0f side %.0f r %.0f)" % [c.z * 100.0, c.y * 100.0, c.x * 100.0, float(s[1]) * 100.0]
		var hip := sk.get_bone_global_pose(sk.find_bone("b00")).origin
		print("SPH %s f%d aset %d hit %d hip (fwd %.0f up %.0f side %.0f):%s" % [clip, f, int(st.aset), int(st.hit), hip.z, hip.y, hip.x, txt])
	return true
