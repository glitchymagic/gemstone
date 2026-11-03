// Shared by the Remaster fighter shaders: the toon interface fx.gd / pass 5 drive (flash, glow, rim_*), material
// classes guessed per texel from the disc texture's own colours (skin / metal / hair / cloth / eyes), and a normal map
// derived on the fly from the texture's luminance (overridden by the baked maps in assets/hd when present).
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform bool alpha_clip = false;
uniform vec4 shade_tint : source_color = vec4(0.62, 0.55, 0.78, 1.0);
uniform float rim_strength = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float spec_size = 0.93;
uniform float spec_strength = 0.35;
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float bump_strength = 2.0;
// baked per-texture maps (tools/hd_maps.py): normal (tangent space), mask R skin G metal B hair A cloth sheen
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_tex = false;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_mask_tex = false;
uniform float mat_class = -1.0;   // per-material override: -1 per texel, 0 cloth, 1 skin, 2 metal, 3 hair, 4 leather, 5 gem

vec3 hd_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

float hd_lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// x skin, y metal, z hair, w cloth (0..1 each)
vec4 hd_classes(vec3 c, vec2 uv) {
	if (use_mask_tex) return texture(mask_tex, uv);
	if (mat_class >= 0.0) {
		float k = mat_class;
		return vec4(float(k == 1.0), float(k == 2.0 || k == 5.0), float(k == 3.0), float(k == 0.0) + 0.5 * float(k == 4.0));
	}
	vec3 h = hd_hsv(c);
	float skin = smoothstep(0.13, 0.08, h.x) * smoothstep(0.015, 0.035, h.x) * smoothstep(0.12, 0.2, h.y) * smoothstep(0.72, 0.55, h.y) * smoothstep(0.3, 0.5, h.z);
	float grey = smoothstep(0.18, 0.08, h.y);
	float metal = grey * smoothstep(0.3, 0.45, h.z) * smoothstep(0.82, 0.68, h.z) * (1.0 - skin) * 0.7;   // mid greys only (white cloth is not metal)
	return vec4(skin, metal, 0.0, (1.0 - skin) * (1.0 - metal));
}

vec3 hd_derived_normal(vec2 uv) {
	if (use_normal_tex) return texture(normal_tex, uv).xyz;
	if (!use_tex) return vec3(0.5, 0.5, 1.0);
	vec2 ts = 1.5 / vec2(textureSize(albedo_tex, 0));
	float l = hd_lum(texture(albedo_tex, uv - vec2(ts.x, 0.0)).rgb);
	float r = hd_lum(texture(albedo_tex, uv + vec2(ts.x, 0.0)).rgb);
	float d = hd_lum(texture(albedo_tex, uv - vec2(0.0, ts.y)).rgb);
	float u = hd_lum(texture(albedo_tex, uv + vec2(0.0, ts.y)).rgb);
	vec3 n = normalize(vec3((l - r) * bump_strength, (d - u) * bump_strength, 1.0));
	return n * 0.5 + 0.5;
}
