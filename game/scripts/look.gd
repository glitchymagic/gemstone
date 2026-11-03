class_name Look
extends RefCounted
## Today's-standard lighting for the ripped Londo: SDFGI, SSAO, SSIL, SSR, volumetric fog with
## sun shafts, glow, AgX tonemap + grade, soft sun shadows. Quality presets scale it.

const PRESETS := ["Low", "Medium", "High", "Ultra"]
static var force_preset := -1   # tests/benchmarks: PS_PRESET env var


static func preset() -> int:   # the current quality preset (PS_PRESET env var wins: tests, renders)
	if force_preset < 0 and OS.has_environment("PS_PRESET"): force_preset = int(OS.get_environment("PS_PRESET"))
	if force_preset >= 0: return force_preset
	var g := UI.game()
	return int(g.get("quality")) if g else 2

static func build_environment(parent: Node, preset := -1) -> WorldEnvironment:
	if force_preset < 0 and OS.has_environment("PS_PRESET"): force_preset = int(OS.get_environment("PS_PRESET"))
	if force_preset >= 0: preset = force_preset
	if preset < 0: preset = Look.preset()
	var we := WorldEnvironment.new(); we.name = "Look"
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.82)
	sm.sky_horizon_color = Color(0.78, 0.82, 0.9)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.66)
	sm.ground_bottom_color = Color(0.2, 0.22, 0.25)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.ssao_enabled = preset >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = preset >= 2
	env.ssil_radius = 4.0
	env.ssr_enabled = preset >= 2
	env.ssr_max_steps = 48
	env.sdfgi_enabled = preset >= 3
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.15
	env.volumetric_fog_enabled = preset >= 2
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.92, 0.9, 0.86)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 70.0
	env.fog_enabled = preset < 2
	env.fog_density = 0.004
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new(); sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.light_angular_distance = 1.2 if preset >= 2 else 0.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.light_volumetric_fog_energy = 1.6
	sun.directional_shadow_max_distance = 60.0
	parent.add_child(sun)
	var rim := DirectionalLight3D.new(); rim.name = "Rim"
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.7, 0.8, 1.0); rim.light_energy = 0.35
	parent.add_child(rim)
	apply_viewport(parent.get_viewport(), preset)
	HD.environment(we, preset)
	return we

## Per-stage tweak (stgN0_info.json "indoor"): roofed stages (Wang-Tang's dojo, ...) block the sun, so they get a warm
## ambient fill, thinner fog and an overhead fill light instead of the open-air Londo setup.
static func stage_tweak(parent: Node, info: Dictionary) -> void:
	var we := parent.get_node_or_null("Look") as WorldEnvironment
	if we == null: return
	var env := we.environment
	apply_background(parent, env, info)
	if not info.get("indoor", false): return
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.86, 0.68)
	env.ambient_light_energy = 0.9
	env.volumetric_fog_density = 0.003
	env.fog_density = 0.001
	var b: Array = info.get("bounds_cm", [-500, -500, 500, 500])
	var fill := OmniLight3D.new(); fill.name = "IndoorFill"
	fill.position = Vector3((float(b[0]) + float(b[2])) * 0.005, float(info.get("floor_y", 0.0)) * 0.01 + 5.0, (float(b[1]) + float(b[3])) * 0.005)
	fill.omni_range = 16.0; fill.light_energy = 1.6; fill.light_color = Color(1.0, 0.9, 0.75); fill.shadow_enabled = true
	parent.add_child(fill)

## The game's own background (stgN0_info.json "bg_rgb": the PowerVR background plane read from Flycast's VRAM in a
## real fight on that stage, tools/bgplane.py): 3 colours at screen (0,0), (640,0), (0,480), shaded as one plane over
## the whole screen wherever no geometry covers it (Londo: dark blue at the top to light blue at the bottom). Drawn the
## same way here, as a full-screen layer behind the 3D; the procedural sky stays only as the ambient / reflection source.
const BG_SHADER := "shader_type canvas_item;\nuniform vec4 c0 : source_color; uniform vec4 c1 : source_color; uniform vec4 c2 : source_color;\nvoid fragment() { COLOR = vec4((c0 + (c1 - c0) * UV.x + (c2 - c0) * UV.y).rgb, 1.0); }"

static func apply_background(parent: Node, env: Environment, info: Dictionary) -> void:
	if not info.has("bg_rgb"): return
	var cs: Array = info.bg_rgb
	if cs.size() == 3 and cs[0] is int: cs = [cs, cs, cs]   # older single-colour entries
	var col := func(c: Array) -> Color: return Color8(int(c[0]), int(c[1]), int(c[2]))
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.background_color = col.call(cs[0])
	if parent == null: return
	var layer := CanvasLayer.new(); layer.name = "GameBackground"; layer.layer = -10
	var rect := ColorRect.new(); rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new(); sh.code = BG_SHADER
	var mat := ShaderMaterial.new(); mat.shader = sh
	for i in 3: mat.set_shader_parameter("c%d" % i, col.call(cs[i]))
	rect.material = mat
	layer.add_child(rect)
	parent.add_child(layer)

static func apply_viewport(vp: Viewport, preset: int) -> void:
	if vp == null: return
	vp.msaa_3d = Viewport.MSAA_2X if preset >= 1 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if preset == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = preset >= 2
	if preset >= 3:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = 0.67
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
