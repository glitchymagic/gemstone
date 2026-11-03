extends SceneTree
## Matched-camera look comparison (Mac, windowed): fighters standing on a stage, close camera from the stage's own
## fight-camera yaw. Godot --path game --resolution 1600x900 -s res://tests/look_shot.gd -- out.png [stage] [ids] [anim]
## PS_LOOK picks the look (remaster, classic, anime, pbr). PS_CAM = "dist,height,fov,turn_deg" overrides the framing;
## PS_SPREAD = metres between fighters; PS_FRAME = frame to grab (default 50); PS_LOOKY = look-at height (0.92 m);
## PS_YAW = degrees added to every fighter's facing (turn a side-on stance toward the camera for portraits).
var n := 0
var out := "/tmp/look.png"
var stage := "stg00"
var ids := ["falcon", "ryoma", "ayame"]
var anim := "idle"
var models: Array = []
var w: Node3D
var ar: Arena
var cam: Camera3D
var grab := 50

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: stage = a[1]
	if a.size() > 2: ids = Array(a[2].split(","))
	if a.size() > 3: anim = a[3]
	if OS.has_environment("PS_FRAME"): grab = int(OS.get_environment("PS_FRAME"))
	w = Node3D.new(); root.add_child(w)

func _build() -> void:   # after the root is in the tree (collision transforms need it)
	var we := Look.build_environment(w, 3)
	if we and we.compositor:   # stills: no motion blur (a close camera turns the idle sway into blur)
		for e in we.compositor.compositor_effects:
			if e is HDPost: (e as HDPost).mblur = 0.0
	ar = Arena.new(); ar.stage = stage; w.add_child(ar); ar.build(2)
	Look.stage_tweak(w, ar.info)
	HD.stage(w, ar)
	for c in ids:
		var pc := str(c).ends_with("+")
		var m := PSModel.create_for(str(c).trim_suffix("+"), pc)
		if m == null: continue
		w.add_child(m); m.play(anim); models.append(m)
	cam = Camera3D.new(); cam.far = 400.0; w.add_child(cam); cam.current = true
	HD.light_rig(cam)

func _place() -> void:
	var sp := ar.spawn_points()
	var c: Vector3 = (sp[0] + sp[1]) * 0.5
	if OS.has_environment("PS_CENTER"):
		var cc := OS.get_environment("PS_CENTER").split(",")
		c = Vector3(float(cc[0]), 0, float(cc[1]))
	var cfg := [3.9, 1.3, 32.0, 0.0]
	if OS.has_environment("PS_CAM"):
		var v := OS.get_environment("PS_CAM").split(",")
		for i in mini(v.size(), 4): cfg[i] = float(v[i])
	var yaw := ar.camera_yaw() + deg_to_rad(cfg[3])
	var back := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	var right := Vector3(back.z, 0, -back.x)
	c.y = ar.ground_y(c)
	var spread := float(OS.get_environment("PS_SPREAD")) if OS.has_environment("PS_SPREAD") else 0.95
	for i in models.size():
		var p: Vector3 = c + right * (float(i) - (models.size() - 1) * 0.5) * spread
		p.y = ar.ground_y(p)
		models[i].global_position = p
		models[i].rotation.y = atan2(back.x, back.z) + deg_to_rad(-18.0 + 18.0 * i + (float(OS.get_environment("PS_YAW")) if OS.has_environment("PS_YAW") else 0.0))
	cam.fov = cfg[2]
	cam.global_position = c + back * cfg[0] + Vector3.UP * cfg[1]
	cam.look_at(c + Vector3.UP * (float(OS.get_environment("PS_LOOKY")) if OS.has_environment("PS_LOOKY") else 0.92), Vector3.UP)

func _process(_d: float) -> bool:
	n += 1
	if n == 1: _build()
	if n == 5: _place()
	if n == grab:
		root.get_viewport().get_texture().get_image().save_png(out)
		print("LOOKSHOT ", out)
		quit()
	return false
