extends RefCounted
## Cinematics + match recording, headless (run by run_tests.gd after the plain match):
## Power Change cutscene (freeze, grey-out, camera swoop, shockwave, snap back), fusion hit-stop + camera, damage-scaled
## sparks / impact frames, round-ending KO slow motion + instant replay (live state restored exactly), recorder contents,
## and a full CPU-vs-CPU match with cinematics on.

var t: SceneTree   # the run_tests.gd runner (check())
var fight: Fight
var n := 0
var step := 0
var finished := false
var mark := {}
var cam_angles := []
var over := false
var pc_frames := 0
var pc_out := 0
var ko_w: RefCounted = null   # tests/ko_watch.gd: every frame from each KO (slow motion, replay, win shot) to the next round

func _init(runner: SceneTree) -> void:
	t = runner

func check(c: bool, what: String) -> void:
	t.call("check", c, what)

func start(chars: Array, stage: String) -> void:
	print("== cinematics")
	fight = Fight.new(); fight.test_mode = true; fight.cine_force = true; fight.cpu_flags = [true, true]
	fight.chars = chars.duplicate()
	if stage != "": fight.stage = stage
	fight.match_over.connect(func(_w, _s): over = true)
	t.root.add_child(fight)
	ko_w = load("res://tests/ko_watch.gd").new(fight)

func _chest(f: Fighter) -> Vector3:
	return f.global_position + Vector3.UP * 1.05

func tick() -> void:
	n += 1
	if fight == null or not is_instance_valid(fight): finished = true; return
	ko_w.tick()
	var c := fight.cinema
	var a: Fighter = fight.fighters[0]; var b: Fighter = fight.fighters[1]
	if b.boss: var sw := a; a = b; b = sw   # Final Valgas never collects stones: P1 is the one who changes
	if OS.has_environment("PS_DEBUG") and n % 120 == 0:
		print("CINE n=%d step=%d phase=%d kind=%s ws=%.2f a=%d b=%d" % [n, step, fight.phase, c.kind, c.world_scale, a.state, b.state])
	if (step >= 2 and step <= 5 or step == 11) and not a.powered: a.gems = 0   # the other fighter mustn't Power Change mid-test (gems land near him)
	if n > 60 * 60 * 10 and not finished:
		check(false, "cinematics test timed out at step %d" % step); finished = true; return
	match step:
		0:
			check(c != null and fight.rec != null, "cinematics + recorder built")
			step = 1
		1:   # wait for the fight to start, then hand P2 three stones
			if fight.phase == Fight.R.FIGHT and n > 40 and b.state in [Fighter.S.IDLE, Fighter.S.RUN] and not b.powered:
				b.pick_gem(); b.pick_gem(); b.pick_gem()
				# the original swaps the form on the transform's morph row (fx-pc, docs/PC.md): the cinematic starts there
				mark = {"pick": n}
				step = 11
		11:
			if b.powered or n - int(mark.pick) > 140:
				check(c.kind == "power" and c.hero == b, "3rd stone's form change starts the Power Change cinematic")
				mark = {"n": n, "apos": a.global_position, "ast": a.state_t, "bst": b.state_t, "tm": fight.timer}
				cam_angles = []
				step = 2
		2:
			var e := n - int(mark.n)
			var rel := fight.cam.global_position - _chest(b)
			cam_angles.append(atan2(rel.z, rel.x))
			if c.kind == "power":   # BUG-4: his posed mesh (head, horns, feet) between the letterbox bars every frame
				var bx := CamCheck.points_box(fight.cam, CamCheck.skin_points(b))
				var bar := 0.11 * c.bar_amt
				pc_frames += 1
				if bx.is_empty() or bx[1] < bar or bx[3] > 1.0 - bar or bx[0] < 0.0 or bx[2] > 1.0:
					pc_out += 1
					if OS.has_environment("PS_PC_DEBUG"): print("PCOUT e=%d t=%.3f box=%s bar=%.3f fov=%.1f off=%s cam=%s aim=%s hero=%s" % [e, c.t, str(bx), bar, fight.cam.fov, str(c.pc_off), str(fight.cam.global_position.snapped(Vector3.ONE * 0.01)), str(c.pc_aim.snapped(Vector3.ONE * 0.01)), str(b.global_position.snapped(Vector3.ONE * 0.01))])
			if e == 30:
				check(a.global_position.is_equal_approx(mark.apos) and is_equal_approx(a.state_t, mark.ast), "the other fighter is frozen")
				check(b.state == Fighter.S.TRANSFORM and b.state_t > 0.4, "the hero plays the transform motion (k3/8) meanwhile")
				check(c.desat > 0.6 and c.post.visible, "the world drains to grey (%.2f)" % c.desat)
				var d := Vector2(rel.x, rel.z).length()
				check(d > 0.7 and d < 10.0, "camera close on the hero (%.1f m)" % d)
				check(is_equal_approx(fight.timer, mark.tm), "round clock stops")
			if e == int((Cinema.PC_BURST + 0.2) * 60):
				check(c.burst_done and c.wave_r > 0.5, "shockwave + recolour wave after the burst")
				var lights := 0
				for it in fight.fx.live: if it[0] is OmniLight3D: lights += 1
				check(lights >= 1, "light burst lights the stage")
			if e == int((Cinema.PC_LEN + 0.15) * 60):
				var swept := 0.0
				for i in range(1, cam_angles.size()): swept += absf(wrapf(cam_angles[i] - cam_angles[i - 1], -PI, PI))
				check(swept > deg_to_rad(100), "camera swooped round him (%.0f deg)" % rad_to_deg(swept))
				check(pc_frames > 100 and pc_out == 0, "Power Change: %s whole between the bars in every frame (%d of %d out)" % [b.char_id, pc_out, pc_frames])
				check(c.kind == "" and c.world_scale == 1.0 and c.desat == 0.0, "time snaps back")
				check(b.powered and b.state != Fighter.S.TRANSFORM, "he's changed and free")
				mark = {"n": n, "ast": a.state_t}
				step = 3
		3:
			if OS.has_environment("PS_DEBUG"): print("CINE3 %d st %d gst %d gst_t %d t %.3f floor %s pos %s hs %.3f rx %s carry %s" % [n - int(mark.n), a.state, a.gst, a.gst_t, a.state_t, str(a.is_on_floor()), str(a.global_position.snapped(Vector3.ONE * 0.01)), a.hitstop, str(a.rx_on), str(a.carry != null)])
			if n - int(mark.n) == 10:
				check(a.state_t != mark.ast or a.state != Fighter.S.IDLE, "the other fighter moves again (state %d gst %d t %.3f held %s rx %s thr %s scale %.2f flow %.2f)" % [a.state, a.gst, a.state_t, str(a.held_by != null), str(a.rx_on), str(a.thr_on), c.scale_for(a), fight._flow_step(1.0)])
			# the Fusion once his own Drive (if the CPU started one) is over: the core takes no Fusion mid-move, and the old
			# attack forced over a running Drive left the CPU a second, real Fusion 33 frames later (Kraken, w8)
			if n - int(mark.n) >= 10 and (not b.pc_on or n - int(mark.n) > 600):
				b.gauge = Rules.GAUGE_MAX
				b.state = Fighter.S.IDLE
				if not b._pc_attack("FX"): b._start_attack("fusion1")   # the game's own Fusion (the core's FX rows: the whole gauge goes on its cost row), else the old attack
				check(c.kind == "fusion" and c.stop_t > 0.0, "Power Fusion: hit-stop + cinematic camera")
				check(c.scale_for(a) == 0.0 and c.scale_for(b) == 0.0, "hit-stop freezes both")
				mark = {"n": n}
				step = 4
		4:
			if n - int(mark.n) == int((Cinema.FUSION_LEN + 0.1) * 60):
				check(c.kind == "", "fusion camera hands back (kind '%s' stop %.2f, %s gst %d %s, %s gst %d)" % [c.kind, c.stop_t, b.char_id, b.gst, b.cur_attack, a.char_id, a.gst])
				var h0: int = c.count.hits; var fx0: int = fight.fx.live.size()
				a.invuln = 0.0; a.state = Fighter.S.IDLE
				a.receive_hit(30, 2.0, false, b.global_position, b)
				check(c.count.hits == h0 + 1 and fight.fx.live.size() > fx0, "every hit gets a spark")
				var i0: int = c.count.impacts
				a.invuln = 0.0; a.state = Fighter.S.IDLE
				c.impact_cd = 0.0
				a.receive_hit(160, 8.0, true, b.global_position, b)
				check(c.count.impacts == i0 + 1 and c.impact > 0.5 and c.stop_t > 0.0, "heavy hit: impact frame + hit-stop")
				mark = {"n": n}
				step = 5
		5:   # round-ending KO
			if n - int(mark.n) >= 90 and c.kind == "" and fight.phase == Fight.R.FIGHT:
				a.invuln = 0.0; a.state = Fighter.S.IDLE; a.hp = 5
				a.receive_hit(200, 8.0, true, b.global_position, b)
				# the original enters its KO phase 3 frames after the hit (fx-flow, Fight.FL_KO_LAG): the KO is registered now
				check((fight.phase == Fight.R.KO or fight.ko_f >= 0) and c.kind == "ko" and c.world_scale < 0.5, "KO: slow motion")
				check(c.hero == b and c.foe == a, "KO camera on the killer + victim")
				mark = {"n": n}
				step = 6
			elif n - int(mark.n) > 2400:   # a round the earlier hits ended: its KO, replay, round end and the next intro first
				check(false, "KO test could not start (phase %d pf %d cam %s replaying %s round %d hp %d/%d)" % [fight.phase, fight.pf, c.kind, str(c.replaying()), fight.round_no, a.hp, b.hp]); step = 9
		6:
			if c.replaying():
				check(int(c.rp_i) >= c.rp_start, "instant replay plays the final seconds")
				mark["live"] = c.rp_saved.duplicate(true)
				mark["seen"] = 0
				step = 7
			elif n - int(mark.n) > 200:
				check(false, "instant replay never started"); step = 9
		7:
			if c.replaying():
				var fr: Dictionary = fight.rec.frames[c.rp_last]
				if mark.seen == 0:
					check((a.model as PSModel).posing, "replay poses the recorded clips")
					var d: Array = fr.f[fight.fighters.find(a)]
					check(a.global_position.distance_to(Vector3(d[0], d[1], d[2])) < 0.001, "replay puts back recorded positions")
					check(fight.hud == null or not fight.hud.visible, "HUD hidden during the replay")
				mark.seen = int(mark.seen) + 1
			else:
				check(int(mark.seen) > 60 and int(mark.seen) < 240, "replay lasts ~2 s (%d frames)" % int(mark.seen))
				var live: Array = mark.live
				check(a.global_position.is_equal_approx(live[fight.fighters.find(a)][0]) and b.global_position.is_equal_approx(live[fight.fighters.find(b)][0]), "live positions restored after the replay")
				check(not (a.model as PSModel).posing, "live animation resumes")
				mark = {"n": n}
				step = 8
		8:
			if fight.phase == Fight.R.ROUND_END or fight.round_no > 1:
				var ev := {}
				for e in fight.rec.events: ev[e.kind] = true
				check(ev.has("power") and ev.has("fusion") and ev.has("ko") and ev.has("hit"), "recorder marked power/fusion/ko/hit %s" % str(ev.keys()))
				var f0: Dictionary = fight.rec.frames[fight.rec.frames.size() - 1]
				check(f0.has("f") and f0.has("c") and f0.has("x") and (f0.f as Array).size() == 2, "snapshots carry fighters, camera, cinematic look")
				mark = {"n": n}
				step = 9
			elif n - int(mark.n) > 400:
				check(false, "round did not end after the replay (phase %d pf %d settle %d; a st %d gst %d hp %d pole %d %s; b st %d gst %d hp %d pole %d %s)" % [fight.phase, fight.pf, fight.settle, a.state, a.gst, a.hp, a.pole_sub, str(a.global_position.snapped(Vector3.ONE * 0.01)), b.state, b.gst, b.hp, b.pole_sub, str(b.global_position.snapped(Vector3.ONE * 0.01))]); step = 9
		9:   # let the rest of the match play out with cinematics on
			if over:
				check(c.count.ko >= 1 and c.count.replay == c.count.ko and fight.round_log.size() >= (1 if "finalvalgas" in fight.chars else 2), "full match with cinematics: %d rounds, KOs %d, replays %d" % [fight.round_log.size(), c.count.ko, c.count.replay])
				print("  cinematics: ", c.count, " frames recorded ", fight.rec.frames.size())
				check(ko_w.ok() and ko_w.windows >= 1, "KO > replay > win: no frozen / pose-less fighters: " + ko_w.report())
				print("  round ends (cinematics): ", ko_w.report())
				var nos := 0
				for fr in fight.rec.frames:
					for d in (fr as Dictionary).f: if String(d[5]) in ["", "Start", "End"]: nos += 1
				check(nos == 0, "recording has a clip for every fighter in every frame (%d without)" % nos)
				finished = true
			elif n > 60 * 60 * 11:   # 9 rounds (draws on Final Valgas's arena: CPUs stall at its blocks) + cinematics pauses
				check(false, "cinematic match did not finish (rounds %s, hp %s, phase %d)" % [str(fight.round_log.map(func(r): return [r.winner, r.how, r.hp])), str(fight.fighters.map(func(f): return f.hp)), fight.phase]); finished = true
