extends SceneTree
## sdf / floor levels on a grid: PS_PROBE="stage x0 z0 half step" (metres) -> rows of sdf (cm), '#' = outside
func _initialize() -> void:
	var a_: PackedStringArray = OS.get_environment("PS_PROBE").split(" ")
	var a := Arena.new(); a.stage = a_[0]; root.add_child(a); a.build(1)
	var x0 := float(a_[1]); var z0 := float(a_[2]); var h := float(a_[3]); var s := float(a_[4])
	var n := int(round(h / s))
	print("rows = z from %.2f down, cols = x from %.2f" % [z0 - h, x0 - h])
	for i in range(-n, n + 1):
		var line := "z %6.2f " % (z0 + i * s)
		for j in range(-n, n + 1):
			var v := (a.air_sdf_at(x0 + j * s, z0 + i * s) if OS.has_environment("PS_AIR") else a.sdf_at(x0 + j * s, z0 + i * s)) * 100.0
			line += ("%4d" % int(v)) if v >= 0 else "  ##"
		print(line)
	quit(0)
