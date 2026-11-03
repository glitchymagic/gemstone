// Remix lighting on a stage's own disc textures (night / sunset / storm), shared by the three blend variants:
// the texels that look like light (bright + warm: windows, lanterns, fires, lamp glass) glow at night, and rain wets
// every surface (darker albedo, glossy, floors glossiest, so SSR picks up reflections).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_tex = true;
uniform bool use_vcol = false;
uniform bool alpha_clip = false;
uniform float roughness = 0.85;
uniform float specular = 0.25;
uniform float wet = 0.0;          // 0..1
uniform float glow = 0.0;         // 0..1 night window/lamp glow
uniform vec4 glow_tint : source_color = vec4(1.0, 0.85, 0.6, 1.0);

float glow_mask(vec3 c) {   // bright, warm AND saturated: lamp glass, lit windows, fire (cream stone and rugs aren't)
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float mx = max(c.r, max(c.g, c.b));
	float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
	return smoothstep(0.5, 0.72, lum) * smoothstep(0.38, 0.55, sat) * step(c.b + 0.08, c.r);
}

void fragment() {
	vec4 t = albedo_color;
	if (use_tex) { t *= texture(albedo_tex, UV); }
	if (use_vcol) { t *= COLOR; }
	if (alpha_clip && t.a < 0.5) { discard; }
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float up = smoothstep(0.55, 0.92, wn.y);
	ALBEDO = t.rgb * mix(1.0, 0.6, wet);
	ROUGHNESS = mix(roughness, mix(0.32, 0.06, up), wet);
	SPECULAR = mix(specular, 0.65, wet);
	EMISSION = t.rgb * glow_tint.rgb * glow_mask(t.rgb) * glow * 4.0;
	ALPHA_OUT;
}
