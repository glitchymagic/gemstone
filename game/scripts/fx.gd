class_name FX
extends Node3D
## GPU particle bursts (hits, gem pickups, Power Change, breaking objects) and screen shake.
## Cinematics add damage-scaled impact sparks (streaks + ring + a short light), the Power Change charge-up and the
## gem-coloured shockwave + light burst. Everything runs on time_scale (0 = frozen, slow motion) except `unscaled` items.

var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var time_scale := 1.0
var live: Array = []   # [node, life left, unscaled, kind, age, extra]
static var _soft: GradientTexture2D
static var _fade: GradientTexture1D
static var _ring: GradientTexture2D
static var _star: ImageTexture

static func _sprites() -> void:
	if _soft: return
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.75))
	_soft = GradientTexture2D.new(); _soft.gradient = g
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5); _soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 64; _soft.height = 64
	var f := Gradient.new()
	f.set_color(0, Color(1, 1, 1, 1)); f.set_color(1, Color(1, 1, 1, 0))
	_fade = GradientTexture1D.new(); _fade.gradient = f
	var r := Gradient.new()
	r.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 0.9, 1.0])
	r.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	_ring = GradientTexture2D.new(); _ring.gradient = r
	_ring.fill = GradientTexture2D.FILL_RADIAL
	_ring.fill_from = Vector2(0.5, 0.5); _ring.fill_to = Vector2(1.0, 0.5)
	_ring.width = 128; _ring.height = 128
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)   # 4 long + 4 short rays round a hot core
	for y in 128:
		for x in 128:
			var v := Vector2(x - 63.5, y - 63.5) / 63.5
			var rr := v.length(); var an := v.angle()
			var rays := pow(absf(cos(an * 2.0)), 40.0) * (1.0 - rr) + 0.55 * pow(absf(cos(an * 2.0 + PI * 0.5)), 60.0) * maxf(0.0, 1.0 - rr * 1.6)
			var a := clampf(exp(-rr * rr * 30.0) + rays * 1.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star = ImageTexture.create_from_image(img)

func spawn(kind: String, pos: Vector3) -> void:
	HDPost.kick(kind)
	if kind == "hit" or kind == "hit_big":   # a flash + sharp sparks + ring (no more clouds of round dots)
		impact_spark(pos, 30 if kind == "hit" else 70)
		if kind == "hit_big": _shake = maxf(_shake, 0.25)
		return
	var p := GPUParticles3D.new()
	p.one_shot = true; p.explosiveness = 0.95; p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP; m.spread = 180.0
	m.gravity = Vector3(0, -9, 0)
	var col := Color(1, 0.85, 0.4)
	var amount := 24; var spd := Vector2(3, 7); var life := 0.35; var size := 0.12
	match kind:
		"hit": col = Color(1.0, 0.9, 0.55); amount = 26; size = 0.16
		"hit_big":
			col = Color(1.0, 0.55, 0.2); amount = 40; spd = Vector2(5, 11); size = 0.16
			_shake = maxf(_shake, 0.25)
		"transform":   # streaks, not dots (160 round dots read as confetti in the 2026-10-23 audit)
			col = Color(0.5, 0.8, 1.0); amount = 44; spd = Vector2(4, 11); life = 0.6; size = 0.22
			_shake = maxf(_shake, 0.4)
		"fusion": col = Color(1.0, 0.35, 0.9); amount = 36; spd = Vector2(5, 13); life = 0.5
		"gem": col = Color(0.6, 1.0, 0.8); amount = 30; life = 0.6
		"break": col = Color(0.75, 0.6, 0.45); amount = 26; m.gravity = Vector3(0, -18, 0); life = 0.7
		"walljump": col = Color(0.9, 0.9, 1.0); amount = 12; life = 0.25
	m.initial_velocity_min = spd.x; m.initial_velocity_max = spd.y
	m.scale_min = size * 0.6; m.scale_max = size * 1.4
	m.color = col
	_sprites()
	m.color_ramp = _fade
	m.damping_min = 2.0; m.damping_max = 4.0
	p.process_material = m
	p.amount = amount; p.lifetime = life
	if kind in ["transform", "fusion", "walljump"]:   # velocity-stretched streaks
		m.particle_flag_align_y = true
		m.scale_min = 0.7; m.scale_max = 1.2
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		p.draw_pass_1 = _quad(col * 2.4, false, Vector2(0.03, size * 1.6))
	else:
		p.draw_pass_1 = _quad(col * 1.6, true)
	_add(p, pos, life + 0.6)
	p.emitting = true

func _quad(col: Color, billboard: bool, size := Vector2(1, 1), tex: Texture2D = null) -> QuadMesh:
	_sprites()
	var q := QuadMesh.new(); q.size = size
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if billboard:
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.billboard_keep_scale = true
	sm.albedo_texture = tex if tex else _soft
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_color = Color(col.r, col.g, col.b)
	q.material = sm
	return q

func _add(n: Node3D, pos: Vector3, life: float, unscaled := false, kind := "", extra = null) -> void:
	add_child(n)
	n.global_position = pos
	if n is GPUParticles3D: (n as GPUParticles3D).speed_scale = 1.0 if unscaled else time_scale
	live.append([n, life, unscaled, kind, 0.0, extra])

func _physics_process(dt: float) -> void:
	for it in live.duplicate():
		var n: Node3D = it[0]
		var s: float = 1.0 if it[2] else time_scale
		it[1] -= dt * s; it[4] += dt * s
		if n is GPUParticles3D: (n as GPUParticles3D).speed_scale = s
		match String(it[3]):
			"flash":   # hit star: pops to full size in 2 frames, fades out
				var uf: float = clampf(it[4] / 0.11, 0.0, 1.0)
				n.scale = Vector3.ONE * float(it[5]) * (0.55 + 0.45 * minf(1.0, it[4] / 0.035))
				(((n as MeshInstance3D).mesh as PrimitiveMesh).material as StandardMaterial3D).albedo_color.a = 1.0 - uf * uf
			"ring":    # flat billboard ring growing out of an impact
				var u: float = clampf(it[4] / 0.22, 0.0, 1.0)
				n.scale = Vector3.ONE * lerpf(0.3, float(it[5]), 1.0 - pow(1.0 - u, 3.0))
				(((n as MeshInstance3D).mesh as PrimitiveMesh).material as StandardMaterial3D).albedo_color.a = 1.0 - u
			"wave":    # floor shockwave: [radius max, colour, delay]
				var e: Array = it[5]
				var u2: float = clampf((it[4] - float(e[2])) / 0.75, 0.0, 1.0)
				n.visible = it[4] >= float(e[2])
				n.scale = Vector3.ONE * maxf(0.05, lerpf(0.2, float(e[0]), 1.0 - pow(1.0 - u2, 2.0)))
				var c: Color = e[1]
				(((n as MeshInstance3D).mesh as PrimitiveMesh).material as StandardMaterial3D).albedo_color = Color(c.r * 3.0, c.g * 3.0, c.b * 3.0, 1.0 - u2)
			"light":   # [peak energy, rise, fall]
				var e2: Array = it[5]
				var a: float = it[4]
				(n as OmniLight3D).light_energy = float(e2[0]) * (clampf(a / float(e2[1]), 0.0, 1.0) if a < float(e2[1]) else maxf(0.0, 1.0 - (a - float(e2[1])) / float(e2[2])))
			"pillar":
				var u3: float = clampf(it[4] / 0.9, 0.0, 1.0)
				n.scale = Vector3(1.0 + u3 * 2.5, 1.0 + u3 * 0.6, 1.0 + u3 * 2.5)
				(((n as MeshInstance3D).mesh as PrimitiveMesh).material as StandardMaterial3D).albedo_color.a = (1.0 - u3) * 0.45
		if it[1] <= 0.0:
			live.erase(it)
			n.queue_free()

## Damage-scaled hit spark (the 2026-10-23 audit: hits used to throw 30-60 round orange dots that read as confetti):
## a white-hot star flash for a few frames, a handful of thin velocity-stretched sparks that cool from white to the hit
## colour, a fast thin ring, and a short light on heavy hits. Count, size and reach grow with the damage.
func impact_spark(pos: Vector3, hp_dmg: int) -> void:
	var dmg := Rules.dmg_1000(hp_dmg)
	var k := clampf(sqrt(maxf(dmg, 10) / 60.0), 0.5, 2.6)
	var hot := Color(1.0, 0.82, 0.45).lerp(Color(1.0, 0.42, 0.12), clampf((dmg - 40) / 160.0, 0.0, 1.0))
	_sprites()
	# star flash: billboard, 0.1 s, grows fast then fades
	var fl := MeshInstance3D.new()
	var fq := _quad(Color(1.0, 0.97, 0.9) * 2.6, true, Vector2(1, 1), _star)
	(fq.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	(fq.material as StandardMaterial3D).no_depth_test = true
	fl.mesh = fq
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fl.rotation.z = _rng.randf() * TAU
	_add(fl, pos, 0.11 + 0.02 * k, false, "flash", 0.55 + 0.35 * k)
	# sparks: few, thin, quick
	var p := GPUParticles3D.new()
	p.one_shot = true; p.explosiveness = 1.0; p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP; m.spread = 180.0
	m.gravity = Vector3(0, -14, 0)
	m.initial_velocity_min = 5.0 * k; m.initial_velocity_max = 11.0 * k
	m.damping_min = 10.0; m.damping_max = 16.0
	m.scale_min = 0.7; m.scale_max = 1.1
	m.color = Color.WHITE
	m.color_ramp = _cool(hot)
	m.particle_flag_align_y = true
	p.process_material = m
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.amount = int(5 + 5 * k); p.lifetime = 0.14 + 0.05 * k
	p.draw_pass_1 = _quad(Color(2.2, 2.0, 1.7), false, Vector2(0.028, 0.16 + 0.1 * k))
	_add(p, pos, p.lifetime + 0.3)
	p.emitting = true
	var ring := MeshInstance3D.new()
	var rq := _quad(hot * 1.8, true, Vector2(1, 1), _ring)
	(rq.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ring.mesh = rq
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(ring, pos, 0.16, false, "ring", 0.65 * k)
	if dmg >= 90:   # a small local glow (a stage-wide burst washed the frame out)
		var l := OmniLight3D.new(); l.light_color = hot; l.omni_range = 2.2 + 0.6 * k; l.light_energy = 0.0
		_add(l, pos, 0.14, false, "light", [0.9 * k, 0.02, 0.11])

static var _cools := {}
static func _cool(hot: Color) -> GradientTexture1D:   # white-hot -> hit colour -> gone
	var key := hot.to_html()
	if _cools.has(key): return _cools[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(hot.r, hot.g, hot.b, 0.9), Color(hot.r, hot.g * 0.6, hot.b * 0.4, 0.0)])
	var t := GradientTexture1D.new(); t.gradient = g
	_cools[key] = t
	return t

## Power Change charge-up: gem-coloured motes pulled into the fighter (real time; the world is frozen meanwhile).
func charge(pos: Vector3, cols: Array, dur: float) -> void:
	for ci in cols.size():
		var p := GPUParticles3D.new()
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
		m.emission_sphere_radius = 1.7
		m.direction = Vector3.ZERO; m.spread = 180.0
		m.gravity = Vector3.ZERO
		m.radial_accel_min = -16.0; m.radial_accel_max = -10.0
		m.tangential_accel_min = 3.0; m.tangential_accel_max = 6.0
		m.damping_min = 1.0; m.damping_max = 2.0
		m.scale_min = 0.6; m.scale_max = 1.0
		m.particle_flag_align_y = true
		var c: Color = cols[ci]
		m.color = c
		_sprites()
		m.color_ramp = _fade
		p.process_material = m
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		p.amount = 14; p.lifetime = 0.5   # was 36 per colour: a cloud of coloured confetti round the fighter
		p.draw_pass_1 = _quad(c * 3.0, false, Vector2(0.022, 0.2))
		_add(p, pos, dur, true)
		p.emitting = true
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.92, 0.8); l.omni_range = 5.0; l.light_energy = 0.0
	_add(l, pos + Vector3(0, 1.2, 0), dur, true, "light", [1.0, dur, 0.05])

## Power Change burst: three shockwave rings in the stones' colours, a big light that lights the
## stage (and the volumetric fog) and a spark burst.
func shockwave(pos: Vector3, cols: Array) -> void:
	_sprites()
	var feet := pos - Vector3.UP * 1.0
	for ci in cols.size():   # torus rings: they read from a low camera too
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new(); tm.inner_radius = 0.94; tm.outer_radius = 1.0; tm.rings = 48; tm.ring_segments = 8
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.material = rm
		ring.mesh = tm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(ring, feet + Vector3.UP * (0.25 + 0.2 * ci), 1.2, true, "wave", [9.0 - ci * 1.6, cols[ci], 0.07 * ci])
		ring.visible = false
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.86, 0.7); l.omni_range = 14.0; l.light_energy = 0.0
	l.shadow_enabled = true
	l.light_volumetric_fog_energy = 2.0
	_add(l, pos + Vector3.UP * 0.8, 1.4, true, "light", [5.0, 0.05, 1.3])
	for ci in cols.size():
		var p := GPUParticles3D.new()
		p.one_shot = true; p.explosiveness = 1.0; p.emitting = false
		var m := ParticleProcessMaterial.new()
		m.direction = Vector3.UP; m.spread = 180.0; m.flatness = 0.6
		m.gravity = Vector3(0, -6, 0)
		m.initial_velocity_min = 8.0; m.initial_velocity_max = 18.0
		m.damping_min = 3.0; m.damping_max = 6.0
		m.scale_min = 0.7; m.scale_max = 1.3
		m.particle_flag_align_y = true
		var c: Color = cols[ci]
		m.color = c; m.color_ramp = _fade
		p.process_material = m
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		p.amount = 24; p.lifetime = 0.7
		p.draw_pass_1 = _quad(c * 3.0, false, Vector2(0.04, 0.45))
		_add(p, pos, 1.5, true)
		p.emitting = true

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func shake_offset() -> Vector3:
	if _shake <= 0.0: return Vector3.ZERO
	_shake = maxf(0.0, _shake - get_physics_process_delta_time() * 1.5)
	var s := _shake * _shake * 0.22   # was 0.5: up to 0.9 m of jitter between two frames on big hits
	return Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), _rng.randf_range(-s, s))
