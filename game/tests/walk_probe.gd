extends SceneTree
## Arena.core_ground stepped like a runner: PS_PROBE="stage x y z dirx dirz [cm_per_frame] [frames] [char]" (metres)
func _initialize() -> void:
	var a_: PackedStringArray = OS.get_environment("PS_PROBE").split(" ")
	var a := Arena.new(); a.stage = a_[0]; root.add_child(a); a.build(1)
	var p := Vector3(float(a_[1]), float(a_[2]), float(a_[3]))
	var d := Vector3(float(a_[4]), 0, float(a_[5])).normalized()
	var sp := (float(a_[6]) if a_.size() > 6 else 9.5) * 0.01
	var n := int(a_[7]) if a_.size() > 7 else 20
	var ch := a_[8] if a_.size() > 8 else "falcon"
	for k in n:
		var r: Dictionary = a.core_ground(p + d * sp, p, ch, false)
		var q: Vector3 = r.pos
		print("f%d %s -> %s grounded %s wall %s kind %s floor %.2f sdf %.3f" % [k, str(p.snapped(Vector3.ONE * 0.001)), str(q.snapped(Vector3.ONE * 0.001)), r.grounded, r.wall, r.ledge_kind, r.floor, a.sdf_at(q.x, q.z)])
		if not r.grounded: q.y -= 0.03   # falling: the core's first frame
		p = q
	quit(0)
