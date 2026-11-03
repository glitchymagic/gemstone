extends SceneTree
const QuietExit = preload("res://tests/quiet_exit.gd")
## BUG-28 breakage hunt (lane pstrailer2, docs/HUNT.md). Drives the remaster like a player and flags every breakage
## frame by frame, with a repro (seed, frame, fighter, stage, look, state).
##   fight:  both fighters human-driven through the keyboard path a player uses (Input events -> PInput.poll_human,
##           P1 = WASD/J/K/Space/L/U/I/Enter, P2 = arrows/keypad) with seeded fuzz: chords and bursts of every button
##           and direction, plus forced situations every few seconds (fighters face to face, at a pole, next to a
##           throwable, at the stage edge, 3 gems = Power Change, low health = KO + next round, clock run down = TIME,
##           pause menu opened and driven). The match restarts when it ends, until FRAMES.
##   menus:  the whole screen flow from the title (Game autoload): random menu keys on title / options / select /
##           arcade ladder / VS / results / continue / pause / replays, P1 fights through the same keys (matches are
##           shortened by running the clock down), title QUIT disabled.
##   static: one-shot checks (every sound / music the code asks for exists on disk, every stage's own music).
## Godot --headless --path game --fixed-fps 60 -s res://tests/hunt.gd -- MODE STAGE a,b SEED FRAMES OUT.jsonl
## (menus/static: STAGE and a,b are "-"). env PS_LOOK (remaster|classic). OUT: one JSON line per first occurrence of a
## finding (cls, key, f, seed, stage, chars, look, ctx), then a "summary" line with counts per class and key.
## Prints HUNT_END <summary> as its last line; tools/hunt.sh runs the matrix, tools/hunt_report.py sums it up.

const KW := preload("res://tests/ko_watch.gd")

class HuntLogger extends Logger:
	var sink: Callable
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var where := "%s:%d" % [file, line]
		for bt in script_backtraces:
			if bt != null and bt.get_frame_count() > 0:
				where = "%s:%d %s" % [bt.get_frame_file(0), bt.get_frame_line(0), bt.get_frame_function(0)]
				break
		var msg := rationale if rationale != "" else code
		var cls: String = ["godot_error", "godot_warning", "script_error", "shader_error"][clampi(error_type, 0, 3)]
		sink.call(cls, where, msg, function)
	func _log_message(_message: String, _error: bool) -> void:
		pass

## Runs after every other node's _process: the checks see the frame as it is drawn (physics + animation done).
class Late extends Node:
	var cb: Callable
	func _ready() -> void:
		process_priority = 1 << 30
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _process(_d: float) -> void:
		cb.call()

var mode := "fight"
var stage := "stg00"
var chars: Array = ["falcon", "ryoma"]
var seed_v := 1
var max_f := 3600
var out: FileAccess
var look := ""
var rng := RandomNumberGenerator.new()
var lg := HuntLogger.new()
var mx := Mutex.new()
var n := 0                 # frames run
var fight: Fight = null
var matches := 0
var counts := {}           # "cls|key" -> count
var first := {}            # "cls|key" -> true
var cls_counts := {}       # cls -> count
var cov := {}             # coverage: frames per fighter state / phase, forced situations run, clips seen
var screens := {}          # menus: screen class -> frames
var transitions := {}      # menus: "A>B" -> count
var last_screen := ""
var scen := ""             # the forced situation running now (context for findings)
var scen_left := 0
var next_scen := 120

# per-player fuzz state
var held_keys: Array = [{}, {}]   # physical keycode -> true (what this player holds now)
var chord_left := [0, 0]
var mash: Array = ["", ""]        # a button being mashed (pressed every other frame)
const KB_KEYS := [
	{"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S, "punch": KEY_J, "kick": KEY_K, "jump": KEY_SPACE,
	 "action": KEY_L, "fusion1": KEY_U, "fusion2": KEY_I, "start": KEY_ENTER},
	{"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "punch": KEY_KP_1, "kick": KEY_KP_2,
	 "jump": KEY_KP_0, "action": KEY_KP_3, "fusion1": KEY_KP_4, "fusion2": KEY_KP_5, "start": KEY_KP_ENTER}]
const DIRS := [[], ["up"], ["down"], ["left"], ["right"], ["up", "left"], ["up", "right"], ["down", "left"], ["down", "right"]]
const MENU_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D, KEY_ENTER, KEY_SPACE, KEY_J,
	KEY_K, KEY_L, KEY_ESCAPE, KEY_O, KEY_KP_ENTER]

# per-fighter detector state
var st_run: Array = [0, 0]        # frames in the current state
var st_last: Array = [-1, -1]
var gst_run: Array = [0, 0]
var gst_last: Array = [-1, -1]
var empty_run: Array = [0, 0]
var still_run: Array = [0, 0]
var stuck_run: Array = [0, 0]
var oom_run: Array = [0, 0]
var wedge_run: Array = [0, 0]      # frames in the air without moving (H-2 / H-3 / H-12)
var pos_last: Array = [Vector3.INF, Vector3.INF]
var sig_last: Array = [PackedFloat32Array(), PackedFloat32Array()]
var dsig_last: Array = [NAN, NAN]
var ov_run := 0
var phase_run := 0
var phase_last := -1
var timer_last := 0.0
var timer_flat := 0
var idle_world := 0
var world_sig := 0.0
var paused_run := 0

# frames a state may last before it counts as stuck (the longest real motion in that state + margin, 60 fps)
const STATE_MAX := {Fighter.S.ATTACK: 420, Fighter.S.GRAB: 300, Fighter.S.HITSTUN: 240, Fighter.S.DOWN: 360,
	Fighter.S.GETUP: 150, Fighter.S.TRANSFORM: 300, Fighter.S.POLE: 360, Fighter.S.JUMP: 600}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	mode = str(a[0]) if a.size() > 0 else "fight"
	stage = str(a[1]) if a.size() > 1 else "stg00"
	if a.size() > 2 and str(a[2]) != "-": chars = Array(str(a[2]).split(","))
	seed_v = int(a[3]) if a.size() > 3 else 1
	max_f = int(a[4]) if a.size() > 4 else 3600
	var op := str(a[5]) if a.size() > 5 else "/tmp/hunt.jsonl"
	out = FileAccess.open(op, FileAccess.WRITE)
	look = OS.get_environment("PS_LOOK") if OS.has_environment("PS_LOOK") else "remaster"
	rng.seed = hash("%s|%s|%s|%d" % [mode, stage, ",".join(chars), seed_v])
	lg.sink = _on_log
	OS.add_logger(lg)
	Input.use_accumulated_input = false   # injected key events reach Input's key state + the viewport at once
	var g := root.get_node_or_null("Game")
	if g: g.set("cinematics", false)   # the default: the original's presentation
	var late := Late.new(); late.name = "HuntLate"; late.cb = _late; root.add_child(late)
	match mode:
		"static": _static_checks()
		"menus":   # the title opens on frame 2 (the Game autoload is not in the tree yet here)
			seed(seed_v)   # the arcade row roll, attract picks ...
			OS.set_environment("PS_SEED", str(seed_v))   # every Fight's arena (gems): the run repeats frame for frame
		_: _new_fight()

func _finalize() -> void:
	_release_all(0); _release_all(1)

## ---------------------------------------------------------------- findings
func _ctx() -> Dictionary:
	var c := {"f": n, "scen": scen, "screen": last_screen}
	var fi := _cur_fight()
	if fi:
		c["phase"] = Fight.R.keys()[fi.phase]
		c["round"] = fi.round_no
		var ps := []
		for f in fi.fighters:
			var m := f.model as PSModel
			ps.append({"id": f.char_id, "st": Fighter.S.keys()[f.state], "gst": f.gst, "hp": f.hp, "gems": f.gems,
				"pc": int(f.powered), "clip": m.current_clip() if m else "", "anim": m.playing if m else "",
				"pos": [snappedf(f.global_position.x, 0.01), snappedf(f.global_position.y, 0.01), snappedf(f.global_position.z, 0.01)]})
		c["p"] = ps
	return c

var log_n := 0
func _on_log(cls: String, where: String, msg: String, _fn: String) -> void:
	mx.lock()
	log_n += 1
	if log_n == 20000: _find("error_flood", "20000+ error lines: run ended early", {})
	var m := msg.strip_edges()
	if m.length() > 160: m = m.substr(0, 160)
	_find(cls, "%s | %s" % [where, m], {})
	mx.unlock()

func _find(cls: String, key: String, extra: Dictionary) -> void:
	var k := cls + "|" + key
	counts[k] = int(counts.get(k, 0)) + 1
	cls_counts[cls] = int(cls_counts.get(cls, 0)) + 1
	if first.has(k): return
	first[k] = true
	var row := {"cls": cls, "key": key, "seed": seed_v, "mode": mode, "stage": _stage_now(), "chars": _chars_now(),
		"look": look, "ctx": _ctx()}
	row.merge(extra)
	if out: out.store_line(JSON.stringify(row)); out.flush()

func _stage_now() -> String:
	var fi := _cur_fight()
	return fi.stage if fi else stage

func _chars_now() -> String:
	var fi := _cur_fight()
	return ",".join(fi.chars) if fi else ",".join(chars)

func _cur_fight() -> Fight:
	if fight and is_instance_valid(fight) and fight.is_inside_tree(): return fight
	var g := root.get_node_or_null("Game")
	if g:
		var c = g.get("current")
		if c is Fight and is_instance_valid(c) and (c as Fight).is_inside_tree(): return c
	return null

## ---------------------------------------------------------------- fight mode
func _new_fight() -> void:
	if fight and is_instance_valid(fight): fight.queue_free()
	_release_all(0); _release_all(1)
	fight = Fight.new(); fight.cpu_flags = [false, false]; fight.no_replay = true
	fight.stage = stage; fight.chars = chars.duplicate()
	fight.seed_override = seed_v
	fight.match_over.connect(func(_w, _s): matches += 1)
	root.add_child(fight)
	_reset_detectors()

func _reset_detectors() -> void:
	st_run = [0, 0]; st_last = [-1, -1]; gst_run = [0, 0]; gst_last = [-1, -1]; empty_run = [0, 0]; still_run = [0, 0]
	stuck_run = [0, 0]; oom_run = [0, 0]; wedge_run = [0, 0]; pos_last = [Vector3.INF, Vector3.INF]; sig_last = [PackedFloat32Array(), PackedFloat32Array()]; dsig_last = [NAN, NAN]
	ov_run = 0; phase_run = 0; phase_last = -1; timer_flat = 0; idle_world = 0

func _process(_d: float) -> bool:
	n += 1
	if mode == "static" or n > max_f or log_n >= 20000:
		_finish(); return true
	if mode == "menus": _menus_tick()
	else: _fight_tick()
	return false

func _late() -> void:
	var fi := _cur_fight()
	if fi and not fi.is_queued_for_deletion() and fi.fighters.size() >= 2: _check_fight(fi)

func _fight_tick() -> void:
	if fight == null or not is_instance_valid(fight):
		_new_fight(); return
	if fight.phase == Fight.R.DONE:
		if fight.phase_t > 0.5: _new_fight()
		return
	if paused:
		_pause_menu_tick(); return
	paused_run = 0
	if fight.phase == Fight.R.FIGHT:
		_scenario_tick()
	for i in 2: _fuzz_player(i)

func _scenario_tick() -> void:
	if scen_left > 0:
		scen_left -= 1
		if scen_left == 0: scen = ""
		return
	next_scen -= 1
	if next_scen > 0: return
	next_scen = rng.randi_range(180, 420)
	var kinds := ["close", "close", "pole", "prop", "edge", "edge", "pc", "lowhp", "time", "pause", "air_close", "fuzz"]
	scen = kinds[rng.randi() % kinds.size()]
	_cov("scen:" + scen)
	scen_left = rng.randi_range(90, 240)
	var fs := fight.fighters
	var who := rng.randi() % 2
	var me: Fighter = fs[who]; var you: Fighter = fs[1 - who]
	var ar := fight.arena
	match scen:
		"close", "air_close":
			var d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			if d.length() < 0.1: d = Vector3.FORWARD
			_place(you, me.global_position + d * rng.randf_range(0.6, 1.4) + (Vector3.UP * 1.5 if scen == "air_close" else Vector3.ZERO))
		"pole":
			if ar.poles.is_empty(): scen = "fuzz"; return
			var p: Vector3 = ar.poles[rng.randi() % ar.poles.size()]
			var d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var fy := ar.floor_y_at(p.x + d.x * 1.2, p.z + d.z * 1.2, p.y + 3.0)   # -INF: no floor there
			if not is_finite(fy): scen = "fuzz"; return
			_place(me, Vector3(p.x, fy + 0.05, p.z) + d * 1.2)
		"prop":
			var live := ar.props.filter(func(x): return is_instance_valid(x) and x.state == Prop.REST)
			if live.is_empty(): scen = "fuzz"; return
			var pr: Node3D = live[rng.randi() % live.size()]
			_place(me, pr.global_position + Vector3(0.9, 0, 0))
		"edge":
			var d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var far := me.global_position + d * 40.0
			var q := ar.clamp_point(far, 0.5)
			var fy := ar.floor_y_at(q.x, q.z, me.global_position.y + 3.0)
			_place(me, Vector3(q.x, (fy if is_finite(fy) else me.global_position.y) + 0.05, q.z))
		"pc":
			var guard := 0
			while not me.powered and guard < 4 and not me.boss:
				me.pick_gem(); guard += 1
		"lowhp":
			you.hp = mini(you.hp, rng.randi_range(1, 6))
		"time":
			# the clock is fight_t (fight frames, fx-flow): a write to .timer is overwritten the next frame (BUG-62)
			fight.fight_t = maxf(fight.fight_t, Fight.FL_TIME_AT - rng.randf_range(30.0, 180.0))
		"pause":
			_tap(KEY_ESCAPE)

func _place(f: Fighter, p: Vector3) -> void:   # like the tape's "place" command (tools/tapes.py)
	if not p.is_finite(): return
	# only where the fighter's capsule fits (stage, scenery, invisible walls): a spot the original lets him stand on but
	# the remaster's collision fills is tests/area_check.gd's "blocked" list, not a fight bug; placing him inside it
	# wedged him there for good
	var cs: CollisionShape3D = null
	for ch in f.get_children(): if ch is CollisionShape3D: cs = ch
	if cs:
		var q := PhysicsShapeQueryParameters3D.new(); q.shape = cs.shape
		q.transform = Transform3D(cs.global_transform.basis, p + (cs.global_position - f.global_position) + Vector3.UP * 0.02)
		q.collision_mask = 1 | 4; q.exclude = [f.get_rid()]
		if not f.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			_cov("place_blocked"); scen = "fuzz"; return
	f.global_position = p
	f.velocity = Vector3.ZERO

## One player's pad this frame: a seeded chord (direction + buttons) held 1-24 frames, or a mashed button.
func _fuzz_player(i: int) -> void:
	var k: Dictionary = KB_KEYS[i]
	if mash[i] != "":
		var kc: int = k[mash[i]]
		if held_keys[i].has(kc): _key(i, kc, false)
		else: _key(i, kc, true)
	chord_left[i] -= 1
	if chord_left[i] > 0: return
	_release_all(i)
	chord_left[i] = rng.randi_range(1, 24)
	mash[i] = ""
	if rng.randf() < 0.12:
		mash[i] = ["punch", "kick", "jump", "action", "fusion1"][rng.randi() % 5]
		chord_left[i] = rng.randi_range(10, 40)
		return
	var want := []
	if rng.randf() > 0.3: want.append_array(DIRS[rng.randi_range(1, DIRS.size() - 1)])
	for b in ["punch", "kick", "jump", "action"]:
		if rng.randf() < 0.22: want.append(b)
	if rng.randf() < 0.05: want.append("fusion1")
	if rng.randf() < 0.05: want.append("fusion2")
	if rng.randf() < 0.004: want.append("start")
	for b in want: _key(i, int(k[b]), true)

func _key(i: int, kc: int, down: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = kc as Key; e.keycode = kc as Key; e.pressed = down
	Input.parse_input_event(e)
	if i >= 0:
		if down: held_keys[i][kc] = true
		else: held_keys[i].erase(kc)

func _release_all(i: int) -> void:
	for kc in held_keys[i].keys(): _key(i, int(kc), false)
	held_keys[i] = {}

func _tap(kc: int) -> void:
	_key(-1, kc, true); _key(-1, kc, false)

## Pause menu: random up/down for a while, then Resume (Escape / start do nothing there: noted in HUNT.md).
func _pause_menu_tick() -> void:
	paused_run += 1
	_release_all(0); _release_all(1)
	if paused_run == 10: _tap(KEY_ESCAPE)   # the original: Start toggles the pause; try Escape and the pad's Start first
	if paused_run == 14:
		for down in [true, false]:
			var jb := InputEventJoypadButton.new(); jb.button_index = JOY_BUTTON_START; jb.pressed = down; jb.device = 0
			Input.parse_input_event(jb)
	if paused_run == 30 and paused: _find("pause", "pause menu: Escape / pad Start don't resume (only its Resume button does)", {})
	if paused_run < 30: return
	if paused_run % 7 == 0: _tap([KEY_UP, KEY_DOWN, KEY_ESCAPE, KEY_ENTER][rng.randi() % 3] if paused_run < 60 else KEY_UP)
	if paused_run >= 60:
		var fo := root.gui_get_focus_owner()
		if fo is Button and (fo as Button).text == "Resume": _tap(KEY_ENTER)
		elif paused_run % 7 == 3: _tap(KEY_UP)
	if paused_run > 600:
		_find("softlock", "pause menu never resumed", {})
		fight._pause(false)

## ---------------------------------------------------------------- menus mode
func _menus_tick() -> void:
	var g := root.get_node_or_null("Game")
	if n == 2 and g: g.call("goto_title")
	var cur = g.get("current") if g else null
	var nm := "-"
	if cur != null and is_instance_valid(cur): nm = (cur as Node).get_script().get_global_name() if (cur as Node).get_script() else cur.get_class()
	if cur is Fight and g: nm = "Fight:%s" % str(g.get("mode"))   # arcade / versus / training / brawl / attract
	if paused: nm = "Pause"
	screens[nm] = int(screens.get(nm, 0)) + 1
	if nm != last_screen:
		if last_screen != "": transitions["%s>%s" % [last_screen, nm]] = int(transitions.get("%s>%s" % [last_screen, nm], 0)) + 1
		last_screen = nm; phase_run = 0
		_reset_detectors()
	if cur is TitleScreen and (cur as TitleScreen).menu != null:   # QUIT ends the run: the hunt keeps it disabled
		for b in (cur as TitleScreen).menu.get_children():
			if b is Button and (b as Button).text == "QUIT": (b as Button).disabled = true
	if cur is Fight and not paused:
		var fi := cur as Fight
		if fi.phase == Fight.R.FIGHT:   # play it through the keys, keep matches short: the clock runs down after ~8 s
			_fuzz_player(0)
			if fi.phase_t > 2.0 and fi.timer > 1.5: fi.fight_t = maxf(fi.fight_t, Fight.FL_TIME_AT - 60.0)   # every round ends on TIME after ~3 s: more screens (BUG-62: the clock is fight_t)
			if rng.randf() < 0.002: fi.fighters[1].hp = mini(fi.fighters[1].hp, 3)
			return
		_release_all(0)
	if rng.randf() < 0.12:
		_tap(MENU_KEYS[rng.randi() % MENU_KEYS.size()])
	# a run of one screen far longer than any real menu needs, with keys coming in: report it once per screen
	if not (cur is Fight) and not (cur is ReplayTheater) and screens[nm] % 7200 == 0:
		_find("menu_stuck", "%s: 120 s of random keys without leaving" % nm, {})

## ---------------------------------------------------------------- detectors
func _check_fight(fi: Fight) -> void:
	if fi.phase != phase_last: phase_last = fi.phase; phase_run = 0
	else: phase_run += 1
	var ph: int = fi.phase
	var lim := {Fight.R.INTRO: 900, Fight.R.KO: 1200, Fight.R.ROUND_END: 900}
	if lim.has(ph) and phase_run == int(lim[ph]) and not paused:
		_find("softlock", "phase %s lasts %d+ frames" % [Fight.R.keys()[ph], phase_run], {})
	if ph == Fight.R.FIGHT and not paused and not fi.trainer:
		if absf(fi.timer - timer_last) < 1e-6: timer_flat += 1
		else: timer_flat = 0
		if timer_flat == 240: _find("softlock", "round clock stands still 4 s in FIGHT", {})
	timer_last = fi.timer
	if fi.timer < 0.0 or fi.timer > Rules.ROUND_TIME + 0.01: _find("hud_range", "timer %s" % str(fi.timer), {})
	_cov("phase:" + Fight.R.keys()[ph])
	if paused: _cov("paused"); return
	var fs := fi.fighters
	var ws := 0.0
	var frz: Fighter = fi.call("_frozen_by", 0) if fi.has_method("_frozen_by") else null   # BUG-65: the disc's world freeze
	for i in mini(fs.size(), 2):
		var f: Fighter = fs[i]
		var p := f.global_position
		ws += p.x * 3.1 + p.y * 7.7 + p.z * 1.3 + f.state * 0.37
		if frz != null and frz != f: _cov("world_frozen"); continue   # held by another's transform / Fusion flash
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z) or is_nan(f.velocity.length()):
			_find("nan", "%s position/velocity NaN" % f.char_id, {"who": i})
			continue
		if f.hp < 0 or f.hp > Rules.MAX_HP: _find("hud_range", "%s hp %d" % [f.char_id, f.hp], {"who": i})
		if f.gems < 0 or f.gems > 3: _find("hud_range", "%s gems %d" % [f.char_id, f.gems], {"who": i})
		if fi.arena.has_area() and p.y < fi.arena.area_floor_min - 1.0:
			_find("fell", "%s below the stage's lowest floor (y %.2f < %.2f)" % [f.char_id, p.y, fi.arena.area_floor_min], {"who": i})
		# out of the map: feet on something that is not the stage's floor / outside the original's area, on the ground
		if fi.arena.has_area() and f.grounded() and f.state not in [Fighter.S.POLE] and fi.arena.out_of_map(p):
			oom_run[i] += 1
			if oom_run[i] == 20: _find("oom", "%s on the ground out of the map 20+ frames (%s)" % [f.char_id, Fighter.S.keys()[f.state]], {"who": i})
		else: oom_run[i] = 0
		# hanging in the air: not on the floor and not moving at all (wedged into collision; poles / transforms hold still)
		# (not in the KO freeze / round end: the disc holds a KO'd launch 90 frames; not in a Power Change move, gst 11:
		# the disc's air Drives / Fusions hover 40-106 frames, e.g. Gunrock 92 at y 785 in o_pc_gunrock; fx-cov2 hunt7)
		if ph == Fight.R.FIGHT and f.gst != 11 and \
				not f.grounded() and f.state not in [Fighter.S.POLE, Fighter.S.TRANSFORM, Fighter.S.GRAB] and f.grabbed == null \
				and p.distance_to(pos_last[i]) < 1e-4 and f.hit_stop <= 0 and f.hitstop <= 0.0:
			wedge_run[i] += 1
			if wedge_run[i] == 60: _find("wedged", "%s hangs in the air without moving 60+ frames (%s, y %.2f)" % [f.char_id,
				Fighter.S.keys()[f.state], p.y], {"who": i})
		else: wedge_run[i] = 0
		pos_last[i] = p
		# states that never end
		if f.state == st_last[i]: st_run[i] += 1
		else: st_last[i] = f.state; st_run[i] = 0
		var mxs: int = int(STATE_MAX.get(f.state, 0))
		if f.boss and f.state == Fighter.S.ATTACK: mxs = 900
		if mxs > 0 and st_run[i] == mxs:
			_find("stuck_state", "%s %s lasts %d+ frames (gst %d, clip %s)" % [f.char_id, Fighter.S.keys()[f.state], mxs, f.gst,
				(f.model as PSModel).current_clip() if f.model is PSModel else ""], {"who": i})
		if ph == Fight.R.FIGHT and f.state == Fighter.S.KO and st_run[i] == 180:
			_find("stuck_state", "%s KO state while the round goes on (FIGHT 180+ frames)" % f.char_id, {"who": i})
		if ph == Fight.R.FIGHT and f.state == Fighter.S.WIN:
			_find("stuck_state", "%s WIN state during FIGHT" % f.char_id, {"who": i})
		if f.gst == gst_last[i]: gst_run[i] += 1
		else: gst_last[i] = f.gst; gst_run[i] = 0
		if f.gst in [4, 6, 2, 24, 32] and gst_run[i] == 120:
			_find("stuck_state", "%s game state %d (a few-frame state) lasts 120+ frames" % [f.char_id, f.gst], {"who": i})
		_cov("st:" + Fighter.S.keys()[f.state]); _cov("gst:%d" % f.gst)
		if f.powered: _cov("powered")
		if f.carry: _cov("carrying")
		if not (f.model is PSModel): continue
		var m := f.model as PSModel
		if m.posing: continue
		var c := m.current_clip()
		_cov("clip:" + c)
		if c == "" or c == "Start" or c == "End":
			empty_run[i] += 1
			if empty_run[i] == 3: _find("anim_empty", "%s AnimationTree '%s' (anim %s, state %s)" % [f.char_id, c, m.playing, Fighter.S.keys()[f.state]], {"who": i})
		else: empty_run[i] = 0
		var s: PackedFloat32Array = KW.pose_sig(m)
		var ds: float = KW.data_sig(m)
		var same: bool = KW._same(s, sig_last[i])
		var dmv := not is_nan(ds) and not is_nan(float(dsig_last[i])) and absf(ds - float(dsig_last[i])) > 2e-3
		if dmv and same:
			stuck_run[i] += 1
			if stuck_run[i] == 3: _find("pose_frozen", "%s pose stands still while clip %s runs" % [f.char_id, c], {"who": i})
		else: stuck_run[i] = 0
		var moving_state := f.state in [Fighter.S.RUN, Fighter.S.ATTACK, Fighter.S.HITSTUN, Fighter.S.GETUP, Fighter.S.TRANSFORM, Fighter.S.GRAB]
		if same and moving_state and m.time_scale > 0.0 and f.hit_stop <= 0 and f.hitstop <= 0.0: still_run[i] += 1
		else: still_run[i] = 0
		if still_run[i] == 20:
			_find("pose_frozen", "%s %s with a still pose 20+ frames (clip %s)" % [f.char_id, Fighter.S.keys()[f.state], c], {"who": i})
		if s.size() > 0 and _is_rest(m):
			_find("tpose", "%s rest pose (T-pose) in %s" % [f.char_id, Fighter.S.keys()[f.state]], {"who": i})
		sig_last[i] = s; dsig_last[i] = ds
	if fs.size() >= 2 and ph == Fight.R.FIGHT:
		var a: Fighter = fs[0]; var b: Fighter = fs[1]
		var grabbing := a.state in [Fighter.S.GRAB] or b.state in [Fighter.S.GRAB] or a.grabbed != null or b.grabbed != null
		if not grabbing and CamCheck.overlap(a, b) > 0.3: ov_run += 1
		else: ov_run = 0
		if ov_run == 30: _find("overlap", "%s and %s inside each other 30+ frames (%s / %s)" % [a.char_id, b.char_id,
			Fighter.S.keys()[a.state], Fighter.S.keys()[b.state]], {})
		if absf(ws - world_sig) < 1e-6: idle_world += 1
		else: idle_world = 0
		world_sig = ws
		if idle_world == 600: _find("softlock", "nothing moves for 10 s in FIGHT while keys come in", {})

func _cov(k: String) -> void:
	cov[k] = int(cov.get(k, 0)) + 1

func _is_rest(m: PSModel) -> bool:
	var sk := m.skeleton()
	if sk == null or sk.get_bone_count() < 4: return false
	for b in sk.get_bone_count():
		var r := sk.get_bone_rest(b)
		if not sk.get_bone_pose_rotation(b).is_equal_approx(r.basis.get_rotation_quaternion()): return false
	return true

## ---------------------------------------------------------------- static checks
func _static_checks() -> void:
	var ids := {}
	var re := RegEx.create_from_string("(?:_sfx|_say|Audio\\.se|Audio\\.music)\\(\"([A-Za-z0-9_]+)\"")
	var d := DirAccess.open("res://scripts")
	for fnm in d.get_files():
		if not fnm.ends_with(".gd"): continue
		var src := FileAccess.get_file_as_string("res://scripts/" + fnm)
		for mt in re.search_all(src):
			ids[mt.get_string(1)] = fnm
	for id in ids:
		var is_music := ResourceLoader.exists("res://assets/audio/%s.mp3" % id)
		var is_se := ResourceLoader.exists("res://assets/audio/se/%s.wav" % id)
		if not is_music and not is_se: _find("sound_missing", "%s asks for '%s': no file" % [ids[id], id], {})
	for stg in ["stg00", "stg10", "stg20", "stg30", "stg40", "stg50", "stg60", "stg70", "stg80", "stg90", "stga0"]:
		var mus := Fight.stage_music(stg)
		if mus != "ST_0" + stg.substr(3, 1).to_upper(): _find("sound_missing", "%s plays %s (its own track is missing)" % [stg, mus], {})

func _finish() -> void:
	var summ := {"summary": true, "mode": mode, "stage": stage, "chars": ",".join(chars), "seed": seed_v, "look": look,
		"frames": n, "matches": matches, "classes": cls_counts, "counts": counts, "cov": cov}
	if mode == "menus": summ["screens"] = screens; summ["transitions"] = transitions
	if out: out.store_line(JSON.stringify(summ)); out.close()
	print("HUNT_END ", JSON.stringify({"frames": n, "matches": matches, "classes": cls_counts}))
	QuietExit.drain(root)   # BUG-38: stop the sounds + let the audio thread free their playbacks (--fixed-fps outruns it)
	quit(0)
