class_name Remix
extends Node3D
## Remix lighting (title menu LIGHTING, Battle Royale setup; "Original" stays the default): Night, Sunset and Storm on
## each stage's own geometry and textures.
## - The stage's own light sources are found in its textures: every triangle whose texel is bright and warm (lit
##   windows, lanterns, lamp glass, fires) is clustered into a few light positions, and a stage shader makes exactly
##   those texels glow at night (shaders/remix_stage*.gdshader).
## - Storm: dark sky, rain + splashes on open-air stages, everything wet (glossy floors for the screen-space
##   reflections), lightning flashes. Snow at night on Mutsu and Oedo.
## - Every heavy effect has a tier on the quality preset (Low/Medium/High/Ultra): lamp count and lamp shadows,
##   rain/snow particle counts, splashes, volumetric fog (High+ as in Look).

const LOOKS := ["original", "night", "sunset", "storm"]
const SNOW_STAGES := ["stg10", "stg60"]
const LAMPS := [3, 6, 10, 16]          # lamp lights per tier
const LAMP_SHADOWS := [0, 0, 2, 4]
const RAIN := [1500, 3000, 6000, 10000]
const SPLASH := [0, 400, 900, 1600]
const SNOW := [800, 1500, 3000, 5000]
const CELL := 2.2                       # lamp clustering grid (m)

var look := "original"
var arena: Arena
var preset := 2
var env: Environment
var sun: DirectionalLight3D
var indoor := false
var lamps: Array[OmniLight3D] = []
var lamp_spots: Array = []              # [pos, colour, weight]
var rain: GPUParticles3D
var splash: GPUParticles3D
var snow: GPUParticles3D
var bolt: DirectionalLight3D
var bolt_t := 3.0
var bolt_age := 99.0
var bolts := 0
var base_amb := 0.5
var rng := RandomNumberGenerator.new()
static var _img_cache := {}
static var _spot_cache := {}

static func apply(parent: Node, p_arena: Arena, p_look: String, p_preset := -1) -> Remix:
	if p_look == "" or p_look == "original" or not p_look in LOOKS: return null
	var r := Remix.new(); r.name = "Remix"
	r.look = p_look; r.arena = p_arena
	r.preset = p_preset if p_preset >= 0 else _quality()
	parent.add_child(r)
	r._build(parent)
	return r

static func _quality() -> int:
	if Look.force_preset >= 0: return Look.force_preset
	var g := UI.game()
	return int(g.get("quality")) if g else 2

static func display(l: String) -> String:
	return {"original": "ORIGINAL", "night": "NIGHT", "sunset": "SUNSET", "storm": "STORM"}.get(l, l.to_upper())

func _build(parent: Node) -> void:
	rng.seed = hash(arena.stage + look)
	indoor = bool(arena.info.get("indoor", false))
	var we := parent.get_node_or_null("Look") as WorldEnvironment
	env = we.environment if we else null
	sun = parent.get_node_or_null("Sun") as DirectionalLight3D
	var rim := parent.get_node_or_null("Rim") as DirectionalLight3D
	var fill := parent.get_node_or_null("IndoorFill") as OmniLight3D
	var sky: Material = null   # ProceduralSkyMaterial (Classic) or the Remaster look's sky_hd shader
	if env and env.sky: sky = env.sky.sky_material
	var we_attr := (we.camera_attributes as CameraAttributesPractical) if we else null
	if we_attr: we_attr.auto_exposure_enabled = false   # Remaster's auto exposure would lift the night back to day
	if env and sky:   # the game's own background plane (Look.apply_background) is the day sky: a remix brings its own
		env.background_mode = Environment.BG_SKY
		var gb := parent.get_node_or_null("GameBackground") as CanvasLayer
		if gb: gb.visible = false
	var wet := 0.0; var glow := 0.0; var lamp_e := 0.0; var lamp_col := Color(1.0, 0.72, 0.42)
	match look:
		"night":
			if sky: _sky(sky, Color(0.012, 0.02, 0.055), Color(0.06, 0.07, 0.13), Color(0.03, 0.03, 0.05), Color(0.01, 0.01, 0.02))
			if sun:
				sun.light_color = Color(0.55, 0.66, 1.0); sun.light_energy = 0.32; sun.rotation_degrees = Vector3(-58, 140, 0)
			if rim: rim.light_color = Color(0.45, 0.55, 1.0); rim.light_energy = 0.3
			if env:
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color(0.3, 0.38, 0.62); env.ambient_light_energy = 0.32
				env.volumetric_fog_density = 0.018; env.volumetric_fog_albedo = Color(0.45, 0.52, 0.7)
				env.fog_light_color = Color(0.05, 0.06, 0.1); env.fog_density = 0.006
				env.glow_intensity = 0.95; env.glow_bloom = 0.12; env.glow_hdr_threshold = 0.85
				env.tonemap_exposure = 1.2; env.adjustment_saturation = 1.05; env.adjustment_contrast = 1.12
			if fill: fill.light_energy = 0.35; fill.light_color = Color(0.6, 0.65, 0.9)
			glow = 1.0; lamp_e = 2.6
		"sunset":
			if sky:
				_sky(sky, Color(0.2, 0.25, 0.5), Color(1.0, 0.5, 0.24), Color(0.55, 0.32, 0.22), Color(0.12, 0.08, 0.08))
				if sky is ProceduralSkyMaterial: (sky as ProceduralSkyMaterial).sun_angle_max = 35.0
			if sun:
				sun.light_color = Color(1.0, 0.5, 0.26); sun.light_energy = 1.9; sun.rotation_degrees = Vector3(-10, -62, 0)
			if rim: rim.light_color = Color(0.55, 0.45, 0.9); rim.light_energy = 0.45
			if env:
				if indoor: env.ambient_light_color = Color(1.0, 0.62, 0.4); env.ambient_light_energy = 0.7
				else: env.ambient_light_energy = 0.5
				env.volumetric_fog_density = 0.014; env.volumetric_fog_albedo = Color(1.0, 0.72, 0.52)
				env.volumetric_fog_anisotropy = 0.75
				env.fog_light_color = Color(0.9, 0.55, 0.35); env.fog_density = 0.005
				env.glow_intensity = 0.7; env.adjustment_saturation = 1.2; env.adjustment_contrast = 1.1
			if fill: fill.light_color = Color(1.0, 0.6, 0.35); fill.light_energy = 1.2
			glow = 0.3; lamp_e = 1.1
		"storm":
			if sky: _sky(sky, Color(0.11, 0.12, 0.15), Color(0.22, 0.24, 0.28), Color(0.1, 0.1, 0.12), Color(0.04, 0.04, 0.05))
			if sun:
				sun.light_color = Color(0.7, 0.76, 0.88); sun.light_energy = 0.32; sun.shadow_blur = 3.0
			if rim: rim.light_color = Color(0.6, 0.7, 0.9); rim.light_energy = 0.3
			if env:
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color(0.36, 0.42, 0.52); env.ambient_light_energy = 0.55
				env.volumetric_fog_density = 0.032; env.volumetric_fog_albedo = Color(0.6, 0.65, 0.72)
				env.fog_light_color = Color(0.2, 0.22, 0.26); env.fog_density = 0.012
				env.adjustment_saturation = 0.82; env.adjustment_contrast = 1.16
				env.ssr_max_steps = 64
			if fill: fill.light_energy = 0.6; fill.light_color = Color(0.7, 0.75, 0.9)
			wet = 0.0 if indoor else 1.0
			glow = 0.55; lamp_e = 1.7
			bolt = DirectionalLight3D.new(); bolt.name = "Lightning"
			bolt.light_color = Color(0.82, 0.88, 1.0); bolt.light_energy = 0.0
			bolt.rotation_degrees = Vector3(-62, rng.randf_range(0, 360), 0)
			bolt.shadow_enabled = preset >= 2
			add_child(bolt)
	if env: base_amb = env.ambient_light_energy
	_remat(wet, glow)
	if lamp_e > 0.0: _lamps(lamp_e, lamp_col)
	if not indoor:
		if look == "storm": _rain()
		if look == "night" and arena.stage in SNOW_STAGES: _snow()

func _sky(m: Material, top: Color, hor: Color, ghor: Color, gbot: Color) -> void:
	if m is ProceduralSkyMaterial:
		var sky := m as ProceduralSkyMaterial
		sky.sky_top_color = top; sky.sky_horizon_color = hor
		sky.ground_horizon_color = ghor; sky.ground_bottom_color = gbot
	elif m is ShaderMaterial:   # Remaster sky (sky_hd): same colours, clouds lit by the remix light, no sun disc but at sunset
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("top_color", top); sm.set_shader_parameter("horizon_color", hor)
		sm.set_shader_parameter("ground_color", ghor)
		sm.set_shader_parameter("cloud_color", hor.lerp(Color(1, 1, 1), 0.25) if look == "sunset" else hor * 1.6)
		sm.set_shader_parameter("sun_disc", 1.0 if look == "sunset" else 0.0)
		if look == "storm": sm.set_shader_parameter("cloud_cover", 0.95)

## Remaster's camera-riding fighter lights (HD.light_rig, warm day key + rims) take the remix's light colour;
## called once the camera exists (fight.gd, replay_theater.gd)
func tint_rig(cam: Camera3D) -> void:
	var rig: Node = cam.get_node_or_null("FighterRig") if cam else null
	if rig == null: return
	var tint: Color = {"night": Color(0.6, 0.7, 1.0), "sunset": Color(1.0, 0.7, 0.5), "storm": Color(0.75, 0.82, 0.95)}.get(look, Color(1, 1, 1))
	var k: float = {"night": 0.75, "sunset": 0.9, "storm": 0.8}.get(look, 1.0)
	for l in rig.get_children():
		(l as Light3D).light_color *= tint; (l as Light3D).light_energy *= k

## ---------- stage materials -> the remix stage shader (same disc textures and blend modes)
func _remat(wet: float, glow: float) -> void:
	var sh := [load("res://shaders/remix_stage.gdshader"), load("res://shaders/remix_stage_blend.gdshader"), load("res://shaders/remix_stage_add.gdshader")]
	var done := {}
	for mi in _stage_meshes():
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is ShaderMaterial and (src as ShaderMaterial).shader and String((src as ShaderMaterial).shader.resource_path).contains("stage_pbr"):
				if not done.has(src):   # Remaster stage surface: its own wet/glow uniforms, on a copy (materials are shared)
					var pm := (src as ShaderMaterial).duplicate() as ShaderMaterial
					pm.set_shader_parameter("wet", wet); pm.set_shader_parameter("glow", glow)
					done[src] = pm
				m.set_surface_override_material(s, done[src])
				continue
			if not (src is StandardMaterial3D) or (src as StandardMaterial3D).emission_enabled: continue
			var sm := src as StandardMaterial3D
			if not done.has(sm):
				var v := 0
				if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA: v = 2 if sm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD else 1
				var nm := ShaderMaterial.new(); nm.shader = sh[v]
				nm.set_shader_parameter("albedo_tex", sm.albedo_texture)
				nm.set_shader_parameter("use_tex", sm.albedo_texture != null)
				nm.set_shader_parameter("albedo_color", sm.albedo_color)
				nm.set_shader_parameter("use_vcol", sm.vertex_color_use_as_albedo)
				nm.set_shader_parameter("alpha_clip", sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
				nm.set_shader_parameter("roughness", sm.roughness)
				nm.set_shader_parameter("specular", sm.metallic_specular)
				nm.set_shader_parameter("wet", wet)
				nm.set_shader_parameter("glow", glow)
				done[sm] = nm
			m.set_surface_override_material(s, done[sm])

func _stage_meshes() -> Array:   # the stage + its props, not the Power Stones
	var out := []
	for mi in Mats._meshes(arena):
		var p: Node = mi
		var gem := false
		while p and p != arena:
			if p is Gem: gem = true; break
			p = p.get_parent()
		if not gem: out.append(mi)
	return out

## ---------- the stage's own light sources, from its textures
func _lamps(energy: float, col: Color) -> void:
	var key := arena.stage
	if not _spot_cache.has(key): _spot_cache[key] = _find_spots()
	lamp_spots = _spot_cache[key]
	var n := mini(LAMPS[clampi(preset, 0, 3)], lamp_spots.size())
	for i in n:
		var sp: Array = lamp_spots[i]
		var l := OmniLight3D.new(); l.name = "Lamp%d" % i
		var c: Color = sp[1]
		l.light_color = col.lerp(c, 0.5)
		l.light_energy = energy
		l.omni_range = 6.5
		l.omni_attenuation = 1.4
		l.light_volumetric_fog_energy = 2.5 if look == "night" else 1.2
		l.shadow_enabled = i < LAMP_SHADOWS[clampi(preset, 0, 3)]
		l.position = sp[0]
		add_child(l)
		lamps.append(l)

static func glow_mask(c: Color) -> float:   # the shader's test, on the CPU
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var mx := maxf(c.r, maxf(c.g, c.b))
	var sat := (mx - minf(c.r, minf(c.g, c.b))) / maxf(mx, 0.001)
	return smoothstep(0.5, 0.72, lum) * smoothstep(0.38, 0.55, sat) * (1.0 if c.b + 0.08 < c.r else 0.0)

func _find_spots() -> Array:
	var cells := {}
	for mi in _stage_meshes():
		var m := mi as MeshInstance3D
		var xf := m.global_transform
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			var tex: Texture2D = null
			if mat is StandardMaterial3D: tex = (mat as StandardMaterial3D).albedo_texture
			elif mat is ShaderMaterial: tex = (mat as ShaderMaterial).get_shader_parameter("albedo_tex")
			if tex == null: continue
			var img := _image(tex)
			if img == null: continue
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			if uvs == null or (uvs as PackedVector2Array).is_empty(): continue
			var idx = arr[Mesh.ARRAY_INDEX]
			var tri: PackedInt32Array = idx if idx != null and (idx as PackedInt32Array).size() > 0 else PackedInt32Array(range(vs.size()))
			var w := img.get_width(); var h := img.get_height()
			for t in range(0, tri.size() - 2, 3):
				var a := tri[t]; var b := tri[t + 1]; var c := tri[t + 2]
				var uv: Vector2 = (uvs[a] + uvs[b] + uvs[c]) / 3.0
				var px := img.get_pixel(posmod(int(uv.x * w), w), posmod(int(uv.y * h), h))
				var g := glow_mask(px)
				if g < 0.45: continue
				var p0 := xf * vs[a]; var p1 := xf * vs[b]; var p2 := xf * vs[c]
				var area := (p1 - p0).cross(p2 - p0).length() * 0.5
				if area < 0.002: continue
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				var ctr := (p0 + p1 + p2) / 3.0
				var key := Vector3i(floori(ctr.x / CELL), floori(ctr.y / CELL), floori(ctr.z / CELL))
				var e: Array = cells.get(key, [Vector3.ZERO, Color(0, 0, 0), 0.0, Vector3.ZERO])
				var wt := area * g
				e[0] += ctr * wt; e[1] += px * wt; e[2] += wt; e[3] += nrm * wt
				cells[key] = e
	var spots := []
	for k in cells:
		var e: Array = cells[k]
		var wt: float = e[2]
		if wt < 0.02: continue
		var p: Vector3 = e[0] / wt
		var nrm: Vector3 = (e[3] as Vector3).normalized() if (e[3] as Vector3).length() > 0.001 else Vector3.UP
		var c: Color = e[1] / wt
		var mx := maxf(c.r, maxf(c.g, c.b))
		if mx > 0.0: c = Color(c.r / mx, c.g / mx, c.b / mx)
		spots.append([p + nrm * 0.45, c, wt])
	spots.sort_custom(func(x, y): return x[2] > y[2])
	var out := []   # spread them out: no two lamps closer than 3 m
	for sp in spots:
		var ok := true
		for o in out: if (o[0] as Vector3).distance_to(sp[0]) < 3.0: ok = false
		if ok: out.append(sp)
		if out.size() >= LAMPS[3]: break
	return out

static func _image(tex: Texture2D) -> Image:
	var k := tex.resource_path if tex.resource_path != "" else str(tex.get_rid())
	if _img_cache.has(k): return _img_cache[k]
	var img: Image = tex.get_image()
	if (img == null or img.is_empty()) and tex.resource_path.ends_with(".png") and FileAccess.file_exists(tex.resource_path):
		img = Image.load_from_file(tex.resource_path)   # headless runs (no texture data on the dummy renderer)
	if img and not img.is_empty():
		if img.is_compressed(): img.decompress()
		if img.get_width() > 256: img.resize(256, maxi(1, img.get_height() * 256 / img.get_width()), Image.INTERPOLATE_BILINEAR)
	else: img = null
	_img_cache[k] = img
	return img

## ---------- weather
func _drops(amount: int, life: float, vel: Vector2, size: Vector2, col: Color, extents: Vector3, streak: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3.DOWN; m.spread = 4.0
	m.initial_velocity_min = vel.x; m.initial_velocity_max = vel.y
	m.gravity = Vector3(0, -4.0, 0)
	if streak: m.particle_flag_align_y = true
	else:
		m.turbulence_enabled = true; m.turbulence_noise_strength = 1.2; m.turbulence_noise_scale = 3.0
		m.gravity = Vector3(0, -0.6, 0)
	p.process_material = m
	p.amount = amount; p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	if streak: p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var q := QuadMesh.new(); q.size = size
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = col
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not streak: sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	FX._sprites()
	sm.albedo_texture = FX._soft
	q.material = sm
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _rain() -> void:
	rain = _drops(RAIN[clampi(preset, 0, 3)], 0.75, Vector2(22, 27), Vector2(0.018, 0.55), Color(0.75, 0.82, 0.95, 0.38), Vector3(15, 0.5, 15), true)
	var sn: int = SPLASH[clampi(preset, 0, 3)]
	if sn > 0:
		splash = GPUParticles3D.new()
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(11, 0.02, 11)
		m.direction = Vector3.UP; m.spread = 35.0
		m.initial_velocity_min = 0.8; m.initial_velocity_max = 1.8
		m.gravity = Vector3(0, -14, 0)
		m.scale_min = 0.5; m.scale_max = 1.0
		splash.process_material = m
		splash.amount = sn; splash.lifetime = 0.22
		splash.local_coords = false
		splash.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 10, 60))
		var q := QuadMesh.new(); q.size = Vector2(0.05, 0.05)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.albedo_color = Color(0.85, 0.9, 1.0, 0.5)
		FX._sprites(); sm.albedo_texture = FX._soft
		q.material = sm
		splash.draw_pass_1 = q
		splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(splash)

func _snow() -> void:
	snow = _drops(SNOW[clampi(preset, 0, 3)], 6.0, Vector2(0.6, 1.4), Vector2(0.07, 0.07), Color(1, 1, 1, 0.85), Vector3(14, 0.5, 14), false)

func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var fwd := -cam.global_transform.basis.z; fwd.y = 0
		var c := cam.global_position + fwd.normalized() * 7.0
		var fy := float(arena.info.get("floor_y", 0.0)) * 0.01
		if rain: rain.global_position = Vector3(c.x, maxf(cam.global_position.y, fy) + 9.0, c.z)
		if snow: snow.global_position = Vector3(c.x, maxf(cam.global_position.y, fy) + 7.0, c.z)
		if splash: splash.global_position = Vector3(c.x, fy + 0.03, c.z)
	if bolt:
		bolt_t -= dt; bolt_age += dt
		if bolt_t <= 0.0:   # a strike: a bright double flash, then 5-12 s to the next
			bolt_age = 0.0; bolts += 1
			bolt_t = rng.randf_range(5.0, 12.0)
			bolt.rotation_degrees = Vector3(rng.randf_range(-70, -45), rng.randf_range(0, 360), 0)
		var a := bolt_age
		var f := 7.0 * exp(-a * 22.0) + (4.5 * exp(-(a - 0.13) * 10.0) if a > 0.13 else 0.0)
		bolt.light_energy = f
		if env:
			env.ambient_light_energy = base_amb + f * 0.09
			env.background_energy_multiplier = 1.0 + f * 0.5
