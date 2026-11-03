extends SceneTree
## Pose strip of one fighter's clips: Godot --path game --resolution 1600x500 -s res://tests/clip_strip.gd -- OUT.png CHAR clip:frame,clip:frame,...
## (clip = the rig's own name, e.g. f0k1_153; frame in 1/60 s steps). Side view, one copy per entry, left to right.
var n := 0
var out := ""
var _poses := []
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var c: String = a[1]
	var items: PackedStringArray = a[2].split(",")
	var w := Node3D.new(); root.add_child(w)
	Look.build_environment(w, 2)
	var x := -1.1 * (items.size() - 1) * 0.5
	for it in items:
		var p := it.split(":")
		var m := PSModel.create_for(c, false)
		w.add_child(m); m.position = Vector3(x, 0, 0); m.rotation.y = PI * 0.5 + deg_to_rad(float(OS.get_environment("PS_YAW")) if OS.has_environment("PS_YAW") else 0.0)
		_poses.append([m, p[0], float(p[1]) / 60.0])
		x += 1.1
	var cam := Camera3D.new(); w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.2, 4.2 + items.size() * 0.35), Vector3(0, 0.9, 0))
func _process(_d: float) -> bool:
	n += 1
	if n >= 2 and n <= 5:   # pose in _process (seek does nothing before the nodes are in the tree)
		for e in _poses:
			var m: PSModel = e[0]
			var ap := m.players.get(m.form) as AnimationPlayer
			for t in m.find_children("*", "AnimationTree", true, false): (t as AnimationTree).active = false
			if ap.has_animation(e[1]): ap.play(e[1], 0.0, 0.0); ap.seek(e[2], true)
			elif n == 2: print("missing ", e[1])
	if n == 8:
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
	return false
