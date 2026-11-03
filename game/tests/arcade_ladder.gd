extends SceneTree
const QuietExit = preload("res://tests/quiet_exit.gd")
## A whole arcade run as the player meets it, both sides the game's own AI (the disc's freeze8 +0x71ED = 1 trick):
## the real Game autoload, the original ladder (Valgas > Final Valgas included), its STAGE / VS / CONTINUE screens; a lost
## fight is continued (the same opponent again, as CONTINUE? does) until the ladder is cleared. Per fight: frames, rounds
## (KO / TIME / draw), stalls (fight phase with nobody's health moving for 30 s), out-of-map frames; softlock = a screen
## or a fight phase that never ends. One line "LADDER {json}" at the end (tools/arcade_ladder.sh runs the seeds).
## PS_SEED=n PS_LADDER_P1=ryoma Godot --headless --path game --fixed-fps 60 -s res://tests/arcade_ladder.gd
const STALL_F := 1800
const SCREEN_MAX_F := 60 * 60 * 8     # no screen (a fight included) should last 8 minutes
const PHASE_MAX_F := 60 * 120          # no round phase but the fight itself lasts 2 minutes
const RUN_MAX_F := 60 * 60 * 90        # the whole run: 90 minutes of game time at most
var g: Node
var p1 := "ryoma"
var n := 0
var cur: Node = null
var cur_kind := ""
var cur_n := 0
var fights := []                       # one dict per fight
var fd := {}
var hp_last := []
var still := 0
var last_phase := -1
var phase_n := 0
var issues := []
var continues := 0
var done := false

func _initialize() -> void:
	g = root.get_node_or_null("Game")
	if OS.has_environment("PS_LADDER_P1"): p1 = OS.get_environment("PS_LADDER_P1")

func _kind(s: Node) -> String:
	if s is Fight: return "fight"
	if s != null and s.get_script() == load("res://scripts/arcade_flow.gd"): return "flow_" + str(s.get("kind"))
	if s is TitleScreen: return "title"
	if s is ResultsScreen: return "results"
	return s.get_class() if s else "none"

func _start() -> void:
	g.set("mode", "arcade")
	g.set("ladder", Roster.load_ladder())
	g.set("arcade_step", 0); g.set("arcade_time_f", 0)
	g.set("chars", [p1, ""]); g.set("cpu", [true, true])
	g.call("next_arcade_fight")

func _issue(what: String) -> void:
	issues.append("f%d %s" % [n, what])
	printerr("ISSUE: ", issues[-1])

func _end_fight() -> void:
	if fd.is_empty(): return
	fights.append(fd); fd = {}

func _physics_process(_d: float) -> bool:
	n += 1
	if n == 2: _start()
	if n <= 2 or done: return false
	var c: Node = g.get("current")
	if c != cur:
		if cur_kind == "fight": _end_fight()
		cur = c; cur_kind = _kind(c); cur_n = 0
		print("frame %d: %s (step %d)" % [n, cur_kind, int(g.get("arcade_step"))])
		if cur_kind == "fight":
			var f := c as Fight
			fd = {"step": int(g.get("arcade_step")), "p2": str(f.chars[1]), "stage": f.stage, "frames": 0, "stalls": 0,
				"oom": 0, "rounds": [], "winner": -1}
			hp_last = []; still = 0; last_phase = -1; phase_n = 0
		elif cur_kind == "flow_continue":   # P1 lost: continue against the same opponent (CONTINUE? answered)
			continues += 1
			g.set("continuing", false)
			g.set("chars", [p1, ""]); g.set("cpu", [true, true])
			g.call("next_arcade_fight")
			return false
	cur_n += 1
	if cur_n > SCREEN_MAX_F: _issue("SOFTLOCK screen %s %d frames" % [cur_kind, cur_n]); _finish(); return true
	if cur_kind == "fight" and c.is_inside_tree():
		var f := c as Fight
		fd.frames = int(fd.frames) + 1
		if f.phase != last_phase:
			last_phase = f.phase; phase_n = 0
		phase_n += 1
		if f.phase != Fight.R.FIGHT and phase_n > PHASE_MAX_F: _issue("SOFTLOCK phase %s %d frames vs %s" % [Fight.R.keys()[f.phase], phase_n, fd.p2]); _finish(); return true
		if f.phase == Fight.R.FIGHT:
			var hp := f.fighters.map(func(x): return x.hp)
			if hp == hp_last: still += 1
			else: still = 0
			hp_last = hp
			if still == STALL_F: fd.stalls = int(fd.stalls) + 1; _issue("STALL 30 s no damage vs %s on %s (step %d)" % [fd.p2, fd.stage, fd.step])
			if still >= STALL_F and (still - STALL_F) % 300 == 0:   # where they are while nothing lands
				print("  STALLAT f%d " % n, " | ".join(f.fighters.map(func(x): return "%s %s st%d gst%d %s hp%d carry %s" % [x.char_id,
					str(x.global_position.snapped(Vector3.ONE * 0.01)), x.state, x.gst, x.gmo, x.hp, str(x.carry != null)])))
				if OS.has_environment("PS_STALL_DEBUG"):   # the fight's phase, each CPU's interrupt state, what is under each fighter
					print("  STALLFIGHT phase %d pf %d mv_ok %d cine '%s' round %d timer %.1f cpu %s" % [f.phase, f.pf, f.mv_ok, f.cinema.kind if f.cinema else "-", f.round_no, f.timer, str(f.cpu_flags)])
					for cg in f.cpus:
						if cg is CPUGame: print("  STALLCPU %s active %d intlv 0x%x mode 0x%x ip %s/%d timer %d go %s stack %d pad 0x%x stuck %d pin %d detour %s" % [cg.me.char_id, cg.active, cg.intlv, cg.mode, str(cg.ip_s), cg.ip_i, cg.timer, str(cg.go), cg.stack.size(), cg.pad, cg.stuck, cg.pin_n, str(cg.detour_on)])
					for x in f.fighters:
						var ss: PhysicsDirectSpaceState3D = x.get_world_3d().direct_space_state
						var q := PhysicsRayQueryParameters3D.create(x.global_position + Vector3.UP * 0.3, x.global_position + Vector3.DOWN * 0.6, 0xFFFFFFFF, [x.get_rid()])
						var h := ss.intersect_ray(q)
						print("  STALLDBG %s rx_on %s grounded %s on_floor %s v %s st_t %.2f gst_t %d under %s" % [x.char_id, str(x.rx_on), str(x.grounded()), str(x.is_on_floor()), str(x.velocity.snapped(Vector3.ONE * 0.01)), x.state_t, x.gst_t, ("%s y %.2f layer %d" % [h.collider.name, h.position.y, h.collider.collision_layer]) if not h.is_empty() else "none"])
			if f.arena and f.arena.has_method("fighter_out_of_map"):
				for x in f.fighters:
					if f.arena.fighter_out_of_map(x): fd.oom = int(fd.oom) + 1
		fd.rounds = f.round_log.duplicate()
		fd.winner = 0 if f.wins[0] > f.wins[1] else (1 if f.wins[1] > f.wins[0] else -1)
	var res: Dictionary = g.get("last_result") if g.get("last_result") is Dictionary else {}
	if res.get("arcade_clear", false) or cur_kind == "results" or cur_kind == "title":
		if cur_kind == "title" and not res.get("arcade_clear", false): _issue("run ended on the title without a clear")
		_finish(); return true
	if n > RUN_MAX_F: _issue("RUN too long (%d frames)" % n); _finish(); return true
	return false

func _finish() -> void:
	if done: return
	done = true
	_end_fight()
	var time_rounds := 0; var draws := 0; var ko := 0
	for f in fights:
		for r in f.rounds:
			if str(r.how) == "TIME": time_rounds += 1
			if int(r.winner) < 0: draws += 1
			if str(r.how) == "KO": ko += 1
	var out := {"p1": p1, "seed": OS.get_environment("PS_SEED"), "frames": n, "fights": fights.size(), "continues": continues,
		"cleared": (g.get("last_result") as Dictionary).get("arcade_clear", false) if g.get("last_result") is Dictionary else false,
		"ko_rounds": ko, "time_rounds": time_rounds, "draw_rounds": draws, "issues": issues,
		"per_fight": fights.map(func(f): return [f.step, f.p2, f.stage, f.frames, f.rounds.size(), f.winner, f.stalls, f.oom])}
	print("LADDER " + JSON.stringify(out))
	QuietExit.drain(root)   # BUG-38: let the audio thread free the sounds before quit (--fixed-fps outruns it)
	quit(0 if issues.is_empty() else 1)
