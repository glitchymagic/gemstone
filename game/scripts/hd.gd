class_name HD
extends RefCounted
## Pass 6 "Remaster" look: the disc's own models and textures with modern materials. Look.mode picks it per game;
## "classic" keeps the pass 1-5 toon look untouched (Mats.toonify).

const LOOKS := ["remaster", "classic"]
static var force_look := ""   # tests / renders: PS_LOOK env var (remaster, classic, anime, pbr)
static var _shaders := {}
const FIGHTER_LAYER := 2

static func look() -> String:
	if force_look == "" and OS.has_environment("PS_LOOK"): force_look = OS.get_environment("PS_LOOK")
	if force_look != "": return force_look
	var g := UI.game()
	return str(g.get("look")) if g and g.get("look") != null else "remaster"

## The subdivided mesh (assets/hd, tools/build_hd.sh) for the Remaster look at Medium and up; Low / Classic keep the
## disc's own mesh.
static func model_path(id: String, fallback: String) -> String:
	if look() == "classic" or Look.preset() < 1: return fallback
	var p := "res://assets/hd/%s.glb" % id
	return p if ResourceLoader.exists(p) else fallback

static func shader(sname: String) -> Shader:
	if not _shaders.has(sname): _shaders[sname] = load("res://shaders/%s.gdshader" % sname)
	return _shaders[sname]

## Fighter materials for the current look. toon = the classic shader PSModel already loaded; id = the form (p00 ...),
## whose derived maps (tools/hd_tex.py: assets/hd/tex/<id>/tNN_{m,s,n}.png) are found by material name.
static func fighter(root: Node, toon: Shader, id := "") -> void:
	var lk := look()
	if lk == "classic":
		Mats.toonify(root, toon)
		return
	var anime := lk == "anime"
	var sh := shader("fighter_anime" if anime else "fighter_pbr")
	var td := "res://assets/hd/tex/%s/" % id
	var low := Look.preset() < 1
	for n in Mats._meshes(root):
		var mi := n as MeshInstance3D
		mi.layers = FIGHTER_LAYER   # the fighter light rig lights only layer 2; contact shadows skip it
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var m := ShaderMaterial.new()
			m.shader = sh
			if src is BaseMaterial3D:
				var tex: Texture2D = (src as BaseMaterial3D).albedo_texture
				if tex:
					m.set_shader_parameter("albedo_tex", tex)
					m.set_shader_parameter("use_tex", true)
				m.set_shader_parameter("alpha_clip", (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			var mn := src.resource_name if src else ""
			if id != "" and mn != "" and ResourceLoader.exists(td + mn + "_m.png"):
				m.set_shader_parameter("mask_m", load(td + mn + "_m.png"))
				m.set_shader_parameter("mask_s", load(td + mn + "_s.png"))
				m.set_shader_parameter("use_maps", true)
				if ResourceLoader.exists(td + mn + "_n.png"):
					m.set_shader_parameter("normal_tex", load(td + mn + "_n.png"))
					m.set_shader_parameter("use_normal_tex", true)
			if low: m.set_shader_parameter("micro", 0.0)
			if anime:
				var o := ShaderMaterial.new(); o.shader = shader("ink")
				m.next_pass = o
			mi.set_surface_override_material(s, m)
	var holder := root.get_parent()
	if holder and holder.get_node_or_null("ContactShadow") == null:
		holder.add_child(contact_shadow())

## A soft dark disc under a fighter's feet (decal on the stage only, layer 1): grounds them where the sun shadow is
## thin or off to one side, like the contact shadows of modern fighting games.
static func contact_shadow() -> Decal:
	var d := Decal.new(); d.name = "ContactShadow"
	d.size = Vector3(1.3, 2.2, 1.3)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.62)); g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.45, Color(0, 0, 0, 0.35))
	var t := GradientTexture2D.new(); t.gradient = g; t.width = 128; t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(0.5, 0.0)
	d.texture_albedo = t
	d.albedo_mix = 1.0
	d.cull_mask = 1
	d.upper_fade = 0.3; d.lower_fade = 0.3
	return d

## Remaster tweaks on top of Look.build_environment (Classic keeps it as it is): bloom only from what is really hot
## (emissive, fire, gem glints, the sun), not from every lit surface, now that materials are physically lit.
static func environment(we: WorldEnvironment, preset: int) -> void:
	if look() == "classic" or we == null: return
	var env := we.environment
	# auto exposure (bright plazas vs the dojo or Valgas's lair), in a narrow range so it never pumps
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = preset >= 1
	ca.auto_exposure_scale = 0.42
	ca.auto_exposure_speed = 0.6
	ca.auto_exposure_min_sensitivity = 88.0
	ca.auto_exposure_max_sensitivity = 160.0
	we.camera_attributes = ca
	var g := UI.game()
	HDPost.impact_ca = bool(g.get("impact_fx")) if g and g.get("impact_fx") != null else true
	if preset >= 1 and RenderingServer.get_rendering_device() != null:
		var post := HDPost.new()
		post.sharpen = [0.0, 0.0, 0.4, 0.55][preset]
		post.mblur = [0.0, 0.0, 0.5, 0.6][preset]
		post.vignette = 0.18
		post.flare = Color(1.0, 0.86, 0.62, 0.0) if preset >= 2 else Color(0, 0, 0, 0)
		var comp := Compositor.new(); comp.compositor_effects = [post]
		we.compositor = comp
		var drv := HDPost.Driver.new(); drv.name = "HDPostDriver"; drv.fx = post
		we.add_child(drv)
	env.glow_hdr_threshold = 1.8
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.volumetric_fog_density = 0.006   # air, not haze: the sky and the far facades stay crisp
	env.volumetric_fog_sky_affect = 0.25

## Fighting-game character lighting: a warm key from camera-left and above (gives faces and muscles their shape), a cool
## and a warm rim from behind, riding the camera and lighting only the fighters (layer 2), so faces read and silhouettes
## pop on every stage and under any roof. The stage's own sun and sky still light them too.
static func light_rig(cam: Camera3D) -> void:
	if look() == "classic" or cam == null: return
	var rig := Node3D.new(); rig.name = "FighterRig"
	cam.add_child(rig)
	for d in [[Vector3(-34, -40, 0), Color(1.0, 0.93, 0.84), 0.4], [Vector3(-14, 152, 0), Color(0.62, 0.76, 1.0), 0.28],
			[Vector3(-24, 212, 0), Color(1.0, 0.84, 0.68), 0.22]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = d[0]; l.light_color = d[1]; l.light_energy = d[2]
		l.light_cull_mask = FIGHTER_LAYER
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 0.0
		l.light_specular = 1.0
		rig.add_child(l)


## ---- Stages ----
## Per-class surface numbers for stage_pbr (tools/hd_stage.py decides each texture's class from the disc texture).
const STAGE_CLASS := {
	"painted": {"rough": 0.75, "rough_var": 0.25, "spec": 0.45, "bump": 0.8, "cavity": 0.3},
	"stone": {"rough": 0.86, "rough_var": 0.3, "spec": 0.4, "bump": 1.6, "cavity": 0.5, "pom": 1.0},
	"wood": {"rough": 0.62, "rough_var": 0.35, "spec": 0.45, "bump": 1.2, "cavity": 0.4},
	"metal": {"rough": 0.32, "rough_var": 0.4, "metal": 0.75, "spec": 0.5, "bump": 0.6, "cavity": 0.3},
	"ground": {"rough": 0.92, "rough_var": 0.15, "spec": 0.3, "bump": 1.4, "cavity": 0.45, "pom": 0.7},
	"cloth": {"rough": 0.85, "rough_var": 0.1, "spec": 0.35, "bump": 0.6, "cavity": 0.2, "sheen": 0.3, "backlight": 0.25},
	"foliage": {"rough": 0.6, "rough_var": 0.2, "spec": 0.4, "bump": 1.0, "cavity": 0.3, "sway": 0.05, "backlight": 0.45},
	"glass": {"rough": 0.04, "rough_var": 0.05, "spec": 0.9, "bump": 0.05, "cavity": 0.0},
	"snow": {"rough": 0.55, "rough_var": 0.1, "spec": 0.5, "bump": 0.5, "cavity": 0.1, "glitter": 1.0, "albedo_mul": 0.8},
}
static var _stage_classes := {}

static func stage_class(key: String) -> String:
	if _stage_classes.is_empty():
		var p := "res://assets/remaster/stage_classes.json"
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary: _stage_classes = j
		if _stage_classes.is_empty(): _stage_classes = {"auto": {}}
	var ov: Dictionary = _stage_classes.get("overrides", {})
	return str(ov.get(key, (_stage_classes.get("auto", {}) as Dictionary).get(key, "painted")))

## Stage materials for the Remaster look (Mats.stage_mats already made the Classic StandardMaterial3D for each surface;
## additive / translucent ones stay as they are, glass gets glossy, the rest becomes stage_pbr / water).
static func stage_mats(root: Node) -> void:
	var p := Look.preset()
	for n in Mats._meshes(root):
		var mi := n as MeshInstance3D
		var aabb := mi.get_aabb()   # local (the props aren't in the tree yet)
		for s in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(s) as StandardMaterial3D
			if src == null: continue
			var tex := src.albedo_texture
			var key := tex.resource_path.get_file().get_basename() if tex else ""
			var cls := stage_class(key)
			if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:   # _add / _blend: lights, glass, splash
				if cls == "glass" or cls == "water":
					src.roughness = 0.05; src.metallic_specular = 0.9
				continue
			var m := ShaderMaterial.new()
			if cls == "water":
				m.shader = shader("water")
				m.set_shader_parameter("albedo_tex", tex)
				m.set_shader_parameter("albedo_color", src.albedo_color)
				mi.set_surface_override_material(s, m)
				continue
			m.shader = shader("stage_pbr_2s" if src.cull_mode == BaseMaterial3D.CULL_DISABLED else "stage_pbr")
			m.set_shader_parameter("albedo_tex", tex)
			m.set_shader_parameter("use_tex", tex != null)
			m.set_shader_parameter("albedo_color", src.albedo_color)
			m.set_shader_parameter("alpha_clip", src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			var c: Dictionary = STAGE_CLASS.get(cls, STAGE_CLASS.painted)
			for k in ["rough", "rough_var", "spec", "bump", "cavity", "metal", "sheen", "backlight", "glitter", "albedo_mul"]:
				if c.has(k): m.set_shader_parameter(k, c[k])
			if c.has("pom") and p >= 2:
				m.set_shader_parameter("pom_depth", c.pom)
				m.set_shader_parameter("pom_steps", 16 if p >= 3 else 8)
			if c.has("sway") and p >= 1:
				m.set_shader_parameter("sway", c.sway)
				m.set_shader_parameter("floor_y", aabb.position.y)
			mi.set_surface_override_material(s, m)

## Per stage: ambient particles, sky (cloud cover; colours: the game's background plane "bg_rgb" when the stage info
## has it (pass 4), else these), colour grade [brightness, contrast, saturation, shadow tint, highlight tint].
const STAGE_FX := {
	"stg00": {"parts": "dust", "sky": [Color(0.3, 0.5, 0.85), Color(0.78, 0.84, 0.92)], "clouds": 0.45,
		"grade": [1.0, 1.06, 1.13, Color(0.02, 0.04, 0.09), Color(1.0, 0.97, 0.9)], "spray": Vector3(0, 0.6, 0.5)},
	"stg10": {"parts": "snow", "sky": [Color(0.42, 0.55, 0.78), Color(0.86, 0.88, 0.92)], "clouds": 0.65,
		"grade": [1.0, 1.06, 1.15, Color(0.02, 0.04, 0.07), Color(0.98, 0.99, 1.0)]},
	"stg20": {"parts": "dust", "sky": [Color(0.4, 0.5, 0.7), Color(0.9, 0.8, 0.65)], "clouds": 0.3,
		"grade": [1.0, 1.08, 1.10, Color(0.05, 0.03, 0.02), Color(1.0, 0.94, 0.84)]},
	"stg30": {"parts": "dust", "sky": [Color(0.2, 0.3, 0.55), Color(0.75, 0.7, 0.8)], "clouds": 0.55,
		"grade": [1.0, 1.08, 1.10, Color(0.04, 0.03, 0.08), Color(1.0, 0.95, 0.92)]},
	"stg40": {"parts": "embers", "sky": [Color(0.35, 0.4, 0.6), Color(0.95, 0.75, 0.55)], "clouds": 0.6,
		"grade": [1.0, 1.1, 1.11, Color(0.06, 0.03, 0.02), Color(1.0, 0.92, 0.8)]},
	"stg50": {"parts": "sand", "sky": [Color(0.3, 0.52, 0.85), Color(0.95, 0.85, 0.7)], "clouds": 0.3,
		"grade": [1.02, 1.07, 1.10, Color(0.05, 0.035, 0.02), Color(1.0, 0.95, 0.82)]},
	"stg60": {"parts": "petals", "sky": [Color(0.38, 0.55, 0.88), Color(0.95, 0.85, 0.85)], "clouds": 0.4,
		"grade": [1.0, 1.06, 1.13, Color(0.04, 0.03, 0.06), Color(1.0, 0.95, 0.93)]},
	"stg70": {"parts": "sand", "sky": [Color(0.25, 0.48, 0.85), Color(1.0, 0.88, 0.68)], "clouds": 0.15,
		"grade": [1.03, 1.08, 1.10, Color(0.06, 0.04, 0.02), Color(1.0, 0.94, 0.8)]},
	"stg80": {"parts": "spray", "sky": [Color(0.25, 0.45, 0.78), Color(0.8, 0.86, 0.92)], "clouds": 0.55, "ground": Color(0.04, 0.13, 0.22),
		"grade": [1.0, 1.06, 1.11, Color(0.02, 0.05, 0.08), Color(0.98, 0.97, 0.94)]},
	"stg90": {"parts": "embers", "sky": [Color(0.12, 0.08, 0.18), Color(0.5, 0.25, 0.3)], "clouds": 0.7,
		"grade": [0.98, 1.12, 1.10, Color(0.06, 0.02, 0.06), Color(1.0, 0.9, 0.85)]},
	"stga0": {"parts": "embers", "sky": [Color(0.1, 0.06, 0.16), Color(0.55, 0.3, 0.35)], "clouds": 0.7,
		"grade": [0.98, 1.12, 1.10, Color(0.06, 0.02, 0.07), Color(1.0, 0.9, 0.86)]},
}

## Stage dressing for the Remaster look, after the arena is built: reflection probe, modern sky, colour grade, ambient
## particles. parent holds the WorldEnvironment "Look".
static func stage(parent: Node, arena: Arena) -> void:
	if look() == "classic" or arena == null: return
	var p := Look.preset()
	var fx: Dictionary = STAGE_FX.get(arena.stage, STAGE_FX.stg00)
	var b := arena.bounds
	var fy := float(arena.info.get("floor_y", 0.0)) * Arena.UNIT if arena.stage != "stg00" else 0.0
	var ctr := Vector3(b.position.x + b.size.x * 0.5, fy, b.position.y + b.size.y * 0.5)
	if p >= 1:
		var rp := ReflectionProbe.new(); rp.name = "StageProbe"
		rp.size = Vector3(b.size.x + 8.0, 14.0, b.size.y + 8.0)
		rp.position = ctr + Vector3(0, 3.0, 0)
		rp.origin_offset = Vector3(0, -1.5, 0)
		rp.box_projection = true
		rp.interior = bool(arena.info.get("indoor", false))
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.cull_mask = 1   # the stage, not the fighters
		parent.add_child(rp)
	var we := parent.get_node_or_null("Look") as WorldEnvironment
	if we: _sky_and_grade(we.environment, fx, arena.info, parent)
	if p >= 1: _particles(parent, str(fx.get("parts", "dust")), ctr, b, p)
	if fx.has("spray") and p >= 1:
		_particles(parent, "spray", fx.spray, Rect2(fx.spray.x - 1.5, fx.spray.z - 1.5, 3.0, 3.0), p)

static func _sky_and_grade(env: Environment, fx: Dictionary, info: Dictionary, parent: Node) -> void:
	var cols: Array = fx.get("sky", [Color(0.3, 0.5, 0.85), Color(0.8, 0.84, 0.9)])
	if info.has("bg_rgb"):   # the game's own background plane (pass 4): top colour -> zenith, bottom -> horizon
		var cs: Array = info.bg_rgb
		if cs.size() == 3 and not (cs[0] is int):
			cols = [Color8(int(cs[0][0]), int(cs[0][1]), int(cs[0][2])), Color8(int(cs[2][0]), int(cs[2][1]), int(cs[2][2]))]
		var bg := parent.get_node_or_null("GameBackground")
		if bg: (bg as CanvasLayer).visible = false
	var sm := ShaderMaterial.new(); sm.shader = shader("sky_hd")
	sm.set_shader_parameter("top_color", cols[0]); sm.set_shader_parameter("horizon_color", cols[1])
	sm.set_shader_parameter("cloud_cover", float(fx.get("clouds", 0.45)))
	if fx.has("ground"): sm.set_shader_parameter("ground_color", fx.ground)
	var sky := Sky.new(); sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	var g: Array = fx.get("grade", [1.0, 1.06, 1.06, Color(0.03, 0.04, 0.07), Color(1.0, 0.97, 0.9)])
	env.adjustment_enabled = true
	env.adjustment_brightness = g[0]; env.adjustment_contrast = g[1]; env.adjustment_saturation = g[2]
	var gr := Gradient.new()
	gr.set_color(0, g[3]); gr.set_color(1, g[4])
	gr.add_point(0.5, Color(0.5, 0.5, 0.5).lerp((g[3] as Color) + (g[4] as Color) - Color(0.5, 0.5, 0.5), 0.12))
	var lut := GradientTexture1D.new(); lut.gradient = gr; lut.width = 256
	env.adjustment_color_correction = lut

static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new(); t.gradient = g; t.width = 64; t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(0.5, 0.0)
	return t

## Ambient particles that fit the stage: sunlit dust motes, embers from the furnaces/lava, sand blowing through,
## Ayame's cherry petals, Mutsu's leaves, sea / fountain spray. Light on the GPU; off on Low.
static func _particles(parent: Node, kind: String, ctr: Vector3, b: Rect2, preset: int) -> void:
	var ps := GPUParticles3D.new(); ps.name = "Ambient_" + kind
	var pm := ParticleProcessMaterial.new()
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _soft_dot()
	var q := QuadMesh.new(); q.material = mat
	var amount := 160; var size := 0.03; var life := 8.0
	var col := Color(1.0, 0.95, 0.85, 0.35)
	var h := 4.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4; pm.turbulence_noise_scale = 3.0
	match kind:
		"dust":
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pm.initial_velocity_min = 0.02; pm.initial_velocity_max = 0.08
			pm.direction = Vector3(1, 0.2, 0.3); pm.spread = 180.0
		"embers":
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			col = Color(2.2, 0.8, 0.25, 0.9); size = 0.035; amount = 140; life = 5.0
			pm.direction = Vector3(0, 1, 0); pm.spread = 25.0
			pm.initial_velocity_min = 0.3; pm.initial_velocity_max = 0.9
			pm.turbulence_noise_strength = 1.2
		"sand":
			col = Color(0.95, 0.82, 0.6, 0.45); size = 0.025; amount = 260; life = 4.0
			pm.direction = Vector3(1, 0.05, 0.2); pm.spread = 12.0
			pm.initial_velocity_min = 1.2; pm.initial_velocity_max = 2.4
			h = 2.0
		"petals", "leaves":
			mat.albedo_texture = null
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			col = Color(1.0, 0.72, 0.8, 1.0) if kind == "petals" else Color(0.75, 0.5, 0.18, 1.0)
			size = 0.045; amount = 90; life = 9.0
			pm.gravity = Vector3(0.15, -0.35, 0.05)
			pm.angular_velocity_min = -180.0; pm.angular_velocity_max = 180.0
			pm.particle_flag_rotate_y = true
			pm.angle_min = -180.0; pm.angle_max = 180.0
			pm.initial_velocity_min = 0.1; pm.initial_velocity_max = 0.3
			h = 6.0
		"snow":
			col = Color(1.0, 1.0, 1.0, 0.85); size = 0.035; amount = 320; life = 7.0
			pm.gravity = Vector3(0.1, -0.6, 0.0)
			pm.initial_velocity_min = 0.0; pm.initial_velocity_max = 0.1
			pm.turbulence_noise_strength = 0.6
			h = 7.0
		"spray":
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			col = Color(0.85, 0.95, 1.0, 0.35); size = 0.04; amount = 120; life = 1.6
			pm.gravity = Vector3(0, -3.0, 0)
			pm.direction = Vector3(0, 1, 0); pm.spread = 35.0
			pm.initial_velocity_min = 1.2; pm.initial_velocity_max = 2.2
			h = 0.4
	q.size = Vector2(size, size)
	pm.color = col
	pm.emission_box_extents = Vector3(b.size.x * 0.5, h * 0.5, b.size.y * 0.5)
	ps.process_material = pm
	ps.draw_pass_1 = q
	ps.amount = amount if preset >= 2 else amount / 2
	ps.lifetime = life
	ps.preprocess = life
	ps.visibility_aabb = AABB(Vector3(-b.size.x, -2, -b.size.y), Vector3(b.size.x * 2, h + 8, b.size.y * 2))
	ps.position = Vector3(ctr.x, ctr.y + h * 0.5 + 0.2, ctr.z) if kind != "spray" else ctr
	ps.layers = 1
	parent.add_child(ps)


## The far blur starts 1 m behind the fighter, measured from where the camera is NOW: a camera that moves after HD.hero
## (the trailer's hero orbit) calls this every frame, or the fighter ends up inside the blur (trailer v2: set at the
## origin, 2 m, with the orbit 4 m out).
static func hero_focus(cam: Camera3D, focus: Vector3) -> void:
	var ca := cam.attributes as CameraAttributesPractical if cam else null
	if ca: ca.dof_blur_far_distance = cam.global_position.distance_to(focus) + 1.0


## Select screen / win pose as a hero render (Remaster): a dark glossy studio floor that reflects the fighter, a warm
## spot from above with a light beam through the fog, a dark studio sky, depth of field past the fighter.
static func hero(parent: Node3D, cam: Camera3D, focus: Vector3, floor_y := 0.0) -> void:
	if look() == "classic" or cam == null: return
	var p := Look.preset()
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	ca.dof_blur_far_enabled = p >= 1
	ca.dof_blur_far_transition = 2.5
	ca.dof_blur_amount = 0.12
	cam.attributes = ca
	hero_focus(cam, focus)
	var fl := MeshInstance3D.new(); fl.name = "StudioFloor"
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.045, 0.045, 0.06); fm.roughness = 0.24; fm.metallic_specular = 0.6
	fl.material_override = fm
	fl.position = Vector3(focus.x, floor_y, focus.z)
	parent.add_child(fl)
	var sp := SpotLight3D.new(); sp.name = "HeroSpot"
	sp.position = focus + Vector3(0.6, 5.5, 1.2)
	sp.look_at_from_position(sp.position, Vector3(focus.x, floor_y, focus.z), Vector3.UP)
	sp.spot_angle = 24.0; sp.spot_range = 12.0; sp.spot_attenuation = 0.6
	sp.light_energy = 4.0; sp.light_color = Color(1.0, 0.9, 0.78)
	sp.shadow_enabled = true; sp.light_volumetric_fog_energy = 3.0
	parent.add_child(sp)
	var we := parent.get_node_or_null("Look") as WorldEnvironment
	if we:
		if we.compositor:   # no motion blur on the slow hero camera moves
			for e in we.compositor.compositor_effects:
				if e is HDPost: (e as HDPost).mblur = 0.0
		var env := we.environment
		var sm := ShaderMaterial.new(); sm.shader = shader("sky_hd")
		sm.set_shader_parameter("top_color", Color(0.015, 0.015, 0.03)); sm.set_shader_parameter("horizon_color", Color(0.1, 0.08, 0.14))
		sm.set_shader_parameter("ground_color", Color(0.01, 0.01, 0.015)); sm.set_shader_parameter("cloud_cover", 0.0)
		sm.set_shader_parameter("sun_disc", 0.0)
		var sky := Sky.new(); sky.sky_material = sm; env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.ambient_light_energy = 0.35
		env.volumetric_fog_density = 0.03
		var sun := parent.get_node_or_null("Sun") as DirectionalLight3D
		if sun: sun.light_energy = 0.25; sun.light_volumetric_fog_energy = 0.0
