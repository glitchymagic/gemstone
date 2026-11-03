extends SceneTree
func _initialize() -> void:
	var a := Arena.new(); a.stage = "stg00"; root.add_child(a); a.build(1)
	for xz in [[0.50, 5.80], [0.50, 5.70], [0.50, 5.65], [0.50, 5.60], [0.50, 5.55], [0.50, 5.50], [0.50, 5.45], [0.50, 5.35], [-2.09, 5.78], [-2.09, 5.70], [-2.09, 5.60], [-0.50, 5.60], [-0.50, 5.50]]:
		var x: float = xz[0]; var z: float = xz[1]
		print("x %.2f z %.2f levels %s wall_at(y0.6) %s wall_at(y0.3) %s floor_y_at(from 0.6) %.2f" % [x, z, str(a.floor_levels(x, z)), a.wall_at(x, z, 0.6), a.wall_at(x, z, 0.3), a.floor_y_at(x, z, 0.6)])
	quit(0)
