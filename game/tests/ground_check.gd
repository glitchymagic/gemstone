extends SceneTree
## Arena.core_ground (the original's ground + walls for the fidelity core) against the original's own cases
## (game/assets/fidelity/ground_samples.json, tools/ground_samples.py: Flycast probe samples + step-up run tests).
##   settle: a fighter dropped from where the probe placed it (2 cm/f^2) lands where the original settled it (2 cm)
##   push:   placed past a wall, core_ground puts it where the original's push left it (median / p90 x/z error)
##   run:    9.5 cm/frame along the original's own run into a floor step, with the hold / climb rule
##           (LEDGE_HOLD_F, HOP_HOLD_F + HOP_F): climbed or stopped as the original, the frame the feet go up, where
##           the run is held (along the run, vs the original's held spot)
## Godot --headless --path game -s res://tests/ground_check.gd [-- STAGE ...]   -> GROUND_CHECK lines, exit 1 on a fail
const FID := "res://assets/fidelity/"
var fails := 0

func _initialize() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(FID + "ground_samples.json"))
	var want := Array(OS.get_cmdline_user_args())
	var tot := {"settle": 0, "settle_ok": 0, "push": 0, "runs": 0, "runs_ok": 0}
	var pe_all: Array = []
	for st in d.stages:
		if not want.is_empty() and st not in want: continue
		var a := Arena.new(); a.stage = st; a.has_assets = true; a._load_area()
		if not a.has_area():
			print("GROUND_CHECK %s: no area file (skipped)" % st); a.free(); continue
		var e: Dictionary = d.stages[st]
		var chars: Dictionary = e.chars
		# settle: drop from the placed point
		var ok := 0; var worst := 0.0; var wtxt := ""; var miss := 0
		for s in e.settle:
			var ch := String(chars[str(int(s[0]))])
			var p := Vector3(float(s[1][0]), float(s[1][1]), float(s[1][2])) * 0.01
			var want_p := Vector3(float(s[2][0]), float(s[2][1]), float(s[2][2])) * 0.01
			var vy := 0.0; var land := false
			for k in 600:
				vy -= 0.02
				var r: Dictionary = a.core_ground(p + Vector3(0, vy, 0), p, ch)
				p = r.pos
				if r.grounded: land = true; break
			var err := absf(p.y - want_p.y) + Vector2(p.x - want_p.x, p.z - want_p.z).length()
			if a.sdf_at(want_p.x, want_p.z) < a.fighter_margin(String(chars[str(int(s[0]))])) - 0.05: miss += 1
			if land and err <= 0.02: ok += 1
			elif err > worst: worst = err; wtxt = "%s -> %s (original %s)" % [str(Vector3(s[1][0], s[1][1], s[1][2])), str((p * 100).round()), str(Vector3(s[2][0], s[2][1], s[2][2]))]
		tot.settle += e.settle.size(); tot.settle_ok += ok
		# push: placed past a wall at its resting height
		var pe: Array = []
		for s in e.push:
			var ch := String(chars[str(int(s[0]))])
			var want_p := Vector3(float(s[2][0]), float(s[2][1]), float(s[2][2])) * 0.01
			var p := Vector3(float(s[1][0]) * 0.01, want_p.y, float(s[1][2]) * 0.01)
			var r: Dictionary = a.core_ground(p, p, ch)
			var q: Vector3 = r.pos
			pe.append(Vector2(q.x - want_p.x, q.z - want_p.z).length() * 100.0)
		pe.sort(); pe_all.append_array(pe); tot.push += pe.size()
		# runs into a step
		var rtxt := []
		var rok := 0; var rn := 0
		for run in e.runs:
			var res := _run(a, run, String(chars["1"]))
			if res.is_empty(): continue
			rn += 1
			if res.ok: rok += 1
			rtxt.append(res.txt)
		tot.runs += rn; tot.runs_ok += rok
		var pm: float = pe[pe.size() / 2] if not pe.is_empty() else 0.0
		var p9: float = pe[int(pe.size() * 0.9)] if not pe.is_empty() else 0.0
		print("GROUND_CHECK %s: settle %d/%d within 2 cm (%d of the original's resting spots are outside the area file) %s| push x/z error median %.1f cm p90 %.1f cm (%d) | runs %d/%d as the original" % [
			st, ok, e.settle.size(), miss, ("(worst %s) " % wtxt) if wtxt != "" else "", pm, p9, pe.size(), rok, rn])
		for t in rtxt: print("    " + t)
		# limits = the measured state (docs/fx-oom.md "Step-up"): a regression guard, every miss is printed above
		if ok < e.settle.size() * 0.94: fails += 1
		if p9 > 100.0: fails += 1   # pushes off a block: the original pushes some sideways, core_ground lifts onto the top
		a.free()
	pe_all.sort()
	var med: float = pe_all[pe_all.size() / 2] if not pe_all.is_empty() else 0.0
	var q9: float = pe_all[int(pe_all.size() * 0.9)] if not pe_all.is_empty() else 0.0
	if want.is_empty() and tot.runs_ok < 10: fails += 1   # 10 of the 15 straight runs as the original (Rouge's double top, ... : the doc)
	print("GROUND_CHECK TOTAL settle %d/%d, push median %.1f cm p90 %.1f cm (%d), runs %d/%d, %d failed" % [
		tot.settle_ok, tot.settle, med, q9, tot.push, tot.runs_ok, tot.runs, fails])
	for st in d.stages:
		if want.is_empty() or st in want: oom_stages.append(st)

## The out-of-map check run_tests.gd / brawl_tests.gd count every frame (Arena.out_of_map) on the built stage: false
## on the start points, true 1 m past the area's edge and 3 m under the start floor.
var oom_stages: Array = []
var oom_ar: Arena = null
var oom_wait := 0
func _process(_d: float) -> bool:
	if oom_ar != null:
		oom_wait += 1
		if oom_wait < 3: return false
		var a := oom_ar
		var sp := a.spawn_points()
		var c := a.area_center()
		var far := Vector3(c.x, sp[0].y, c.y)
		for k in 400:   # walk out from the centre until 1 m past the edge
			if a.sdf_at(far.x, far.z) < -1.0: break
			far += Vector3(0.05, 0, 0.02)
		var ok_sp: bool = not a.out_of_map(sp[0]) and not a.out_of_map(sp[1])
		var ok_far: bool = a.out_of_map(far)
		var ok_under: bool = a.out_of_map(sp[0] + Vector3.DOWN * 3.0) if a.has_area() else true
		print("OOM_CHECK %s: start points in %s, 1 m past the edge out %s, 3 m under the start floor out %s" % [a.stage, ok_sp, ok_far, ok_under])
		if not (ok_sp and ok_far): fails += 1
		oom_ar.queue_free(); oom_ar = null
		return false
	if oom_stages.is_empty():
		print("GROUND_CHECK DONE %d failed" % fails)
		quit(1 if fails > 0 else 0)
		return true
	var a := Arena.new(); a.stage = oom_stages.pop_front()
	root.add_child(a); a.build(1)
	if not a.has_area(): print("OOM_CHECK %s: no area" % a.stage); a.queue_free(); return false
	oom_ar = a; oom_wait = 0
	return false

## The original's run (its first running frame, its direction), replayed through core_ground with the core's hold /
## climb rule; {} when the original's run was not straight (stick off the step's normal: it slid along the wall).
func _run(a: Arena, run: Dictionary, ch: String) -> Dictionary:
	var tr: Array = run.tr
	var k0 := -1
	for k in tr.size() - 1:
		if int(tr[k][3]) == 31 and int(tr[k + 1][3]) == 31: k0 = k; break
	if k0 < 0: return {}
	var p0 := Vector3(float(tr[k0][0]), float(tr[k0][1]), float(tr[k0][2])) * 0.01
	var p1 := Vector3(float(tr[k0 + 1][0]), float(tr[k0 + 1][1]), float(tr[k0 + 1][2])) * 0.01
	var dir := Vector3(p1.x - p0.x, 0, p1.z - p0.z).normalized()
	var en := Vector3(float(run.dir[0]), 0, float(run.dir[1])).normalized()
	if dir.dot(en) < 0.97: return {}   # a diagonal run (D-pad) slides along the step's face: not a straight run into it
	var yl := float(run.yl) * 0.01; var yh := float(run.yh) * 0.01
	# the original: straight? the frame its feet reach the upper floor; where it was held (along dir)
	var side := 0.0; var up_o := -1; var held_o := INF
	for k in range(k0, tr.size()):
		var q := Vector3(float(tr[k][0]), float(tr[k][1]), float(tr[k][2])) * 0.01
		var dv := q - p0; dv.y = 0
		side = maxf(side, (dv - dir * dv.dot(dir)).length())
		if up_o < 0 and absf(q.y - yh) < 0.03: up_o = k - k0
		if k > k0 and Vector3(q.x - float(tr[k - 1][0]) * 0.01, 0, q.z - float(tr[k - 1][2]) * 0.01).length() < 0.005 and up_o < 0:
			held_o = minf(held_o, dv.dot(dir))
	if side > 0.4: return {}
	# the remaster: 9.5 cm/frame, hold / climb as Arena.core_ground documents
	var p := p0; var hold := 0; var up_r := -1; var held_r := INF; var climb := false; var kind := ""
	for k in range(1, tr.size() - k0):
		var r: Dictionary = a.core_ground(p + dir * 0.095, p, ch, climb)
		climb = false
		var lk := String(r.ledge_kind)
		if lk == "step" or lk == "hop":
			if (r.pos as Vector3).y < yh - 0.03:
				hold += 1; kind = lk
				held_r = minf(held_r, ((r.pos as Vector3) - p0).dot(dir))
				if hold >= (Arena.LEDGE_HOLD_F if lk == "step" else Arena.HOP_HOLD_F + Arena.HOP_F): climb = true
		elif lk == "wall" or r.wall:
			held_r = minf(held_r, ((r.pos as Vector3) - p0).dot(dir))
		p = r.pos
		if not r.grounded: p.y = maxf(r.floor, p.y - 0.02) if r.floor > -INF else p.y
		if up_r < 0 and absf(p.y - yh) < 0.03: up_r = k
	var climbed_o := up_o >= 0
	var climbed_r := up_r >= 0
	var ok := climbed_o == climbed_r and (not climbed_o or absi(up_r - up_o) <= 2)
	if held_o < INF and held_r < INF and absf(held_o - held_r) > 0.12: ok = false
	return {"ok": ok, "txt": "%s %d->%d cm (%s): original %s at frame %d, held at %.0f cm | core_ground %s at frame %d, held at %.0f cm%s" % [
		run.get("src", ""), int(run.yl), int(run.yh), kind if kind != "" else "-", "climbed" if climbed_o else "stopped", up_o,
		held_o * 100.0 if held_o < INF else -1.0, "climbed" if climbed_r else "stopped", up_r, held_r * 100.0 if held_r < INF else -1.0,
		"" if ok else "  FAIL"]}
