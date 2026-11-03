extends SceneTree
## The original's fight replayed into the remaster's stage, to measure the fight camera on the original's own fighter
## positions (no remaster AI, no out-of-map wandering): both fighters are placed at the feet the original logged every
## frame (tools/stagelog.py: dumps/cap/TAG.bin, 188-byte frames), facing each other, and the camera is either
##   PS_MODE=orig      the original's own camera (eye +0x450 looking at the smoothed target +0x480), remaster fades on
##   PS_MODE=remaster  the remaster's fight camera (scripts/fight_cam.gd) fed those positions
## One line per frame into PS_AUDIT (scripts/cam_check.gd's frame, so tools/cam_audit.py reads it) + "ref" = the
## original's eye / target / yaw / distance and "base" = the remaster's pure rule (tools/cam_fid.py: the fidelity numbers).
## Godot --headless --path game --fixed-fps 60 -s res://tests/cam_replay.gd
##   env PS_STAGE=stg80 PS_CAMLOG=/abs/cl80.bin PS_MODE=remaster PS_AUDIT=/abs/out.jsonl [PS_FROM=0 PS_N=frames]
##   PS_SHOTS=i,j,.. + PS_SHOT_DIR=/abs: windowed (no --headless), the full look, a PNG at those original frame indices
## Only the original's fight frames are replayed: before its match end, neither fighter in intro / round end / Power
## Change (states 21 / 22 / 23); a gap restarts the camera (the original's own camera is copied in at a restart).
const FS := 188
var f: Fight
var frames: Array = []   # [i, F1, F2, E, S, s1, s2]
var k := 0
var n_out := 0
var mode := "remaster"
var audit: FileAccess
var settle := 0
var shots := {}
var pending_shot := ""

func _initialize() -> void:
	mode = OS.get_environment("PS_MODE") if OS.has_environment("PS_MODE") else "remaster"
	_load(OS.get_environment("PS_CAMLOG"))
	if OS.has_environment("PS_SHOTS"):
		for x in OS.get_environment("PS_SHOTS").split(","): shots[int(x)] = true
	f = Fight.new(); f.test_mode = shots.is_empty()
	f.stage = OS.get_environment("PS_STAGE"); f.chars = ["falcon", "ryoma"]; f.cpu_flags = [true, true]
	root.add_child(f)
	audit = FileAccess.open(OS.get_environment("PS_AUDIT"), FileAccess.WRITE)
	print("CAM_REPLAY %s %s: %d frames" % [f.stage, mode, frames.size()])

func _v(b: PackedByteArray, o: int) -> Vector3:
	return Vector3(b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8))

func _load(path: String) -> void:
	var raw := FileAccess.get_file_as_bytes(path)
	var n := raw.size() / FS
	var s1 := PackedInt32Array(); s1.resize(n)
	for i in n: s1[i] = raw[i * FS + 110]
	var end := n   # the match end: the first state-21 run longer than 10 s (the log runs on into the next screen)
	var run := 0
	for i in n:
		run = run + 1 if s1[i] == 21 else 0
		if run > 600: end = i - run + 1; break
	var from := int(OS.get_environment("PS_FROM")) if OS.has_environment("PS_FROM") else 0
	var cnt := int(OS.get_environment("PS_N")) if OS.has_environment("PS_N") else n
	for i in range(from, mini(end, from + cnt)):
		var o := i * FS
		var b := raw.slice(o, o + FS)
		var a1 := b[110]; var a2 := b[114]
		if a1 in [21, 22, 23] or a2 in [21, 22, 23]: continue
		var e := _v(b, 48)
		if e == Vector3.ZERO: continue
		frames.append([i, _v(b, 116) * 0.01, _v(b, 128) * 0.01, e * 0.01, _v(b, 72) * 0.01, a1, a2])

func _process(dt: float) -> bool:
	if pending_shot != "":
		root.get_texture().get_image().save_png(pending_shot); pending_shot = ""
	settle += 1
	if settle < 30: return false   # the fight's _ready, models loaded and posed (idle) before it is frozen
	if settle == 30:
		f.process_mode = Node.PROCESS_MODE_DISABLED   # no AI, no physics: the log moves the fighters
		f.phase = Fight.R.FIGHT
	if k >= frames.size():
		audit.close()
		print("CAM_REPLAY_DONE %d frames" % n_out)
		quit()
		return true
	var fr: Array = frames[k]
	var gap := k == 0 or int(fr[0]) != int(frames[k - 1][0]) + 1
	k += 1
	var p1: Vector3 = fr[1]; var p2: Vector3 = fr[2]
	f.fighters[0].global_position = p1; f.fighters[1].global_position = p2
	for i in 2:
		var me: Fighter = f.fighters[i]; var other: Vector3 = p2 if i == 0 else p1
		var d := other - me.global_position; d.y = 0
		if d.length() > 0.01: me.facing = d.normalized(); me._apply_facing()
	var eye: Vector3 = fr[3]; var s: Vector3 = fr[4]
	if f.fcam == null:
		f.fcam = FightCam.new(); f.fcam.setup(f)
	var fc := f.fcam
	if mode == "orig":
		f.cam.global_position = eye; f.cam.look_at(s, Vector3.UP)
	else:
		if gap:   # (re)start from the original's camera state, like the game's own after its round intro
			fc.tgt = s
			fc.hd = Vector2(eye.x - s.x, eye.z - s.z).length(); fc.eye_y = eye.y
			fc.base_yaw = atan2(eye.x - s.x, eye.z - s.z) + PI
			fc.want_i = -1; fc.aim = 0.0; fc.extra = 0.0; fc.yaw_off = 0.0; fc.pull = 1.0; fc.lift = 0.0
			fc.want = [0.0, 1.0, 0.0]
		fc.update(1.0 / 60.0)
	fc.post(1.0 / 60.0)
	var row := CamCheck.frame(f, n_out + 1)
	var oy := rad_to_deg(atan2(eye.x - s.x, eye.z - s.z))
	row["of"] = fr[0]
	row["ref"] = {"eye": [snappedf(eye.x, 0.01), snappedf(eye.y, 0.01), snappedf(eye.z, 0.01)],
		"tgt": [snappedf(s.x, 0.01), snappedf(s.y, 0.01), snappedf(s.z, 0.01)], "yaw": snappedf(oy, 0.01),
		"hd": snappedf(Vector2(eye.x - s.x, eye.z - s.z).length(), 0.01), "st": [fr[5], fr[6]]}
	var c := f.cam.global_position
	var la := c - f.cam.global_basis.z * 10.0
	row["live"] = {"yaw": snappedf(rad_to_deg(atan2(c.x - la.x, c.z - la.z)), 0.01)}
	if fc.base.size() > 0 and mode != "orig":
		var bt: Vector3 = fc.base.tgt
		row["base"] = {"yaw": snappedf(rad_to_deg(float(fc.base.yaw)) + 180.0, 0.01), "hd": snappedf(float(fc.base.hd), 0.01),
			"eye_y": snappedf(float(fc.base.eye_y), 0.01), "tgt": [snappedf(bt.x, 0.01), snappedf(bt.y, 0.01), snappedf(bt.z, 0.01)]}
	if OS.has_environment("PS_PCLEAR") and not fc.fid.is_empty():   # per preset: is the line target -> eye free?
		var space := f.get_world_3d().direct_space_state
		var hdr := Vector2(eye.x - s.x, eye.z - s.z).length()
		var pc := []
		for yd in fc.fid.yaws_deg:
			var yr := deg_to_rad(float(yd))
			var e2 := Vector3(s.x + sin(yr) * hdr, eye.y, s.z + cos(yr) * hdr)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(s, e2, 1))
			pc.append(-1.0 if hit.is_empty() else snappedf(s.distance_to(hit.position) / s.distance_to(e2), 0.01))
		row["pclear"] = pc
	audit.store_line(JSON.stringify(row))
	n_out += 1
	if shots.has(int(fr[0])):   # saved at the start of the next frame, once this one is drawn
		pending_shot = OS.get_environment("PS_SHOT_DIR") + "/%s_%s_%06d.png" % [f.stage, mode, int(fr[0])]
	return false
