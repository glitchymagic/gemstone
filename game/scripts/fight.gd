class_name Fight
extends Node3D
## One match: arena, fighters (human/CPU), the original-style camera, HUD, rounds, gems, Power Change, music.
## 1v1 is the original. Battle Royale (chars.size() 3-4, or 2v2 via teams): every fighter fights the nearest / chosen
## enemy, KO'd fighters stay down until the round ends, the round goes to the last team standing (time: most health).
## Also run headless by tests/run_tests.gd (CPU vs CPU).

signal match_over(winner: int, stats: Array)
signal tape_done

enum R { INTRO, FIGHT, KO, ROUND_END, DONE, READY }   # INTRO/READY/FIGHT/KO/ROUND_END = the original's round phase 1/2/3/4/5

## --- Round flow, frame for frame (lane pstrailer2 fx-flow; docs/FLOW.md, tools/flowlog.py + tools/flow_diff.py) ----------
## Logged in Flycast (round phase byte 0x0C7F302C, MV_OK 0x0C7F3050, clock 0x0C7F304D, both players' state/motion):
const FL_LEAD := 67          # phase 1 (round 1 only): frames before P1's intro
const FL_SLOT := [120, 123]  # P1's / P2's intro slot: its k3/0 (state 22) plays from the slot's first frame, then idle
const FL_READY := 152        # phase 2: frame 0 no input, 1..150 directions + jump only (MV_OK 1), 151 everything (2)
const FL_SEC := 60           # the clock: 99 for the first 60 fight frames ...
const FL_TIME_AT := 5999     # ... 0 at fight frame 5940, held 60 frames: the TIME event (input off 2 frames later)
const FL_KO_LAG := 3         # the KO hit on frame H: H+1, H+2 still fight (input off on H+2), phase 4 on H+3
const FL_KO_FREEZE := 90     # phase 4: one tick, then the whole world stands still 90 frames ...
const FL_KO_SLOW := 15       # ... then 15 ticks, one every FL_KO_EVERY frames (1/4 speed), then full speed
const FL_KO_EVERY := 4
const FL_SETTLE := 2         # phase 5 starts 2 frames after the loser is lying (state 15) and the winner idle (state 0)
const FL_TIME_CALL := 183    # phase 4 after TIME
const FL_POSE_AT := 2        # phase 5: the poses (and the stage's win spots) on its third frame
const FL_ROUND_END := 245    # phase 5 between rounds (draws included)
const FL_MATCH_WON := 307    # the match's last phase 5: won by P1 (the arcade player) ...
const FL_MATCH_LOST := 275   # ... won by the CPU (then the continue countdown)
const FL_VALGAS_END := 1132  # arcade, Valgas beaten: win pose until frame 276, then his change k3/13 60 > 14 240 > 15 240 > 16 316
const FL_VALGAS_AT := 276
const FL_FV_INTRO := [2, 163]  # Final Valgas: no lead-in / P1 intro; his own state-22 slot (k0/0) from frame 2, 163 frames
const FL_DEMO_LEN := 2181      # attract demo (1v1): fight frames, clock frozen at 99 (2 demos logged: 2181 / 2180)
const FL_DEMO_POSE := 380      # then "VS RANKING": P1 k3/2 on the win spot, P2 state 8 k0/0 on the lose spot
var pf := 0                  # frames into the current phase
var fight_t := 0.0           # fight frames this round (the clock); cinematics' world scale slows it
var mv_ok := 0               # the original's MV_OK: 0 no input, 1 directions + jump, 2 everything
var ko_f := -1               # frames since the round-ending event (KO hit or TIME), -1 = none
var ko_how := ""
var settle := -1
var round_end_len := FL_ROUND_END
var elapsed_f := 0           # arcade TIME on the HUD (fight frames of the whole run until the KO / TIME)
var flow_log: FileAccess     # PS_FLOW_LOG: one row per frame in tools/flowlog.py's schema (tools/flow_diff.py)
var flow_spots := {}         # this stage's win spots (assets/fidelity/flow.json), {} = poses where they stand
var pose_focus: Array = []   # phase 5: who the camera frames (the winner on his spot)

var chars := ["falcon", "ryoma"]
var cpu_flags := [false, true]
var pads := [0, 1]
var kbs := [0, 1]
var test_mode := false
var arena: Arena
var fighters: Array[Fighter] = []
var cpus := [null, null]
var inputs: Array[PInput] = []
var cam: Camera3D
var hud: HUD
var fx: FX
var music: AudioStreamPlayer
var vo: AudioStreamPlayer     # the game's announcer (NA.BIN: "Are you ready?", "Action!", "K.O.!", "Time!", "Perfect!")
var phase := R.INTRO
var phase_t := 0.0
var timer := Rules.ROUND_TIME
var round_no := 1
var wins := [0, 0]
var round_log := []
var frame_ms := []
var cam_yaw := 0.0
var stage := "stg00"
var paused_menu: Control
var teams := [0, 1]
var rec: Replay          # every match is recorded (instant replay, replay theater, highlights)
var cinema: Cinema       # null = Cinematics Off (the original's presentation)
var cine_force := false  # tests: cinematics on in test mode
var save_replay := false # tests / tools: save the recording even in test mode
var no_replay := false   # proof runs (tests/ko_check.gd): never add the match to the player's replay theater
var replay_path := ""
var lighting := "original"   # remix lighting (scripts/remix.gd): original | night | sunset | storm
var seed_override := -1
var remix: Remix
var training := false   # Training room (scripts/training.gd): you vs a dummy, the game's hit data on screen
var trainer: Training
var attract := false     # title-screen demo: CPU vs CPU, any button returns to the title
var arcade_step := -1   # arcade fight index (0 = first): the CPU's strength level comes from it (Rules.ARCADE_CPU_LEVEL)
## Fidelity pass (tests/tape_run.gd, tools/fidelity_diff.py): both fighters read one input tape (per frame the
## Dreamcast pad bits of P1 and P2, tools/tapes.py) from the first FIGHT frame on, and every frame is logged in the
## schema of the original's reference log (tools/reflog.py) BEFORE that frame's input, like Flycast's capture.
var tape: Array = []          # [[p1 mask, p2 mask], ...]
var tape_f := -1              # frame index into the tape (-1 = not started)
var sfxm: SfxMap               # the original's sound cues (sfx_map.gd, BUG-36)
var tape_log: FileAccess
var tape_cam: Array = []      # optional: the original's camera (eye, target) per frame, for the D-pad -> world mapping
const DC_BTN := {"punch": 0x400, "kick": 0x200, "jump": 0x4, "action": 0x2, "start": 0x8}

static var _fights_in_process := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not test_mode:
		Look.build_environment(self)
	arena = Arena.new(); arena.name = "Arena"; arena.stage = stage
	add_child(arena)
	# PS_SEED: repeatable renders. The disc's C rand is never re-seeded, so a CONTINUE (the same fight again) plays out
	# differently: PS_SEED seeds the process's first fight only and later fights keep drawing from the same stream.
	var seed_v := int(OS.get_environment("PS_SEED")) + _fights_in_process if OS.has_environment("PS_SEED") else int(Time.get_unix_time_from_system())
	arena.build(seed_override if seed_override >= 0 else (1234 if test_mode else seed_v))
	if OS.has_environment("PS_SEED") and _fights_in_process == 0: CPUGame.rand_state = int(OS.get_environment("PS_SEED"))   # the C rand the AI draws from
	_fights_in_process += 1
	cam_yaw = arena.camera_yaw()
	if not test_mode: Look.stage_tweak(self, arena.info)
	if not test_mode: HD.stage(self, arena)   # Remaster look (pass 6); a no-op in Classic
	if lighting != "original": remix = Remix.apply(self, arena, lighting)   # remix lighting, on top of the look
	cam = Camera3D.new(); cam.fov = 41.1; cam.far = 400.0; cam.current = true
	add_child(cam)
	if not test_mode: HD.light_rig(cam)
	if remix: remix.tint_rig(cam)
	fx = FX.new(); add_child(fx)
	rec = Replay.new()
	var g := UI.game()
	if cine_force or (not test_mode and g != null and bool(g.get("cinematics"))):
		cinema = Cinema.new(); cinema.name = "Cinema"; add_child(cinema); cinema.setup(self)
	var n := chars.size()
	while cpu_flags.size() < n: cpu_flags.append(true)
	if teams.size() < n: teams = range(n)
	while pads.size() < n: pads.append(pads.size())
	while kbs.size() < n: kbs.append(-1)
	cpus.resize(n)
	wins = []
	for i in n: wins.append(0)   # per team (team ids are 0..n-1)
	for i in n:
		var f := Fighter.new(); f.name = "P%d" % (i + 1)
		var inp := PInput.new(); inputs.append(inp)
		f.setup(i, chars[i], inp)
		f.team = int(teams[i])
		f.arena = arena
		add_child(f)
		fighters.append(f)
		f.fx.connect(_on_fx)
		f.knocked_out.connect(_on_ko)
		f.fx.connect(func(k: String, _p: Vector3): if k == "fusion": _on_fusion(f))
		f.powered_changed.connect(func(_x): if f.powered: _on_power(f))
		f.damaged.connect(func(_x, dmg: int): _on_damaged(f, dmg))
	fighters[0].opponent = fighters[1]; fighters[1].opponent = fighters[0]
	arena.fighters = fighters
	sfxm = SfxMap.make(self, stage)
	_retarget()
	for i in n:
		if cpu_flags[i]:
			# The ORIGINAL's CPU (cpu_game.gd, BUG-24) for every 1-on-1 fight: Arcade, VS, the attract demo. cpu.gd stays
			# only where the original has nothing to port: Battle Royale / 2v2 (3-4 fighters) and Final Valgas, whose own
			# AI 0x0C08D5CE is not ported yet (docs/CPU.md section 9).
			var lv := cpu_level_for()
			if n == 2 and not fighters[i].boss and CPUGame.load_data():
				var c := CPUGame.new(fighters[i], arena, lv)
				c.fight_index = cpu_fight_index()
				# test harness only (tests/arcade_ladder.gd): P1's AI stands in for a player, on a normal fight's scripts
				# (the disc's fight 1 scripts only go for objects, so CPU-vs-CPU fight 1 is two drawn rounds forever)
				if i == 0 and OS.has_environment("PS_P1_FIGHT"): c.fight_index = int(OS.get_environment("PS_P1_FIGHT"))
				cpus[i] = c
			else:
				cpus[i] = CPU.new(fighters[i], arena, 11 + i * 31)
			fighters[i].ctrl = cpus[i].input
			# the game scales the CPU's hits both ways by its level (Rules.CPU_ATK/DEF): arcade and the attract demo
			if arcade_step >= 0 or attract: fighters[i].cpu_level = lv
			# test harness only (tests/arcade_ladder.gd): the stand-in player's own hit scaling, so a whole-ladder run
			# reaches Final Valgas (at the same level as the CPU it lost 11 fights in a row to Valgas, lad2 w7)
			if i == 0 and OS.has_environment("PS_P1_LEVEL"): fighters[i].cpu_level = int(OS.get_environment("PS_P1_LEVEL"))
	if training:
		trainer = Training.new(); trainer.name = "Training"; add_child(trainer); trainer.setup(self)
	if not test_mode:
		hud = HUD.new(); hud.fight = self; add_child(hud)
		if attract:
			var demo := UI.label("DEMO  -  PRESS ANY BUTTON", 34, Color(1, 0.9, 0.5))
			demo.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); demo.position.y = -70
			hud.add_child(demo)
		music = AudioStreamPlayer.new(); add_child(music)
		var s := Audio.music(stage_music(stage))   # each stage its own track (was always Londo's ST_00)
		if s: music.stream = s; music.volume_db = -6.0; music.play()
		vo = AudioStreamPlayer.new(); vo.volume_db = 0.0; add_child(vo)
	var fj = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/flow.json"))
	if fj is Dictionary: flow_spots = (fj.get("win_spots", {}) as Dictionary).get(stage, {})
	if OS.has_environment("PS_FLOW_LOG"): flow_log = FileAccess.open(OS.get_environment("PS_FLOW_LOG"), FileAccess.WRITE)
	rec.begin(self)
	_start_round()

## The CPU's level byte 0x0C7F305C (= the rank counter 0x0C7F305D / 8). Arcade: the level logged at each fight
## (Rules.ARCADE_CPU_LEVEL, 9 at fight 1 ... 29 at Final Valgas). Everything else (the attract demo, VS / test
## CPU-vs-CPU): measured in the attract demo (Flycast u2, 10-27: 0x0C7F305C = 25, rank 200, both CPUs).
const ATTRACT_CPU_LEVEL := 25
const ATTRACT_FIGHT_INDEX := 7   # 0x0C7F2E46 / 0x0C7F2EBE (REG_FIGHT) during the attract demo
func cpu_level_for() -> int:
	if arcade_step >= 0: return Rules.ARCADE_CPU_LEVEL[mini(arcade_step, Rules.ARCADE_CPU_LEVEL.size() - 1)]
	if OS.has_environment("PS_CPU_LEVEL"): return int(OS.get_environment("PS_CPU_LEVEL"))
	return ATTRACT_CPU_LEVEL

## REG_FIGHT (op 22): the human's arcade fight index (0x0C7F2E46 + 120 * player). Fight 1 (index 0) is scripted
## gentler: most fighters' default scripts only go for objects there (docs/CPU.md section 6).
func cpu_fight_index() -> int:
	if arcade_step >= 0: return arcade_step
	if OS.has_environment("PS_FIGHT"): return int(OS.get_environment("PS_FIGHT"))
	return ATTRACT_FIGHT_INDEX

func _start_round() -> void:
	pf = 0; ko_f = -1; ko_how = ""; settle = -1; fight_t = 0.0; mv_ok = 0; pose_focus = []
	round_end_len = FL_ROUND_END
	if trainer:   # Training room (not in the original): straight into the fight
		_reset_round(); phase = R.FIGHT; mv_ok = 2
	elif attract and fighters.size() == 2:   # the original's demo: no intro / Ready, straight into the fight (o_screens)
		_reset_round(); phase = R.FIGHT; mv_ok = 2
	elif round_no == 1 and fighters.size() == 2:
		_reset_round(); phase = R.INTRO
		intro_mot = [0, 0] if test_mode else [randi() % 2, randi() % 2]
	else:
		if round_no == 1: _reset_round()
		phase = R.READY   # rounds 2+: the fighters go back to the start points on the Ready's second frame
	if cinema: cinema.round_reset()
	if phase == R.READY: _on_ready()

## The original's fighters stand idle on the start points from the round's first frame: put the feet on the floor
## (the start points sit 5 cm up) so the first frame isn't a 5 cm drop + landing (state 14 > 6)
func _settle_feet() -> void:
	for f in fighters:
		f.flow_pose(0, 0, 0)
		if f.is_inside_tree():   # down onto the floor only: x / z stay exactly on the start point
			var p := f.global_position
			f.velocity = Vector3.DOWN * 9.0; f.move_and_slide()
			var gy: float = arena.ground_y(p) if arena and arena.has_method("ground_y") else f.global_position.y
			f.global_position = Vector3(p.x, gy if absf(gy - f.global_position.y) < 0.1 else f.global_position.y, p.z)
		f.velocity = Vector3.ZERO; f.vcm = Vector3.ZERO

func _on_ready() -> void:
	if hud: hud.announce("ROUND %d" % round_no, 1.0)
	_say("vo_ready")

func _reset_round() -> void:
	arena.clear_gems()
	if fighters.size() != 2: arena.scatter_gems(Rules.GEMS_IN_PLAY)
	if fighters.size() == 2:
		var sp := arena.spawn_points()
		var d: Vector3 = sp[1] - sp[0]; d.y = 0
		fighters[0].reset_round(sp[0], d)
		fighters[1].reset_round(sp[1], -d)
	else:   # the stage's two real start points + mirrored ones; teammates start side by side
		var sp := arena.spawn_points_n(fighters.size(), teams)
		var c := Vector3.ZERO
		for p in sp: c += p
		c /= sp.size()
		for i in fighters.size():
			var d: Vector3 = c - sp[i]; d.y = 0
			fighters[i].reset_round(sp[i], d if d.length() > 0.1 else Vector3.FORWARD)
	_settle_feet()
	if fighters.size() == 2:   # the original: every round each fighter starts holding one stone, the third is on the floor
		for f in fighters:
			f.gems = 0 if f.boss else Rules.GEMS_HELD_AT_START; f.gem_count_changed.emit(f)
		# the third colour is queued; the drop clock puts it on a drop spot at fight frame 299 (vs Final Valgas, who
		# holds none, 2 colours: docs/ITEMS.md 2)
		arena.gem_round_start([1, 2] if fighters[1].boss else [2])
	timer = Rules.ROUND_TIME
	phase_t = 0.0

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	if cinema and cinema.replaying():   # instant replay: the fight stands still while its last seconds play back
		cinema.tick(dt)
		fx.time_scale = 1.0
		cinema.camera(cam, dt)
		if fcam: fcam.post(dt)
		return
	phase_t += dt
	var ws := 1.0   # cinematics: world time scale (0 = frozen by a Power Change / hit-stop, <1 = slow motion)
	if cinema:
		cinema.tick(dt)
		ws = 0.0 if cinema.stop_t > 0.0 else cinema.world_scale
		fx.time_scale = ws
	var sdt := dt * _flow_step(ws)   # the original's KO freeze / 1/4-speed steps (0 = this frame stands still)
	if not tape.is_empty():
		if tape_f < 0 and phase == R.FIGHT: tape_f = 0
		if tape_f >= 0:
			if tape_log: tape_log.store_line(JSON.stringify(tape_row()))
			if tape_f >= tape.size(): tape_done.emit(); tape = []; tape_f = -1
			elif tape[tape_f].size() > 2:
				for c in tape[tape_f][2]: _tape_cmd(str(c))
	if sfxm: sfxm.tick(fighters, tape_f)
	var basis := Basis(Vector3.UP, fcam.yaw if fcam else cam_yaw)   # controls follow the live camera yaw
	if fighters.size() > 2: _retarget()
	for i in fighters.size():
		var f := fighters[i]
		f.cam_basis = basis
		var fdt := sdt
		if cinema: fdt = dt * cinema.scale_for(f)
		# the body's animation runs on the fighter's own clock (KO slow motion included: at 1x the winner's attack clip
		# ended early and its last frame stood frozen while the slowed state machine caught up)
		var fz := _frozen_by(0)   # BUG-65: another fighter's transform / Fusion flash stops this one
		if fz != null and fz != f: fdt = 0.0
		if f.model is PSModel: (f.model as PSModel).time_scale = fdt / dt if dt > 0.0 else 1.0
		if fdt <= 0.0: continue   # frozen: no input, no physics, no animation
		if tape_f >= 0:
			_tape_input(i)
		elif mv_ok > 0 and (phase == R.FIGHT or phase == R.READY):
			if trainer and i == 1 and cpus[i] and not trainer.uses_cpu(): trainer.drive(cpus[i].input, fdt)
			elif cpus[i]: cpus[i].tick(fdt, basis)
			elif fighters.size() == 2: inputs[i].poll_human(kbs[i] if not cpu_flags[1 - i] or i == 0 else -1, pads[i] if pads[i] < Input.get_connected_joypads().size() else -1)
			else: inputs[i].poll_human(kbs[i], Input.get_connected_joypads()[pads[i]] if pads[i] >= 0 and pads[i] < Input.get_connected_joypads().size() else -1)
			if mv_ok == 1:   # "Ready": the original masks the pad to directions + jump (MV_OK 1, & 0xF4)
				var pi: PInput = cpus[i].input if cpus[i] else inputs[i]
				for b in PInput.BUTTONS:
					if b != "jump": pi.held[b] = false; pi.pressed[b] = false
		else:
			(cpus[i].input if cpus[i] else inputs[i]).set_state(Vector2.ZERO, {})
		f.recover_on = phase == R.FIGHT and fz == null   # recovery ticks in round phase 3 only, never in a world freeze (HEALTH.md, BUG-65)
		f.tick(fdt)
	if Fighter.CORE and sdt > 0.0: Fighter.body_push(fighters)   # the original's push on the overlap frame (BUG-45)
	if (phase == R.FIGHT or phase == R.KO) and sdt * ws > 0.0 and _frozen_by(0) == null:   # BUG-65: stage timers stop too
		arena.tick(sdt * ws)
	if flow_log: flow_log.store_line(JSON.stringify(flow_row()))
	pf += 1
	if tape_f >= 0: tape_f += 1
	_update_camera(dt)
	if cinema: cinema.camera(cam, dt)
	fcam.post(dt)
	rec.capture(self)
	frame_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	if not test_mode and phase == R.FIGHT and not attract:
		var esc := Input.is_physical_key_pressed(KEY_ESCAPE)
		var st := esc and not _esc_held   # on the press, like the pad's Start (held, it re-paused right after Resume)
		_esc_held = esc
		for i in fighters.size(): if not cpu_flags[i] and inputs[i].is_pressed("start"): st = true
		if st: _pause(true)

func _end_round(winner: int, how: String) -> void:   # winner = team (in 1v1 and free-for-all: the player index)
	if winner >= 0: wins[winner] += 1
	# Final Valgas's fight is ONE round on the disc (fx-fv logs, Falcon vs him L29: his KO -> phase 5 307 frames -> the
	# ending; Falcon's KO -> phase 5 275 -> CONTINUE?, both after round 1)
	if winner >= 0 and fighters.size() == 2 and (fighters[0].boss or fighters[1].boss): wins[winner] = maxi(wins[winner], Rules.ROUNDS_TO_WIN)
	elif fighters.size() == 2 and winner < 0:   # the original ended a match after two drawn rounds: a draw counts for both (PROVISIONAL)
		wins[0] += 1; wins[1] += 1
	round_log.append({"round": round_no, "winner": winner, "how": how, "hp": fighters.map(func(f): return f.hp), "time_left": snappedf(timer, 0.01)})
	_set_phase(R.ROUND_END)
	round_end_len = FL_ROUND_END
	var mw := Rules.match_winner(wins)
	if mw >= 0 and not (fighters.size() == 2 and wins[0] == wins[1]):   # this round decides the match (a draw match: 245)
		round_end_len = FL_MATCH_LOST if _cpu_side_won(mw) else FL_MATCH_WON
		if mw == 0 and arcade_step >= 0 and fighters[1].char_id == "valgas": round_end_len = FL_VALGAS_END
	end_winner = winner; end_how = how
	var star := -1
	for i in fighters.size():
		if fighters[i].hp > 0 and (winner == fighters[i].team):
			if star < 0 or fighters[i].hp > fighters[star].hp: star = i
	if cinema: cinema.on_round_end(star)
	if hud:   # the winner by name (the owner's first match video said "P1 WINS"), low on the screen, off the winner's face
		var who := "TEAM %s" % ["RED", "BLUE"][clampi(winner, 0, 1)] if is_teams() else \
			(Roster.display_name(fighters[star].char_id).to_upper() if star >= 0 else "P%d" % (winner + 1))
		var txt := ("DRAW" if winner < 0 else "%s WINS" % who) if how != "TIME" else "TIME OVER"
		if how == "TIME": _say("vo_time")
		elif star >= 0 and fighters[star].hp >= Rules.MAX_HP: _say("vo_perfect")
		if cinema and star >= 0:   # the winner's name in the letterbox bar, under him (TIME OVER stays on screen too)
			cinema.show_banner("%s WINS" % who, 2.0)
			if how == "TIME": hud.announce(txt, 1.6)
		else: hud.announce(txt, 1.6)

## The original's match-end phase 5: 307 frames when the player's side (P1 in arcade) won, 275 when the CPU beat him
func _cpu_side_won(w: int) -> bool:
	if fighters.size() != 2 or w < 0 or w > 1: return false
	if cpu_flags[w] and not cpu_flags[1 - w]: return true
	return cpu_flags[0] and cpu_flags[1] and w == 1   # CPU vs CPU (attract, tests): P2 stands for the CPU side

var end_winner := -1
var end_how := ""
var ko_loser: Fighter
static var _intro_frames := {}
var intro_mot := [0, 0]   # the original picks each fighter's intro from k3/0 and k3/1 (both logged; the pick looks random)

func _set_phase(p: int) -> void:
	phase = p; pf = 0; phase_t = 0.0

## The original's round phases frame by frame (constants FL_* above). Called first thing every frame; returns 1.0 when
## the world moves this frame, 0.0 while the KO freeze / slow steps hold it.
func _flow_step(ws: float) -> float:
	var tick := 1.0
	match phase:
		R.INTRO:
			if pf == 0: _settle_feet()   # the physics space is up from the first frame on
			if fighters[1].char_id == "finalvalgas":   # o_ladder 9730-9894: P1 has no intro, his own 163-frame slot
				if pf == FL_FV_INTRO[0]: fighters[1].flow_pose(0, 0, 22)
				if pf >= FL_FV_INTRO[0] + FL_FV_INTRO[1]:
					fighters[1].flow_pose(0, 0, 0); _set_phase(R.READY); mv_ok = 0; _on_ready()
				return tick
			for i in 2:
				var at: int = FL_LEAD + (0 if i == 0 else FL_SLOT[0])
				var n := intro_frames(fighters[i].char_id, intro_mot[i])
				if pf == at and n > 0: fighters[i].flow_pose(3, intro_mot[i], 22)
				elif pf == at + n and n > 0 and fighters[i].gst == 22: fighters[i].flow_pose(0, 0, 0)
			if pf >= FL_LEAD + FL_SLOT[0] + FL_SLOT[1]:
				_set_phase(R.READY); mv_ok = 0; _on_ready()
		R.READY:
			if pf == 1:
				mv_ok = 1
				if round_no > 1: _reset_round()
			elif pf == FL_READY - 1: mv_ok = 2
			elif pf >= FL_READY:
				_set_phase(R.FIGHT); mv_ok = 2
				if hud: hud.announce("ACTION!", 0.8)   # the original's call (and its announcer line)
				_say("vo_action")
				_fight_clock(ws)
		R.FIGHT:
			if ko_f >= 0:
				ko_f += 1
				if ko_f == FL_KO_LAG - 1: mv_ok = 0
				if ko_f >= FL_KO_LAG: _set_phase(R.KO)
			elif _frozen_by(1) == null: _fight_clock(ws)   # BUG-65: the clock stands still in a world freeze
		R.KO:
			if ko_how == "TIME":
				if pf >= FL_TIME_CALL: _end_round(_round_winner(), "TIME")
			else:
				if not cinema and pf > 0 and pf <= FL_KO_FREEZE + FL_KO_SLOW * FL_KO_EVERY:
					tick = 1.0 if pf > FL_KO_FREEZE and (pf - FL_KO_FREEZE - 1) % FL_KO_EVERY == 0 else 0.0
				var w := _round_winner()
				var ok := ko_loser == null or ko_loser.state == Fighter.S.KO or (ko_loser.gst == 15 and ko_loser.hp <= 0)   # the disc: lying, state 15
				for f in fighters:
					if f.team == w and f.hp > 0 and (f.is_busy() or f.state == Fighter.S.JUMP): ok = false
				if cinema and cinema.busy(): ok = false
				if pf > 1800: ok = true   # never stall (a winner stuck in a remaster-only state)
				if ok: settle += 1
				if settle >= FL_SETTLE: _end_round(w, "KO")
		R.ROUND_END:
			if pf == FL_POSE_AT and end_how != "DEMO": _poses()   # logged on frame 2 (once on frame 3, a match won on Londo)
			if round_end_len == FL_VALGAS_END:   # arcade: Valgas beaten -> he turns into Final Valgas (o_ladder 8431-9563)
				var at := FL_VALGAS_AT
				if pf == at:
					_place(fighters[0], [-340.0, 100.0, -400.0]); fighters[0].gst = 8
					_place(fighters[1], [0.0, 0.0, 0.0]); pose_focus = [fighters[1], fighters[1]]
				for k in 4:
					if pf == at + [0, 60, 300, 540][k]: fighters[1].flow_pose(3, 13 + k, 42)
			if pf >= round_end_len: _next_round()
	return tick

## BUG-65 (fx-cov2, o_pc_freeze + every disc log's recovery counters): the disc stops the WORLD while a fighter Power
## Changes (the transform's 130 rows) and while a Fusion flashes (the 40 rows after the first row of the Fusion's first
## 40+-row hold: Ryoma's k1/108 fr 25 from its row 26; every Fusion in pc_moves.json has one): the other fighters (no
## input, no movement, no animation: P2's run and punch during P1's transform never happened), the round clock (99 held
## 189 frames), the recovery counters and the stage's timers (the floor gem came at 469 instead of 299 after one
## transform + one Fusion) all stand still. Reverts and Drives don't stop it.
## Rows [a, b] of F's Power Change timeline during which the world stands still (a > b: none).
static func freeze_window(f: Fighter) -> Vector2i:
	if not f.pc_on: return Vector2i(1, 0)
	if f.pc_kind == "tf": return Vector2i(0, f.pc_rows.size())   # the whole transform (+ its end frame for the clock)
	if f.pc_kind != "atk" or not f.pc_name.begins_with("F"): return Vector2i(1, 0)
	var rows: Array = f.pc_rows
	var s := 0
	for i in range(1, rows.size() + 1):
		if i == rows.size() or (rows[i] as Array).slice(0, 3) != (rows[s] as Array).slice(0, 3):
			if i - s >= 40: return Vector2i(s + 1, s + 40)
			s = i
	return Vector2i(1, 0)

## The fighter whose transform / Fusion flash stops the world on this frame (null: none). AHEAD = 1 before the fighters
## tick (their row this frame is pc_i + 1), 0 after.
func _frozen_by(ahead: int) -> Fighter:
	if not Fighter.CORE: return null
	for f in fighters:
		if not f.pc_on: continue
		var w := freeze_window(f)
		var r := f.pc_i + ahead
		if r >= w.x and r <= w.y: return f
	return null

## Phase 3's clock, once per fight frame (from the phase's first frame): 99 for 60 frames ... 0 at frame 5940, TIME at 5999
func _fight_clock(ws: float) -> void:
	if trainer: return   # training: the clock stands still
	if attract and fighters.size() == 2:   # the demo: the clock stays 99; after 2181 frames P1 poses as the winner
		fight_t += ws
		if fight_t >= FL_DEMO_LEN:
			_set_phase(R.ROUND_END); mv_ok = 0; round_end_len = FL_DEMO_POSE; end_winner = 0; end_how = "DEMO"; _poses()
		return
	timer = maxf(0.0, Rules.ROUND_TIME - floorf(fight_t / FL_SEC))
	if fight_t >= FL_TIME_AT: ko_f = 0; ko_how = "TIME"; ko_loser = null
	fight_t += ws
	if ws > 0.0: elapsed_f += 1

func _next_round() -> void:
	var mw := Rules.match_winner(wins)
	var draw_match: bool = fighters.size() == 2 and wins[0] == wins[1] and wins[0] >= Rules.ROUNDS_TO_WIN
	if end_how == "DEMO": draw_match = true   # the attract demo is one timed round
	if mw >= 0 or draw_match or round_no >= 9:
		if draw_match: mw = -1
		_set_phase(R.DONE)
		if (not test_mode or save_replay) and not attract and not no_replay:   # every match lands in the replay theater
			replay_path = rec.save()
			var g := UI.game()
			if g: g.set("last_replay", replay_path)
		var st := fighters.map(func(f): return f.stats)
		match_over.emit(mw, st)
	else:
		round_no += 1
		_start_round()

## Phase 5's third frame: the winner's pose (k3/2 or k3/3, state 21) on the stage's win spot, the loser lying (k2/144,
## state 8) on its spot off camera (all 11 stages logged, assets/fidelity/flow.json); lost on TIME: state 8 standing in
## k0/0 on the lose spot; a TIME draw: P1 k3/5, P2 k3/6 where they stand.
func _poses() -> void:
	if fighters.size() != 2:
		for f in fighters:
			if f.hp > 0 and f.team == end_winner: f.set_state(Fighter.S.WIN)
		return
	var sp: Dictionary = flow_spots
	if end_winner < 0:
		fighters[0].flow_pose(3, 5, 21); fighters[1].flow_pose(3, 6, 21)
		return
	var w := fighters[end_winner]; var l := fighters[1 - end_winner]
	# k3/2 or k3/3: logged both for round and match wins, no rule found (6 samples): the game's rand, a coin here
	w.flow_pose(3, 2 + randi() % 2 if not test_mode and end_how != "DEMO" else 2, 21)
	if end_how == "TIME" or end_how == "DEMO": l.flow_pose(0, 0, 8)   # lost on time / the demo: state 8 standing in k0/0
	elif l.char_id == "finalvalgas": l.flow_pose(0, 0, 0)   # beaten Final Valgas stands (state 0, k0/0, o_ladder)
	else: l.flow_pose(2, 144, 8)
	if sp.has("win"):
		_place(w, sp.win); _place(l, sp.lose)
		pose_focus = [w, w]

func _place(f: Fighter, cm: Array) -> void:
	f.global_position = Vector3(float(cm[0]), float(cm[1]) + 5.0, float(cm[2])) * 0.01
	f.velocity = Vector3.ZERO

## Frames of a fighter's round intro (k3/0 or k3/1, state 22) = its motion length + 1 (logged: Ryoma k3/0 106, Falcon
## k3/0 120 / k3/1 119, Wang-Tang k3/0 100)
static func intro_frames(cid: String, mot := 0) -> int:
	if _intro_frames.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/clip_frames.json"))
		if d is Dictionary:
			for c in d:
				for k in d[c]:
					if str(k).ends_with("k3_000") or str(k).ends_with("k3_001"): _intro_frames[c + str(k).right(1)] = int(d[c][k]) + 1
	return int(_intro_frames.get(cid + str(mot), 0))

## The camera's targets: both fighters, or the winner alone while he poses on the stage's win spot
func cam_targets() -> Array:
	return pose_focus if pose_focus.size() == 2 else fighters

## One row per frame in tools/flowlog.py's schema (phase = the original's round phase byte: 1 intro, 2 ready, 3 fight,
## 4 KO/TIME call, 5 poses), for tools/flow_diff.py
const FLOW_PHASE := {R.INTRO: 1, R.READY: 2, R.FIGHT: 3, R.KO: 4, R.ROUND_END: 5, R.DONE: 0}
func flow_row() -> Dictionary:
	var ps := []
	for f in fighters:
		var kind := -1; var mot := -1
		if f.model is PSModel:   # the clip asked for this frame (the AnimationTree shows it from this frame's draw on)
			var pm := f.model as PSModel
			var clip := pm.clip_for(pm.playing) if pm.playing != "" else pm.current_clip()
			var k := clip.find("k")
			if k >= 0 and clip.length() >= k + 6: kind = int(clip.substr(k + 1, 1)); mot = int(clip.substr(k + 3, 3))
		var p := f.global_position * 100.0
		ps.append({"x": snappedf(p.x, 0.1), "y": snappedf(p.y, 0.1), "z": snappedf(p.z, 0.1), "kind": kind, "mot": mot,
			"st": f.gst, "hp": f.hp, "rstate": Fighter.S.keys()[f.state]})
	return {"f": Engine.get_physics_frames(), "phase": FLOW_PHASE.get(phase, 0), "mvok": mv_ok, "clock": int(timer),
		"elapsed": elapsed_f, "p": ps}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _oh_t := -99.0
func _sfx(id: String, db := 0.0) -> void:
	if vo == null: return
	var st := Audio.se(id)
	if st == null: return
	if _sfx_pool.is_empty():
		for i in 6:
			var p := AudioStreamPlayer.new(); add_child(p); _sfx_pool.append(p)
	var pick: AudioStreamPlayer = _sfx_pool[0]
	for p in _sfx_pool:
		if not p.playing: pick = p; break
	pick.stream = st; pick.volume_db = db; pick.play()

func _say(id: String) -> void:
	if vo == null: return
	var st := Audio.se(id)
	if st: vo.stream = st; vo.play()

static func stage_music(stg: String) -> String:   # STGn0 -> ST_0n (Londo ST_00 ... Final Valgas's arena ST_0A)
	var n := stg.substr(3, 1).to_upper()
	return "ST_0" + n if ResourceLoader.exists("res://assets/audio/ST_0%s.mp3" % n) else "ST_00"

func is_teams() -> bool:
	for i in teams.size():
		if int(teams[i]) != i: return true
	return false

func _round_winner() -> int:
	if fighters.size() == 2: return Rules.round_winner(fighters[0].hp, fighters[1].hp)
	return Rules.team_round_winner(fighters.map(func(f): return f.hp), teams)

## Battle Royale: who each fighter is after. Humans: the nearest enemy still standing; CPUs choose their own (cpu.gd).
func _retarget() -> void:
	for i in fighters.size():
		var f := fighters[i]
		f.enemies = fighters.filter(func(o): return o != f and o.team != f.team and o.hp > 0)
		if cpus[i] != null and fighters.size() > 2: continue
		var best: Fighter = null; var bd := 1e9
		for o in f.enemies:
			var d: float = (o.global_position - f.global_position).length()
			if d < bd: bd = d; best = o
		if best: f.opponent = best
		elif fighters.size() > 2:
			for o in fighters: if o != f and o.team != f.team: f.opponent = o

func _on_ko(f: Fighter) -> void:
	if phase != R.FIGHT: return
	if trainer: trainer.on_ko(f); return
	if fighters.size() > 2:
		if f.gems > 0: arena.spill_gems(f.global_position, f.gems); f.gems = 0   # his stones go back in play
		var alive := {}
		for o in fighters: if o.hp > 0: alive[o.team] = true
		if alive.size() > 1:   # more than one team still standing: he stays down, the round goes on
			rec.mark("down", fighters.find(f.last_hit_by) if f.last_hit_by else -1)
			if hud: hud.announce("%s DOWN!" % Roster.display_name(f.char_id).to_upper(), 1.2)
			if cinema: cinema.on_hit(f, 150)
			return
	if ko_f < 0: ko_f = 0; ko_how = "KO"; ko_loser = f   # phase 4 starts FL_KO_LAG frames after this hit (_flow_step)
	_say("vo_ko")
	rec.mark("ko", fighters.find(f.last_hit_by) if f.last_hit_by else -1)
	if cinema:
		cinema.on_ko(f)
		if hud: hud.announce("K.O.", 1.8, 0.24)   # high: the KO shot frames the victim mid-screen
	elif not test_mode:   # the original's KO: a 90-frame freeze, then 1/4-speed steps (_flow_step), no extra slow motion
		if hud: hud.announce("K.O.", 1.8)

func _on_fx(kind: String, pos: Vector3) -> void:
	match kind:   # the game's own sounds (tools/sfx_extract.py; which sample when: its sound chip logged in a real fight)
		"hit": if sfxm == null: _sfx("se_hit", -4.0)   # sfx_map plays the disc's impact per attack
		"hit_big":
			if sfxm == null: _sfx("se_hit_heavy", -2.0)
			if sfxm == null and phase_t - _oh_t > 3.0 and phase == R.FIGHT: _oh_t = phase_t; _say("vo_ohno")   # sfx_map: on a gem knocked out
	if cinema and kind in ["hit", "hit_big"]: return   # cinematics draw a damage-scaled spark for it (cinema.on_hit)
	if fx: fx.spawn(kind, pos)
	rec.fx_event(kind, pos)

func _on_power(f: Fighter) -> void:
	rec.mark("power", fighters.find(f))
	if cinema: cinema.on_power(f)

func _on_fusion(f: Fighter) -> void:
	rec.mark("fusion", fighters.find(f))
	if cinema: cinema.on_fusion(f)

func _on_damaged(victim: Fighter, dmg: int) -> void:
	rec.mark("hit", fighters.find(victim.last_hit_by) if victim.last_hit_by else -1, dmg)
	if cinema: cinema.on_hit(victim, dmg)

# The fight camera: the original's rule (measured from its camera object in RAM) + modern framing, wall avoidance and
# scenery fades: scripts/fight_cam.gd.
var fcam: FightCam
var cam_tgt := Vector3.ZERO   # tests / shot.gd debug: the camera's (smoothed) target

func _update_camera(dt: float) -> void:
	if fcam == null:
		fcam = FightCam.new(); fcam.setup(self)
	fcam.update(dt)
	cam_tgt = fcam.tgt

func _unhandled_input(e: InputEvent) -> void:
	if attract and e.is_pressed() and not e is InputEventMouseMotion:
		var g := UI.game()
		if g: g.set("lighting", "original"); g.set("mode", "versus"); g.call("goto_title")

var _esc_held := false
func _pause(on: bool) -> void:
	get_tree().paused = on
	if not on: _esc_held = Input.is_physical_key_pressed(KEY_ESCAPE)
	if on and paused_menu == null:
		paused_menu = UI.pause_menu(self)
		hud.add_child(paused_menu)
	elif not on and paused_menu:
		paused_menu.queue_free(); paused_menu = null

func avg_frame_ms() -> float:
	if frame_ms.is_empty(): return 0.0
	var s := 0.0
	for v in frame_ms: s += v
	return s / frame_ms.size()


## Fidelity tape: this frame's pad bits -> the fighter's controls. The D-pad is camera-relative like the original's
## (UP = the camera's forward); with tape_cam the original's own camera yaw that frame decides it.
func _tape_input(i: int) -> void:
	var row: Array = tape[mini(tape_f, tape.size() - 1)] if tape_f < tape.size() else [0, 0]
	var m: int = int(row[i]) if i < row.size() else 0
	var mv := Vector2(float(m & 0x80 != 0) - float(m & 0x40 != 0), float(m & 0x20 != 0) - float(m & 0x10 != 0))
	var now := {}
	for b in DC_BTN: now[b] = m & int(DC_BTN[b]) != 0
	if not tape_cam.is_empty() and fighters.size() > i:
		var c: Array = tape_cam[mini(tape_f, tape_cam.size() - 1)]
		var fwd := Vector3(float(c[3]) - float(c[0]), 0, float(c[5]) - float(c[2])).normalized()
		fighters[i].cam_basis = Basis(Vector3.UP, atan2(-fwd.x, -fwd.z))
	inputs[i].set_state(mv.limit_length(1.0), now)
	fighters[i].ctrl = inputs[i]

## One frame in the reference-log schema (tools/reflog.py): cm, cm/frame, the game's u16 facing, motion ids
const GAME_STATE := {Fighter.S.IDLE: 0, Fighter.S.RUN: 31, Fighter.S.JUMP: 5, Fighter.S.ATTACK: 10, Fighter.S.GRAB: 37,
	Fighter.S.CARRY: 40, Fighter.S.HITSTUN: 27, Fighter.S.DOWN: 15, Fighter.S.GETUP: 16, Fighter.S.TRANSFORM: 23,
	Fighter.S.POLE: 34, Fighter.S.KO: 15, Fighter.S.WIN: 21}
func tape_row() -> Dictionary:
	var ps := []
	for f in fighters:
		var p := f.global_position * 100.0
		var v := f.vcm if Fighter.CORE else f.velocity * 100.0 / 60.0
		var ang := int(round(atan2(f.facing.x, f.facing.z) / TAU * 65536.0)) & 0xFFFF
		var clip := ""
		var fr := 0
		if f.model is PSModel:
			clip = (f.model as PSModel).current_clip()
			fr = f.gmo_f if f.core_atk else (f.pc_fr if f.pc_on else int((f.model as PSModel).clip_pos() * 60.0 + 0.001))
		var kind := -1; var mot := -1
		var key := GameHits.key_of(clip)   # "k1_016" (Kraken's own clip prefix starts with a k as well)
		if key.length() == 6 and key[0] == "k": kind = int(key.substr(1, 1)); mot = int(key.substr(3, 3))
		var st: int = f.gst if Fighter.CORE else GAME_STATE.get(f.state, -1)
		if not Fighter.CORE and f.state == Fighter.S.ATTACK and f.powered: st = 11
		ps.append({"x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01), "vx": snappedf(v.x, 0.001),
			"vy": snappedf(v.y, 0.001), "vz": snappedf(v.z, 0.001), "ang": ang, "kind": kind, "mot": mot, "fr": fr, "st": st,
			"hp": f.hp, "pc": int(f.powered), "gauge": int(f.gauge * 24.0), "combo": f.combo_hits, "gems": f.gems,
			"rstate": Fighter.S.keys()[f.state]})
	var eye := cam.global_position * 100.0 if cam else Vector3.ZERO
	var tg := cam_tgt * 100.0
	return {"f": tape_f, "p": ps, "timer": int(ceil(timer)), "eye": [snappedf(eye.x, 0.1), snappedf(eye.y, 0.1), snappedf(eye.z, 0.1)],
		"tgt": [snappedf(tg.x, 0.1), snappedf(tg.y, 0.1), snappedf(tg.z, 0.1)], "phase": R.keys()[phase]}

## Tape row commands (tools/tapes.py '@' lines; flycast_drive.lua tapeCmd does the same in the original)
func _tape_cmd(c: String) -> void:
	var w := c.split(" ", false)
	if w.size() < 3: return
	var fi := int(w[1]) - 1
	if fi < 0 or fi >= fighters.size(): return
	var f := fighters[fi]
	match w[0]:
		"place":
			f.global_position = Vector3(float(w[2]), float(w[3]), float(w[4])) * 0.01
			f.velocity = Vector3.ZERO
			var a := float(w[5]) / 65536.0 * TAU
			f.facing = Vector3(sin(a), 0, cos(a)); f._apply_facing()
		"hp":
			f.hp = int(w[2])
		"gems":
			f.gems = int(w[2]); f.gem_count_changed.emit(f)
