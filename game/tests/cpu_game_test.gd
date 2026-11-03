extends SceneTree
## The ported original CPU (scripts/cpu_game.gd) driving both fighters of a real match, headless. Reports what the
## AI did in the numbers tools/cpu_stats.py gives for the disc (game/assets/fidelity/cpu_stats.json): presses,
## jumps, spacing, the AI's Mode / Table shares, plus a check that every frame ran (no script error, no stuck yield).
##   Godot --headless --path game --fixed-fps 60 -s res://tests/cpu_game_test.gd   (PS_TEST_CHARS=a,b PS_STAGE=stg00
##   PS_CPU_LEVEL=9 PS_FRAMES=3600 PS_SEED=1)

var fight: Fight
var frames := 0
var max_frames := 3600
var swapped := false
var cpus: Array = []
var st := [{}, {}]
var t0 := 0
var match_done := false
var match_w := -2
var _tr0 := int(OS.get_environment("PS_TRACE_F0")) if OS.has_environment("PS_TRACE_F0") else 0      # PS_TRACE window
var _tr1 := int(OS.get_environment("PS_TRACE_F1")) if OS.has_environment("PS_TRACE_F1") else 600
var log_f: FileAccess = null   # PS_CPU_LOG=file.jsonl: per-frame rows in tools/cpu_stats.py's schema (stats / compare)

func _initialize() -> void:
	if not CPUGame.load_data():
		print("FAIL cpu_ai.json missing"); quit(1); return
	max_frames = int(OS.get_environment("PS_FRAMES")) if OS.has_environment("PS_FRAMES") else 3600
	CPUGame.rand_state = int(OS.get_environment("PS_SEED")) if OS.has_environment("PS_SEED") else 1
	fight = Fight.new(); fight.test_mode = true; fight.cpu_flags = [true, true]
	fight.chars = ["falcon", "ryoma"]
	if OS.has_environment("PS_TEST_CHARS"): fight.chars = Array(OS.get_environment("PS_TEST_CHARS").split(","))
	if OS.has_environment("PS_STAGE"): fight.stage = OS.get_environment("PS_STAGE")
	root.add_child(fight)
	if OS.has_environment("PS_MATCH"):   # play to the match result (max PS_FRAMES): the no-stall check per stage
		fight.match_over.connect(func(w: int, _st: Array): match_w = w; match_done = true)
	for i in 2: st[i] = {"press": {}, "jumps": 0, "modes": {}, "tables": {}, "dist": 0.0, "n": 0, "pads": 0, "ops": 0}
	t0 = Time.get_ticks_msec()
	if OS.has_environment("PS_CPU_LOG"): log_f = FileAccess.open(OS.get_environment("PS_CPU_LOG"), FileAccess.WRITE)

func _swap() -> void:
	var lvl := int(OS.get_environment("PS_CPU_LEVEL")) if OS.has_environment("PS_CPU_LEVEL") else 9
	for i in 2:
		var f: Fighter = fight.fighters[i]
		f.cpu_level = lvl
		var c := CPUGame.new(f, fight.arena, lvl)
		c.fight_index = int(OS.get_environment("PS_FIGHT")) if OS.has_environment("PS_FIGHT") else 0
		fight.cpus[i] = c
		f.ctrl = c.input
		cpus.append(c)
	swapped = true

func _process(_dt: float) -> bool:
	if not swapped:
		if fight.fighters.size() == 2: _swap()
		return false
	frames += 1
	if log_f: _log_row()
	for i in 2:
		var c: CPUGame = cpus[i]
		var s: Dictionary = st[i]
		if OS.has_environment("PS_TRACE") and i == int(OS.get_environment("PS_TRACE")) and frames >= _tr0 and frames < _tr1:
			var cc: Array = c._code()
			var tp := CPUGame.pos_cm(c.me)
			print("f%d %s:%d op %s ph %d pad %x st %d mode %x tbl %d stack %d fired %x pos (%d %d %d) seen (%d %d %d) tpos (%d %d %d)" % [frames, c.ip_s, c.ip_i,
				str(cc[c.ip_i]) if c.ip_i < cc.size() else "-", c.phase, c.pad, CPUGame.gstate(c.me), c.mode, c.table, c.stack.size(),
				c.fired, tp.x, tp.y, tp.z, c.seen.x, c.seen.y, c.seen.z, c.tpos.x, c.tpos.y, c.tpos.z])
		if OS.has_environment("PS_TRACE_POS") and frames % 30 == 0:
			var pp := CPUGame.pos_cm(c.me)
			var col: KinematicCollision3D = c.me.get_last_slide_collision()
			print("f%d P%d mode %x tbl %d st %d pos (%d %d %d) tpos (%d %d %d) stuck %d pad %x vcm %s wall %s hit %s" % [frames, i + 1, c.mode, c.table,
				CPUGame.gstate(c.me), pp.x, pp.y, pp.z, c.tpos.x, c.tpos.y, c.tpos.z, c.stuck, c.pad, str(c.me.vcm.round()),
				c.me.is_on_wall(), (str(col.get_collider().name) + str((col.get_position() * 100).round())) if col else "-"])
		s.n += 1
		if c.pad != 0: s.pads += 1
		for b in [[0x400, "punch"], [0x200, "kick"], [0x4, "jump"], [0x600, "action"]]:
			if c.pad & int(b[0]) == int(b[0]) and c.prev & int(b[0]) != int(b[0]): s.press[b[1]] = int(s.press.get(b[1], 0)) + 1
		var mk := "%02x" % c.mode
		s.modes[mk] = int(s.modes.get(mk, 0)) + 1
		var tk := "%02x/%d" % [c.mode, c.table]
		s.tables[tk] = int(s.tables.get(tk, 0)) + 1
		var me: Fighter = fight.fighters[i]; var op: Fighter = fight.fighters[1 - i]
		s.dist += Vector2(me.global_position.x - op.global_position.x, me.global_position.z - op.global_position.z).length() * 100.0
	if frames >= max_frames or fight.fighters.is_empty() or match_done:
		_report(); return true
	return false

func _log_row() -> void:
	var row: Dictionary = fight.tape_row()
	row["f"] = frames
	row["phase"] = 3 if fight.phase == Fight.R.FIGHT else 1
	row["lvl"] = cpus[0].level
	row["clock"] = int(row.get("timer", 0))
	for i in 2:
		var c: CPUGame = cpus[i]
		var p: Dictionary = row.p[i]
		p["ch"] = c.ch; p["mode"] = c.mode; p["intlv"] = c.intlv; p["mask"] = c.mask; p["tbl"] = c.table
		p["pad"] = c.pad; p["prs"] = c.pad & ~c.prev; p["int"] = c.fired
		p["tgt"] = 0 if c.target == null or c.target is Fighter else 1
	log_f.store_line(JSON.stringify(row))

func _report() -> void:
	if log_f: log_f.close()
	var mins := frames / 3600.0
	var okc := true
	for i in 2:
		var s: Dictionary = st[i]
		var c: CPUGame = cpus[i]
		var pm := {}
		for k in s.press: pm[k] = snappedf(s.press[k] / mins, 0.1)
		var modes := {}
		for k in s.modes: modes[k] = snappedf(float(s.modes[k]) / s.n, 0.001)
		var tabs: Array = s.tables.keys()
		tabs.sort_custom(func(a, b): return s.tables[a] > s.tables[b])
		var top := {}
		for k in tabs.slice(0, 10): top[k] = snappedf(float(s.tables[k]) / s.n, 0.001)
		print("P%d %s L%d: presses/min %s pad frames %.2f spacing %.0f cm" % [i + 1, c.me.char_id, c.level, pm,
			float(s.pads) / s.n, s.dist / s.n])
		print("   modes ", modes)
		print("   mode/table ", top)
		if s.pads == 0: okc = false
	if OS.has_environment("PS_MATCH"):
		print("match: %s winner P%d, rounds %s" % ["over" if match_done else "NOT OVER", match_w + 1, str(fight.round_log)])
	print("cpu_game: %d frames, wall %d ms -> %s" % [frames, Time.get_ticks_msec() - t0, "PASS" if okc else "FAIL (no input)"])
