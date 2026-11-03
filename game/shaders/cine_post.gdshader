shader_type spatial;
// Cinematics post pass (a full-screen quad on the fight camera, drawn first among the transparent objects so sparks
// and shockwaves stay in colour): the world drains to cold grey around a fighter who keeps his colour (Power Change),
// a recolour wave runs out from him when time snaps back, impact frames (inverted, high contrast) and white flashes.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float desat = 0.0;                      // 0..1 world desaturation
uniform float desat_all = 0.0;                  // 0..1 desaturation that ignores the hero (replay look)
uniform vec3 hero_pos = vec3(0.0, -100.0, 0.0); // world, chest height
uniform vec2 hero_r = vec2(0.85, 1.25);         // keep-colour ellipsoid around the hero (xz, y) in metres
uniform float wave_r = 0.0;                     // recolour wave radius in metres (0 = none)
uniform vec4 wave_col : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float impact = 0.0;                     // 1 = full impact frame
uniform float flash = 0.0;                      // 1 = white
uniform int dbg = 0;                            // 1 = show reconstructed world xz (debug)

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	vec3 w = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;
	vec3 q = (w - hero_pos) / vec3(hero_r.x, hero_r.y, hero_r.x);
	float keep = 1.0 - smoothstep(0.8, 1.0, length(q));
	float dist = length(w.xz - hero_pos.xz);
	float inwave = wave_r > 0.01 ? 1.0 - smoothstep(wave_r - 0.8, wave_r, dist) : 0.0;
	float edge = wave_r > 0.01 ? exp(-pow((dist - wave_r) / 0.45, 2.0)) : 0.0;
	float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 grey = vec3(g) * vec3(0.82, 0.88, 1.0) * 0.8;
	float amt = max(desat * (1.0 - keep) * (1.0 - inwave), desat_all);
	vec3 o = mix(c, grey, amt);
	o += wave_col.rgb * edge * wave_col.a * desat * 2.5;
	// impact frame / flash (2026-10-23 audit): the old ink-black / paper-white inversion and the mix toward white turned
	// whole frames white; a mix toward white happens in linear light, so even 10% lifted the blacks to mid grey after
	// gamma. Now the impact is a short contrast punch and the flash a brighten: blacks stay black.
	float ip = clamp(impact, 0.0, 1.0);
	o = mix(o, o * o * 1.8, ip * 0.35);
	o *= 1.0 + clamp(flash, 0.0, 1.0) * 0.45;
	if (dbg == 1) { o = vec3(fract(w.x), fract(w.y), fract(w.z)); }
	if (dbg == 2) { o = vec3(clamp(dist / 20.0, 0.0, 1.0), keep, inwave); }
	ALBEDO = o;
}
