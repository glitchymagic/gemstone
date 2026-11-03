extends SceneTree
## Windowed screenshot + frame-time harness (Mac only).
## Godot --path game --resolution 1920x1080 -s res://tests/shot.gd -- <kind> <out.png> [frames]
## kinds: stage, title, select, fight (CPU vs CPU; shot taken at a hit / power change / wide)

var kind := "stage"
var out := "/tmp/shot.png"
var wait := 90
var n := 0
var node: Node
var cam: Camera3D
var fight: Fight
var times := []
var gpu := []
var cpu := []
var want := ""
var phys0 := 0   # physics frame of the forced event (shot delays count physics frames: the window may run at 120 Hz)

func _initialize() -> void:
	if OS.has_environment("PS_NOVSYNC"): DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: kind = a[0]
	if a.size() > 1: out = a[1]
	if a.size() > 2: wait = int(a[2])
	if a.size() > 3: want = a[3]
	match kind:
		"title": node = TitleScreen.new()
		"select": node = SelectScreen.new()
		"theater":   # PS_REPLAY=/abs/x.psr, PS_HEAD=frame, PS_PHOTO=1
			var th := ReplayTheater.new(); th.path = OS.get_environment("PS_REPLAY"); node = th
			th.playing = false
			th.ready.connect(func():
				th.head = float(OS.get_environment("PS_HEAD")) if OS.has_environment("PS_HEAD") else 600.0
				if OS.has_environment("PS_PHOTO"): th._toggle_photo())
		"fight":
			fight = Fight.new(); fight.cpu_flags = [true, true]; node = fight
			if OS.has_environment("PS_STAGE"): fight.stage = OS.get_environment("PS_STAGE")
			if OS.has_environment("PS_CHARS"): fight.chars = Array(OS.get_environment("PS_CHARS").split(","))
			if OS.has_environment("PS_LIGHT"): fight.lighting = OS.get_environment("PS_LIGHT")
		_:
			node = Node3D.new()
			Look.build_environment(node, 3)
			var ar := Arena.new(); node.add_child(ar)
			if OS.has_environment("PS_STAGE"): ar.stage = OS.get_environment("PS_STAGE")
			ar.build(2)
			Look.stage_tweak(node, ar.info)
			cam = Camera3D.new(); cam.fov = 55; node.add_child(cam); cam.current = true
	root.add_child(node)

func _process(dt: float) -> bool:
	n += 1
	if n > 10:
		times.append(dt * 1000.0)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
	if cam and n == 2:
		var a := OS.get_cmdline_user_args()
		if a.size() >= 11:   # stage camera override after <kind> <out> <wait> <want>: px py pz tx ty tz fov (metres)
			cam.fov = float(a[10])
			cam.global_position = Vector3(float(a[4]), float(a[5]), float(a[6])); cam.look_at(Vector3(float(a[7]), float(a[8]), float(a[9])), Vector3.UP)
		else:
			cam.global_position = Vector3(-6.5, 8.5, -9.5); cam.look_at(Vector3(1.0, 0.5, 2.0), Vector3.UP)
	if OS.has_environment("PS_MULTI") and str(n) in OS.get_environment("PS_MULTI").split(","):   # extra frames: out_<n>.png
		root.get_viewport().get_texture().get_image().save_png(out.get_basename() + "_%d.png" % n)
	var ready := n >= wait and (want == "" or fight == null)
	if fight and want != "" and n > 60:
		var f0: Fighter = fight.fighters[0]; var f1: Fighter = fight.fighters[1]
		if want == "hit": ready = n >= wait and (f0.state == Fighter.S.HITSTUN or f1.state == Fighter.S.HITSTUN or f0.state == Fighter.S.DOWN or f1.state == Fighter.S.DOWN) and fight.phase == Fight.R.FIGHT
		elif want == "power": ready = (f0.state == Fighter.S.TRANSFORM or f1.state == Fighter.S.TRANSFORM) and (f0.state_t > 1.05 or f1.state_t > 1.05)
		elif want == "forcepower":
			if n == wait: f1.pick_gem(); f1.pick_gem(); f1.pick_gem(); phys0 = Engine.get_physics_frames()
			ready = n > wait and Engine.get_physics_frames() - phys0 >= int(OS.get_environment("PS_SHOT_DELAY") if OS.has_environment("PS_SHOT_DELAY") else "50")
		elif want == "forcefusion":   # P2 changes at `wait`, fires a Power Fusion 160 frames later
			if n == wait: f1.pick_gem(); f1.pick_gem(); f1.pick_gem(); phys0 = Engine.get_physics_frames()
			if phys0 > 0 and Engine.get_physics_frames() - phys0 >= 160 and (fight.cinema == null or fight.cinema.kind == ""):
				f1.state = Fighter.S.IDLE; f1.gauge = Rules.GAUGE_MAX; f1._start_attack("fusion1"); phys0 = -Engine.get_physics_frames()
			ready = phys0 < 0 and Engine.get_physics_frames() + phys0 >= int(OS.get_environment("PS_SHOT_DELAY") if OS.has_environment("PS_SHOT_DELAY") else "20")
		elif want == "forceko":   # P2 lands a final blow on P1 at `wait`; shot PS_SHOT_DELAY frames later
			if n == wait:
				f0.invuln = 0.0; f0.state = Fighter.S.IDLE; f0.hp = 5
				f0.receive_hit(200, 8.0, true, f1.global_position, f1)
				phys0 = Engine.get_physics_frames()
			ready = n > wait and Engine.get_physics_frames() - phys0 >= int(OS.get_environment("PS_SHOT_DELAY") if OS.has_environment("PS_SHOT_DELAY") else "30")
		if n > wait * 20: ready = true
	if ready:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		if fight: print("CAMDBG f0=", fight.fighters[0].global_position, " f1=", fight.fighters[1].global_position, " cam=", fight.cam.global_position, " tgt=", fight.cam_tgt)
		if fight and fight.cinema: print("CINEDBG kind=%s t=%.2f burst=%s wave=%.2f desat=%.2f" % [fight.cinema.kind, fight.cinema.t, fight.cinema.burst_done, fight.cinema.wave_r, fight.cinema.desat])
		times.sort()
		var avg := 0.0
		for t in times: avg += t
		avg /= maxf(1, times.size())
		print("SHOT %s %dx%d frames=%d avg_frame=%.2fms p95=%.2fms" % [out, img.get_width(), img.get_height(), n, avg, times[int(times.size() * 0.95)] if times.size() > 0 else 0.0])
		gpu.sort(); cpu.sort()
		var g := 0.0
		for t in gpu: g += t
		var c := 0.0
		for t in cpu: c += t
		if gpu.size() > 0: print("RENDER gpu avg=%.2fms p95=%.2fms  cpu avg=%.2fms" % [g / gpu.size(), gpu[int(gpu.size() * 0.95)], c / cpu.size()])
		quit()
		return true
	return false
