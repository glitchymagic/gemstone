shader_type spatial;
// Remaster look B, "stylized PBR" (Street Fighter 6 / Tekken 8 direction) on the disc's own models and textures.
// Per-texel material classes from tools/hd_tex.py (derived from each form's own texture colours, hd_classes.json):
// skin with subsurface scattering + soft spec, cloth sheen + weave, leather and metal speculars with clearcoat, hair
// anisotropy, gem glints + faux refraction, wet eyes. A normal map derived from the texture's painted folds and seams,
// per-part ray-traced AO baked into the subdivided mesh (COLOR.r), specular occlusion, procedural micro detail that
// fades out before it can shimmer. Godot's own GGX lighting; the fighter light rig (hd.gd) adds key + 2 rims.
render_mode cull_disabled;   // the disc draws fighter polygons double-sided (Ayame's cape shows its pattern from both sides)
#include "res://shaders/hd_common.gdshaderinc"
// tools/hd_tex.py maps (4th channel stored as 0.1 + 0.9 * value)
uniform sampler2D mask_m : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;   // R skin G hair B metal A leather
uniform sampler2D mask_s : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;   // R gem G eyes B seam line A painted shade
uniform bool use_maps = false;
uniform float normal_depth = 1.0;
uniform float sss = 0.6;
uniform float sheen = 0.35;
uniform float micro = 1.0;          // procedural micro detail (weave, grain, pores); 0 on Low
uniform float ao_strength = 1.0;
uniform float gem_glint = 1.0;


float hd_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float hd_vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hd_hash(i), hd_hash(i + vec2(1, 0)), u.x), mix(hd_hash(i + vec2(0, 1)), hd_hash(i + vec2(1, 1)), u.x), u.y);
}

// slope (d/du, d/dv) of a height pattern at p, faded to zero once one period gets under ~2 pixels (no shimmer)
vec2 hd_slope_noise(vec2 p, float amp) {
	float fade = clamp(1.6 - 2.0 * length(fwidth(p)), 0.0, 1.0);
	if (fade <= 0.0 || amp <= 0.0) return vec2(0.0);
	float e = 0.15;
	float h = hd_vnoise(p);
	return vec2(hd_vnoise(p + vec2(e, 0.0)) - h, hd_vnoise(p + vec2(0.0, e)) - h) / e * amp * fade;
}

vec2 hd_slope_weave(vec2 p, float amp) {
	float fade = clamp(1.6 - 2.0 * length(fwidth(p)), 0.0, 1.0);
	if (fade <= 0.0 || amp <= 0.0) return vec2(0.0);
	// plain weave: alternating over/under threads in u and v
	float cu = cos(p.x * 6.2832), cv = cos(p.y * 6.2832);
	float su = sin(p.x * 6.2832), sv = sin(p.y * 6.2832);
	float checker = sign(sin(floor(p.x) * 3.1416 + floor(p.y) * 3.1416 + 0.5) + 1e-3);
	return vec2(-su * (0.5 + 0.5 * cv * checker), -sv * (0.5 - 0.5 * cu * checker)) * amp * fade;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) { c *= texture(albedo_tex, UV); }
	if (alpha_clip && c.a < 0.5) { discard; }
	float skin = 0.0, hair = 0.0, metal = 0.0, leather = 0.0, gem = 0.0, eyes = 0.0, line = 0.0, shade = 0.5;
	if (use_maps) {
		vec4 m = texture(mask_m, UV);
		vec4 s = texture(mask_s, UV);
		skin = m.r; hair = m.g; metal = m.b; leather = clamp((m.a - 0.1) / 0.9, 0.0, 1.0);
		gem = s.r; eyes = s.g; line = s.b; shade = clamp((s.a - 0.1) / 0.9, 0.0, 1.0);
	} else {
		vec4 k = hd_classes(c.rgb, UV);
		skin = k.x; metal = k.y; hair = k.z; leather = 0.0;
	}
	float cloth = clamp(1.0 - skin - hair - metal - leather - gem - eyes, 0.0, 1.0);
	float l = hd_lum(c.rgb);

	// albedo: metal reads brighter as a metallic base colour; seams keep the disc's painted design
	vec3 alb = c.rgb;
	alb = mix(alb, pow(alb, vec3(0.85)) * 1.12, metal);
	alb = mix(alb, mix(vec3(l), alb, 1.18) * vec3(1.0, 0.97, 0.95), skin);   // skin: a little richer and warmer under PBR light
	ALBEDO = alb;

	// normal: derived map + procedural micro detail per class (texture-space frequency: one texel of the 4x map)
	vec2 ts = vec2(textureSize(albedo_tex, 0));
	vec3 nm = (use_normal_tex ? texture(normal_tex, UV).xyz : hd_derived_normal(UV)) * 2.0 - 1.0;
	vec2 d = vec2(0.0);
	d += hd_slope_weave(UV * ts * 0.5, 0.10 * cloth * micro);
	d += hd_slope_noise(UV * ts * 0.7, 0.09 * leather * micro);
	d += hd_slope_noise(UV * ts * 1.4, 0.035 * skin * micro);
	d += hd_slope_noise(vec2(UV.x * ts.x * 2.0, UV.y * ts.y * 0.15), 0.07 * hair * micro);   // strands
	nm.xy += d;
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.45, skin);

	// occlusion: baked per-part ray AO (vertex colour R) x the painted creases and seams
	float cav = mix(1.0, smoothstep(0.0, 0.5, shade), 0.5 * (cloth + leather)) * (1.0 - 0.45 * line);
	float ao = mix(1.0, COLOR.r, ao_strength) * cav;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;

	float rough = 0.84 * cloth + 0.5 * skin + 0.36 * hair + 0.26 * metal + 0.4 * leather + 0.05 * gem + 0.08 * eyes;
	rough += (0.5 - shade) * 0.2 * (cloth + leather);
	rough += (hd_vnoise(UV * ts * 0.12) - 0.5) * 0.12 * (metal + leather + skin);   // smudges, oil, wear
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = metal * 0.9;
	// specular occlusion: no reflections out of crevices
	SPECULAR = (0.35 * cloth + 0.36 * skin + 0.5 * hair + 0.5 * metal + 0.6 * leather + 1.0 * gem + 0.7 * eyes) * mix(1.0, ao, 0.85);
	SSS_STRENGTH = skin * sss;
	RIM = clamp(cloth * sheen + hair * 0.25, 0.0, 1.0);
	RIM_TINT = 0.55;
	ANISOTROPY = hair * 0.55;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	CLEARCOAT = leather * 0.55 + metal * 0.3 + gem * 0.8;
	CLEARCOAT_ROUGHNESS = 0.18;

	// gems: faux refraction (the texture seen through the facet, shifted by the view) + glints that twinkle as the
	// fighter turns; eyes: a touch of their own light so the sclera never goes grey in shadow
	vec3 em = vec3(0.0);
	if (gem > 0.01) {
		vec3 inner = texture(albedo_tex, UV + VIEW.xy * 0.03).rgb;
		vec2 cell = floor(UV * ts * 0.06);
		float tw = fract(hd_hash(cell) * 7.0 + dot(NORMAL, VIEW) * 4.0 + VIEW.x * 3.0);
		float glint = smoothstep(0.95, 1.0, tw) * step(0.85, hd_hash(cell + 3.1)) * smoothstep(0.4, 0.8, dot(NORMAL, VIEW));
		em += gem * (inner * inner * 0.6 + vec3(glint) * 2.5 * gem_glint);
	}
	em += eyes * c.rgb * 0.1;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	em += rim_color.rgb * rim * rim_strength * 0.25 * (0.4 + 0.6 * l) * ao;
	EMISSION = em + flash.rgb * flash.a + glow.rgb * glow.a;
}
