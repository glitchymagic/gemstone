class_name HDPost
extends CompositorEffect
## Remaster post on the GPU after the transparent pass (HDR, before tonemap/glow): contrast-adaptive sharpen (TAA/FSR2
## soften the image), motion blur from the velocity buffer only where things move fast (attacks, throws, knockdowns; a
## slow camera drift stays sharp), a short chromatic-aberration pulse on big hits (settings toggle), a sun lens flare
## that hides when anything covers the sun, a light vignette. HDPost.driver() feeds it per frame.

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D src;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3) uniform sampler2D vel_tex;
layout(push_constant, std430) uniform Params {
	vec2 size; float sharpen; float ca;
	float mblur; float mb_min; vec2 sun_uv;
	vec4 flare;
	float aspect; float vignette; float use_vel; float pad;
} p;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) return;
	vec2 inv = 1.0 / p.size;
	vec2 uv = (vec2(px) + 0.5) * inv;
	vec3 c = textureLod(src, uv, 0.0).rgb;
	if (p.sharpen > 0.0) {
		vec3 n = textureLod(src, uv + vec2(0.0, -inv.y), 0.0).rgb;
		vec3 s = textureLod(src, uv + vec2(0.0, inv.y), 0.0).rgb;
		vec3 e = textureLod(src, uv + vec2(inv.x, 0.0), 0.0).rgb;
		vec3 w = textureLod(src, uv + vec2(-inv.x, 0.0), 0.0).rgb;
		vec3 mn = min(c, min(min(n, s), min(e, w)));
		vec3 mx = max(c, max(max(n, s), max(e, w)));
		c = clamp(c + (4.0 * c - n - s - e - w) * p.sharpen * 0.25, mn, mx);
	}
	if (p.mblur > 0.0 && p.use_vel > 0.0) {
		vec2 v = textureLod(vel_tex, uv, 0.0).xy * p.mblur;
		float len = length(v);
		float k = smoothstep(p.mb_min, p.mb_min * 3.0, len);
		if (k > 0.0) {
			v *= min(1.0, 0.05 / max(len, 1e-6));
			vec3 acc = c;
			for (int i = 0; i < 10; i++) acc += textureLod(src, uv + v * (float(i) / 9.0 - 0.5), 0.0).rgb;
			c = mix(c, acc / 11.0, k);
		}
	}
	if (p.ca > 0.0) {
		vec2 d = (uv - 0.5) * p.ca;
		c.r = mix(c.r, textureLod(src, uv + d, 0.0).r, 1.0);
		c.b = mix(c.b, textureLod(src, uv - d, 0.0).b, 1.0);
	}
	if (p.flare.a > 0.0) {
		float vis = 0.0;
		for (int i = 0; i < 9; i++) {
			vec2 o = vec2(float(i % 3) - 1.0, float(i / 3) - 1.0) * 0.006;
			vec2 q = p.sun_uv + o;
			bool inside = q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0;
			vis += (inside && textureLod(depth_tex, q, 0.0).r <= 0.0) ? 1.0 / 9.0 : 0.0;
		}
		if (vis > 0.0) {
			vec2 asp = vec2(p.aspect, 1.0);
			float r = length((uv - p.sun_uv) * asp);
			vec3 fl = p.flare.rgb * (exp(-r * 22.0) * 0.5 + exp(-r * 5.0) * 0.05);
			vec2 dir = vec2(0.5) - p.sun_uv;
			const float gk[5] = float[](0.35, 0.7, 1.15, 1.45, 1.9);
			const float gs[5] = float[](0.035, 0.022, 0.06, 0.03, 0.09);
			const vec3 gc[5] = vec3[](vec3(1.0, 0.8, 0.5), vec3(0.5, 1.0, 0.7), vec3(0.6, 0.7, 1.0), vec3(1.0, 0.6, 0.9), vec3(0.7, 0.85, 1.0));
			for (int i = 0; i < 5; i++) {
				float d = length((uv - (p.sun_uv + dir * gk[i])) * asp);
				fl += p.flare.rgb * gc[i] * smoothstep(gs[i], gs[i] * 0.55, d) * 0.07;
			}
			float ring = length((uv - (p.sun_uv + dir * 2.0)) * asp);
			fl += p.flare.rgb * vec3(0.6, 0.8, 1.0) * smoothstep(0.03, 0.0, abs(ring - 0.32)) * 0.025;
			c += fl * vis;
		}
	}
	if (p.vignette > 0.0) {
		float r = length((uv - 0.5) * vec2(p.aspect, 1.0));
		c *= mix(1.0, smoothstep(1.25, 0.35, r), p.vignette);
	}
	imageStore(color_image, px, vec4(c, 1.0));
}
"""

# the colour buffer can't be texture_copy'd (no COPY_FROM usage): a tiny compute pass copies it first
const COPY_GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D copy_image;
layout(push_constant, std430) uniform Params { vec2 size; vec2 pad; } p;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) return;
	imageStore(copy_image, px, imageLoad(color_image, px));
}
"""

var sharpen := 0.0
var ca := 0.0
var mblur := 0.0
var mb_min := 0.006
var sun_uv := Vector2(-1, -1)
var flare := Color(0, 0, 0, 0)
var vignette := 0.0
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var copy_shader: RID
var copy_pipeline: RID
var sampler: RID

static var _kick := 0.0   # impact pulse (FX.spawn on big hits), decays in the driver
static var impact_ca := true   # settings toggle

static func kick(kind: String) -> void:
	match kind:
		"hit_big": _kick = maxf(_kick, 1.0)
		"transform", "fusion": _kick = maxf(_kick, 0.8)

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(_setup)

func _setup() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null: return
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = GLSL
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("HDPost: " + spirv.compile_error_compute)
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var csrc := RDShaderSource.new()
	csrc.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	csrc.source_compute = COPY_GLSL
	var cspv := rd.shader_compile_spirv_from_source(csrc)
	if cspv.compile_error_compute != "":
		push_error("HDPost copy: " + cspv.compile_error_compute)
		return
	copy_shader = rd.shader_create_from_spirv(cspv)
	copy_pipeline = rd.compute_pipeline_create(copy_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR; ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE; ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler = rd.sampler_create(ss)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd:
		if shader.is_valid(): rd.free_rid(shader)
		if copy_shader.is_valid(): rd.free_rid(copy_shader)
		if sampler.is_valid(): rd.free_rid(sampler)

func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new(); u.uniform_type = type; u.binding = binding
	for i in ids: u.add_id(i)
	return u

func _render_callback(_type: int, render_data: RenderData) -> void:
	if rd == null or not pipeline.is_valid() or not copy_pipeline.is_valid(): return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null: return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0: return
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var vel := buffers.get_velocity_layer(view)
		var fmt := rd.texture_get_format(color)
		if not buffers.has_texture("hd_post", "copy"):
			buffers.create_texture("hd_post", "copy", fmt.format,
				RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
				RenderingDevice.TEXTURE_SAMPLES_1, size, buffers.get_view_count(), 1, true, false)
		var copy := buffers.get_texture_slice("hd_post", "copy", view, 0, 1, 1)
		var gx := (size.x + 7) / 8
		var gy := (size.y + 7) / 8
		var cset := UniformSetCacheRD.get_cache(copy_shader, 0, [_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [copy])])
		var cpc := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
		var cl0 := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl0, copy_pipeline)
		rd.compute_list_bind_uniform_set(cl0, cset, 0)
		rd.compute_list_set_push_constant(cl0, cpc, cpc.size())
		rd.compute_list_dispatch(cl0, gx, gy, 1)
		rd.compute_list_end()
		var use_vel := 1.0 if vel.is_valid() else 0.0
		var us := [_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [sampler, copy]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [sampler, depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [sampler, vel if vel.is_valid() else copy])]
		var uset := UniformSetCacheRD.get_cache(shader, 0, us)
		var pc := PackedFloat32Array([size.x, size.y, sharpen, ca if impact_ca else 0.0,
			mblur, mb_min, sun_uv.x, sun_uv.y,
			flare.r, flare.g, flare.b, flare.a,
			float(size.x) / float(size.y), vignette, use_vel, 0.0])
		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, uset, 0)
		var bytes := pc.to_byte_array()
		rd.compute_list_set_push_constant(cl, bytes, bytes.size())
		rd.compute_list_dispatch(cl, gx, gy, 1)
		rd.compute_list_end()


## Per-frame feed: sun position on screen, the impact pulse. Lives under the WorldEnvironment.
class Driver extends Node:
	var fx: HDPost
	var sun_color := Color(1.0, 0.85, 0.6)
	func _process(dt: float) -> void:
		HDPost._kick = maxf(0.0, HDPost._kick - dt * 3.5)
		fx.ca = 0.006 * HDPost._kick * HDPost._kick
		var cam := get_viewport().get_camera_3d()
		var sun := get_parent().get_parent().get_node_or_null("Sun") as DirectionalLight3D if get_parent() and get_parent().get_parent() else null
		fx.flare.a = 0.0
		if cam and sun and sun.visible and fx.flare.r + fx.flare.g + fx.flare.b > 0.0:
			var to_sun := sun.global_transform.basis.z.normalized()   # a directional light shines along -Z
			var far := cam.global_position + to_sun * 500.0
			if not cam.is_position_behind(far):
				var vp := get_viewport().get_visible_rect().size
				fx.sun_uv = cam.unproject_position(far) / vp
				fx.flare.a = 1.0
