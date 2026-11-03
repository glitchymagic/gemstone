extends SceneTree
## Render the ripped fighters standalone: Godot --path game --resolution 1600x900 -s res://tests/model_shot.gd -- out.png anim [ids]
## ids = comma list (default falcon,ryoma); each fighter is shown in both forms, facing the camera.
var n := 0
var out := "/tmp/models.png"
var anim := "idle"
var ids := ["falcon", "ryoma"]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: anim = a[1]
	if a.size() > 2: ids = Array(a[2].split(","))
	var w := Node3D.new(); root.add_child(w)
	Look.build_environment(w, 2)
	var x := -0.8 * (ids.size() * 2 - 1)
	for c in ids:
		for pc in [false, true]:
			var m := PSModel.create_for(c, pc)
			w.add_child(m); m.position = Vector3(x, 0, 0); m.rotation.y = PI + deg_to_rad(float(OS.get_environment("PS_YAW")) if OS.has_environment("PS_YAW") else 0.0)
			m.play(anim)
			x += 1.6
	var cam := Camera3D.new(); cam.fov = 40; w.add_child(cam); cam.current = true
	var zm := float(OS.get_environment("PS_ZOOM")) if OS.has_environment("PS_ZOOM") else 1.0   # giants (Final Valgas)
	cam.look_at_from_position(Vector3(0, 1.3, -3.1 * ids.size()) * zm, Vector3(0, 1.0, 0) * zm, Vector3.UP)
func _process(_d: float) -> bool:
	n += 1
	if n == 40:
		root.get_viewport().get_texture().get_image().save_png(out)
		quit()
	return false
