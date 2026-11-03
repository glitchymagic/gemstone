shader_type sky;
// Remaster sky: zenith -> horizon gradient in the stage's colours (the game's own background plane when known),
// soft procedural clouds lit from the sun side, sun disc + glow. Static (no TIME), so the radiance map stays cached.
uniform vec4 top_color : source_color = vec4(0.3, 0.5, 0.85, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.8, 0.84, 0.9, 1.0);
uniform vec4 ground_color : source_color = vec4(0.22, 0.22, 0.24, 1.0);
uniform float cloud_cover = 0.45;
uniform vec4 cloud_color : source_color = vec4(1.0, 0.98, 0.96, 1.0);
uniform float sun_disc = 1.0;

float sk_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float sk_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(sk_hash(i), sk_hash(i + vec2(1, 0)), u.x), mix(sk_hash(i + vec2(0, 1)), sk_hash(i + vec2(1, 1)), u.x), u.y);
}
float sk_fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * sk_noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color.rgb, top_color.rgb, smoothstep(0.0, 0.55, h));
	col = mix(col, ground_color.rgb, smoothstep(0.0, -0.1, h));
	vec3 sd = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float sunf = max(dot(d, sd), 0.0);
	if (h > 0.0) {
		vec2 p = d.xz / (h + 0.15) * 1.6;
		float n = sk_fbm(p);
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, n) * smoothstep(0.0, 0.15, h);
		float lit = sk_fbm(p + sd.xz * 0.15);
		vec3 cc = cloud_color.rgb * mix(0.72, 1.08, clamp((n - lit) * 4.0 + 0.5, 0.0, 1.0));
		cc += (LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0)) * pow(sunf, 12.0) * 0.35;
		col = mix(col, cc * mix(horizon_color.rgb, vec3(1.0), 0.6), c);
	}
	if (LIGHT0_ENABLED) {
		col += LIGHT0_COLOR * (smoothstep(0.99965, 0.9999, sunf) * 18.0 + pow(sunf, 220.0) * 0.8 + pow(sunf, 8.0) * 0.08) * sun_disc;
	}
	COLOR = col;
}
