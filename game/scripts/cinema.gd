class_name Cinema
extends Node3D
## Cinematics (title menu CINEMATICS ON/OFF; Off = the original's presentation: the fight camera and plain sparks).
## - Power Change (3rd gem): hit-stop, the rest of the scene freezes and drains to grey while the camera swoops round the
##   fighter during the game's own transform motion (k3/8, 130 frames); a gem-coloured shockwave + light burst lights the
##   stage, then time snaps back behind a recolour wave.
## - Power Fusion: hit-stop, a short side-on camera, shake.
## - Every connected hit: sparks, streaks and a ring scaled by its damage; impact frames on the heavy ones.
## - Round-ending KO: slow motion from a low hero angle, a ~2 s instant replay of the final hit, then the winner.
## Fight asks scale_for() how fast each fighter runs this frame and lets camera() override its camera.

const PC_LEN := 130.0 / 60.0   # the game's transform state = the whole cutscene
const PC_BURST := 1.45         # shockwave moment inside the transform motion (s)
const BLEND_BACK := 0.3
const FUSION_LEN := 0.85
const FUSION_STOP := 0.2
const KO_SLOW := 1.4           # real seconds of slow motion after the final hit
const KO_SCALE := 0.22
const REPLAY_PRE := 80         # recorded frames before the KO frame shown in the instant replay
const REPLAY_SLOW := 24        # ... the last of them play at REPLAY_SLOW_K
const REPLAY_SLOW_K := 0.4
const IMPACT_GAP := 0.14       # fusions hit every few frames: impact frames at most this often

var fight: Fight
var kind := ""                 # "", power, fusion, ko, replay, win
var t := 0.0
var hero: Fighter
var foe: Fighter
var world_scale := 1.0
var stop_t := 0.0
var post: MeshInstance3D
var post_mat: ShaderMaterial
var ui: CanvasLayer
var bars: Array[ColorRect] = []
var caption: Label
var banner: Label
var banner_t := 0.0
var bar_amt := 0.0
var bar_want := 0.0
var desat := 0.0
var desat_all := 0.0
var wave_r := 0.0
var impact := 0.0
var flash := 0.0
var impact_cd := 0.0
var cam_start: Transform3D
var cam_last: Transform3D
var look_pt := Vector3.ZERO
var back_t := 0.0
var orbit := Vector3.ZERO      # start angle, start radius, start height (power swoop)
var sweep := 0.0
var side := 1.0
var burst_done := false
var ko_frame := 0
var rp_i := 0.0
var rp_start := 0
var rp_end := 0
var rp_last := -1
var rp_saved := []
var rng := RandomNumberGenerator.new()
var count := {"power": 0, "fusion": 0, "ko": 0, "replay": 0, "hits": 0, "impacts": 0}

func setup(f: Fight) -> void:
	fight = f
	rng.seed = 99
	post = MeshInstance3D.new(); post.name = "CinePost"
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	post_mat = ShaderMaterial.new(); post_mat.shader = load("res://shaders/cine_post.gdshader")
	post_mat.render_priority = -128   # first of the transparent pass: sparks / rings draw over it in colour
	q.material = post_mat; post.mesh = q
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.visible = false
	f.cam.add_child(post)
	ui = CanvasLayer.new(); ui.layer = 6; add_child(ui)
	for i in 2:
		var r := ColorRect.new(); r.color = Color(0, 0, 0); r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(r); bars.append(r)
	caption = UI.label("", 46, Color(1, 0.88, 0.45))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.position = Vector2(60, 40)
	ui.add_child(caption)
	banner = UI.label("", 64, Color(1.0, 0.85, 0.25))   # the winner's name, centred in the lower letterbox bar
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 12)
	banner.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	ui.add_child(banner)

func busy() -> bool:   # the fight holds its KO phase until the slow motion + replay are over
	return kind == "ko" or kind == "replay"

func replaying() -> bool:
	return kind == "replay"

func scale_for(f: Fighter) -> float:
	if stop_t > 0.0: return 0.0
	if kind == "power" and f == hero: return 1.0
	return world_scale

## ---------- triggers
func on_power(f: Fighter) -> void:
	if not f.powered or busy() or kind == "win": return
	count.power += 1
	hero = f; foe = f.opponent
	kind = "power"; t = 0.0; burst_done = false
	world_scale = 0.0; stop_t = 0.0
	impact = 1.0; desat = 0.0; wave_r = 0.0
	bar_want = 1.0
	cam_start = fight.cam.global_transform
	var c := _chest(hero)
	var rel := cam_start.origin - c
	orbit = Vector3(atan2(rel.z, rel.x), clampf(Vector2(rel.x, rel.z).length(), 3.0, 9.0), rel.y)
	var a_end := _best_angle(c, 3.3, -0.45)   # finish in front of him, in the clear, for the burst
	var d := wrapf(a_end - orbit.x, -PI, PI)
	if absf(d) < 2.1: d += TAU * (1.0 if d >= 0.0 else -1.0)
	var d2 := d - TAU * signf(d)   # the other way round: take whichever passes further from walls
	if absf(d2) >= 2.1 and absf(d2) <= 4.4 and _arc_loss(c, d2) < _arc_loss(c, d) - 0.5: d = d2
	sweep = d
	pc_env = _pc_envelope(hero); pc_aim_set = false; pc_fov = FOV
	if fight.hud: fight.hud.visible = false
	fight.fx.charge(c, Gem.COLORS, PC_BURST)
	fight.rec.fx_event("charge", c, PC_BURST)

func on_fusion(f: Fighter) -> void:
	if busy() or kind == "power": return
	count.fusion += 1
	hero = f; foe = f.opponent
	kind = "fusion"; t = 0.0
	stop_t = FUSION_STOP; world_scale = 1.0
	impact = 0.8; bar_want = 0.7
	cam_start = fight.cam.global_transform
	side = 1.0
	var l1 := _side_loss(_cam_fusion, 1.0); var l2 := _side_loss(_cam_fusion, -1.0)
	var ab := _flat((foe.global_position if foe else hero.global_position + hero.facing) - hero.global_position)
	var perp := Vector3(-ab.z, 0, ab.x)
	side = 1.0 if perp.dot(cam_start.origin - hero.global_position) >= 0.0 else -1.0
	if absf(l1 - l2) > 0.3: side = 1.0 if l1 < l2 else -1.0   # the side with room for the camera
	fight.fx.shake(0.5)

func on_hit(victim: Fighter, dmg: int) -> void:
	count.hits += 1
	var pos := _chest(victim)
	fight.fx.impact_spark(pos, dmg)
	fight.rec.fx_event("spark", pos, dmg)
	if impact_cd > 0.0: return
	var d := Rules.dmg_1000(dmg)
	if d >= 100 or victim.state == Fighter.S.DOWN or victim.hp <= 0:
		impact = 1.0; stop_t = maxf(stop_t, 0.05 + minf(d, 300) / 4000.0)
		fight.fx.shake(minf(0.7, 0.2 + d / 500.0))
		count.impacts += 1; impact_cd = IMPACT_GAP
	elif d >= 55:
		impact = maxf(impact, 0.45); impact_cd = IMPACT_GAP
	else:
		flash = maxf(flash, 0.12)

func on_ko(victim: Fighter) -> void:
	count.ko += 1
	foe = victim
	hero = victim.last_hit_by if victim.last_hit_by and victim.last_hit_by != victim else victim.opponent
	ko_frame = fight.rec.frames.size()
	kind = "ko"; t = 0.0
	world_scale = KO_SCALE; stop_t = 0.1
	desat = 0.0; wave_r = 0.0; burst_done = false   # a cutscene it cut short
	impact = 1.0; flash = 0.3; bar_want = 1.0
	cam_start = fight.cam.global_transform
	var kv := _flat(victim.global_position - (hero.global_position if hero else victim.global_position - victim.facing))
	var perp := Vector3(-kv.z, 0, kv.x)
	side = 1.0 if perp.dot(cam_start.origin - victim.global_position) >= 0.0 else -1.0
	ko_v = Vector3.ZERO; ko_floor = victim.global_position.y
	ko_a = _clear_angle(victim.global_position, atan2(perp.z * side, perp.x * side), 4.6, 1.1)
	fight.fx.shake(0.7)

func on_round_end(winner: int) -> void:
	if winner < 0 or winner >= fight.fighters.size(): _finish(); return
	hero = fight.fighters[winner]
	kind = "win"; t = 0.0; world_scale = 1.0; bar_want = 1.0
	cam_start = fight.cam.global_transform
	win_a = _clear_angle(hero.global_position, atan2(hero.facing.z, hero.facing.x), 4.4, 1.15)   # in front, clear

func show_banner(text: String, secs: float) -> void:
	banner.text = text; banner_t = secs

func round_reset() -> void:   # a new round cuts straight back to the fight camera
	off_s = Vector3.ZERO
	kind = ""; world_scale = 1.0; stop_t = 0.0; back_t = 0.0
	desat = 0.0; desat_all = 0.0; wave_r = 0.0; bar_want = 0.0; bar_amt = 0.0
	caption.text = ""
	if fight.hud: fight.hud.visible = true

## ---------- per frame (real dt), before the fighters tick
func tick(dt: float) -> void:
	t += dt
	stop_t = maxf(0.0, stop_t - dt)
	impact = maxf(0.0, impact - dt * 20.0)
	flash = maxf(0.0, flash - dt * 6.0)
	impact_cd = maxf(0.0, impact_cd - dt)
	back_t = maxf(0.0, back_t - dt)
	match kind:
		"power":
			world_scale = 0.0
			if not burst_done:
				desat = minf(1.0, desat + dt * 3.5)
				if t >= PC_BURST: _burst()
			else:
				wave_r += dt * 24.0
			if t >= PC_LEN: _finish()
		"fusion":
			if t >= FUSION_LEN: _finish()
		"ko":
			world_scale = KO_SCALE
			if t >= KO_SLOW: _start_replay()
		"replay":
			_replay_step()
	bar_amt = move_toward(bar_amt, bar_want, dt * 4.0)
	banner_t = maxf(0.0, banner_t - dt)
	banner.visible = banner_t > 0.0
	banner.modulate.a = clampf(banner_t / 0.25, 0.0, 1.0)
	_apply_post()

func _burst() -> void:
	burst_done = true
	var c := _chest(hero)
	impact = 1.0; flash = 0.3
	fight.fx.shockwave(c, Gem.COLORS)
	fight.rec.fx_event("shockwave", c)
	fight.fx.shake(0.8)

func _finish() -> void:
	if kind != "" and kind != "win": back_t = BLEND_BACK
	kind = ""; world_scale = 1.0
	desat = 0.0; wave_r = 0.0; desat_all = 0.0; bar_want = 0.0
	caption.text = ""
	if fight.hud: fight.hud.visible = true

## ---------- instant replay: the last seconds before the KO, from the match recording
func _start_replay() -> void:
	var fr: Array = fight.rec.frames
	rp_start = maxi(0, ko_frame - REPLAY_PRE); rp_end = fr.size() - 1
	if rp_end - rp_start < 20:
		kind = ""; world_scale = 1.0; return
	count.replay += 1
	rp_saved = []
	for f in fight.fighters:
		rp_saved.append([f.global_position, f.velocity, f.model.rotation.y if f.model else 0.0])
	var ps := []
	for p in fight.arena.props: ps.append([p.position, p.rotation, p.visible])
	rp_saved.append(ps)
	fight.rec.paused = true
	kind = "replay"; t = 0.0; world_scale = 0.0
	rp_i = rp_start; rp_last = rp_start - 1
	rp_a = _replay_angle()
	caption.text = "REPLAY"
	desat_all = 0.22; flash = 0.7
	if fight.hud: fight.hud.visible = false

func _replay_step() -> void:
	var fr: Array = fight.rec.frames
	var i := mini(int(rp_i), rp_end)
	Replay.apply_fighters(fr[i], fight.fighters)
	Replay.apply_props(fr[i], fight.arena.props)
	for k in range(rp_last + 1, i + 1):   # sparks + bursts that happened in the frames we just crossed
		for e in (fr[k] as Dictionary).get("e", []): play_fx_event(e)
	rp_last = i
	var sp := 1.0
	if rp_i >= ko_frame - REPLAY_SLOW and rp_i < ko_frame: sp = REPLAY_SLOW_K
	elif rp_i >= ko_frame: sp = 2.5   # those frames were recorded in slow motion already
	rp_i += sp
	if rp_i > rp_end: _end_replay()

func play_fx_event(e: Array) -> void:
	replay_fx(fight.fx, e)

static func replay_fx(fx: FX, e: Array) -> void:   # a recorded fx event, again (instant replay, theater, highlights)
	var p := Vector3(e[1], e[2], e[3])
	match String(e[0]):
		"spark": fx.impact_spark(p, int(e[4]) if e.size() > 4 else 12)
		"shockwave": fx.shockwave(p, Gem.COLORS)
		"charge": fx.charge(p, Gem.COLORS, float(e[4]) if e.size() > 4 else PC_BURST)
		_: fx.spawn(String(e[0]), p)

func _end_replay() -> void:
	for i in fight.fighters.size():
		var f: Fighter = fight.fighters[i]
		var s: Array = rp_saved[i]
		f.global_position = s[0]; f.velocity = s[1]
		if f.model:
			f.model.rotation.y = s[2]
			if f.model is PSModel: (f.model as PSModel).unpose()
	var ps: Array = rp_saved[fight.fighters.size()]
	for k in mini(ps.size(), fight.arena.props.size()):
		var p: Node3D = fight.arena.props[k]
		p.position = ps[k][0]; p.rotation = ps[k][1]; p.visible = ps[k][2]
	fight.rec.paused = false
	kind = ""; world_scale = 1.0
	desat_all = 0.0; caption.text = ""; flash = 0.5
	bar_want = 1.0
	if fight.hud: fight.hud.visible = true

## ---------- camera (after the fight camera is placed; overrides it while a cinematic runs)
const FOV := 41.1
func camera(cam: Camera3D, dt: float) -> void:
	var live := cam.global_transform
	var want: Transform3D
	cam.fov = FOV
	match kind:
		"power": want = _cam_power()
		"fusion": want = _cam_fusion()
		"ko": want = _cam_ko()
		"replay": want = _cam_replay()
		"win": want = _cam_win()
		_:
			if back_t > 0.0:
				var k := smoothstep(0.0, 1.0, 1.0 - back_t / BLEND_BACK)
				cam.global_transform = cam_last.interpolate_with(live, k)
			return
	if kind == "power":   # framed on the whole motion, round walls (_pc_fit)
		want = _pc_fit(want, cam)
		cam.fov = pc_fov
	elif kind == "fusion": want = _unblock(want)   # ko / replay / win pick a clear angle up front
	else: want = _look(_arm_flat(look_pt, want.origin), look_pt)
	if kind in ["power", "fusion", "ko"] and t < 0.18:   # a fast move in from the fight camera, not a cut
		want = cam_start.interpolate_with(want, smoothstep(0.0, 1.0, t / 0.18))
		if kind == "power": want = _pc_hold(want, cam)
	cam_last = want
	cam.global_transform = want
	cam.global_position += fight.fx.shake_offset()

## Angle round p (radius r, eye height h over p's floor) nearest to `pref` with a clear view of p: no wall between,
## no wall filling the frame within a few metres of the lens (scripts/fight_cam.gd _clutter).
func _clear_angle(p: Vector3, pref: float, r: float, h: float) -> float:
	var best := pref; var bs := -1e9
	var lp := p + Vector3.UP * 1.0
	var space := fight.get_world_3d().direct_space_state
	for k in 24:
		var a := pref + (k - 12) * TAU / 24.0
		var e := p + Vector3(cos(a) * r, h, sin(a) * r)
		var sc := cos(a - pref) * 2.0
		for da in [-0.25, 0.0, 0.3]:
			var e2 := p + Vector3(cos(a + da) * r, h, sin(a + da) * r)
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(lp, e2 + (e2 - lp).normalized() * 0.6, 1, _ex())): sc -= 3.0
			if fight.fcam and fight.fcam._clutter(e2, lp, space, _ex()) > 0.08: sc -= 2.0
		if sc > bs: bs = sc; best = a
	return best

## Spring arm without the crane: a wall between the subject and the eye brings the eye in front of it.
func _arm_flat(from: Vector3, eye: Vector3) -> Vector3:
	if not fight.is_inside_tree(): return eye
	var dir := (eye - from).normalized()
	var hit := fight.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, eye + dir * 0.6, 1, _ex()))
	if not hit: return eye
	var p: Vector3 = Vector3(hit.position) - dir * 0.6
	return p if (p - from).dot(dir) > 1.2 else from + dir * 1.2

## The end angle of the swoop: in front of the hero, with clear sight (no wall, prop or other fighter in between).
func _best_angle(c: Vector3, r: float, h: float) -> float:
	var front := atan2(hero.facing.z, hero.facing.x)
	var best := front; var bs := -1e9
	look_pt = c + Vector3.UP * 0.2
	for k in 24:
		var a := front + (k - 12) * TAU / 24.0
		var eye := c + Vector3(cos(a) * r, h, sin(a) * r)
		var sc := cos(a - front) * 2.0
		if not _clear(eye): sc -= 6.0
		var ray := _arm(look_pt, eye)
		sc -= (eye - ray).length() * 3.0
		if sc > bs: bs = sc; best = a
	return best

func _side_loss(cam_fn: Callable, s_: float) -> float:   # spring-arm shortening + occlusion for one side
	var keep := side; var kt := t
	side = s_
	var loss := 0.0
	for k in 4:
		t = k * 0.35
		var w: Transform3D = cam_fn.call()
		loss += (_arm(look_pt, w.origin) - w.origin).length() + (0.0 if _clear(w.origin) else 1.5)
	side = keep; t = kt
	return loss

func _arc_loss(c: Vector3, d: float) -> float:   # how much the spring arm would have to shorten along a sweep
	var loss := 0.0
	for k in range(1, 9):
		var a := orbit.x + d * k / 8.0
		var eye := c + Vector3(cos(a) * 3.3, -0.45, sin(a) * 3.3)
		loss += (_arm(c, eye) - eye).length()
	return loss

## Spring arm: if a wall (the stage's own geometry) is between the subject and the planned eye, stop a metre short of it
## and crane up, if there's room above. Placed objects don't stop it: they fade (scripts/scenery_fade.gd).
const ARM_MARGIN := 1.0
func _arm(from: Vector3, eye: Vector3) -> Vector3:
	if not fight.is_inside_tree(): return eye
	var space := fight.get_world_3d().direct_space_state
	var ex := _ex()
	var dir := (eye - from).normalized()
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, eye + dir * ARM_MARGIN, 1, ex))
	if not hit: return eye
	var p: Vector3 = Vector3(hit.position) - dir * ARM_MARGIN
	if (p - from).dot(dir) < 0.8: p = from + dir * 0.8
	var lost := (eye - p).length()
	var up := minf(lost * 0.6, 2.0)
	var roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * (up + 0.5), 1, ex))
	if roof: up = maxf(0.0, Vector3(roof.position).y - p.y - 0.5)
	return p + Vector3.UP * up

func _ex() -> Array:
	return [fight.arena.scenery_body.get_rid()] if fight.arena.scenery_body else []

func _cam_power() -> Transform3D:
	var c := _chest(hero)
	var u := smoothstep(0.0, PC_BURST, t)
	var x := clampf(t / (PC_BURST * 0.7), 0.0, 1.0)
	var near := 1.0 - pow(1.0 - x, 3.0)    # close in fast, then circle at a full-body distance
	var a := orbit.x + sweep * u
	var r := lerpf(orbit.y, 3.3, near)
	var h := lerpf(orbit.z, -0.45, near)  # low: looking up at him
	if burst_done:   # pull back and up with the shockwave
		var b := smoothstep(0.0, PC_LEN - PC_BURST, t - PC_BURST)
		r += 1.4 * b; h += 2.2 * b
	look_pt = c + Vector3.UP * 0.2
	return _look(c + Vector3(cos(a) * r, h, sin(a) * r), look_pt)

## ---------- Power Change framing (BUG-4, docs/fx-ko.md). The transform motion (k3/8) lifts tall forms off the floor
## (Falcon's robot leaps: feet 2.1 m up, head 3.1 m, ~12 frames) while the swoop circled at chest height and passed
## ~2.2 m from him: before this the body left the frame in 68 of Falcon's 130 cutscene frames. The camera now knows the
## whole motion up front: the disc mesh's boxes per bone (assets/fidelity/bone_boxes.json, tests/bone_boxes.gd) posed
## along the transform clip give the body's extent every 1/30 s; it aims at the middle of what the next PC_AHEAD
## seconds (and the live pose) cover and backs off along its line (a wider lens where a wall is behind it) until all
## of it sits between the letterbox bars.
const PC_AHEAD := 0.4
const PC_SAFE := 0.035   # margin inside the letterbox bars (fraction of the screen height)
const PC_FOV_MAX := 72.0
const PC_TIGHT := 0.35   # closest the eye goes to a wall when no line round him fits otherwise (near plane 0.05)
var pc_env := []         # [[clip time, world AABB of the posed mesh], ...] along the transform clip
var pc_clip := ""
var pc_aim := Vector3.ZERO
var pc_aim_set := false
var pc_fov := FOV

static var _bb := {}     # form id -> {bone name: AABB in bone space (disc cm)}
static func bone_boxes(id: String) -> Dictionary:
	if not _bb.has("_loaded"):
		_bb["_loaded"] = {}
		var p := "res://assets/fidelity/bone_boxes.json"
		var j = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		if j is Dictionary:
			for fid in j:
				var o := {}
				for bn in j[fid]:
					var v: Array = j[fid][bn]
					o[bn] = AABB(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
				_bb[fid] = o
	return _bb.get(id, {})

## The posed mesh of f right now (world AABB of its bones' boxes); an empty AABB without box data.
static func pose_box(f: Fighter) -> AABB:
	var m := f.model as PSModel
	if m == null: return AABB()
	var sk := m.skeleton(); var bx := bone_boxes(str(m.ids.get(m.form, "")))
	if sk == null or bx.is_empty(): return AABB()
	var out := AABB(); var first := true
	for bn in bx:
		var bi := sk.find_bone(bn)
		if bi < 0: continue
		var b: AABB = sk.global_transform * sk.get_bone_global_pose(bi) * (bx[bn] as AABB)
		if first: out = b; first = false
		else: out = out.merge(b)
	return out

## The transform clip sampled from its tracks (not the live skeleton) every 1/30 s: where the body will be.
func _pc_envelope(f: Fighter) -> Array:
	var out := []
	var m := f.model as PSModel
	if m == null: return out
	var sk := m.skeleton(); var ap: AnimationPlayer = m.players.get(m.form)
	var bx := bone_boxes(str(m.ids.get(m.form, "")))
	pc_clip = m.clip_for("transform")
	if sk == null or ap == null or bx.is_empty() or pc_clip == "" or not ap.has_animation(pc_clip): return out
	var a := ap.get_animation(pc_clip)
	var tr := {}   # bone -> [position, rotation, scale] track (-1 = rest)
	for ti in a.get_track_count():
		var path := String(a.track_get_path(ti)); var ci := path.rfind(":")
		var bi := sk.find_bone(path.substr(ci + 1)) if ci >= 0 else -1
		if bi < 0: continue
		if not tr.has(bi): tr[bi] = [-1, -1, -1]
		match a.track_get_type(ti):
			Animation.TYPE_POSITION_3D: tr[bi][0] = ti
			Animation.TYPE_ROTATION_3D: tr[bi][1] = ti
			Animation.TYPE_SCALE_3D: tr[bi][2] = ti
	var order := []   # parents first
	var seen := {}
	for i in sk.get_bone_count():
		var chain := []; var b := i
		while b >= 0 and not seen.has(b): chain.push_front(b); seen[b] = true; b = sk.get_bone_parent(b)
		order.append_array(chain)
	var boxes := []   # [bone, AABB]
	for bn in bx:
		var bi := sk.find_bone(bn)
		if bi >= 0: boxes.append([bi, bx[bn]])
	var xf := sk.global_transform
	var tt := 0.0
	while tt <= a.length + 0.001:
		var g := {}
		for bi in order:
			var rest := sk.get_bone_rest(bi)
			var k: Array = tr.get(bi, [-1, -1, -1])
			var pos: Vector3 = a.position_track_interpolate(k[0], tt) if k[0] >= 0 else rest.origin
			var rot: Quaternion = a.rotation_track_interpolate(k[1], tt) if k[1] >= 0 else rest.basis.get_rotation_quaternion()
			var scl: Vector3 = a.scale_track_interpolate(k[2], tt) if k[2] >= 0 else rest.basis.get_scale()
			var loc := Transform3D(Basis(rot) * Basis.from_scale(scl), pos)
			var par := sk.get_bone_parent(bi)
			g[bi] = (g[par] as Transform3D) * loc if par >= 0 else loc
		var u := AABB(); var first := true
		for it in boxes:
			var b: AABB = xf * (g[it[0]] as Transform3D) * (it[1] as AABB)
			if first: u = b; first = false
			else: u = u.merge(b)
		out.append([tt, u])
		tt += 1.0 / 30.0
	return out

## What the frame has to hold now: the live pose + the motion's next PC_AHEAD seconds.
func _pc_need() -> AABB:
	var need := pose_box(hero)
	var m := hero.model as PSModel
	var ct := m.clip_pos() if m and m.current_clip() == pc_clip else t
	for s in pc_env:
		if float(s[0]) >= ct - 0.05 and float(s[0]) <= ct + PC_AHEAD:
			need = (s[1] as AABB) if need.size == Vector3.ZERO else need.merge(s[1])
	return need

## The planned swoop line (aim -> planned eye), or the nearest line round him with room behind the lens for the
## distance the framing needs (stage walls and floors, the other fighter not in between); the eye goes as far back as
## the framing needs, and where a wall stops it short the lens widens instead.
const PC_TRY := [[0.0, 0.0], [0.25, 0.0], [-0.25, 0.0], [0.0, 0.3], [0.5, 0.0], [-0.5, 0.0], [0.25, 0.3], [-0.25, 0.3],
	[0.8, 0.0], [-0.8, 0.0], [0.0, 0.6], [0.5, 0.3], [-0.5, 0.3], [1.2, 0.0], [-1.2, 0.0], [0.8, 0.4], [-0.8, 0.4],
	[1.7, 0.2], [-1.7, 0.2], [2.3, 0.3], [-2.3, 0.3], [PI, 0.3], [0.0, 1.0]]
var pc_off := Vector2.ZERO   # smoothed [yaw, pitch] offset from the planned line

func _pc_fit(want: Transform3D, cam: Camera3D) -> Transform3D:
	var need := _pc_need()
	if need.size == Vector3.ZERO: return want
	var ctr := need.get_center()
	if not pc_aim_set: pc_off = Vector2.ZERO
	pc_aim = ctr if not pc_aim_set else pc_aim.lerp(ctr, 0.25)
	pc_aim_set = true
	look_pt = pc_aim
	var asp := 16.0 / 9.0
	if cam.is_inside_tree(): asp = cam.get_viewport().get_visible_rect().size.aspect()
	var base := want.origin - pc_aim
	var d_plan := base.length()
	var yaw0 := atan2(base.z, base.x)
	var pitch0 := atan2(base.y, Vector2(base.x, base.z).length())
	var best := Vector2.ZERO; var bc := INF
	for c in PC_TRY:
		var o := Vector2(c[0], c[1])
		var e := _pc_try(_pc_dir(yaw0 + o.x, pitch0 + o.y), d_plan, need, asp)
		var cost := absf(o.x - pc_off.x) * 1.2 + absf(o.x) * 0.4 + absf(o.y) * 1.0
		if float(e[2]) > FOV: cost += 50.0 + (float(e[2]) - FOV)   # a wall behind: only with a wider lens
		if not e[3]: cost += 200.0
		if _pc_fighter_between(pc_aim + _pc_dir(yaw0 + o.x, pitch0 + o.y) * float(e[1])): cost += 8.0
		if cost < bc: bc = cost; best = o
	pc_off = pc_off.lerp(best, 0.2) if t > 0.02 else best
	var dir := _pc_dir(yaw0 + pc_off.x, pitch0 + pc_off.y)
	var r := _pc_try(dir, d_plan, need, asp)
	if not r[3] and pc_off != best:   # easing over there would leave him cut: go straight to the clear line
		pc_off = best
		dir = _pc_dir(yaw0 + pc_off.x, pitch0 + pc_off.y)
		r = _pc_try(dir, d_plan, need, asp)
	var d: float = r[1]; var fov: float = r[2]
	pc_fov = fov if fov >= pc_fov else lerpf(pc_fov, fov, 0.25)   # widen at once, narrow back quickly
	return _look(pc_aim + dir * d, pc_aim)

## One line of sight: [room behind the eye, eye distance, lens fov, whole body between the bars?]
func _pc_try(dir: Vector3, d_plan: float, need: AABB, asp: float) -> Array:
	var d := maxf(d_plan, _pc_need_d(pc_aim, dir, need, FOV, asp))
	var room := _pc_room(dir, d + ARM_MARGIN)
	if room >= d: return [room, d, FOV, true]
	# a wall behind: as far as it lets the eye go, then a wider lens; boxed in (Ryoma's change in a Mutsu porch corner, w9:
	# the last 6 frames cut at 72 deg with the eye 0.8 m out) the eye may go up to PC_TIGHT from the wall instead of 1 m
	var out := []
	for mg in [ARM_MARGIN, PC_TIGHT]:
		var rm: float = room + ARM_MARGIN - mg
		var dd := maxf(rm, 0.8)
		var fv := _pc_need_fov(pc_aim, dir, need, dd, asp)
		out = [rm, dd, clampf(fv, FOV, PC_FOV_MAX), fv <= PC_FOV_MAX]
		if out[3]: break
	return out

static func _pc_dir(yaw: float, pitch: float) -> Vector3:
	pitch = clampf(pitch, -0.55, 1.25)
	return Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))

## The eye sits on the line aim + dir * d looking back at the aim, so the view basis is fixed and a corner's screen
## offset is its sideways / vertical offset over its depth (its depth along the view + d): the smallest d (and at a
## given d the narrowest lens) holding every corner between the bars has a closed form.
const PC_SIDE := 0.04
static func _pc_basis(dir: Vector3) -> Array:
	var f := -dir; var r := f.cross(Vector3.UP).normalized()
	return [f, r, r.cross(f)]

static func _pc_need_d(aim: Vector3, dir: Vector3, box: AABB, fov: float, asp: float, bar := 0.11 + PC_SAFE) -> float:
	var b := _pc_basis(dir)
	var tv := tan(deg_to_rad(fov) * 0.5)
	var ky := 2.0 * tv * (0.5 - bar); var kx := 2.0 * tv * asp * (0.5 - PC_SIDE)
	var d := 0.0
	for k in 8:
		var p := box.get_endpoint(k) - aim
		var cf := p.dot(b[0])
		d = maxf(d, maxf(maxf(absf(p.dot(b[2])) / ky, absf(p.dot(b[1])) / kx), 0.3) - cf)
	return d

static func _pc_need_fov(aim: Vector3, dir: Vector3, box: AABB, d: float, asp: float, bar := 0.11 + PC_SAFE) -> float:
	var b := _pc_basis(dir)
	var tv := 0.0
	for k in 8:
		var p := box.get_endpoint(k) - aim
		var z := p.dot(b[0]) + d
		if z < 0.3: return 180.0
		tv = maxf(tv, maxf(absf(p.dot(b[2])) / (2.0 * (0.5 - bar) * z), absf(p.dot(b[1])) / (2.0 * asp * (0.5 - PC_SIDE) * z)))
	return rad_to_deg(2.0 * atan(tv))

## How far the eye can go from the aim along dir before the stage's own geometry (less the arm margin).
func _pc_room(dir: Vector3, want: float) -> float:
	if not fight.is_inside_tree(): return want
	var hit := fight.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pc_aim, pc_aim + dir * want, 1, _ex()))
	return want if not hit else pc_aim.distance_to(hit.position) - ARM_MARGIN

func _pc_fighter_between(eye: Vector3) -> bool:
	var seg := eye - pc_aim
	for f in fight.fighters:
		if f == hero: continue
		var fc: Vector3 = (f as Fighter).global_position + Vector3.UP * 0.9
		var u := clampf((fc - pc_aim).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		if u > 0.05 and fc.distance_to(pc_aim + seg * u) < 0.6: return true
	return false

## The blend in from the fight camera: keep its line, back off along it while he doesn't fit between the bars as they
## are now (they slide in over 0.25 s).
func _pc_hold(want: Transform3D, cam: Camera3D) -> Transform3D:
	var need := _pc_need()
	if need.size == Vector3.ZERO: return want
	var fwd := -want.basis.z
	var e := want.origin
	var asp := 16.0 / 9.0
	if cam.is_inside_tree(): asp = cam.get_viewport().get_visible_rect().size.aspect()
	var bar := 0.11 * bar_amt + 0.01
	var room := 30.0
	if fight.is_inside_tree():
		var hit := fight.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(e, e - fwd * 30.0, 1, _ex()))
		if hit: room = maxf(0.0, e.distance_to(hit.position) - 0.5)
	var back := clampf(_pc_need_d(e, -fwd, need, cam.fov, asp, bar), 0.0, room)
	return Transform3D(want.basis, e - fwd * back)

func _cam_fusion() -> Transform3D:   # side-on two-shot: the attacker and whoever he's unloading on, slow push in
	var a := hero.global_position
	var b := foe.global_position if foe else a + hero.facing * 2.0
	var to := _flat(b - a)
	var sep := minf(Vector2(b.x - a.x, b.z - a.z).length(), 3.5)
	var mid := a + to * clampf(sep * 0.4, 0.6, 1.4)
	var perp := Vector3(-to.z, 0, to.x) * side
	var u := smoothstep(0.0, FUSION_LEN, t)
	var eye := mid + perp * (3.4 + sep * 0.55 - 0.6 * u) - to * 0.4 + Vector3.UP * (1.0 - 0.25 * u)
	look_pt = mid + Vector3.UP * 1.0
	return _look(eye, look_pt)

func _cam_ko() -> Transform3D:   # side-on at the clear angle picked at the KO, following the victim smoothly (his
	var v := foe.global_position        # launch tilts the camera up instead of dragging it into the air)
	ko_v = v if ko_v == Vector3.ZERO else ko_v.lerp(v, 0.12)
	var a := ko_a + 0.3 * smoothstep(0.0, KO_SLOW, t) * side
	var base := Vector3(ko_v.x, ko_floor + (ko_v.y - ko_floor) * 0.35, ko_v.z)
	look_pt = Vector3(ko_v.x, ko_v.y + 0.9, ko_v.z)
	return _look(base + Vector3(cos(a) * 4.6, 1.1, sin(a) * 4.6), look_pt)

var ko_a := 0.0
var ko_v := Vector3.ZERO
var ko_floor := 0.0

func _cam_replay() -> Transform3D:   # side-on two-shot from the clearest side (picked when the replay starts), slow pan
	var v := foe.global_position
	var k := hero.global_position if hero else v
	var mid := (v + k) * 0.5
	var u := float(rp_i - rp_start) / maxf(1.0, float(rp_end - rp_start))
	var a := rp_a + lerpf(-0.3, 0.3, u)
	var r := 4.8 + minf((v - k).length(), 4.0) * 0.45
	look_pt = mid + Vector3.UP * 1.0
	return _look(mid + Vector3(cos(a) * r, 1.9, sin(a) * r), look_pt)

var rp_a := 0.0
## The replay's angle: round the two fighters, side-on preferred, the one with a clear view (no wall between, none
## filling the frame near the lens) at the replay's start, middle and end.
func _replay_angle() -> float:
	var fr: Array = fight.rec.frames
	var mids := []
	for i in [rp_start, (rp_start + rp_end) / 2, rp_end]:
		var fs: Array = fr[mini(i, fr.size() - 1)].f
		var p0 := Vector3(fs[0][0], fs[0][1], fs[0][2]); var p1 := Vector3(fs[1][0], fs[1][1], fs[1][2])
		mids.append([(p0 + p1) * 0.5, minf(p0.distance_to(p1), 4.0)])
	var p0n := Vector3(fr[rp_end].f[0][0], 0, fr[rp_end].f[0][2]); var p1n := Vector3(fr[rp_end].f[1][0], 0, fr[rp_end].f[1][2])
	var kv := _flat(p1n - p0n)
	var side_a := atan2(kv.x, -kv.z)   # perpendicular to the line between them
	var best := side_a; var bs := -1e9
	var space := fight.get_world_3d().direct_space_state
	for j in 16:
		var a := side_a + j * TAU / 16.0
		var sc := -absf(sin(a - side_a)) * 2.0   # side-on first
		for m in mids:
			var mid: Vector3 = m[0]
			var r := 4.8 + float(m[1]) * 0.45
			var lp := mid + Vector3.UP * 1.0
			for da in [-0.3, 0.0, 0.3]:
				var e := mid + Vector3(cos(a + da) * r, 1.9, sin(a + da) * r)
				var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(lp, e + (e - lp).normalized() * 0.6, 1, _ex()))
				if ray: sc -= 3.0
				if fight.fcam and fight.fcam._clutter(e, lp, space, _ex()) > 0.08: sc -= 2.0
		if sc > bs: bs = sc; best = a
	return best

var win_a := 0.0

func _cam_win() -> Transform3D:   # the winner's pose: slow push in from the clear front angle, head to toe inside the
	var c := _chest(hero)          # letterbox bars (the first match video cut his head and feet), his name below him
	var u := smoothstep(0.0, 2.0, t)
	var a := win_a + 0.25 * u
	var r := 4.7 - 0.6 * u
	look_pt = hero.global_position + Vector3.UP * 1.12
	return _look(c + Vector3(cos(a) * r, 0.1 - 0.1 * u, sin(a) * r), look_pt)

func _look(eye: Vector3, at: Vector3) -> Transform3D:
	if (at - eye).length() < 0.01: eye += Vector3.BACK
	return Transform3D().looking_at(at - eye, Vector3.UP).translated(eye)

var off_s := Vector3.ZERO   # smoothed occlusion offset (the planned path stays exact when nothing is in the way)

func _unblock(want: Transform3D) -> Transform3D:   # keep stage walls and props out from between camera and subject
	var eye := _arm(look_pt, want.origin)
	var best := eye
	if not _clear(eye):
		best = look_pt + (eye - look_pt) * 0.35 + Vector3.UP * 1.0
		for c in [[0.8, 0.0], [1.0, 0.7], [0.65, 0.5], [0.8, 1.3], [0.5, 1.0], [0.4, 1.8]]:
			var e: Vector3 = look_pt + (eye - look_pt) * float(c[0]) + Vector3.UP * float(c[1])
			if _clear(e):
				best = e; break
	off_s = off_s.lerp(best - eye, 0.18)
	return _look(eye + off_s, look_pt)

func _clear(eye: Vector3) -> bool:   # walls and the other fighter; placed objects fade instead
	if not fight.is_inside_tree(): return true
	var space := fight.get_world_3d().direct_space_state
	var ex := _ex()
	for tp in [look_pt, look_pt + Vector3.UP * 0.6, look_pt - Vector3.UP * 0.9]:
		for ab in [[tp, eye], [eye, tp]]:
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(ab[0], ab[1], 1, ex)): return false
		var seg: Vector3 = eye - tp
		for f in fight.fighters:   # another fighter right in front of the subject
			var fc: Vector3 = (f as Fighter).global_position + Vector3.UP * 0.9
			if fc.distance_to(tp) < 0.7: continue
			var uf := clampf((fc - tp).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
			if uf > 0.05 and fc.distance_to(tp + seg * uf) < 0.55: return false
	return true

## ---------- post pass
func _apply_post() -> void:
	var on := desat > 0.001 or desat_all > 0.001 or impact > 0.001 or flash > 0.001 or wave_r > 0.0
	post.visible = on
	var vs := Vector2(1920, 1080)
	if is_inside_tree(): vs = get_viewport().get_visible_rect().size
	var h := vs.y * 0.11 * bar_amt
	bars[0].position = Vector2.ZERO; bars[0].size = Vector2(vs.x, h)
	bars[1].position = Vector2(0, vs.y - h); bars[1].size = Vector2(vs.x, h)
	banner.position = Vector2(0, vs.y - vs.y * 0.11); banner.size = Vector2(vs.x, vs.y * 0.11)
	if not on: return
	post_mat.set_shader_parameter("desat", desat)
	post_mat.set_shader_parameter("desat_all", desat_all)
	post_mat.set_shader_parameter("hero_pos", _chest(hero) if hero else Vector3(0, -100, 0))
	post_mat.set_shader_parameter("wave_r", wave_r)
	post_mat.set_shader_parameter("impact", impact)
	post_mat.set_shader_parameter("flash", flash)
	if OS.has_environment("PS_POST_DBG"): post_mat.set_shader_parameter("dbg", int(OS.get_environment("PS_POST_DBG")))

func post_state() -> Array:   # recorded per frame so replays and highlights show the same look
	var hp := _chest(hero) if hero else Vector3(0, -100, 0)
	return [desat, desat_all, hp.x, hp.y, hp.z, wave_r, impact, flash, bar_amt, caption.text]

func _chest(f: Fighter) -> Vector3:
	return f.global_position + Vector3.UP * 1.05

static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else Vector3.FORWARD
