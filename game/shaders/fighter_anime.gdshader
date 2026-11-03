shader_type spatial;
// Remaster look (the owner's pick: "next-gen anime", Guilty Gear Strive / DBFZ direction) on the disc's own models and
// textures. Lit only by the fighter rig (HD.light_rig: one key light from the camera side, two back rims) plus any fx
// light, never by the stage's ambient, so every fighter reads the same on every stage, like Strive's character lights.
// - Authored shadow ramps per material class (ramp_tex rows: cloth skin hair metal leather gem eyes), crisp 2-3 tone
//   bands with a warm terminator line; the class weights per texel come from tools/hd_classes.py (mask_m / mask_s).
// - The shadow threshold is pushed by the baked ambient occlusion of each rigid part (vertex COLOR.r) and by the disc
//   artists' own painted folds (mask_s.a), so creases fall into shadow first, as hand-authored anime shading does.
// - Face normals are bent toward a head-centred sphere at build time (tools/hd_mesh.py): clean anime face shadows.
// - Inner lines: the texture's own painted strokes, sharpened into ink (mask_s.b). Outer lines: ink.gdshader.
// - Hair gets a jagged angel-ring band, metal stylized env bands + a hard glint, gems a sparkle and their own glow.
render_mode cull_disabled, ambient_light_disabled;   // the disc draws fighter polygons double-sided
#include "res://shaders/hd_common.gdshaderinc"
uniform sampler2D ramp_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D mask_m : filter_linear_mipmap, repeat_enable;   // R skin G hair B metal A leather (A = 0.1 + 0.9 v)
uniform sampler2D mask_s : filter_linear_mipmap, repeat_enable;   // R gem G eyes B inner line A painted shade
uniform bool use_masks = false;
uniform float ao_push = 0.32;       // how far a fully occluded texel moves the shadow threshold
uniform float paint_push = 0.55;    // same, for the painted folds
uniform float line_strength = 0.75;
uniform vec4 key_tint : source_color = vec4(1.0);   // per stage (HD.stage_tint), multiplies the key light
uniform vec4 shadow_tint : source_color = vec4(1.0);
uniform float rim_width = 0.28;
uniform float gem_glow = 0.35;
varying vec4 k1;   // skin hair metal leather
varying vec3 k2;   // gem eyes cloth
varying float push;
varying vec3 base;

float dec(float a) { return clamp((a - 0.1) / 0.9, 0.0, 1.0); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec4 c = albedo;
	if (use_tex) { c *= texture(albedo_tex, UV); }
	if (alpha_clip && c.a < 0.5) { discard; }
	vec4 m = vec4(0.0), s = vec4(0.0, 0.0, 0.0, 0.5);
	if (use_masks) {
		m = texture(mask_m, UV); m.a = dec(m.a);
		s = texture(mask_s, UV); s.a = dec(s.a);
	} else {
		vec4 h = hd_classes(c.rgb, UV);   // no baked masks (Classic assets): guess skin / metal from the colour
		m = vec4(h.x, h.z, h.y, 0.0);
	}
	k1 = m;
	float cloth = clamp(1.0 - m.r - m.g - m.b - m.a - s.r - s.g, 0.0, 1.0);
	k2 = vec3(s.r, s.g, cloth);
	float ao = COLOR.r;
	push = (1.0 - ao) * ao_push + (0.5 - s.a) * paint_push;
	// inner ink: the painted strokes, crisped (anti-aliased by screen-space width)
	float lw = fwidth(s.b) * 1.5 + 0.02;
	float ink = smoothstep(0.42 - lw, 0.42 + lw, s.b) * line_strength;
	vec3 col = mix(c.rgb, c.rgb * c.rgb * 0.35, ink);
	ALBEDO = col;
	base = col;
	// hard surfaces get the texture's luminance as bump (screen-space surface gradient, no tangents needed)
	float hard = m.b + s.r;
	if (hard > 0.05 && use_tex) {
		float hgt = hd_lum(c.rgb) * bump_strength * 0.02 * hard;
		vec3 dpx = dFdx(VERTEX), dpy = dFdy(VERTEX);
		vec3 r1 = cross(dpy, NORMAL), r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		vec3 g = sign(det) * (dFdx(hgt) * r1 + dFdy(hgt) * r2);
		NORMAL = normalize(abs(det) * NORMAL - g);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float gem = s.r;
	EMISSION = flash.rgb * flash.a + glow.rgb * glow.a + col * gem * gem_glow;
}

vec3 ramp(float x, float row) { return texture(ramp_tex, vec2(clamp(x, 0.004, 0.996), (row + 0.5) / 7.0)).rgb; }

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lc = LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL && LIGHT.z > -0.05) {
		// the key: authored ramp per class, threshold pushed by AO + painted folds (+ any cast shadow)
		float x = ndl * 0.5 + 0.5 - push - (1.0 - ATTENUATION) * 0.5;
		vec3 r = ramp(x, 0.0) * k2.z + ramp(x, 1.0) * k1.r + ramp(x, 2.0) * k1.g + ramp(x, 3.0) * k1.b
			+ ramp(x, 4.0) * k1.a + ramp(x, 5.0) * k2.x + ramp(x, 6.0) * k2.y;
		float lit = smoothstep(0.47, 0.53, x);
		r = mix(r * shadow_tint.rgb, r, lit);
		DIFFUSE_LIGHT += r * lc * key_tint.rgb;
		vec3 h = normalize(LIGHT + VIEW);
		float nh = dot(NORMAL, h);
		// hair: angel ring (an annulus around the highlight on the sphere-bent hair normals), jagged like strands
		float jag = hash(floor(UV * vec2(90.0, 6.0))) * 0.035;
		float ring = smoothstep(0.80 + jag, 0.83 + jag, nh) * (1.0 - smoothstep(0.90 + jag, 0.93 + jag, nh));
		// metal: stylized environment bands from the view-space normal (sky band above, dark horizon, bright rim)
		float ny = NORMAL.y;
		float band = smoothstep(0.25, 0.32, ny) * (1.0 - smoothstep(0.62, 0.7, ny)) + smoothstep(-0.55, -0.62, ny) * 0.5;
		float glint = smoothstep(0.965, 0.975, nh);
		float sparkle = smoothstep(0.985, 0.99, nh) + smoothstep(0.93, 0.95, nh) * step(0.93, hash(floor(UV * 64.0)));
		float leather = smoothstep(0.92, 0.94, nh);
		vec3 spec = vec3(ring * 0.55 * lit) * k1.g
			+ (base * band * 1.1 + vec3(glint * 1.6)) * k1.b
			+ vec3(sparkle * 1.8 * lit) * k2.x
			+ vec3(leather * 0.35 * lit) * k1.a
			+ vec3(smoothstep(0.985, 0.99, nh) * 0.18 * lit) * k1.r;
		SPECULAR_LIGHT += spec * lc * key_tint.rgb * spec_strength * 2.6;
	} else if (LIGHT_IS_DIRECTIONAL) {
		// back rims: a crisp line along the silhouette on the side facing the rim light, per class
		float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float w = rim_width * (1.0 + 0.4 * k1.b + 0.3 * k2.x - 0.25 * k1.r);
		float rim = smoothstep(1.0 - w, 1.0 - w + 0.05, fr) * smoothstep(-0.15, 0.25, ndl);
		SPECULAR_LIGHT += rim * lc * rim_color.rgb * rim_strength * (base * 0.6 + 0.55);
	} else {
		// fx / stage point lights: a toon step
		float lit = smoothstep(0.0, 0.08, ndl) * ATTENUATION;
		DIFFUSE_LIGHT += lit * lc * 0.9;
	}
}
