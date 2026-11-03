class_name Training
extends Node3D
## Training room (title: TRAINING): you against a dummy on any stage, with the game's own hit data on screen.
## - Overlay: every fighter's body spheres (blue, the game's body set for the motion being played) and live attack
##   spheres (red, the motion's hit step at this frame), straight from GameHits (Pn0_HIT.BIN + the PL sphere sets).
## - Frame data: the move being played, its motion key, the frame it's on, the frames its attack spheres are live
##   (the game's hit steps), recovery after them, the game's damage record, and the damage that really landed.
## - Dummy: STAND / JUMP / WALK / CPU; health refills, the clock doesn't run, a KO doesn't end the round.
## Keys: F1 overlay, F2 dummy, F3 Power Change, F4 reset, F5 health refill, Esc menu.

const DUMMY := ["stand", "jump", "walk", "cpu"]
const C_BODY := Color(0.25, 0.6, 1.0, 0.85)
const C_ATK := Color(1.0, 0.18, 0.12, 1.0)
const SEG := 20

var fight: Fight
var overlay := true
var dummy := "stand"
var refill := true
var mesh := ImmediateMesh.new()
var label: Label
var last := {"dmg": 0, "combo": 0, "combo_dmg": 0, "move": "", "rec": {}}
var _t := 0.0
var _refill_t := [0.0, 0.0]
var _prev_keys := {}

func setup(f: Fight) -> void:
	fight = f
	var mi := MeshInstance3D.new(); mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1 | HD.FIGHTER_LAYER
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 100
	mi.material_override = m
	add_child(mi)
	if not f.test_mode:
		var cl := CanvasLayer.new(); cl.layer = 5; add_child(cl)
		label = UI.label("", 17, Color(1, 1, 1))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.position = Vector2(24, 150); label.size = Vector2(760, 300)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 6)
		cl.add_child(label)
	for i in f.fighters.size():
		var who: Fighter = f.fighters[i]
		who.damaged.connect(func(_x, dmg: int): _on_damaged(who, dmg))

func _on_damaged(victim: Fighter, dmg: int) -> void:
	if victim != fight.fighters[1]: return
	var by: Fighter = victim.last_hit_by if victim.last_hit_by else fight.fighters[0]
	last.dmg = dmg
	last.combo = by.combo_hits
	last.combo_dmg = (int(last.combo_dmg) if by.combo_hits > 1 else 0) + dmg
	last.move = by.cur_attack
	_refill_t[1] = 1.2

## The dummy's controls for this frame (fight.gd calls it instead of the CPU unless the dummy is on CPU)
func drive(inp: PInput, dt: float) -> void:
	_t += dt
	var now := {}
	var m := Vector2.ZERO
	match dummy:
		"jump": now["jump"] = fmod(_t, 1.1) < 0.1
		"walk": m = Vector2(1.0 if fmod(_t, 4.0) < 2.0 else -1.0, 0.0)
	inp.set_state(m, now)

func uses_cpu() -> bool:
	return dummy == "cpu"

func on_ko(f: Fighter) -> void:   # no KO in training: the fighter goes down and gets back up with full health
	f.hp = Rules.MAX_HP

func key_tap(k: Key) -> bool:
	var d := Input.is_physical_key_pressed(k)
	var was: bool = _prev_keys.get(k, false)
	_prev_keys[k] = d
	return d and not was

func _process(dt: float) -> void:
	if fight == null: return
	if key_tap(KEY_F1): overlay = not overlay
	if key_tap(KEY_F2): dummy = DUMMY[(DUMMY.find(dummy) + 1) % DUMMY.size()]
	if key_tap(KEY_F3):
		var p: Fighter = fight.fighters[0]
		if not p.powered:
			for k in 3: p.pick_gem()
	if key_tap(KEY_F4): fight.call("_start_round")
	if key_tap(KEY_F5): refill = not refill
	for i in fight.fighters.size():   # health comes back a moment after the last hit
		var f: Fighter = fight.fighters[i]
		_refill_t[i] = maxf(0.0, _refill_t[i] - dt)
		if refill and _refill_t[i] <= 0.0 and f.state != Fighter.S.HITSTUN: f.hp = Rules.MAX_HP
	_draw()
	if label: label.text = text()

func _draw() -> void:
	mesh.clear_surfaces()
	if not overlay: return
	var any := false
	for f in fight.fighters:
		var fi := f as Fighter
		for s in fi.body_spheres():
			any = _sphere(any, s[0], float(s[1]), C_BODY)
		for s in attack_spheres(fi):
			any = _sphere(any, s[0], float(s[1]), C_ATK)
	if any: mesh.surface_end()

## Live attack spheres of a fighter at this frame (empty between hit steps and for moves the game doesn't hit with)
static func attack_spheres(f: Fighter) -> Array:
	var gh: GameHits = f.ghits
	if gh == null or not gh.ok or not (f.model is PSModel): return []
	var mo := f._motion()
	if not gh.has_move(mo[0]): return []
	var st := gh.at(mo[0], mo[1])
	if st.hit == 0 or st.aset == 0: return []
	return gh.world_spheres(gh.atk_sets, st.aset, (f.model as PSModel).skeleton(), f)

func _sphere(open: bool, c: Vector3, r: float, col: Color) -> bool:
	if not open: mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var cam := get_viewport().get_camera_3d()
	var axes := [[Vector3.RIGHT, Vector3.UP], [Vector3.RIGHT, Vector3.BACK], [Vector3.UP, Vector3.BACK]]
	if cam:   # the outline facing the camera reads best, plus the horizontal ring
		var b := cam.global_transform.basis
		axes = [[b.x, b.y], [Vector3.RIGHT, Vector3.BACK]]
	for a in axes:
		for k in SEG:
			var t0 := TAU * k / SEG; var t1 := TAU * (k + 1) / SEG
			mesh.surface_set_color(col)
			mesh.surface_add_vertex(c + (a[0] * cos(t0) + a[1] * sin(t0)) * r)
			mesh.surface_set_color(col)
			mesh.surface_add_vertex(c + (a[0] * cos(t1) + a[1] * sin(t1)) * r)
	return true

## Frame data of a motion from the game's hit steps: live frames (first, last), total length, recovery after the hits
static func frame_data(f: Fighter, key: String) -> Dictionary:
	var gh: GameHits = f.ghits
	var out := {"key": key, "live": Vector2i(-1, -1), "total": 0, "recovery": 0, "dmg": -1, "type": 0}
	if gh == null or not gh.ok: return out
	out.live = gh.active_window(key)
	if f.model is PSModel:
		var m := f.model as PSModel
		out.total = int(round(m.clip_length(m.current_clip()) * 60.0)) + 1
	if out.live.y >= 0: out.recovery = maxi(0, out.total - out.live.y - 1)
	var hid := gh.first_hit(key)
	if hid == 0 and gh.code_hits.has(key): hid = int(gh.code_hits[key])
	if hid:
		var rec := gh.record(hid)
		out.dmg = int(rec.get("dmg", -1)); out.type = int(rec.get("type", 0))
	return out

func text() -> String:
	var p: Fighter = fight.fighters[0]
	var mo := p._motion()
	var s := "TRAINING    F1 boxes %s   F2 dummy %s   F3 Power Change   F4 reset   F5 refill %s\n" % [
		"ON" if overlay else "OFF", dummy.to_upper(), "ON" if refill else "OFF"]
	s += "%s   %s   motion %s   frame %d\n" % [Roster.display_name(p.char_id).to_upper(),
		p.cur_attack.to_upper() if p.state == Fighter.S.ATTACK else Fighter.S.keys()[p.state], mo[0], mo[1]]
	if p.state == Fighter.S.ATTACK or p.state == Fighter.S.GRAB:
		var fd := frame_data(p, mo[0])
		if fd.live.x >= 0:
			s += "hits on frames %d-%d   recovery %d   total %d" % [fd.live.x, fd.live.y, fd.recovery, fd.total]
		else:
			s += "no attack spheres in the game's data (projectile / effect move: remaster reach)   total %d" % fd.total
		if fd.dmg >= 0: s += "   base damage %d of 240%s" % [fd.dmg, "  (throw)" if fd.type == 2 else ""]
		s += "\n"
	else:
		s += "\n"
	if last.move != "":
		s += "last hit %s: %d damage   combo %d hits, %d damage" % [String(last.move).to_upper(), last.dmg, last.combo, last.combo_dmg]
	return s
