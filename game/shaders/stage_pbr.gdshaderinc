// Remaster stage surfaces on the disc's own (4x) textures: per-material PBR from the texture's class
// (tools/hd_stage.py: stone, wood, metal, ground, cloth, foliage, painted), a normal map derived on the fly from the
// texture's luminance, parallax occlusion on stone/brick (height = the texture's own light/dark: mortar sits low),
// luminance-driven roughness + cavity occlusion, wind sway on the disc's own leaf cards. hd.gd sets the per-class numbers.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_tex = true;
uniform bool alpha_clip = false;
uniform float rough = 0.8;
uniform float rough_var = 0.3;    // dark texels (grime, mortar, gaps) rougher, light ones smoother
uniform float metal = 0.0;
uniform float spec = 0.5;
uniform float bump = 1.0;          // derived normal strength
uniform float cavity = 0.35;       // occlusion from dark texels (crevices)
uniform float pom_depth = 0.0;     // parallax depth (UV units x 100); 0 = off
uniform int pom_steps = 0;         // quality tier: 0 off, 8 High, 16 Ultra
uniform float sway = 0.0;          // wind sway amplitude (metres at 3 m above the floor)
uniform float floor_y = 0.0;        // the mesh's own lowest point (local units): sway grows with height above it
uniform float backlight = 0.0;     // light through thin leaves / cloth
uniform float sheen = 0.0;
uniform float glitter = 0.0;     // snow: sparse view-dependent sparkles
uniform float wet = 0.0;         // remix storm (pass 5): darker albedo, glossy, floors glossiest (SSR reflections)
uniform float glow = 0.0;        // remix night: lamp glass, lit windows and fire texels glow
uniform vec4 glow_tint : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float albedo_mul = 1.0;  // snow: real snow reflects ~80%, the disc paints it pure white

float st_lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float glow_mask(vec3 c) {   // same test as remix_stage.gdshaderinc: bright, warm AND saturated
	float mx = max(c.r, max(c.g, c.b));
	float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
	return smoothstep(0.5, 0.72, st_lum(c)) * smoothstep(0.38, 0.55, sat) * step(c.b + 0.08, c.r);
}

void vertex() {
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float k = clamp((VERTEX.y - floor_y) * length(MODEL_MATRIX[1].xyz) / 3.0, 0.0, 1.0);
		float t = TIME;
		vec3 off = vec3(sin(t * 1.3 + w.x * 0.9 + w.z * 0.4), 0.0, 0.7 * sin(t * 1.1 + w.z * 0.8 + w.x * 0.3));
		off += vec3(0.25 * sin(t * 4.7 + w.y * 3.0 + w.x * 2.0));
		VERTEX += inverse(mat3(MODEL_MATRIX)) * (off * sway * k * k);
	}
}

void fragment() {
	vec2 ts = vec2(textureSize(albedo_tex, 0));
	vec2 dx = dFdx(UV * ts), dy = dFdy(UV * ts);
	float lod = 0.5 * log2(max(dot(dx, dx), dot(dy, dy)));
	vec2 uv = UV;
	if (pom_steps > 0 && pom_depth > 0.0) {
		vec3 vd = normalize(normalize(-VERTEX) * mat3(TANGENT, -BINORMAL, NORMAL));
		float n = mix(float(pom_steps), float(pom_steps) * 0.5, abs(vd.z));
		float ld = 1.0 / n;
		vec2 delta = vd.xy * pom_depth * 0.01 / n;
		float hl = max(lod, 0.0) + 1.5;
		float depth = 1.0 - st_lum(textureLod(albedo_tex, uv, hl).rgb);
		float cur = 0.0;
		for (int i = 0; i < 32; i++) {
			if (cur >= depth || i >= pom_steps) break;
			uv -= delta;
			depth = 1.0 - st_lum(textureLod(albedo_tex, uv, hl).rgb);
			cur += ld;
		}
		vec2 prev = uv + delta;
		float after = depth - cur;
		float before = (1.0 - st_lum(textureLod(albedo_tex, prev, hl).rgb)) - cur + ld;
		uv = mix(uv, prev, after / (after - before + 1e-5));
	}
	vec4 c = albedo_color;
	if (use_tex) { c *= texture(albedo_tex, uv); }
	if (alpha_clip && c.a < 0.5) { discard; }
	float up = smoothstep(0.55, 0.92, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
	ALBEDO = c.rgb * albedo_mul * mix(1.0, 0.6, wet);
	float lb = st_lum(textureLod(albedo_tex, uv, max(lod, 0.0) + 2.5).rgb);
	float l = st_lum(c.rgb);
	// derived normal (Sobel on the texture's luminance, one notch blurrier than what's on screen: no shimmer)
	float nl = max(lod, 0.0) + 0.75;
	vec2 px = exp2(nl) / ts;
	float a = st_lum(textureLod(albedo_tex, uv - vec2(px.x, 0.0), nl).rgb);
	float b = st_lum(textureLod(albedo_tex, uv + vec2(px.x, 0.0), nl).rgb);
	float d = st_lum(textureLod(albedo_tex, uv - vec2(0.0, px.y), nl).rgb);
	float u = st_lum(textureLod(albedo_tex, uv + vec2(0.0, px.y), nl).rgb);
	NORMAL_MAP = normalize(vec3((a - b) * bump * 2.0, (u - d) * bump * 2.0, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = mix(clamp(rough + (lb - l) * rough_var * 2.0 + (0.45 - l) * rough_var * 0.5, 0.03, 1.0), mix(0.32, 0.06, up), wet);
	METALLIC = metal;
	float ao = mix(1.0, smoothstep(0.0, 0.8, l / max(lb, 0.04)), cavity);
	AO = ao;
	AO_LIGHT_AFFECT = 0.2;
	SPECULAR = mix(spec * ao, 0.65, wet);
	BACKLIGHT = c.rgb * backlight;
	RIM = sheen;
	RIM_TINT = 0.5;
	vec3 em = c.rgb * glow_tint.rgb * glow_mask(c.rgb) * glow * 4.0;
	if (glitter > 0.0) {
		vec2 cell = floor(uv * ts * 1.5);
		float h = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
		float tw = fract(h * 13.0 + dot(NORMAL, VIEW) * 6.0 + VIEW.x * 4.0);
		em += vec3(smoothstep(0.97, 1.0, tw) * step(0.9, h)) * glitter * 1.5 * clamp(1.0 - lod * 0.5, 0.0, 1.0);
	}
	EMISSION = em;
}
