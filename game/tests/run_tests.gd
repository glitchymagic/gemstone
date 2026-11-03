extends SceneTree
const QuietExit = preload("res://tests/quiet_exit.gd")
## Headless tests. Run:  Godot --headless --path game --fixed-fps 60 -s res://tests/run_tests.gd
## Unit tests (rules, gems, Power Change, rounds) then a full CPU-vs-CPU match to a result.

var passes := 0
var fails := 0
var fight: Fight
var frames := 0
var t_start := 0
var done := false

func check(cond: bool, what: String) -> void:
	if cond: passes += 1
	else:
		fails += 1
		printerr("FAIL: ", what)

func _initialize() -> void:
	print("== unit tests")
	# damage
	check(Rules.damage(100, false, false) == 100, "plain damage")
	check(Rules.damage(100, true, false) == 120, "powered attacker x1.2 (game)")
	check(Rules.damage(100, false, true) == 50, "powered victim x0.5 (game)")
	# the game's formula against real hits logged in Flycast (tools/hitlog.py hits hdA: attract demo, both CPUs at
	# level 25, Falcon on Ayame, defence 1.05)
	check(Rules.game_damage(12, 1.05, 1, 1, false, false, 25, 25) == 11, "logged: Falcon air kick, 1 gem -> 11")
	check(Rules.game_damage(24, 1.05, 1, 3, true, false, 25, 25, 3) == 26, "logged: Power Missile -> 26")
	check(Rules.game_damage(12, 1.05, 6, 3, true, false, 25, 25, 4) == 6, "logged: 6th hit in a row halved -> 6")
	check(Rules.game_damage(12, 1.05, 7, 3, true, false, 25, 25, 4) == 3, "logged: 7th hit -> 3")
	check(Rules.game_damage(12, 1.05, 9, 3, true, false, 25, 25, 4) == 1, "logged: never below 1")
	check(Rules.MAX_HP == 240, "the game's health is 240")
	var gh := GameHits.load_for("p00")
	check(gh.ok, "Falcon's hit data off the disc (p00_hit.json)")
	if gh.ok:
		var s1 := gh.at("k1_016", 2); var s2 := gh.at("k1_016", 6)
		check(s1.hit == 1 and s1.aset == 0 and s2.hit == 1 and s2.aset == 2, "jab: hit 1 armed at 0, left arm spheres from frame 5")
		check(gh.active_window("k1_016") == Vector2i(5, 8), "jab live spheres frames 5-8 (logged: Flycast hdA) (%s)" % str(gh.active_window("k1_016")))
		check(int(gh.record(1).dmg) == 12, "jab base damage 12")
		check(absf(GameHits.load_for("p90").defence - 0.7) < 0.001 and absf(GameHits.load_for("pa0").defence - 0.5) < 0.001,
			"Valgas takes 0.7x, Final Valgas 0.5x")
	var env := Environment.new()
	var bgn := Node.new(); root.add_child(bgn)
	Look.apply_background(bgn, env, {"bg_rgb": [[9, 42, 147], [9, 42, 147], [86, 138, 226]]})
	check(env.background_mode == Environment.BG_CANVAS and bgn.get_child_count() == 1,
		"stage background = the game's PowerVR plane, drawn as a screen layer")
	bgn.queue_free()
	var i30 = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ripped/stg30_info.json"))
	check(i30 is Dictionary and i30.get("bg_argb", []) == ["FF92A69A", "FF92A69A", "FF92A69A"], "Jack's stage plane read from VRAM (FF92A69A)")
	check(Roster.pick_row(0) == 0 and Roster.pick_row(32767) == 6 and Roster.pick_row(31000) == 1,
		"arcade row = int(rand/32768*255) % 8 (game)")
	check(Rules.apply_damage(50, 80) == 0, "hp floors at 0")
	check(Rules.apply_damage(500, 120) == 380, "hp subtract")
	# gems
	check(Rules.gems_dropped(2, true, false) == 1, "knockdown drops one gem")
	check(Rules.gems_dropped(2, false, false) == 0, "light hit keeps gems")
	check(Rules.gems_dropped(0, true, false) == 0, "nothing to drop")
	check(Rules.gems_dropped(3, true, true) == 0, "changed fighter drops none")
	check(Rules.gems_dropped(3, true, false, true) == 2, "Valgas knocks out two")
	check(Rules.should_power_change(3) and not Rules.should_power_change(2), "3 gems = Power Change")
	# gauge
	var g := Rules.GAUGE_MAX
	var secs := 0.0
	while g > 0.0 and secs < 60.0:
		g = Rules.drain_gauge(g, 1.0 / 60.0); secs += 1.0 / 60.0
	check(absf(secs - 40.0) < 0.05, "gauge lasts 40 s free (game: 2400, 1 per frame) (got %.2f)" % secs)
	check(Rules.can_fusion(Rules.FUSION_MIN) and not Rules.can_fusion(Rules.FUSION_MIN - 1), "fusion threshold")
	# rounds
	check(Rules.round_winner(100, 0) == 0 and Rules.round_winner(0, 5) == 1, "KO winner")
	check(Rules.round_winner(0, 0) == -1 and Rules.round_winner(300, 300) == -1, "draws")
	check(Rules.round_winner(400, 300) == 0, "time over: more health wins")
	check(Rules.match_winner([2, 1]) == 0 and Rules.match_winner([1, 1]) == -1, "match winner at 2 rounds")
	pass

func _fighter_tests() -> void:
	# fighter-level: gem pickup -> Power Change -> gauge drains -> gems scatter back
	var arena := Arena.new(); root.add_child(arena); arena.build(3)
	var f := Fighter.new(); var inp := PInput.new(); f.setup(0, "falcon", inp); f.arena = arena
	root.add_child(f); arena.fighters = [f]
	f.reset_round(Vector3(3, 0.1, 2), Vector3.FORWARD)
	f.pick_gem(); f.pick_gem()
	check(f.gems == 2 and not f.powered, "two gems, not changed")
	f.pick_gem()
	# the original (docs/PC.md, fx-pc): state 23 from the third gem's frame, the form + gauge 2400 on the morph row,
	# gems kept until the revert, gauge -1 per frame, the revert once it is 0
	check(f.state == Fighter.S.TRANSFORM and f.gst == 23 and f.gems == 3, "third gem -> transform (state 23) at once")
	var morph := -1
	for i in 130:
		f.tick(1.0 / 60.0)
		if morph < 0 and f.powered: morph = i
	check(f.powered and f.gems == 3 and f.gst != 23 and morph > 20 and f.pc_g == 2400 - (129 - morph),
		"130-frame transform, form + full gauge on the morph row (%d), gauge %d, state %d" % [morph, f.pc_g, f.gst])
	for i in 60 * 41: f.tick(1.0 / 60.0)
	check(not f.powered and f.gems == 0, "Power Change ends when the gauge drains (2400 frames) and the revert runs")
	check(arena.gems.size() == Rules.GEMS_IN_PLAY, "gems scatter back after the change (%d)" % arena.gems.size())
	# gem knocked out on hit
	arena.clear_gems()
	f.reset_round(Vector3(3, 0.1, 2), Vector3.FORWARD)
	f.gems = 2
	var hit := f.receive_hit(80, 8.0, true, Vector3(2, 0, 2), null)
	check(hit and f.gems == 1 and arena.gems.size() == 1, "knockdown knocks a gem out")
	check(f.state == Fighter.S.DOWN and f.hp == Rules.MAX_HP - 80, "knockdown state + damage")
	check(not f.can_be_hit(), "downed fighter can't be hit")
	for i in 60 * 2: f.tick(1.0 / 60.0)
	check(f.invuln > 0.0 or f.state == Fighter.S.IDLE, "gets up with invincibility")
	# pole swing (docs/OBJ.md 1, the disc's 48 CPU logs): in the air, the ACTION press next to a pole catches it
	# (k2/211, 10 cm from the axis), punch swings (k1/150 on the axis), the hop flies (k1/151) and lands; no button = no catch
	check(arena.poles.size() >= 2, "stage poles from the game's record tag (%d)" % arena.poles.size())
	if arena.poles.size() > 0:
		var pole: Vector3 = arena.poles[0]
		f.reset_round(pole + Vector3(0.85, 0.6, 0), Vector3.LEFT)
		f.set_state(Fighter.S.JUMP); f.velocity = Vector3(-1.0, 0.5, 0)
		var caught := false; var flew := false; var snap := 99.0; var no_btn := true
		var pad := PInput.new(); var was_ctrl = f.ctrl; f.ctrl = pad
		for i in 150:
			var btn := {}
			if i == 2: btn = {"action": true}
			if i == 14: btn = {"punch": true}
			pad.set_state(Vector2.ZERO, btn)
			f.tick(1.0 / 60.0)
			if i <= 2 and f.state == Fighter.S.POLE: no_btn = false
			if f.state == Fighter.S.POLE and not caught:
				caught = true; snap = Vector2(f.global_position.x - pole.x, f.global_position.z - pole.z).length()
			if caught and f.pole_sub == 2: flew = true
			if caught and f.state == Fighter.S.IDLE: break
		f.ctrl = was_ctrl
		check(no_btn and caught and absf(snap - 0.1) < 0.01 and flew and f.state == Fighter.S.IDLE,
			"pole: action in the air catches (10 cm from the axis: %.3f m), punch swings, the hop lands" % snap)
	f.queue_free(); arena.queue_free()
	load("res://tests/remix_tests.gd").run(self)
	print("unit: %d passed, %d failed" % [passes, fails])

func _start_match() -> void:
	print("== CPU vs CPU match")
	fight = Fight.new(); fight.test_mode = true; fight.cpu_flags = [true, true]
	fight.chars = ["falcon", "ryoma"]
	if OS.has_environment("PS_TEST_CHARS"): fight.chars = Array(OS.get_environment("PS_TEST_CHARS").split(","))   # any ripped pair
	if OS.has_environment("PS_STAGE"): fight.stage = OS.get_environment("PS_STAGE")
	print("  fighters: ", fight.chars, " stage: ", fight.stage)
	fight.match_over.connect(_on_over)
	root.add_child(fight)
	ko_w = load("res://tests/ko_watch.gd").new(fight)
	t_start = Time.get_ticks_msec()

func _on_over(w: int, st: Array) -> void:
	done = true
	var wall := Time.get_ticks_msec() - t_start
	print("match over: winner P%d after %d frames (%.1f s game time), wall %d ms" % [w + 1, frames, frames / 60.0, wall])
	for r in fight.round_log: print("  round ", r)
	print("  stats P1 ", st[0]); print("  stats P2 ", st[1])
	print("  avg fight logic frame: %.3f ms, avg wall frame: %.3f ms" % [fight.avg_frame_ms(), float(wall) / max(1, frames)])
	check(w >= 0 or fight.round_log.size() > 0, "match reached a result")
	var boss_fight: bool = "finalvalgas" in fight.chars   # Final Valgas: one round on the disc (fx-fv)
	check(fight.round_log.size() >= (1 if boss_fight else Rules.ROUNDS_TO_WIN), "played all rounds needed")
	check(st[0].hits + st[1].hits > 0, "fighters landed hits")
	check(st[0].get("sphere_hits", 0) + st[1].get("sphere_hits", 0) > 0, "hits decided by the game's own spheres (%d)" % (st[0].get("sphere_hits", 0) + st[1].get("sphere_hits", 0)))
	_map_checks(fight.arena)
	_model_checks()

## Out of the map (the owner saw fighters on white fog): every frame, every fighter's feet over the stage's own floor (a
## downward ray hits stage geometry) inside the original's playable area (assets/fidelity, Arena.out_of_map), and the
## gems / throwables too.
var oom_only := OS.has_environment("PS_OOM_ONLY")
var oom_frames := 0
var oom_obj := 0
var oom_n := 0
var oom_worst := ""
var _oom_prev := {}
func _watch_map() -> void:
	var ar: Arena = fight.arena
	oom_n += 1
	var bad := false
	var tr := OS.get_environment("PS_TRACE_F").split("-") if OS.has_environment("PS_TRACE_F") else PackedStringArray()
	for f in fight.fighters:
		if tr.size() == 2 and frames >= int(tr[0]) and frames <= int(tr[1]):   # every fighter, every frame in the window
			print("TRACE f%d %s %s st%d gst%d gmo %s rx %s held %s v%s grounded %s sdf %.2f lv %s" % [frames, f.char_id, str(f.global_position.snapped(Vector3.ONE * 0.01)),
				f.state, f.gst, f.gmo, str(f.rx_on), str(f.held_by != null), str(f.velocity.snapped(Vector3.ONE * 0.1)), str(f.grounded()), ar.sdf_at(f.global_position.x, f.global_position.z),
				str(ar.floor_levels(f.global_position.x, f.global_position.z))])
		if OS.has_environment("PS_OOM_DEBUG") and (ar.fighter_out_of_map(f, fight.cinema != null and fight.cinema.replaying()) or _oom_prev.get(f, false)):
			print("OOM f%d %s %s st%d gst%d v%s sdf %.2f lv %s floor %s" % [frames, f.char_id, str(f.global_position.snapped(Vector3.ONE * 0.01)),
				f.state, f.gst, str(f.velocity.snapped(Vector3.ONE * 0.1)), ar.sdf_at(f.global_position.x, f.global_position.z),
				str(ar.floor_levels(f.global_position.x, f.global_position.z)), str(f.is_on_floor())])
		_oom_prev[f] = ar.fighter_out_of_map(f, fight.cinema != null and fight.cinema.replaying())
		if ar.fighter_out_of_map(f, fight.cinema != null and fight.cinema.replaying()):
			bad = true
			if oom_worst == "": oom_worst = "%s at %s (sdf %.2f) frame %d" % [f.char_id, str(f.global_position.snapped(Vector3.ONE * 0.01)), ar.sdf_at(f.global_position.x, f.global_position.z), frames]
	if bad: oom_frames += 1
	if CamCheck.objects_out(ar) > 0:
		oom_obj += 1
		if oom_obj == 1 or (OS.has_environment("PS_OOM_DEBUG") and oom_obj % 300 == 0):   # which one, once
			for g in ar.gems:
				if is_instance_valid(g) and ar.out_of_map((g as Node3D).global_position, CamCheck.OBJ_TOL): print("OOM-OBJ f%d gem %s" % [frames, str((g as Node3D).global_position.snapped(Vector3.ONE * 0.01))])
			for p in ar.props:
				var pr := p as Prop
				if pr: ar._air = pr.state == Prop.FLYING   # as CamCheck.objects_out: a flying object in the air area
				var po := pr and pr.state in [Prop.REST, Prop.FLYING] and not (pr.state == Prop.REST and pr.global_position.is_equal_approx(pr.home)) and ar.out_of_map(pr.global_position + Vector3.UP * 0.1, CamCheck.OBJ_TOL)
				ar._air = false
				if po:
					print("OOM-OBJ f%d prop part %d state %d at %s home %s" % [frames, pr.part, pr.state, str(pr.global_position.snapped(Vector3.ONE * 0.01)), str(pr.home.snapped(Vector3.ONE * 0.01))])

func _map_checks(ar: Arena) -> void:
	print("  out of the map: %d of %d frames (fighters), %d frames (gems / throwables) %s" % [oom_frames, oom_n, oom_obj, oom_worst])
	check(not ar.has_assets or ar.has_area(), "the stage's measured playable area is loaded (assets/fidelity/%s_area.json)" % ar.stage)
	check(oom_frames == 0, "no fighter out of the map: 0 of %d frames (%d) %s" % [oom_n, oom_frames, oom_worst])
	check(oom_obj == 0, "no gem / throwable out of the map (%d frames)" % oom_obj)
	if ar.has_area():
		var sp := ar.spawn_points()
		check(not ar.out_of_map(sp[0]) and not ar.out_of_map(sp[1]), "start points on the floor inside the area")
		var ok := true
		for i in 50:
			if ar.out_of_map(ar.random_floor_point()): ok = false
		check(ok, "random floor points (gems, respawns) all inside the area")

var stage := 0
var cine: RefCounted = null
var theater: RefCounted = null
var brawl: RefCounted = null
var attract_t: RefCounted = null
var training_t = null
var cine_chars := []
var ko_w: RefCounted = null   # tests/ko_watch.gd: every frame from each KO to the next round
var cine_stage := ""
var seen := [{}, {}]
var bone_moved := [false, false]
var bone_first := [null, null]

func _watch_models() -> void:
	for i in 2:
		if fight.fighters.size() <= i: return
		var f: Fighter = fight.fighters[i]
		if not (f.model is PSModel): continue
		var m: PSModel = f.model
		if m.playing != "": seen[i][m.playing] = true
		var sk := (m.forms[m.form] as Node).find_child("Skeleton3D", true, false) as Skeleton3D
		if sk:
			var p := sk.get_bone_global_pose(sk.find_bone("b08")).origin
			if bone_first[i] == null: bone_first[i] = p
			elif (p - bone_first[i]).length() > 5.0: bone_moved[i] = true

func _model_checks() -> void:
	for i in 2:
		var f: Fighter = fight.fighters[i]
		check(f.model is PSModel, "P%d has the ripped model" % (i + 1))
		if not (f.model is PSModel): continue
		var m: PSModel = f.model
		print("  P%d clips used: %s" % [i + 1, ", ".join(PackedStringArray(seen[i].keys()))])
		var nf := 1 if m.forms.size() == 1 and m.trees.size() == 1 and f.char_id == "finalvalgas" else 2   # PA0: one form on the disc
		check(m.forms.size() == nf and m.trees.size() == nf, "P%d all forms rigged with an AnimationTree (%d)" % [i + 1, nf])
		var ap: AnimationPlayer = m.players[false]
		var need := 50 if nf == 1 else 80   # Final Valgas has 57 motions on the disc
		check(ap.get_animation_list().size() >= need, "P%d RAM-captured clips imported (%d)" % [i + 1, ap.get_animation_list().size()])
		if fight.fighters[i].boss:   # Final Valgas never walks (logged): idle + his own attack chains only
			var own: bool = seen[i].has("drive_p")   # fx-fv2: his fighter code plays his disc motions by id (z0k1_096..104 ...)
			for k in seen[i]: own = own or str(k).begins_with("z0k1_")
			check(seen[i].has("idle") and own and not seen[i].has("run") and not seen[i].has("transform"), "P%d (boss) played idle + logged attacks, never runs/transforms" % (i + 1))
		else:
			check(seen[i].has("idle") and seen[i].has("run"), "P%d played idle + run" % (i + 1))
		var atk := 0
		for k in seen[i]:   # the fidelity core plays the game's own motion clips by id (..k1_016)
			if String(k).begins_with("punch") or String(k).begins_with("kick") or k in ["dash", "air", "fusion1", "fusion2", "drive_p", "drive_k"] or String(k).substr(2, 3) == "k1_": atk += 1
		check(atk > 0, "P%d played attack clips %s" % [i + 1, str(seen[i].keys())])
		check(bone_moved[i], "P%d skeleton actually animated (right hand bone moved)" % (i + 1))

func _process(_dt: float) -> bool:
	stage += 1
	if stage == 2: _fighter_tests(); return false
	if stage == 3 and OS.has_environment("PS_UNIT_ONLY"):   # the unit checks alone (seconds; the matches are the rest)
		print("TOTAL: %d passed, %d failed" % [passes, fails]); QuietExit.drain(root); quit(0 if fails == 0 else 1); return true
	if stage == 3: _start_match(); return false
	if oom_only and brawl != null:   # PS_OOM_ONLY (fx-oom2 iteration): the plain match, then the Battle Royale, nothing else
		if not brawl.finished: brawl.tick(); return false
		print("TOTAL: %d passed, %d failed" % [passes, fails])
		print("TESTS-OK" if fails == 0 else "TESTS-FAILED")
		quit(0 if fails == 0 else 1)
		return true
	if cine != null:
		if not cine.finished: cine.tick(); return false
		if theater == null and cine.fight and is_instance_valid(cine.fight):
			theater = load("res://tests/theater_tests.gd").new(self, cine.fight)
		if theater and not theater.finished: theater.tick(); return false
		if brawl == null:
			brawl = load("res://tests/brawl_tests.gd").new(self, cine_chars, cine_stage)
		if not brawl.finished: brawl.tick(); return false
		if attract_t == null: attract_t = load("res://tests/attract_tests.gd").new(self)
		if not attract_t.finished: attract_t.tick(); return false
		if training_t == null: training_t = load("res://tests/training_tests.gd").new(self)
		if not training_t.finished: training_t.tick(); return false
		print("TOTAL: %d passed, %d failed" % [passes, fails])
		print("TESTS-OK" if fails == 0 else "TESTS-FAILED")
		QuietExit.drain(root)   # BUG-38: stop the sounds + let the audio thread free their playbacks (--fixed-fps outruns it)
		quit(0 if fails == 0 else 1)
		return true
	if fight == null: return false
	frames += 1
	_watch_models()
	ko_w.tick()
	if fight.is_inside_tree() and fight.arena: _watch_map()
	if OS.has_environment("PS_DEBUG") and frames % 600 == 0 and fight.fighters.size() == 2:
		var a: Fighter = fight.fighters[0]; var b: Fighter = fight.fighters[1]
		print("DBG t=%d p1 %s st%d hp%d | p2 %s st%d hp%d phase %d" % [frames / 60, str(a.global_position.snapped(Vector3.ONE * 0.1)), a.state, a.hp, str(b.global_position.snapped(Vector3.ONE * 0.1)), b.state, b.hp, fight.phase])
	if done or frames > 60 * 60 * 6:
		if not done: check(false, "match did not finish in 6 game-minutes")
		if cine == null:   # then the same pair again with cinematics on (tests/cine_tests.gd)
			check(fight.cinema == null, "cinematics stay off in the plain match (the original's presentation)")
			check(ko_w.ok(), "round ends without frozen / pose-less fighters: " + ko_w.report())
			print("  round ends: ", ko_w.report())
			var ch: Array = fight.chars; var st: String = fight.stage
			cine_chars = ch.duplicate(); cine_stage = st
			fight.queue_free()
			if oom_only:
				brawl = load("res://tests/brawl_tests.gd").new(self, cine_chars, cine_stage)
				return false
			cine = load("res://tests/cine_tests.gd").new(self)
			cine.start(ch, st)
			return false
		if not cine.finished:
			cine.tick(); return false
		print("TOTAL: %d passed, %d failed" % [passes, fails])
		print("TESTS-OK" if fails == 0 else "TESTS-FAILED")
		QuietExit.drain(root)   # BUG-38: stop the sounds + let the audio thread free their playbacks (--fixed-fps outruns it)
		quit(0 if fails == 0 else 1)
		return true
	return false
