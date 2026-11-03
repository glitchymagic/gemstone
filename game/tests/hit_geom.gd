extends SceneTree
## Pass 4 check: the remaster's skeleton at a move's frames vs the game's logged sphere positions.
## Godot --headless --path game -s res://tests/hit_geom.gd -- CHAR ACTION BONE F0 F1
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
	var clip := m.clip_for(a[1])
	var sk := m.skeleton()
	var bi := sk.find_bone("b%02d" % int(a[2]))
	for f in range(int(a[3]), int(a[4]) + 1):
		ap.play(clip); ap.seek(f / 60.0, true, true)
		sk.force_update_all_bone_transforms()
		var p := sk.get_bone_global_pose(bi).origin   # model space, cm (the GLB is in game units)
		var r := sk.get_bone_global_pose(sk.find_bone("b00")).origin
		print("GEOM %s f%d bone %d: from feet %.1f height %.1f (root %.1f, %.1f, %.1f)" % [clip, f, int(a[2]), Vector2(p.x, p.z).length(), p.y, r.x, r.y, r.z])
	return true
