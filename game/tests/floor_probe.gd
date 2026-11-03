extends SceneTree
## Floor data at a point: PS_PROBE="stage x z [y]" (metres) -> floor_levels, floor_y_at from y, wall_at, sdf
func _initialize() -> void:
	var a_: PackedStringArray = OS.get_environment("PS_PROBE").split(" ")
	var a := Arena.new(); a.stage = a_[0]; root.add_child(a); a.build(1)
	var x := float(a_[1]); var z := float(a_[2]); var y := float(a_[3]) if a_.size() > 3 else 3.0
	for dx in [-0.25, 0.0, 0.25]:
		print("x %.2f z %.2f levels %s floor_y_at(from %.2f) %.2f wall_at %s sdf %.2f" % [x + dx, z, str(a.floor_levels(x + dx, z)), y, a.floor_y_at(x + dx, z, y), a.wall_at(x + dx, z, y), a.sdf_at(x + dx, z)])
	quit(0)
