shader_type spatial;
// Remaster water on the disc's own water texture: the texture drifts in two layers, ripples from two scrolling
// copies of its own luminance as normals, screen-space refraction of what's under it, depth tint, Fresnel
// reflection (the stage's reflection probe + sky), foam where it meets geometry.
render_mode blend_mix, cull_disabled, depth_draw_always;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 flow = vec2(0.03, 0.02);
uniform float ripple = 1.2;
uniform float refract = 0.04;
uniform vec4 deep : source_color = vec4(0.02, 0.18, 0.22, 1.0);
uniform float paint = 0.75;

float w_lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec2 w_slope(vec2 uv, float lod) {
	vec2 px = 2.0 / vec2(textureSize(albedo_tex, 0));
	float a = w_lum(textureLod(albedo_tex, uv - vec2(px.x, 0.0), lod).rgb);
	float b = w_lum(textureLod(albedo_tex, uv + vec2(px.x, 0.0), lod).rgb);
	float d = w_lum(textureLod(albedo_tex, uv - vec2(0.0, px.y), lod).rgb);
	float u = w_lum(textureLod(albedo_tex, uv + vec2(0.0, px.y), lod).rgb);
	return vec2(a - b, u - d);
}

void fragment() {
	vec2 uv1 = UV + TIME * flow;
	vec2 uv2 = UV * 1.37 - TIME * flow.yx * 0.8 + 0.31;
	vec3 tex = mix(texture(albedo_tex, uv1).rgb, texture(albedo_tex, uv2).rgb, 0.5) * albedo_color.rgb;
	vec2 s = (w_slope(uv1, 1.0) + w_slope(uv2, 1.5)) * ripple;
	NORMAL_MAP = normalize(vec3(s, 1.0)) * 0.5 + 0.5;
	// how much water lies between the surface and what's behind it
	float zs = texture(depth_tex, SCREEN_UV).r;
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zs, 1.0);
	float thick = clamp(-wp.z / wp.w + VERTEX.z, 0.0, 10.0);
	vec2 ruv = clamp(SCREEN_UV + s * refract * clamp(thick, 0.0, 1.0), vec2(0.0), vec2(1.0));
	vec3 under = textureLod(screen_tex, ruv, 0.0).rgb;
	float absorb = 1.0 - exp(-thick * 1.6);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	// the disc's own painted water (Londo's fountain: a painted sky reflection) stays the main colour; the refraction
	// of what's under the surface shows through it, deeper water turns to the deep tint
	vec3 body = mix(under * vec3(0.45, 0.7, 0.95), tex, paint);
	body = mix(body, deep.rgb + tex * 0.4, absorb * 0.7);
	float foam = smoothstep(0.12, 0.0, thick) * 0.6;
	ALBEDO = vec3(0.0);
	EMISSION = mix(body, vec3(0.9), foam) * (1.0 - fres * 0.6);
	ROUGHNESS = 0.03 + foam * 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = 1.0;   // the refraction already shows what's under the surface
}
