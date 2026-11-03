extends RefCounted
## Battle Royale, headless (after the theater tests in run_tests.gd): team round rule, a 4-CPU free-for-all and a 2v2
## on this run's stage: spawn points, everyone fights, downed fighters stay down, no friendly fire, the camera keeps
## everyone in view, CPU target choice, both matches finish.

var t: SceneTree
var fight: Fight
var n := 0
var step := 0
var finished := false
var hitters := {}
var friendly := 0
var in_view := 0
var samples := 0
var stayed_down := true
var over := false
var stage := ""
var base: Array = []

func _init(runner: SceneTree, chars: Array, p_stage: String) -> void:
	t = runner; stage = p_stage
	for c in chars: if not Roster.is_boss(c): base.append(c)
	for c in ["wangtang", "ayame", "gunrock", "rouge"]:
		if base.size() < 4 and not c in base: base.append(c)

func check(c: bool, what: String) -> void:
	t.call("check", c, what)

func _start(teams: Array) -> void:
	hitters = {}; friendly = 0; in_view = 0; samples = 0; over = false; stayed_down = true; oom = 0; oom_n = 0; oom_at = ""
	fight = Fight.new(); fight.test_mode = true
	fight.chars = base.duplicate(); fight.cpu_flags = [true, true, true, true]; fight.teams = teams.duplicate()
	if stage != "": fight.stage = stage
	fight.match_over.connect(func(_w, _s): over = true)
	t.root.add_child(fight)
	for f in fight.fighters:
		f.damaged.connect(func(v: Fighter, _d: int):
			if v.last_hit_by:
				hitters[v.last_hit_by.pid] = true
				if v.last_hit_by.team == v.team: friendly += 1)

var oom := 0
var oom_n := 0
var oom_at := ""
var _oom_run := {}
var _trb := OS.get_environment("PS_TRACE_B").split("-") if OS.has_environment("PS_TRACE_B") else PackedStringArray()
func _watch() -> void:
	oom_n += 1   # out of the map (run_tests.gd _watch_map): every frame, every phase
	var dbg := OS.has_environment("PS_OOM_DEBUG")
	var counted := false
	for f in fight.fighters:
		var o := fight.arena.fighter_out_of_map(f, fight.cinema != null and fight.cinema.replaying())
		if dbg:   # PS_OOM_DEBUG: each fighter's first frame out, every 60th frame of a run, and the frame it ends
			var rn: int = _oom_run.get(f, 0)
			if o and (rn == 0 or rn % 60 == 0) or (not o and rn > 0):
				var p := f.global_position
				print("OOMB n%d %s %s %s st%d gst%d gmo %s v%s sdf %.2f air %.2f lv %s run %d" % [oom_n, "out" if o else "back", f.char_id,
					str(p.snapped(Vector3.ONE * 0.01)), f.state, f.gst, f.gmo, str(f.velocity.snapped(Vector3.ONE * 0.1)),
					fight.arena.sdf_at(p.x, p.z), fight.arena.air_sdf_at(p.x, p.z), str(fight.arena.floor_levels(p.x, p.z)), rn])
			_oom_run[f] = (rn + 1) if o else 0
		if _trb.size() == 2 and oom_n >= int(_trb[0]) and oom_n <= int(_trb[1]):   # PS_TRACE_B=a-b: every fighter, those frames
			var p := f.global_position
			print("TRACEB n%d %s %s st%d gst%d gmo %s v%s sdf %.2f lv %s floor %s" % [oom_n, f.char_id, str(p.snapped(Vector3.ONE * 0.01)),
				f.state, f.gst, f.gmo, str(f.velocity.snapped(Vector3.ONE * 0.1)), fight.arena.sdf_at(p.x, p.z),
				str(fight.arena.floor_levels(p.x, p.z)), str(f.is_on_floor())])
		if o and not counted:
			oom += 1; counted = true
			if oom_at == "": oom_at = "%s at %s (state %d gst %d atk %s pc %s floor %s)" % [f.char_id, str(f.global_position.snapped(Vector3.ONE * 0.01)), f.state, f.gst, f.cur_attack, str(f.powered), str(f.is_on_floor())]
			if not dbg: break
	if fight.phase != Fight.R.FIGHT: return
	if n % 30 == 0:
		for f in fight.fighters:
			if f.hp <= 0: continue
			samples += 1
			if fight.cam.is_position_in_frustum(f.global_position + Vector3.UP * 0.9): in_view += 1
			elif OS.has_environment("PS_DEBUG"):
				var lp := fight.cam.global_transform.affine_inverse() * (f.global_position + Vector3.UP * 0.9)
				print("OUT P%d local %s tgt %s cam %s" % [f.pid + 1, str(lp.snapped(Vector3.ONE * 0.1)), str(fight.cam_tgt.snapped(Vector3.ONE * 0.1)), str(fight.cam.global_position.snapped(Vector3.ONE * 0.1))])
	for f in fight.fighters:   # a downed fighter in a round still going stays down
		if f.hp <= 0 and f.state not in [Fighter.S.DOWN, Fighter.S.KO] and not f._shot_this_frame():   # a shot's KO: the reaction starts next frame (disc)
			if stayed_down: print("NOT-DOWN %s hp %d state %s gst %d gmo %s powered %s rx %s phase %s tail %d thr %s pc %s/%s held %s hist %s now %d" % [f.char_id, f.hp, Fighter.S.keys()[f.state], f.gst, f.gmo, f.powered, f.rx_on, f.rx_phase, f.rx_tail.size(), f.thr_on, f.pc_on, f.pc_kind, str(f.held_by != null), str(f.gst_hist), Engine.get_physics_frames()])
			stayed_down = false

func tick() -> void:
	n += 1
	match step:
		0:
			print("== battle royale")
			check(Rules.team_round_winner([500, 0, 0, 0], [0, 1, 2, 3]) == 0, "last one standing wins the round")
			check(Rules.team_round_winner([300, 0, 200, 150], [0, 0, 1, 1]) == 1, "time over: the team with more health")
			check(Rules.team_round_winner([0, 0, 0, 0], [0, 1, 2, 3]) == -1, "nobody standing = draw")
			_start([0, 1, 2, 3])
			step = 1
		1:
			var sp := fight.arena.spawn_points_n(4)
			var apart := true
			for i in 4:
				for j in range(i + 1, 4):
					if Vector2(sp[i].x - sp[j].x, sp[i].z - sp[j].z).length() < 1.5: apart = false
			check(sp.size() == 4 and apart, "4 start points, apart (%s)" % str(sp.map(func(p): return Vector2(p.x, p.z).snapped(Vector2.ONE * 0.1))))
			check(sp.all(func(p): return not fight.arena.out_of_map(p)), "4 start points on the floor inside the playable area")
			check(fight.fighters.size() == 4 and fight.fighters[0].enemies.size() == 3, "4 fighters, 3 enemies each")
			# target choice: a CPU that hunts stones goes after the one holding two
			var c0: CPU = fight.cpus[0]
			c0.style = "gems"
			fight.fighters[2].gems = 2
			c0._pick_target()
			check(fight.fighters[0].opponent == fight.fighters[2], "CPU goes after the fighter holding two stones")
			fight.fighters[2].gems = 0
			step = 2
		2:
			_watch()
			if over or n > 60 * 60 * 12:   # 4 fighters: up to 5 rounds of the disc's 99 s clock (each one 1 win, then the decider)
				check(over, "free-for-all match finished")
				check(hitters.size() >= 3, "at least 3 of 4 fighters landed hits (%d)" % hitters.size())
				check(stayed_down, "downed fighters stay down until the round ends")
				check(samples > 0 and float(in_view) / samples > 0.9, "camera keeps everyone in view (%d / %d)" % [in_view, samples])
				check(fight.round_log.any(func(r): return r.how == "KO") or hitters.size() >= 3, "they fight: a KO or hits all round")
				var ends := fight.round_log.map(func(r): return r.how)
				print("  FFA rounds: ", fight.round_log.map(func(r): return [r.winner, r.how]))
				check(oom == 0, "free-for-all: no fighter out of the map (%d of %d frames) %s" % [oom, oom_n, oom_at])
				fight.queue_free()
				_start([0, 0, 1, 1])
				step = 3
		3:
			_watch()
			if over or n > 60 * 60 * 16:
				check(over, "2v2 match finished")
				check(friendly == 0, "no friendly fire in 2v2 (%d)" % friendly)
				check(stayed_down, "2v2: downed fighters stay down until the round ends")
				var w: Array = fight.round_log.map(func(r): return int(r.winner))
				check(w.all(func(x): return x in [-1, 0, 1]), "2v2 rounds go to a team %s" % str(w))
				print("  2v2 rounds: ", fight.round_log.map(func(r): return [r.winner, r.how]))
				check(oom == 0, "2v2: no fighter out of the map (%d of %d frames) %s" % [oom, oom_n, oom_at])
				fight.queue_free()
				finished = true
