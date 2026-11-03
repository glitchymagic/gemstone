extends SceneTree
## Power Change cinematic framing proof (BUG-4): a CPU-vs-CPU fight in the real flow with cinematics on; once the fight
## runs, P1 gets three stones; every frame of the cutscene measures P1's screen box from his posed mesh
## (CamCheck.skin_points: head, horns, feet) and from the game's body spheres (CamCheck.screen_box) against the frame
## and the letterbox bars. Godot --headless --path game --fixed-fps 60 -s res://tests/pc_check.gd -- STAGE a,b
## env: PS_SEED, PS_LOOK, PS_PC_AT=frames into the fight before the stones (default 90), PS_PC_TRACE=1 per-frame lines.
## Prints PC_CHECK <a> <stage> frames=.. out_frame=.. out_bars=.. sph_out=.. worst top/bottom/left/right, quits 0 if 0.
var n := 0
var f: Fight
var fight_n := 0
var given := false
var done := false
var frames := 0
var out_frame := 0    # mesh box past a frame edge
var out_bars := 0     # mesh box under a letterbox bar (or past the edge)
var sph_out := 0      # body-sphere box past a frame edge
var worst := [1.0, 0.0, 1.0, 0.0]   # min top, max bottom, min left, max right (mesh)
var at := 90
var first_bad := []
var fill := 0.0       # mean mesh-box height (fraction of the screen): how big he is
var fill_min := 1.0
var jump := 0.0       # largest frame-to-frame move of the mesh box centre (screen fractions): a whip
var _prev_c := Vector2(-1, -1)

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = Fight.new(); f.cpu_flags = [true, true]; f.cine_force = true; f.no_replay = true
	f.stage = str(a[0]); f.chars = Array(str(a[1]).split(","))
	if OS.has_environment("PS_SEED"): f.seed_override = int(OS.get_environment("PS_SEED"))
	if OS.has_environment("PS_PC_AT"): at = int(OS.get_environment("PS_PC_AT"))
	root.add_child(f)

func _process(_d: float) -> bool:
	n += 1
	if n > 60 * 90:
		return _end("TIMEOUT")
	var h: Fighter = f.fighters[0]
	if f.phase == Fight.R.FIGHT: fight_n += 1
	if not given:
		if fight_n >= at and h.state in [Fighter.S.IDLE, Fighter.S.RUN] and h.is_on_floor() and not h.powered and f.cinema.kind == "":
			h.pick_gem(); h.pick_gem(); h.pick_gem()
			given = true
		return false
	var c := f.cinema
	if c.kind != "power":
		if frames > 0: return _end("")
		return false
	frames += 1
	var bx := CamCheck.points_box(f.cam, CamCheck.skin_points(h))
	var sb := CamCheck.screen_box(f.cam, h)
	var bar := 0.11 * c.bar_amt
	if bx.is_empty(): out_frame += 1; out_bars += 1
	else:
		worst = [minf(worst[0], bx[1]), maxf(worst[1], bx[3]), minf(worst[2], bx[0]), maxf(worst[3], bx[2])]
		fill += bx[3] - bx[1]; fill_min = minf(fill_min, bx[3] - bx[1])
		var cc := Vector2((bx[0] + bx[2]) * 0.5, (bx[1] + bx[3]) * 0.5)
		if _prev_c.x >= 0.0 and c.t > 0.2: jump = maxf(jump, cc.distance_to(_prev_c))   # after the 0.18 s blend-in
		_prev_c = cc
		var of: bool = bx[1] < 0.0 or bx[3] > 1.0 or bx[0] < 0.0 or bx[2] > 1.0
		var ob: bool = of or bx[1] < bar or bx[3] > 1.0 - bar
		if of: out_frame += 1
		if ob: out_bars += 1
		if (of or ob) and first_bad.size() < 4: first_bad.append("t=%.2f box %s bar %.3f" % [c.t, str(bx.map(func(v): return snappedf(v, 0.001))), bar])
	if sb.is_empty() or sb[1] < 0.0 or sb[3] > 1.0 or sb[0] < 0.0 or sb[2] > 1.0: sph_out += 1
	if OS.has_environment("PS_PC_TRACE"):
		var sp := CamCheck.skin_points(h)
		var ylo := 1e9; var yhi := -1e9; var c3 := Vector3.ZERO
		for p in sp: ylo = minf(ylo, p.y); yhi = maxf(yhi, p.y); c3 += p
		if sp.size() > 0: c3 /= sp.size()
		print("PCT t=%.3f box %s sph %s bar %.3f cam %s hero %s mesh y %.2f..%.2f centre %s clip %s %.2f" % [c.t, str(bx.map(func(v): return snappedf(v, 0.001))), str(sb.map(func(v): return snappedf(v, 0.001))), bar, str(f.cam.global_position.snapped(Vector3.ONE * 0.01)),
			str(h.global_position.snapped(Vector3.ONE * 0.01)), ylo, yhi, str(c3.snapped(Vector3.ONE * 0.01)), (h.model as PSModel).current_clip(), (h.model as PSModel).clip_pos()])
	return false

func _end(why: String) -> bool:
	if done: return true
	done = true
	var ok := why == "" and frames > 100 and out_bars == 0
	print("PC_CHECK %s %s look=%s seed=%s frames=%d out_frame=%d out_bars=%d sph_out=%d worst top %.3f bottom %.3f left %.3f right %.3f fill %.2f (min %.2f) whip %.3f %s%s %s" % [
		f.chars[0], f.stage, OS.get_environment("PS_LOOK"), OS.get_environment("PS_SEED"), frames, out_frame, out_bars, sph_out,
		worst[0], worst[1], worst[2], worst[3], fill / maxf(1, frames), fill_min, jump, why, "" if first_bad.is_empty() else str(first_bad), "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
	return true
