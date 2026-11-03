class_name PSModel
extends Node3D
## The ripped fighter: the disc's Pxx.MDL parts rigidly skinned to the skeleton read out of the game's RAM
## (assets/ripped/<id>.glb, built by tools/export_rig.py), animated by the game's own motions recorded from
## RAM while its Motion Check debug menu played them (tools/clips.py). Normal and Power Change forms.
## Each form gets an AnimationTree (state machine of every captured clip, short cross-fades).

const RIP_DIR := "res://assets/ripped/"
static func files(char_id: String) -> Array:
	for c in Roster.ALL:
		if c.id == char_id: return (c.files as String).to_lower().split("/")
	return []
const UNIT := 0.01   # disc units are centimetres
const XFADE := 0.06

var forms := {}          # bool -> Node3D (the imported GLB scene)
var ids := {}            # bool -> the form's disc id (p00, p01 ...)
var trees := {}          # bool -> AnimationTree
var players := {}        # bool -> AnimationPlayer
var clipmap := {}        # bool -> {game name: clip name}
var vgroups := {}        # bool -> [[head parts], [right hand parts], [left hand parts]] (MeshInstance3D)
var vsel := {}           # bool -> {clip: [head, right, left]} the game's per-motion face/hand choice
var chains := {}         # bool -> {action: next action} motion sequences logged in real fights (drive K 96 > 97)
var form := false
var playing := ""
var then_anim := ""      # queued follow-up once the current one-shot ends (jump start -> air, pick-up -> carry)
var then_left := 0.0
var toon: Shader
var time_scale := 1.0    # cinematics: 0 = frozen, 0.25 = slow motion (the trees are advanced by hand at this rate)
var posing := false      # replays: the AnimationPlayer is driven straight from a recorded clip + time
## Root motion (2026-10-23 audit of the owner's match video): the game moves a fighter by its motion's hip translation, and
## attack clips carry the hip up to 2.5 m forward. Before, that travel was only drawn: the body walked into the other
## fighter and snapped back when the next clip started. While root_motion is on (attacks, grabs: fighter.gd) the
## visible body is pinned over the collision body (the form's offset = -hip x/z) and the hip's travel goes to the
## fighter as root_delta, which moves the body (move_and_collide stops it at the other fighter or a wall, like the
## game's push sphere). Clip changes / cross-fades / loops never count as travel.
var root_motion := false
var root_delta := Vector3.ZERO   # PSModel space, metres, not yet taken by the fighter
var pin := Vector3.ZERO          # the form's offset (PSModel space)
var _rm_clip := ""
var _rm_pos := 0.0
var _rm_prev := Vector3.ZERO
var _rm_hold := 0.0
var _rm_pinned := false
var _hip := {}                   # form -> b00 bone index

static func available(char_id: String) -> bool:
	var f := files(char_id)
	return not f.is_empty() and ResourceLoader.exists(RIP_DIR + str(f[0]) + ".glb")

static func create_for(char_id: String, power: bool) -> PSModel:
	if not available(char_id): return null
	var m := PSModel.new()
	m.name = "PSModel"
	m.char_id = char_id
	m._load(char_id)
	m.set_form(power)
	return m

func _load(char_id: String) -> void:
	toon = load("res://shaders/toon.gdshader")
	for i in mini(2, files(char_id).size()):   # Final Valgas (PA0) has no Power Change form
		var id: String = files(char_id)[i]
		var path := HD.model_path(id, RIP_DIR + id + ".glb")
		if not ResourceLoader.exists(path): continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		inst.scale = Vector3.ONE * UNIT
		add_child(inst)
		var f := i == 1
		forms[f] = inst
		ids[f] = id
		var cm := {}
		var mp := RIP_DIR + id + "_clips.json"
		if FileAccess.file_exists(mp):
			var j = JSON.parse_string(FileAccess.get_file_as_string(mp))
			if j is Dictionary:
				cm = j.get("map", {})
				var gs := []
				for g in j.get("variant_groups", []):
					var nodes := []
					for pn in g: nodes.append(inst.find_child(pn, true, false))
					gs.append(nodes)
				vgroups[f] = gs
				vsel[f] = j.get("variants", {})
				chains[f] = j.get("chains", {})
				for pn in j.get("hidden", []):
					var mi := inst.find_child(pn, true, false)
					if mi: (mi as Node3D).visible = false
				var ap0 := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if ap0:
					for cn in j.get("loops", []):
						if ap0.has_animation(cn): ap0.get_animation(cn).loop_mode = Animation.LOOP_LINEAR
		clipmap[f] = cm
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			players[f] = ap
			trees[f] = _make_tree(inst, ap)
		_apply_joint_scale(inst, char_id, f)
		HD.fighter(inst, toon, id)

func _make_tree(inst: Node3D, ap: AnimationPlayer) -> AnimationTree:
	var sm := AnimationNodeStateMachine.new()
	for an in ap.get_animation_list():
		var node := AnimationNodeAnimation.new()
		node.animation = an
		sm.add_node(an, node)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	inst.add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.tree_root = sm
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # advanced in _process
	tree.active = true
	return tree

func has_clip(anim: String) -> bool:   # mapped for this fighter (clip_for falls back to idle)
	var cm: Dictionary = clipmap.get(form, {})
	var ap: AnimationPlayer = players.get(form)
	return cm.has(anim) and ap != null and ap.has_animation(cm[anim])

func clip_for(anim: String) -> String:
	var cm: Dictionary = clipmap.get(form, {})
	var c: String = cm.get(anim, anim)
	var ap: AnimationPlayer = players.get(form)
	if ap and ap.has_animation(c): return c
	c = cm.get("idle", "idle")
	return c if ap and ap.has_animation(c) else ""

func clip_length(anim: String) -> float:
	var c := clip_for(anim)
	if c == "": return 0.0
	return (players[form] as AnimationPlayer).get_animation(c).length

func chain_length(anim: String) -> float:   # one action + its logged follow-ups (chains), in seconds
	var t := 0.0; var a := anim; var seen := {}
	while a != "" and not seen.has(a) and has_clip(a):
		seen[a] = true
		t += clip_length(a)
		a = (chains.get(form, {}) as Dictionary).get(a, "")
	return t

## The clip the AnimationTree is on right now and its play position (s): the game's hit steps run on motion frames
func current_clip() -> String:
	var tree: AnimationTree = trees.get(form)
	if tree == null: return ""
	var pb := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	return String(pb.get_current_node())

func clip_pos() -> float:
	var tree: AnimationTree = trees.get(form)
	if tree == null: return 0.0
	var pb := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	return pb.get_current_play_position()

var _skel := {}
func skeleton() -> Skeleton3D:
	if not _skel.has(form):
		var f: Node = forms.get(form)
		_skel[form] = f.find_child("Skeleton3D", true, false) as Skeleton3D if f else null
	return _skel[form]

func set_form(power: bool) -> void:
	if not forms.has(power): power = false
	form = power
	for k in forms:
		forms[k].visible = (k == power)
		(forms[k] as Node3D).position = Vector3.ZERO
	pin = Vector3.ZERO; _rm_clip = ""; root_delta = Vector3.ZERO
	for k in trees: (trees[k] as AnimationTree).active = (k == power)
	var p := playing
	playing = ""
	play(p if p != "" else "idle")
	# a re-activated tree restarts in its empty Start node and only takes the clip on its next advance: take it now, so
	# this frame's recording (replay.gd, captured before the trees advance) and the new form's skeleton have the clip
	var tr: AnimationTree = trees.get(power)
	if tr and tr.is_inside_tree(): tr.advance(0.0)

func _apply_variants(c: String) -> void:
	var sel: Array = (vsel.get(form, {}) as Dictionary).get(c, [0, 0, 0])
	var gs: Array = vgroups.get(form, [])
	for gi in gs.size():
		var want := int(sel[gi]) if gi < sel.size() else 0
		var nodes: Array = gs[gi]
		if want >= nodes.size() or nodes[want] == null: want = 0
		for ni in nodes.size():
			if nodes[ni]: (nodes[ni] as Node3D).visible = (ni == want)

func play_then(anim: String, next: String) -> void:
	play(anim)
	if playing != anim: return
	var c := clip_for(anim)
	then_anim = next if c != "" and c != clip_for(next) else ""
	then_left = clip_length(anim)
	if then_anim == "": play(next)

func _process(dt: float) -> void:
	if posing: return
	dt *= time_scale
	var tree: AnimationTree = trees.get(form)
	if tree and tree.active:
		if not _posed: tree.advance(dt)   # the core posed this frame itself (core_frame): what you see is what hits
		_posed = false
		_root_motion(dt)
	if then_anim == "": return
	then_left -= dt
	if then_left <= 0.0:
		var n := then_anim
		then_anim = ""
		play(n)

func play(anim: String) -> void:
	then_anim = ""
	var tree: AnimationTree = trees.get(form)
	if tree == null: return
	var c := clip_for(anim)
	if c == "": return
	var sm := tree.tree_root as AnimationNodeStateMachine
	var pb := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var cur := pb.get_current_node()
	if anim == playing and cur == StringName(c) and (players[form] as AnimationPlayer).get_animation(c).loop_mode != Animation.LOOP_NONE: return
	playing = anim
	_apply_variants(c)
	if cur == c or cur in [&"", &"Start", &"End"]:   # same clip again, or the machine sits in its empty Start / End
		pb.start(c, true)          # node (no pose to cross-fade from: travel from there blends in the rest pose)
		_queue_chain(anim)
		return
	if not sm.has_transition(cur, c):
		var tr := AnimationNodeStateMachineTransition.new()
		tr.xfade_time = XFADE
		tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		sm.add_transition(cur, c, tr)
	pb.travel(c, true)
	_queue_chain(anim)

func _queue_chain(anim: String) -> void:
	var nx: String = (chains.get(form, {}) as Dictionary).get(anim, "")
	if nx != "" and has_clip(nx):
		then_anim = nx
		then_left = clip_length(anim)

## The hip's horizontal offset from the model origin (PSModel space, metres) in the pose on display now.
func hip_offset() -> Vector3:
	var sk := skeleton()
	var inst: Node3D = forms.get(form)
	if sk == null or inst == null: return Vector3.ZERO
	if not _hip.has(form): _hip[form] = sk.find_bone("b00")
	var bi: int = _hip[form]
	if bi < 0: return Vector3.ZERO
	var rel := inst.global_transform.affine_inverse() * sk.global_transform
	var p := Transform3D(inst.basis, Vector3.ZERO) * (rel * sk.get_bone_global_pose(bi).origin)
	return Vector3(p.x, 0.0, p.z)

## fx-reach (docs/REACH.md, BUG-97): where the disc draws the body and where it hits.
## - Size: the fight draws each fighter at a joint scale (its joint matrices carry it: every body / attack sphere radius
##   in RAM = the file radius x that scale, and joint-to-joint distances disc / clip are the same): Gunrock 1.2, Jack
##   1.135, Wang-Tang 0.91 ... (assets/fidelity/body_scale.json, [normal, Power Change]). The clips keep the disc's hip
##   height but their bone offsets are the raw ones, so the core scales everything below the hip: b00's pose scale.
## - Hip: the RAM-captured clip's hip carries Motion Check's own travel. On the moves_* tapes the disc's hip joint sits at
##   the clip's hip (clip frame = game frame - 1) minus the table travel the core already moved the fighter by (0-3 cm on
##   every logged ground attack), except the air attacks and a few long-travel ones (k1/74, Ryoma k1/26 ...): those take
##   the disc's own hip, per game frame, from assets/fidelity/hip_pin.json.
## travel_on: the core owns the pose and the pin this frame (core_frame).
const BODY_SCALE := "res://assets/fidelity/body_scale.json"
const HIP_PIN := "res://assets/fidelity/hip_pin.json"
static var _bscale := {}
static var _hpin := {}
var char_id := ""
var travel_on := false
var travel_pin := Vector3.ZERO   # PSModel space, metres
var _travel_was := false
var _posed := false              # core_frame set this frame's pose (the tree's own advance waits)

static func _reach_tables() -> void:
	if _bscale.is_empty() and FileAccess.file_exists(BODY_SCALE): _bscale = JSON.parse_string(FileAccess.get_file_as_string(BODY_SCALE))
	if _hpin.is_empty() and FileAccess.file_exists(HIP_PIN): _hpin = JSON.parse_string(FileAccess.get_file_as_string(HIP_PIN))

static func joint_scale(cid: String, power: bool) -> float:
	_reach_tables()
	var e = _bscale.get(cid)
	if not (e is Array) or (e as Array).size() < 2: return 1.0
	var v = e[1 if power else 0]
	return float(v) if v != null else 1.0

func _apply_joint_scale(inst: Node3D, cid: String, power: bool) -> void:
	var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null: return
	var bi := sk.find_bone("b00")
	if bi >= 0: sk.set_bone_pose_scale(bi, Vector3.ONE * joint_scale(cid, power))

## The core's pose for game frame g of its motion: clip frame g - 1 exactly (the game's frame counter, not the tree's own
## clock: the tree lagged one frame and cross-faded the first 4), and the pin that puts the hip where the disc draws it.
## table_pin = the table travel the fighter already moved (side, up, forward, metres; ground attacks).
func core_frame(clip: String, g: int, table_pin: Vector3) -> void:
	var tree: AnimationTree = trees.get(form)
	if tree == null or posing or not (players[form] as AnimationPlayer).has_animation(clip): return
	var pb := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	pb.start(clip, true); tree.advance(0.0)
	var t := maxf(0.0, float(g - 1)) / 60.0
	if t > 0.0: tree.advance(t)
	if playing != "" and clip_for(playing) != clip: playing = ""
	_reach_tables()
	var rows = (_hpin.get(char_id, {}) as Dictionary).get(clip)
	if rows is Array and (rows as Array).size() > 0:
		var r: Array = rows[clampi(g, 0, (rows as Array).size() - 1)]
		travel_pin = Vector3(float(r[0]) * UNIT, 0.0, float(r[1]) * UNIT)   # the disc's hip - the clip's hip (side, fwd)
	else:
		travel_pin = table_pin
	travel_on = true; _posed = true
	_root_motion(0.0)

func _root_motion(dt: float) -> void:
	if travel_on:
		_travel_was = true
		_rm_pinned = false; _rm_prev = hip_offset(); _rm_clip = current_clip(); _rm_pos = clip_pos()
		_set_pin(travel_pin)
		return
	if _travel_was:   # the core's motion is over: the next clip's hip is over the feet again
		_travel_was = false
		_set_pin(Vector3.ZERO)
	var h := hip_offset()
	var c := current_clip(); var pos := clip_pos()
	if c != _rm_clip or pos + 0.0001 < _rm_pos:
		_rm_hold = XFADE + 0.02; _rm_clip = c
	elif _rm_hold > 0.0: _rm_hold -= dt
	elif root_motion: root_delta += h - _rm_prev
	_rm_prev = h; _rm_pos = pos
	if root_motion or (_rm_pinned and _rm_hold > 0.0):
		_rm_pinned = true
		pin = -h
	else:
		_rm_pinned = false
		pin = pin.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * dt))
	_set_pin(pin)

func _set_pin(v: Vector3) -> void:
	pin = v
	var inst: Node3D = forms.get(form)
	if inst: inst.position = v

func take_root_delta() -> Vector3:
	var d := root_delta
	root_delta = Vector3.ZERO
	return d

## How far a clip carries the hip (metres, horizontal): attacks with travel move the fighter by it (root motion).
func root_travel(anim: String) -> float:
	var c := clip_for(anim)
	var ap: AnimationPlayer = players.get(form)
	if c == "" or ap == null: return 0.0
	var a := ap.get_animation(c)
	var best := 0.0
	for ti in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_POSITION_3D or not String(a.track_get_path(ti)).ends_with(":b00"): continue
		for k in a.track_get_key_count(ti):
			var v: Vector3 = a.track_get_key_value(ti, k)
			best = maxf(best, Vector2(v.x, v.z).length() * UNIT)
	return best

## Replays: what is on screen now ([form, clip, time, pin x, pin z]) and putting a recorded one back.
func snapshot() -> Array:
	var tree: AnimationTree = trees.get(form)
	if tree == null or posing:
		var ap0: AnimationPlayer = players.get(form)
		return [form, String(ap0.current_animation) if ap0 else "", ap0.current_animation_position if ap0 and ap0.current_animation != "" else 0.0, pin.x, pin.z]
	var pb := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	return [form, String(pb.get_current_node()), pb.get_current_play_position(), pin.x, pin.z]

## The live AnimationTree is left active while posing: it is advanced by hand (_process) and posing skips that, so it
## simply waits. Deactivating it (as before 10-26) restarted its state machine in the empty Start node: after every
## instant replay both fighters stood in the rest pose / froze mid-air until their next action (BUG-2), and the
## recorder stored those frames as clip "Start", which replays could not pose.
var _live := []   # [form, pin] when posing started

func pose(f: bool, clip: String, t: float, pin_xz := Vector2.ZERO) -> void:
	if not posing:
		posing = true
		_live = [form, pin]
	if not forms.has(f): f = false
	if f != form:
		form = f
		for k in forms: forms[k].visible = (k == form)
	var ap: AnimationPlayer = players.get(form)
	if ap == null or clip == "" or not ap.has_animation(clip): return
	if ap.current_animation != clip:
		ap.play(clip, 0.0, 0.0)
		_apply_variants(clip)
	var a := ap.get_animation(clip)
	if a.loop_mode == Animation.LOOP_NONE: t = minf(t, a.length - 0.0005)   # at its very end the player stops (no clip)
	ap.seek(t, true)
	_set_pin(Vector3(pin_xz.x, 0.0, pin_xz.y))

func unpose() -> void:   # back to the live AnimationTree (it resumes exactly where it was)
	if not posing: return
	posing = false
	for k in players: (players[k] as AnimationPlayer).stop(true)
	if not _live.is_empty():
		form = _live[0]; _set_pin(_live[1])
	for k in forms: forms[k].visible = (k == form)
	for k in trees: (trees[k] as AnimationTree).active = (k == form)
	var c := current_clip()
	if c != "" and c != "Start": _apply_variants(c)
	_rm_clip = ""   # the live pose comes back: no travel from the jump
