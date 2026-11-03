extends SceneTree
## Rig check: pose the imported GLB at a clip frame and print bone positions (character space, cm).
func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var clip: String = OS.get_cmdline_user_args()[1]
	var fr := int(OS.get_cmdline_user_args()[2])
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	print("anims ", ap.get_animation_list().size(), " bones ", sk.get_bone_count())
	ap.play(clip); ap.seek(fr / 60.0, true)
	sk.force_update_all_bone_transforms()
	for bn in ["b00", "b04", "b08", "b15", "b18"]:
		var b := sk.find_bone(bn)
		print("bone ", bn, " ", sk.get_bone_global_pose(b).origin)
	quit()
