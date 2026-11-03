extends SceneTree
## Graphics reel segments (Mac, windowed, Movie Maker). tools/hd_reel.sh runs them and cuts the reel.
## Godot --path game --resolution 1920x1080 --fixed-fps 60 --write-movie OUT.avi -s res://tests/reel.gd -- MODE FRAMES ARGS
##   hero  FRAMES ids          studio hero orbit (select-screen look), FRAMES split between the fighters; "id:pc" = its
##                             Power Change form, "id@intro" = the action it plays (default PS_HERO_ANIM, else idle);
##                             framed head to feet on the live skeleton; PS_HERO_ANG="from,to" degrees (default -70,70);
##                             native resolution + MSAA 4x (no FSR2 / TAA), depth of field focused on the fighter every frame
##   fight FRAMES stage a,b    CPU vs CPU on the stage, the game's own fight camera
##   dolly FRAMES stage ids    slow camera move over the stage with the fighters in their stance (identical path every
##                             run: the before/after wipe renders it once per look)
## PS_LOOK picks the look as everywhere else; PS_LIGHT=night|sunset|storm remixes the dolly's stage lighting.
var mode := "hero"
var frames := 300
var args := []
var n := 0
var w: Node3D
var cam: Camera3D
var model: PSModel
var ids := []
var ar: Arena
var models := []
var c0 := Vector3.ZERO
var back := Vector3.BACK
var hero_d := -1.0
var hero_y := 1.0
var hero_n := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	mode = a[0]; frames = int(a[1]); args = a.slice(2)

func _start() -> void:
	match mode:
		"fight":
			var f := Fight.new(); f.cpu_flags = [true, true]
			f.stage = args[0]; f.chars = Array(str(args[1]).split(","))
			root.add_child(f)
		"hero":
			w = Node3D.new(); root.add_child(w)
			Look.build_environment(w, 3)
			cam = Camera3D.new(); cam.fov = 30; w.add_child(cam); cam.current = true
			HD.light_rig(cam)
			HD.hero(w, cam, Vector3(0, 1.0, 0))
			# Ultra's FSR2 at 0.67 scale + its temporal pass ghosted the moving idle (a double head, trailer v2): render
			# native with MSAA instead
			var vp := w.get_viewport()
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR; vp.scaling_3d_scale = 1.0
			vp.use_taa = false; vp.msaa_3d = Viewport.MSAA_4X
			ids = Array(str(args[0]).split(","))
		"dolly":
			w = Node3D.new(); root.add_child(w)
			Look.build_environment(w, 3)
			ar = Arena.new(); ar.stage = args[0]; w.add_child(ar); ar.build(2)
			Look.stage_tweak(w, ar.info)
			HD.stage(w, ar)
			var rmx: Remix = Remix.apply(w, ar, OS.get_environment("PS_LIGHT")) if OS.has_environment("PS_LIGHT") else null
			cam = Camera3D.new(); cam.fov = 34; cam.far = 400.0; w.add_child(cam); cam.current = true
			HD.light_rig(cam)
			if rmx: rmx.tint_rig(cam)
			var sp := ar.spawn_points()
			c0 = (sp[0] + sp[1]) * 0.5
			if OS.has_environment("PS_CENTER"):
				var cc := OS.get_environment("PS_CENTER").split(",")
				c0 = Vector3(float(cc[0]), 0, float(cc[1]))
			c0.y = ar.ground_y(c0)
			back = Basis(Vector3.UP, ar.camera_yaw()) * Vector3(0, 0, -1)
			var right := Vector3(back.z, 0, -back.x)
			var cs := Array(str(args[1]).split(","))
			for i in cs.size():
				var m := PSModel.create_for(str(cs[i]), false)
				if m == null: continue
				w.add_child(m); m.play("idle"); models.append(m)
				var p: Vector3 = c0 + right * (float(i) - (cs.size() - 1) * 0.5) * 1.1
				p.y = ar.ground_y(p)
				m.global_position = p
				m.rotation.y = atan2(back.x, back.z) + deg_to_rad(-25.0 + 50.0 * i)

func _hero_frame() -> void:
	var per := maxi(1, frames / ids.size())
	var k := mini(n / per, ids.size() - 1)
	if model == null or model.get_meta("id", "") != ids[k]:
		if model: model.queue_free()
		var an := str(ids[k]).split("@")
		var idp := an[0].split(":")
		model = PSModel.create_for(idp[0], idp.size() > 1 and idp[1] == "pc")
		model.set_meta("id", ids[k])
		w.add_child(model)
		model.play(an[1] if an.size() > 1 else OS.get_environment("PS_HERO_ANIM") if OS.has_environment("PS_HERO_ANIM") else "idle")
		hero_n = 0
	hero_n += 1
	var t := float(n % per) / float(per)
	var rg := (OS.get_environment("PS_HERO_ANG") if OS.has_environment("PS_HERO_ANG") else "-70,70").split(",")
	var ang := deg_to_rad(lerpf(float(rg[0]), float(rg[1]), t))
	# fit head to feet: the skeleton's highest / lowest joints (+ the head's own size), eased so moves don't pump the zoom
	var sk := model.skeleton()
	var top := 1.7; var bot := 0.0
	if sk:
		top = -1e9; bot = 1e9
		for i in sk.get_bone_count():
			var y := (sk.global_transform * sk.get_bone_global_pose(i)).origin.y
			top = maxf(top, y); bot = minf(bot, y)
		top += 0.32; bot = minf(bot, 0.0) - 0.06
	var half := (top - bot) * 0.5 * 1.12
	var want := half / tan(deg_to_rad(cam.fov) * 0.5)
	if hero_n <= 3: hero_d = want; hero_y = (top + bot) * 0.5   # its first frame is the rest pose round the origin
	hero_d = want if want > hero_d else lerpf(hero_d, want, 0.02)   # out at once (a jump never leaves the frame), in slowly
	hero_y = lerpf(hero_y, (top + bot) * 0.5, 0.05)
	var d := hero_d * lerpf(1.0, 0.94, t)   # a slow push in
	cam.global_position = Vector3(sin(ang) * d, hero_y + 0.12 + 0.18 * sin(t * PI), cos(ang) * d)
	cam.look_at(Vector3(0, hero_y, 0), Vector3.UP)
	HD.hero_focus(cam, Vector3(0, hero_y, 0))

func _dolly_frame() -> void:
	var t := float(n) / float(frames)
	var e := t * t * (3.0 - 2.0 * t)
	var side := Vector3(back.z, 0, -back.x)
	var pos := c0 + back * lerpf(7.5, 3.6, e) + Vector3.UP * lerpf(2.6, 1.45, e) + side * lerpf(-1.8, 1.2, e)
	cam.global_position = pos
	cam.look_at(c0 + Vector3.UP * lerpf(0.7, 1.0, e), Vector3.UP)

func _process(_d: float) -> bool:
	n += 1
	if n == 1: _start()
	if mode == "hero" and n >= 1: _hero_frame()
	if mode == "dolly" and n >= 2: _dolly_frame()
	if n >= frames:
		quit()
		return true
	return false
