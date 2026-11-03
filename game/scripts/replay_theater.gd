class_name ReplayTheater
extends Node3D
## Replay theater: plays a recorded match (scripts/replay.gd) by putting each frame's snapshot back on display-only
## fighters, props and stones, with the recorded camera and cinematic look. Play/pause, 0.5x / 0.25x slow motion,
## scrub, jump between moments, free camera, photo mode (no HUD, depth of field, PNG to user://photos), and
## "Save highlight": the best 15-25 s rendered offline by Godot's Movie Maker at 1080p60, then ffmpeg -> H.264 MP4.
## Render mode (main.gd --highlight ...): no UI, plays the given segments once, fades, quits (Movie Maker writes it).

const SPEEDS := [1.0, 0.5, 0.25]

var rep: Replay
var path := ""
var segments: Array = []   # render mode: [{"psr": path, "from": f, "to": f}, ...]; optional per segment: "title" (the
						   # first one's card text, "" = none), "hud": false (clean frames), "fade": false (no black dips),
						   # "zoom": z (a tighter lens from the recorded eye, up to z x, framed on the fighters: _zoom)
var seg_i := 0
var render := false
var quit_at_end := true    # render mode: quit when the last segment is done (Movie Maker then closes the file)
var render_done := false
var arena: Arena
var fighters: Array[Fighter] = []
var cam: Camera3D
var fx: FX
var fcam: FightCam         # only its post pass: stage objects in the way fade, a fighter at the lens turns see-through
var hud_on := true
var zoom_max := 1.0
var zoom := [1.0, 0.0, 0.0]   # eased [zoom, yaw, pitch] on top of the recorded camera
var audit: FileAccess        # render mode, PS_AUDIT=/abs/file.jsonl: every rendered frame's fighter screen boxes (the
							 # final camera, zoom included: tools/trailer_audit.py checks heads / feet / sides)
var gem_nodes: Array = []
var post: MeshInstance3D
var post_mat: ShaderMaterial
var hud: HUD
var ui: CanvasLayer
var bars: Array[ColorRect] = []
var caption: Label
var info: Label
var status: Label
var title_card: Label
var fade: ColorRect
var bar: Control
var music: AudioStreamPlayer
var env_root: Node3D
var head := 0.0
var speed_i := 0
var playing := true
var free_cam := false
var photo := false
var pivot := Vector3.ZERO
var yaw := 0.0
var pitch := -0.35
var dist := 6.5
var last_i := -1
var seg_t := 0
var job := {}              # highlight render in flight: {"pid": n, "avi": p, "mp4": p, "stage": "render"|"encode"}
var timer := 60.0          # HUD fields (same names as Fight's)
var wins := [0, 0]
var cpu_flags := [true, true]
var teams := [0, 1]
var chars: Array = []

func _ready() -> void:
	if render:
		_load(segments[0].psr)
		head = float(segments[0].from)
	elif rep == null:
		var all := Replay.list_saved()
		if path == "" and not all.is_empty(): path = all[0]
		if path != "": _load(path)
	if rep == null:
		_empty(); return
	_build()

func _empty() -> void:
	var c := Camera3D.new(); c.current = true; add_child(c)
	ui = CanvasLayer.new(); add_child(ui)
	var l := UI.label("NO REPLAYS YET\nplay a match: every match is recorded", 54, Color(1, 0.85, 0.3))
	l.set_anchors_preset(Control.PRESET_FULL_RECT); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.add_child(l)

func _load(p: String) -> void:
	rep = Replay.load_file(p)
	path = p

func _build() -> void:
	for c in get_children(): c.queue_free()
	fighters.clear(); gem_nodes.clear(); bars.clear(); last_i = -1
	env_root = Node3D.new(); add_child(env_root)
	Look.build_environment(env_root)
	if render:   # offline: full resolution even at Ultra (no FSR upscale)
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR; get_viewport().scaling_3d_scale = 1.0
	arena = Arena.new(); arena.stage = String(rep.meta.get("stage", "stg00"))
	env_root.add_child(arena)
	arena.build(1)
	Look.stage_tweak(env_root, arena.info)
	HD.stage(env_root, arena)   # Remaster look (pass 6); a no-op in Classic
	var rmx: Remix = null
	var lit := String(rep.meta.get("lighting", rep.meta.get("look", "original")))   # "look" = recordings before the merge
	if lit != "original" and ResourceLoader.exists("res://scripts/remix.gd"):
		rmx = Remix.apply(env_root, arena, lit)   # remix lighting
	chars = rep.meta.get("chars", ["falcon", "ryoma"])
	cpu_flags = rep.meta.get("cpu", [true, true])
	teams = rep.meta.get("teams", range(chars.size()))
	wins = []
	for i in chars.size():
		var f := Fighter.new(); f.name = "R%d" % (i + 1)
		f.setup(i, chars[i], PInput.new())
		env_root.add_child(f)
		fighters.append(f)
		wins.append(0)
	cam = Camera3D.new(); cam.fov = 41.1; cam.far = 400.0; cam.current = true
	env_root.add_child(cam)
	HD.light_rig(cam)
	if rmx: rmx.tint_rig(cam)
	fcam = FightCam.new(); fcam.fade.setup(arena)
	var ca := CameraAttributesPractical.new()
	var we := env_root.get_node_or_null("Look") as WorldEnvironment
	if we and we.camera_attributes is CameraAttributesPractical:   # keep the look's exposure (Remaster auto exposure)
		ca = we.camera_attributes.duplicate()
	cam.attributes = ca
	fx = FX.new(); env_root.add_child(fx)
	post = MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	post_mat = ShaderMaterial.new(); post_mat.shader = load("res://shaders/cine_post.gdshader")
	post_mat.render_priority = -128
	q.material = post_mat; post.mesh = q
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(post)
	hud = HUD.new(); hud.fight = self; add_child(hud)
	ui = CanvasLayer.new(); ui.layer = 7; add_child(ui)
	for i in 2:
		var r := ColorRect.new(); r.color = Color(0, 0, 0); r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(r); bars.append(r)
	caption = UI.label("", 46, Color(1, 0.88, 0.45)); caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.position = Vector2(60, 40); ui.add_child(caption)
	if not render:
		bar = Control.new(); bar.set_anchors_preset(Control.PRESET_FULL_RECT); bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.draw.connect(_draw_bar); ui.add_child(bar)
		info = UI.label("", 26, Color(0.9, 0.95, 1.0)); info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT); info.position = Vector2(60, -150); ui.add_child(info)
		status = UI.label("", 30, Color(1, 0.85, 0.3)); status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.set_anchors_preset(Control.PRESET_TOP_RIGHT); status.position = Vector2(-60, 130); ui.add_child(status)
	title_card = UI.label("", 64, Color(1, 0.88, 0.35))
	title_card.set_anchors_preset(Control.PRESET_FULL_RECT); title_card.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_card.position.y = -150
	ui.add_child(title_card)
	fade = ColorRect.new(); fade.color = Color(0, 0, 0, 0); fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE; ui.add_child(fade)
	music = AudioStreamPlayer.new(); add_child(music)
	var s := Audio.music("ST_00")
	if s: music.stream = s; music.volume_db = -6.0; music.play()
	if render:   # title card: names grouped by team ("FALCON vs RYOMA", "A & B vs C & D")
		var teams: Array = rep.meta.get("teams", range(chars.size()))
		var by := {}
		for i in chars.size(): by[int(teams[i]) if i < teams.size() else i] = by.get(int(teams[i]) if i < teams.size() else i, []) + [Roster.display_name(chars[i]).to_upper()]
		title_card.text = "  vs  ".join(PackedStringArray(by.values().map(func(v): return " & ".join(PackedStringArray(v)))))
		if (segments[seg_i] as Dictionary).has("title"): title_card.text = String(segments[seg_i].title)   # "" = no card (trailer cuts)
		hud_on = bool((segments[seg_i] as Dictionary).get("hud", true))
		zoom_max = float((segments[seg_i] as Dictionary).get("zoom", 1.0)); zoom = [1.0, 0.0, 0.0]
		_settle(int(head))
	_show(int(head))

## ---------- one recorded frame on screen
func _show(k: int) -> void:
	k = clampi(k, 0, rep.frames.size() - 1)
	var s: Dictionary = rep.frames[k]
	Replay.apply_fighters(s, fighters)
	var fs: Array = s.f
	for i in mini(fs.size(), fighters.size()):
		var d: Array = fs[i]
		var f := fighters[i]
		f.hp = int(d[7]); f.gems = int(d[8]); f.gauge = float(d[9]); f.powered = bool(d[11])
	Replay.apply_props(s, arena.props)
	var gs: Array = s.get("g", [])
	while gem_nodes.size() < gs.size():
		var g := Gem.new(); g.color_idx = int(gs[gem_nodes.size()][3]); arena.add_child(g); gem_nodes.append(g)
	for gi in gem_nodes.size():
		var g: Gem = gem_nodes[gi]
		g.visible = gi < gs.size()
		if g.visible:
			if g.color_idx != int(gs[gi][3]):   # a different stone in this slot now: rebuild it in its colour
				g.queue_free(); g = Gem.new(); g.color_idx = int(gs[gi][3]); arena.add_child(g); gem_nodes[gi] = g
			g.global_position = Vector3(gs[gi][0], gs[gi][1], gs[gi][2])
			if g.visual: g.visual.rotation.y = k * 0.04
	timer = float(s.get("tm", 60.0))
	var w: Array = s.get("w", [0, 0])
	for i in mini(w.size(), wins.size()): wins[i] = int(w[i])
	if not free_cam:
		cam.global_transform = Replay.cam_transform(s)
		cam.fov = float((s.c as Array)[4])
		if zoom_max > 1.0: _zoom(s)
	_look(s.get("x", []))
	fcam.post_for(fighters, cam, 1.0 / 60.0)
	if k > last_i and k - last_i < 12:   # sparks + bursts of the frames just crossed (not when scrubbing far)
		for j in range(last_i + 1, k + 1):
			for e in (rep.frames[j] as Dictionary).get("e", []): Cinema.replay_fx(fx, e)
	last_i = k

func _look(x: Array) -> void:   # the recorded cinematic post pass + letterbox + caption
	var on := x.size() >= 10 and not photo
	var bar_amt := float(x[8]) if on else 0.0
	var vs := get_viewport().get_visible_rect().size
	var h := vs.y * 0.11 * bar_amt
	bars[0].position = Vector2.ZERO; bars[0].size = Vector2(vs.x, h)
	bars[1].position = Vector2(0, vs.y - h); bars[1].size = Vector2(vs.x, h)
	caption.text = String(x[9]) if on else ""
	hud.visible = hud_on and not photo and bar_amt < 0.5
	var pv := on and (float(x[0]) > 0.001 or float(x[1]) > 0.001 or float(x[5]) > 0.0 or float(x[6]) > 0.001 or float(x[7]) > 0.001)
	post.visible = pv
	if not pv: return
	post_mat.set_shader_parameter("desat", float(x[0]))
	post_mat.set_shader_parameter("desat_all", float(x[1]))
	post_mat.set_shader_parameter("hero_pos", Vector3(x[2], x[3], x[4]))
	post_mat.set_shader_parameter("wave_r", float(x[5]))
	post_mat.set_shader_parameter("impact", float(x[6]))
	post_mat.set_shader_parameter("flash", float(x[7]))

## A render that starts mid-match: run the fade pass over the second before `k` so objects the live camera had already
## faded (and a fighter it had turned see-through) start that way.
func _settle(k: int) -> void:
	k = clampi(k, 0, rep.frames.size() - 1)
	for j in range(maxi(0, k - 60), k):
		var s: Dictionary = rep.frames[j]
		Replay.apply_fighters(s, fighters)
		Replay.apply_props(s, arena.props)
		cam.global_transform = Replay.cam_transform(s)
		cam.fov = float((s.c as Array)[4])
		if zoom_max > 1.0: _zoom(s)
		fcam.post_for(fighters, cam, 1.0 / 60.0)
	last_i = k - 1

## Render option "zoom": the recorded camera's eye stays where it was (so nothing new gets between it and the fighters)
## and the lens narrows, re-aimed at the fighters' screen box, up to zoom_max x and never so far that a head, foot or
## side leaves the frame; eased. Cinematics (letterbox up) keep their own framing.
func _zoom(s: Dictionary) -> void:
	var x: Array = s.get("x", [])
	if x.size() >= 10 and float(x[8]) > 0.01:   # a cinematic: its own framing, from its first frame (it cuts anyway)
		zoom = [1.0, 0.0, 0.0]; return
	var base := cam.global_transform; var fov0 := cam.fov
	var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
	for b in _boxes():
		lo = Vector2(minf(lo.x, b[0]), minf(lo.y, b[1])); hi = Vector2(maxf(hi.x, b[2]), maxf(hi.y, b[3]))
	var want := [1.0, 0.0, 0.0]
	if hi.x > lo.x:
		lo.y -= 0.02   # hair above the head sphere
		var c := (lo + hi) * 0.5
		var z := minf(zoom_max, minf(0.84 / maxf(hi.x - lo.x, 0.01), 0.80 / maxf(hi.y - lo.y, 0.01)))
		z = maxf(1.0, z)
		var tv := tan(deg_to_rad(fov0) * 0.5); var th := tv * 16.0 / 9.0
		# turn the lens toward the box centre, only as far as the zoom needs (z = 1: the recorded aim)
		var k := clampf((z - 1.0) / maxf(zoom_max - 1.0, 0.01), 0.0, 1.0)
		want = [z, -atan((c.x - 0.5) * 2.0 * th) * k, -atan((c.y - 0.52) * 2.0 * tv) * k]
	# ease in slowly, out fast (a fighter leaving the frame wins over a smooth zoom)
	for i in 3:
		var out: bool = i == 0 and float(want[0]) < float(zoom[0])
		zoom[i] = lerpf(float(zoom[i]), float(want[i]), 0.25 if out else 0.07)
	# and a hard rule on top of the easing: every fighter whole inside the frame, or less zoom / less turn
	for it in 12:
		_lens(base, fov0)
		var ok := true
		for b in _boxes():
			if b[0] < 0.01 or b[1] < 0.01 or b[2] > 0.99 or b[3] > 0.99: ok = false
		if ok or float(zoom[0]) <= 1.0: break
		zoom = [maxf(1.0, 1.0 + (float(zoom[0]) - 1.0) * 0.8), float(zoom[1]) * 0.8, float(zoom[2]) * 0.8]
	if float(zoom[0]) <= 1.0: cam.global_transform = base; cam.fov = fov0

func _lens(base: Transform3D, fov0: float) -> void:
	var b := base.basis
	b = Basis(b.y, float(zoom[1])) * b
	b = Basis(b.x, float(zoom[2])) * b
	cam.global_transform = Transform3D(b.orthonormalized(), base.origin)
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov0) * 0.5) / float(zoom[0])))

func _boxes() -> Array:   # screen boxes of the fighters still in it (Battle Royale: the knocked-out ones don't count)
	var out := []
	var fs: Array = fighters.filter(func(f): return f.hp > 0) if fighters.size() > 2 else fighters
	for f in fs:
		var b := CamCheck.screen_box(cam, f)
		if not b.is_empty(): out.append(b)
	return out

## ---------- playback
func _process(dt: float) -> void:
	if rep == null or render_done: return
	if render:
		_render_step(); return
	_poll_job()
	var pad := _pad()
	if playing:
		head += SPEEDS[speed_i]
		if head >= rep.frames.size() - 1: head = rep.frames.size() - 1; playing = false
	var scrub := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT): scrub -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT): scrub += 1.0
	if pad >= 0 and not free_cam: scrub += Input.get_joy_axis(pad, JOY_AXIS_LEFT_X) if absf(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)) > 0.25 else 0.0
	if scrub != 0.0: head = clampf(head + scrub * 4.0, 0.0, rep.frames.size() - 1)
	if free_cam: _free_cam(dt, pad)
	_show(int(head))
	if free_cam: _place_free_cam()
	_dof()
	_info()
	if bar: bar.queue_redraw()

func _pad() -> int:
	var p := Input.get_connected_joypads()
	return int(p[0]) if p.size() > 0 else -1

func _free_cam(dt: float, pad: int) -> void:
	var mv := Vector2.ZERO; var rot := Vector2.ZERO; var zoom := 0.0
	if Input.is_physical_key_pressed(KEY_W): mv.y -= 1
	if Input.is_physical_key_pressed(KEY_S): mv.y += 1
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1
	if Input.is_physical_key_pressed(KEY_UP): rot.y += 1
	if Input.is_physical_key_pressed(KEY_DOWN): rot.y -= 1
	if Input.is_physical_key_pressed(KEY_Z): zoom -= 1
	if Input.is_physical_key_pressed(KEY_X): zoom += 1
	if pad >= 0:
		var l := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var r := Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if l.length() > 0.2: mv += l
		if r.length() > 0.2: rot += r
		zoom += Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT)
	yaw -= rot.x * dt * 2.0
	pitch = clampf(pitch + rot.y * dt * 1.5, -1.4, 0.4)
	dist = clampf(dist + zoom * dt * 6.0, 1.2, 25.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw)); var right := Vector3(cos(yaw), 0, -sin(yaw))
	pivot += (right * mv.x - fwd * mv.y) * dt * 6.0

func _place_free_cam() -> void:
	var off := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.global_position = pivot + off
	cam.look_at(pivot, Vector3.UP)

func _enter_free_cam() -> void:
	free_cam = true
	var c := Vector3.ZERO
	for f in fighters: c += f.global_position
	pivot = c / maxf(1, fighters.size()) + Vector3.UP * 1.0
	var rel := cam.global_position - pivot
	dist = clampf(rel.length(), 2.0, 20.0)
	yaw = atan2(rel.x, rel.z)
	pitch = -asin(clampf(rel.y / maxf(rel.length(), 0.01), -1.0, 1.0))

func _dof() -> void:
	var ca := cam.attributes as CameraAttributesPractical
	ca.dof_blur_far_enabled = photo; ca.dof_blur_near_enabled = photo
	if not photo: return
	var focus := (cam.global_position - pivot).length() if free_cam else 6.0
	ca.dof_blur_far_distance = focus + 1.5; ca.dof_blur_far_transition = 4.0
	ca.dof_blur_near_distance = maxf(0.3, focus - 1.8); ca.dof_blur_near_transition = 1.0
	ca.dof_blur_amount = 0.14

func _info() -> void:
	ui.visible = true
	if info == null: return
	info.visible = not photo
	if bar: bar.visible = not photo
	var secs := head / 60.0
	info.text = "%s   %d:%04.1f / %d:%04.1f   %s%s\n%s" % [("PLAY" if playing else "PAUSE"), int(secs) / 60, fmod(secs, 60.0),
		rep.frames.size() / 3600, fmod(rep.frames.size() / 60.0, 60.0), (str(SPEEDS[speed_i]) + "x"), ("   FREE CAMERA" if free_cam else ""),
		"Space/A play   S/X slow-mo   Left/Right scrub   Q/E moments   F/Y free cam   P/Select photo   C photo shot   H/Start save highlight   Esc/B back"]

func _draw_bar() -> void:
	if photo: return
	var vs := bar.size
	var r := Rect2(60, vs.y - 80, vs.x - 120, 14)
	bar.draw_rect(r.grow(3), Color(0, 0, 0, 0.6))
	var n := float(maxi(1, rep.frames.size() - 1))
	bar.draw_rect(Rect2(r.position, Vector2(r.size.x * head / n, r.size.y)), Color(1, 0.8, 0.25))
	var hl := rep.pick_highlight()
	bar.draw_rect(Rect2(r.position.x + r.size.x * hl.x / n, r.position.y - 8, r.size.x * (hl.y - hl.x) / n, 4), Color(0.4, 0.9, 1.0, 0.9))
	for e in rep.events:
		var col: Color = {"power": Color(0.4, 0.8, 1.0), "fusion": Color(1.0, 0.4, 0.9), "ko": Color(1.0, 0.3, 0.2)}.get(e.kind, Color(0, 0, 0, 0))
		if col.a == 0.0: continue
		var x := r.position.x + r.size.x * float(e.f) / n
		bar.draw_rect(Rect2(x - 2, r.position.y - 6, 4, r.size.y + 12), col)

func _jump(dirn: int) -> void:   # previous / next marked moment (a little before it)
	var best := -1
	for e in rep.events:
		if not e.kind in ["power", "fusion", "ko"]: continue
		var f := maxi(0, int(e.f) - 45)
		if dirn > 0 and f > int(head) + 5 and (best < 0 or f < best): best = f
		if dirn < 0 and f < int(head) - 5 and (best < 0 or f > best): best = f
	if best >= 0: head = best; last_i = best - 100

func _photo_shot() -> void:
	DirAccess.make_dir_recursive_absolute("user://photos")
	var p := "user://photos/photo_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(p))
	if status: status.text = "Photo saved: %s" % ProjectSettings.globalize_path(p)

func _unhandled_input(e: InputEvent) -> void:
	if rep == null or render:
		if e.is_pressed() and not render: UI.game().call("goto_title")
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_SPACE: playing = not playing
			KEY_S: if not free_cam: speed_i = (speed_i + 1) % SPEEDS.size()
			KEY_F: _toggle_free()
			KEY_P: _toggle_photo()
			KEY_C: _photo_shot()
			KEY_Q: _jump(-1)
			KEY_E: _jump(1)
			KEY_H: save_highlight()
			KEY_COMMA: head = maxf(0, head - 1); playing = false
			KEY_PERIOD: head = minf(rep.frames.size() - 1, head + 1); playing = false
			KEY_ESCAPE: UI.game().call("goto_title")
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_A: playing = not playing
			JOY_BUTTON_X: speed_i = (speed_i + 1) % SPEEDS.size()
			JOY_BUTTON_Y: _toggle_free()
			JOY_BUTTON_BACK: _toggle_photo()
			JOY_BUTTON_RIGHT_STICK: _photo_shot()
			JOY_BUTTON_LEFT_SHOULDER: _jump(-1)
			JOY_BUTTON_RIGHT_SHOULDER: _jump(1)
			JOY_BUTTON_DPAD_LEFT: head = maxf(0, head - 1); playing = false
			JOY_BUTTON_DPAD_RIGHT: head = minf(rep.frames.size() - 1, head + 1); playing = false
			JOY_BUTTON_START: save_highlight()
			JOY_BUTTON_B: UI.game().call("goto_title")
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		if not free_cam: _enter_free_cam()
		yaw -= e.relative.x * 0.006; pitch = clampf(pitch - e.relative.y * 0.005, -1.4, 0.4)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not free_cam: _enter_free_cam()
		dist = clampf(dist + (-0.6 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.6), 1.2, 25.0)

func _toggle_free() -> void:
	if free_cam: free_cam = false
	else: _enter_free_cam()

func _toggle_photo() -> void:
	photo = not photo
	if photo:
		playing = false
		if not free_cam: _enter_free_cam()

## ---------- highlights: Movie Maker render in a second Godot process, then ffmpeg
func save_highlight() -> void:
	if not job.is_empty(): return
	var hl := rep.pick_highlight()
	var dir := ProjectSettings.globalize_path("user://highlights/")
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := dir + "highlight_%s" % Time.get_datetime_string_from_system().replace(":", "-")
	var segs := [{"psr": ProjectSettings.globalize_path(path), "from": hl.x, "to": hl.y}]
	var jf := stem + ".json"
	var fa := FileAccess.open(jf, FileAccess.WRITE); fa.store_string(JSON.stringify(segs)); fa.close()
	var args := Highlight.render_args(jf, stem + ".avi")
	var pid := OS.create_process(OS.get_executable_path(), args)
	job = {"pid": pid, "avi": stem + ".avi", "mp4": stem + ".mp4", "stage": "render"}
	status.text = "Rendering highlight (%.0f s) ..." % ((hl.y - hl.x) / 60.0)

func _poll_job() -> void:
	if job.is_empty() or OS.is_process_running(int(job.pid)): return
	if job.stage == "render":
		if not FileAccess.file_exists(job.avi):
			status.text = "Highlight render failed"; job = {}; return
		var ff := Highlight.ffmpeg()
		if ff == "":
			status.text = "Saved %s (no ffmpeg on this machine for the MP4)" % job.avi; job = {}; return
		job.pid = OS.create_process(ff, Highlight.encode_args(job.avi, job.mp4))
		job.stage = "encode"
		status.text = "Encoding MP4 ..."
	else:
		status.text = ("Saved %s" % job.mp4) if FileAccess.file_exists(job.mp4) else "MP4 encode failed (%s kept)" % job.avi
		job = {}

func _render_step() -> void:   # one recorded frame per rendered frame (Movie Maker runs at a fixed 60 fps)
	var s: Dictionary = segments[seg_i]
	var from := int(s.from); var to := int(s.to)
	var k := from + seg_t
	_show(k)
	if audit == null and OS.has_environment("PS_AUDIT"): audit = FileAccess.open(OS.get_environment("PS_AUDIT"), FileAccess.WRITE)
	if audit:
		var x: Array = (rep.frames[clampi(k, 0, rep.frames.size() - 1)] as Dictionary).get("x", [])
		audit.store_line(JSON.stringify({"seg": seg_i, "rf": k, "zoom": snappedf(float(zoom[0]), 0.001),
			"cine": x.size() >= 10 and float(x[8]) > 0.01, "hud": hud.visible,
			"box": fighters.map(func(f): return CamCheck.screen_box(cam, f).map(func(v): return snappedf(v, 0.001)) if f.hp > 0 or fighters.size() <= 2 else [])}))
	var tot := 0
	for sg in segments: tot += int(sg.to) - int(sg.from) + 1
	var done := 0
	for j in seg_i: done += int(segments[j].to) - int(segments[j].from) + 1
	var g := done + seg_t
	# fade in from black, a title card over the first 2.5 s, fade out at the very end; dip to black between segments
	var a := 0.0
	if g < 18: a = 1.0 - g / 18.0
	if tot - g < 30: a = maxf(a, 1.0 - (tot - g) / 30.0)
	if seg_i > 0 and seg_t < 8: a = maxf(a, 1.0 - seg_t / 8.0)
	if to - k < 8 and seg_i < segments.size() - 1: a = maxf(a, 1.0 - (to - k) / 8.0)
	fade.color.a = a if bool(s.get("fade", true)) else 0.0
	title_card.modulate.a = clampf(1.0 - (g - 120) / 30.0, 0.0, 1.0) if g < 150 else 0.0
	seg_t += 1
	if k >= to:
		seg_i += 1; seg_t = 0
		if seg_i >= segments.size():
			render_done = true
			if audit: audit.close(); audit = null
			if quit_at_end: get_tree().quit()
			return
		_load(String(segments[seg_i].psr))
		head = float(segments[seg_i].from)
		_build()
		_show(int(segments[seg_i].from))
