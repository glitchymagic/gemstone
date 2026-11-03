shader_type spatial;
// Anime toon look: hard two-tone terminator, tinted shadow, toon spec, rim light.
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_tex = false;
uniform bool alpha_clip = false;
uniform vec4 shade_tint : source_color = vec4(0.62, 0.55, 0.78, 1.0);
uniform float rim_strength = 0.55;
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float spec_size = 0.93;
uniform float spec_strength = 0.35;
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	vec4 c = albedo;
	if (use_tex) { c *= texture(albedo_tex, UV); }
	ALBEDO = c.rgb;
	if (alpha_clip && c.a < 0.5) { discard; }
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = rim_color.rgb * rim * rim_strength + flash.rgb * flash.a + glow.rgb * glow.a;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, ndl) * smoothstep(0.35, 0.45, ATTENUATION);
	vec3 band = mix(shade_tint.rgb * 0.45, vec3(1.0), lit);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float s = smoothstep(spec_size, spec_size + 0.02, dot(NORMAL, h)) * lit;
	SPECULAR_LIGHT += s * spec_strength * LIGHT_COLOR / PI;
}
