extends SceneTree
## Final Valgas's own AI (scripts/cpu_fv.gd, 0x0C08D5CE) against the ported normal CPU (cpu_game.gd) on his arena,
## headless, the way the disc logs were taken (tools/fv_log.py: P1 = the game's AI, level frozen, fight index 8).
##   Godot --headless --path game --fixed-fps 60 -s res://tests/cpu_fv_test.gd
##   PS_TEST_CHARS=falcon PS_STAGE=stga0 PS_CPU_LEVEL=29 PS_FRAMES=21000 PS_SEED=1 PS_MATCH=1
##   PS_CPU_LOG=file.jsonl   per-frame rows in tools/cpu_stats.py's schema (P2 mode = 0x10 * state + command)
##   PS_TRACE=1              Final Valgas's block every frame for the first 900 frames

var fight: Fight
var frames := 0
var max_frames := 21000
var swapped := false
var cpus: Array = []
var t0 := 0
var match_done := false
var match_w := -2
var log_f: FileAccess = null
var presses := {}
var attacks := {}
var cmd_frames := {}
var last_st := ""

func _initialize() -> void:
	if not CPUGame.load_data() or not CPUFV.load_data():
		print("FAIL cpu_ai.json / fv_ai.json missing"); quit(1); return
	max_frames = int(OS.get_environment("PS_FRAMES")) if OS.has_environment("PS_FRAMES") else 21000
	CPUGame.rand_state = int(OS.get_environment("PS_SEED")) if OS.has_environment("PS_SEED") else 1
	fight = Fight.new(); fight.test_mode = true; fight.cpu_flags = [true, true]
	var p1 := OS.get_environment("PS_TEST_CHARS") if OS.has_environment("PS_TEST_CHARS") else "falcon"
	fight.chars = [p1.split(",")[0], "finalvalgas"]
	fight.stage = OS.get_environment("PS_STAGE") if OS.has_environment("PS_STAGE") else "stga0"
	root.add_child(fight)
	if OS.has_environment("PS_MATCH"):
		fight.match_over.connect(func(w: int, _st: Array): match_w = w; match_done = true)
	t0 = Time.get_ticks_msec()
	if OS.has_environment("PS_CPU_LOG"): log_f = FileAccess.open(OS.get_environment("PS_CPU_LOG"), FileAccess.WRITE)

func _swap() -> void:
	var lvl := int(OS.get_environment("PS_CPU_LEVEL")) if OS.has_environment("PS_CPU_LEVEL") else 29
	var f1: Fighter = fight.fighters[0]
	f1.cpu_level = lvl
	var c := CPUGame.new(f1, fight.arena, lvl)
	c.fight_index = 8
	fight.cpus[0] = c; f1.ctrl = c.input; cpus.append(c)
	var f2: Fighter = fight.fighters[1]
	f2.cpu_level = lvl
	if OS.has_environment("PS_FV_OLD"):   # the remaster's old boss AI (cpu.gd _boss_tick): the "before" numbers
		cpus.append(null); swapped = true; return
	var v := CPUFV.new(f2, fight.arena, lvl)
	fight.cpus[1] = v; f2.ctrl = v.input; cpus.append(v)
	swapped = true

func _process(_dt: float) -> bool:
	if not swapped:
		if fight.fighters.size() == 2: _swap()
		return false
	frames += 1
	var v: CPUFV = cpus[1]
	if log_f: _log_row()
	var me: Fighter = fight.fighters[1]
	var s: String = str(Fighter.S.keys()[me.state]) + ":" + me.cur_attack
	if s != last_st and me.state == Fighter.S.ATTACK: attacks[me.cur_attack] = int(attacks.get(me.cur_attack, 0)) + 1
	last_st = s
	if OS.has_environment("PS_OOM_OBJ") and frames % 60 == 0:   # which gem / throwable is out of the map (run_tests' count)
		var ar: Arena = fight.arena
		for g in ar.gems:
			if is_instance_valid(g) and ar.out_of_map((g as Node3D).global_position, CamCheck.OBJ_TOL): print("f%d gem out at %s" % [frames, str(((g as Node3D).global_position * 100).round())])
		for pp in ar.props:
			var pr := pp as Prop
			if pr == null or pr.state not in [Prop.REST, Prop.FLYING]: continue
			if pr.state == Prop.REST and pr.global_position.is_equal_approx(pr.home): continue
			if ar.out_of_map(pr.global_position + Vector3.UP * 0.1, CamCheck.OBJ_TOL): print("f%d prop %s out at %s state %d home %s" % [frames, pr.name, str((pr.global_position * 100).round()), pr.state, str((pr.home * 100).round())])
	if v == null:
		if frames >= max_frames or fight.fighters.is_empty() or match_done: _report(); return true
		return false
	if OS.has_environment("PS_TRACE") and frames < 900:
		print("f%d st %d sub %d cmd %d ph %d n %d lst %s:%d band %d zone %d/%d lock %d pad %x prs %x fst %s" % [frames, v.st, v.sub,
			v.cmd, v.ph, v.n, v.lst, v.lpos, v.band, v.zone_at, v.zone(), v.lock, v.pad, v.pressed,
			Fighter.S.keys()[v.me.state]])
	if v.pressed != 0: presses["%x" % v.pressed] = int(presses.get("%x" % v.pressed, 0)) + 1
	var k := "%d/%d" % [v.st, v.cmd]
	cmd_frames[k] = int(cmd_frames.get(k, 0)) + 1
	if frames >= max_frames or fight.fighters.is_empty() or match_done:
		_report(); return true
	return false

func _log_row() -> void:
	var row: Dictionary = fight.tape_row()
	row["f"] = frames
	row["phase"] = 3 if fight.phase == Fight.R.FIGHT else 1
	row["lvl"] = cpus[0].level
	row["clock"] = int(row.get("timer", 0))
	var c: CPUGame = cpus[0]
	var p: Dictionary = row.p[0]
	p["ch"] = c.ch; p["mode"] = c.mode; p["intlv"] = c.intlv; p["mask"] = c.mask; p["tbl"] = c.table
	p["pad"] = c.pad; p["prs"] = c.pad & ~c.prev
	p["tgt"] = 0 if c.target == null or c.target is Fighter else 1
	var v: CPUFV = cpus[1]
	var q: Dictionary = row.p[1]
	q["ch"] = 10; q["tgt"] = 0
	if v == null: q["mode"] = 0; q["intlv"] = 0; q["mask"] = 0; q["tbl"] = 0; q["pad"] = 0; q["prs"] = 0
	else:
		q["mode"] = 0x10 * v.st + v.cmd; q["intlv"] = v.band; q["mask"] = v.lock; q["tbl"] = v.li
		q["pad"] = v.pad; q["prs"] = v.pressed
		q["fv"] = [v.st, v.sub, v.ph, v.cmd, v.zone_at, v.n, v.lst, v.lpos]
	log_f.store_line(JSON.stringify(row))

func _report() -> void:
	if log_f: log_f.close()
	var mins := frames / 3600.0
	var pm := {}
	for k in presses: pm[k] = snappedf(presses[k] / mins, 0.1)
	var am := {}
	for k in attacks: am[k] = snappedf(attacks[k] / mins, 0.1)
	var cf := {}
	for k in cmd_frames: cf[k] = snappedf(float(cmd_frames[k]) / frames, 0.001)
	print("Final Valgas L%d: presses/min %s attacks/min %s state/command shares %s" % [cpus[0].level, pm, am, cf])
	if OS.has_environment("PS_MATCH"):
		print("match: %s winner P%d, rounds %s" % ["over" if match_done else "NOT OVER", match_w + 1, str(fight.round_log)])
	var okc := not presses.is_empty() or cpus[1] == null
	print("cpu_fv: %d frames, wall %d ms -> %s" % [frames, Time.get_ticks_msec() - t0, "PASS" if okc else "FAIL (no press)"])
