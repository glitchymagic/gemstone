extends RefCounted
## Round end, frame by frame (BUG-2 of lane pstrailer2): from each round-ending KO until the next round starts (or the
## match is over), every fighter must be playing a real clip (the AnimationTree state machine never sits in its empty
## "Start" / "End" node, the replay never poses nothing) and its pose must move whenever its clip is still running.
## The original (logged in Flycast): the KO'd fighter stays in its lying motion k2/144, the winner plays its win motion
## k3/2 or k3/3 (state 21); no frozen frames. Used by tests/run_tests.gd (plain match), tests/cine_tests.gd (cinematics
## on) and tests/ko_check.gd (seeded proof runs).

var fight: Fight
var on := false            # inside a KO .. next round window
var frames := 0            # frames watched
var empty := 0             # frames x fighters with no clip ("", Start, End)
var stuck := 0             # frames x fighters whose clip data moved but the drawn pose didn't
var held := 0              # frames x fighters in a round-end state (KO / down / win) standing still 12+ frames, not
						   # in a resting end pose (lying, a win motion that doesn't loop)
var held_other := 0        # the same for a fighter still finishing a move (an attack / pole state outlasting its clip):
						   # reported, not BUG-2 (the move's timing, see docs/fx-ko.md)
var windows := 0           # KO windows watched
var bad := []              # first few offenders, for the failure message
var other := []            # held_other offenders (fighter, state, clip)
var _sig := {}             # fighter -> last pose signature
var _dsig := {}            # fighter -> last clip-data signature
var _run := {}             # fighter -> frames in a row unchanged while its clip data moved
var _still := {}           # fighter -> frames in a row with the pose unchanged (time running)
var _clip := {}            # fighter -> last frame's clip (a new clip starts a new still run)
const HELD_RUN := 12       # the trailer audit's "frozen" (hit-stops are shorter)
const STUCK_RUN := 2

func _init(f: Fight) -> void:
	fight = f

static func clip_of(m: PSModel) -> String:
	if m.posing:
		var ap: AnimationPlayer = m.players.get(m.form)
		return String(ap.current_animation) if ap else ""
	return m.current_clip()

static func pose_sig(m: PSModel) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var sk := m.skeleton()
	if sk == null: return out
	for i in sk.get_bone_count():
		var o := sk.get_bone_pose_position(i); var q := sk.get_bone_pose_rotation(i)
		out.append_array([o.x, o.y, o.z, q.x, q.y, q.z, q.w])
	return out

static func _same(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if absf(a[i] - b[i]) > 1e-5: return false
	return true

## What the clip's own data says the pose is now (its tracks at the play position); NAN when no clip is live.
## Some disc motions hold still (Valgas's win k3/2 is a 7-frame loop of one pose): those frames must not count.
static func data_sig(m: PSModel) -> float:
	if m.posing or m.time_scale <= 0.0: return NAN
	var c := m.current_clip()
	var ap: AnimationPlayer = m.players.get(m.form)
	if ap == null or not ap.has_animation(c): return NAN
	var a := ap.get_animation(c)
	var t := m.clip_pos()
	var sg := float(c.hash() % 997)
	for ti in a.get_track_count():
		match a.track_get_type(ti):
			Animation.TYPE_ROTATION_3D:
				var q := a.rotation_track_interpolate(ti, t); sg += (q.x * 1.3 + q.y * 2.1 + q.z * 3.7 + q.w * 0.7) * (ti + 1)
			Animation.TYPE_POSITION_3D:
				var v := a.position_track_interpolate(ti, t); sg += (v.x + v.y * 1.7 + v.z * 2.3) * 0.01 * (ti + 1)
	return sg

## An end pose the game holds: the KO'd fighter lying (k2/153 > k2/144) and a winner whose win motion doesn't loop.
static func resting(f: Fighter, m: PSModel) -> bool:
	if f.hp <= 0 and m.playing in ["down", "lying"]: return true
	# the original's lying motion (k2/144 / 145) is one held pose for anyone knocked down (5-10 rows, x4 in the KO's
	# quarter-speed steps: docs/REACT.md, docs/FLOW.md), not a frozen fighter
	if f.state == Fighter.S.DOWN and m.playing == "lying": return true
	# a launch's fall: the disc holds k2/98 (k2/130 from the side) at its last row until the floor or a wall (REACT.md
	# class 1 step 1), x4 in the KO's quarter speed: 5+ frames of one pose
	# (by the clip on screen too: on the landing frame the reaction already asks for k2/99 while the tree, advanced later in
	# the frame, still shows the held k2/98 row: stg30 w8, PS_KO_DEBUG)
	var c := clip_of(m)
	if m.playing.ends_with("k2_098") or m.playing.ends_with("k2_130") or c.ends_with("k2_098") or c.ends_with("k2_130"): return true
	return f.state == Fighter.S.WIN and m.playing in ["win", "win2"]

func tick() -> void:
	if fight == null or not is_instance_valid(fight) or not fight.is_inside_tree(): return
	if not on:
		if fight.phase == Fight.R.KO:
			on = true; windows += 1; _sig = {}; _dsig = {}; _run = {}; _still = {}; _clip = {}
		else: return
	elif fight.phase == Fight.R.INTRO or fight.phase == Fight.R.FIGHT:
		on = false; return
	frames += 1
	for f in fight.fighters:
		if not (f.model is PSModel): continue
		var m := f.model as PSModel
		var c := clip_of(m)
		if c == "" or c == "Start" or c == "End":
			empty += 1
			if bad.size() < 6: bad.append("round %d phase %d %s st%d cine '%s' clip '%s' playing '%s'" % [fight.round_no,
				fight.phase, f.char_id, f.state, fight.cinema.kind if fight.cinema else "-", c, m.playing])
		var s := pose_sig(m)
		var ds := data_sig(m)
		var mv := not is_nan(ds) and _dsig.has(f) and not is_nan(float(_dsig[f])) and absf(ds - float(_dsig[f])) > 2e-3
		if mv and _sig.has(f) and _same(s, _sig[f]):
			_run[f] = int(_run.get(f, 0)) + 1
			if int(_run[f]) >= STUCK_RUN:
				stuck += 1
				if bad.size() < 6: bad.append("stuck round %d %s clip %s pos %.3f" % [fight.round_no, f.char_id, c, m.clip_pos()])
		else: _run[f] = 0
		if not m.posing and m.time_scale > 0.0 and _sig.has(f) and _same(s, _sig[f]) and c == str(_clip.get(f, c)): _still[f] = int(_still.get(f, 0)) + 1
		else: _still[f] = 0
		if int(_still[f]) >= HELD_RUN and not resting(f, m):
			if f.state in [Fighter.S.KO, Fighter.S.WIN, Fighter.S.DOWN]:
				held += 1
				if bad.size() < 6: bad.append("held round %d phase %d %s st%d hp%d clip %s playing '%s' pos %.3f" % [fight.round_no, fight.phase, f.char_id, f.state, f.hp, c, m.playing, m.clip_pos()])
				if OS.has_environment("PS_KO_DEBUG"):
					var tr: AnimationTree = m.trees.get(m.form)
					var pb := tr.get("parameters/playback") as AnimationNodeStateMachinePlayback
					print("KOHELD f%d %s ts %.2f active %s posed %s fading '%s' path %s len %.3f then '%s' %.3f rx %s/%s m %d row %d st %d gst %d floor %s y %.2f" % [Engine.get_physics_frames(), f.char_id, m.time_scale, tr.active, m._posed, pb.get_fading_from_node(), str(pb.get_travel_path()), pb.get_current_length(), m.then_anim, m.then_left, f.rx_on, f.rx_phase, f.rx_m, f.rx_mrow, f.state, f.gst, str(f.grounded()), f.global_position.y])
			else:
				held_other += 1
				if other.size() < 4 and not other.has("%s st%d %s" % [f.char_id, f.state, c]): other.append("%s st%d %s" % [f.char_id, f.state, c])
		_sig[f] = s
		_dsig[f] = ds
		_clip[f] = c

func ok() -> bool:
	return empty == 0 and stuck == 0 and held == 0

func report() -> String:
	return "%d KO windows, %d frames: %d with no clip, %d stuck, %d held%s; finishing a move: %d held%s" % [windows, frames,
		empty, stuck, held, "" if bad.is_empty() else " (" + "; ".join(bad) + ")", held_other,
		"" if other.is_empty() else " (" + ", ".join(other) + ")"]
