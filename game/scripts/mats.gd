class_name Mats
extends RefCounted
## Swaps the imported glTF materials for the toon/outline look, keeping the disc textures.

static var outline_shader: Shader

static func toonify(root: Node, toon: Shader, outline := true) -> void:
	if outline_shader == null and ResourceLoader.exists("res://shaders/outline.gdshader"):
		outline_shader = load("res://shaders/outline.gdshader")
	for n in _meshes(root):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			var m := ShaderMaterial.new()
			m.shader = toon
			if src is BaseMaterial3D:
				var tex: Texture2D = (src as BaseMaterial3D).albedo_texture
				if tex:
					m.set_shader_parameter("albedo_tex", tex)
					m.set_shader_parameter("use_tex", true)
				m.set_shader_parameter("alpha_clip", (src as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			if outline and outline_shader:
				var o := ShaderMaterial.new(); o.shader = outline_shader
				m.next_pass = o
			mi.set_surface_override_material(s, m)

static func _meshes(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh: out.append(n)
	for c in n.get_children(): _meshes(c, out)
	return out

## Stage: keep the disc texture, crisp filtering upgrade, alpha scissor for cut-out leaves/rails.
static func stage_mats(root: Node) -> void:
	_stage_classic(root)
	if HD.look() != "classic": HD.stage_mats(root)

static func _stage_classic(root: Node) -> void:
	for n in _meshes(root):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s)
			if src is StandardMaterial3D:
				var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.roughness = 0.85
				m.metallic_specular = 0.25
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				var rn := src.resource_name
				if rn.ends_with("_add"):   # the disc's translucent list with dst = ONE (light shafts, glows): additive.
					# Lit, not unshaded: the TSP says "modulate", so the game scales these by its per-vertex lighting
					# (Gunrock's furnace column is near-invisible in the game's fight frames, blinding when unlit)
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				elif rn.ends_with("_blend"):   # translucent list, src alpha / inverse src alpha
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.alpha_scissor_threshold = 0.5
				mi.set_surface_override_material(s, m)
