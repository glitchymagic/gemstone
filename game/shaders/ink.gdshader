shader_type spatial;
// Remaster ink line (next_pass of the anime look): inverted hull pushed out in VIEW space, so the line keeps a steady
// on-screen width at any zoom. Width varies like a drawn line: per part from the build (vertex COLOR.g: big parts
// thicker, the face thinner), thicker on the silhouette than where the surface faces the camera, tapered with
// distance. The hull follows TANGENT, which tools/hd_mesh.py fills with the normal averaged over coincident vertices,
// so the line stays closed across the disc's hard edges. The ink takes a dark shade of the texture under it (coloured
// lines, as in Strive) instead of flat black.
render_mode unshaded, cull_front, depth_draw_opaque, skip_vertex_transform;
uniform float width = 0.0026;
uniform vec4 color : source_color = vec4(0.07, 0.04, 0.08, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform bool smooth_hull = false;   // the HD mesh's TANGENT carries the welded normal
uniform bool alpha_clip = false;
uniform float tint = 0.32;          // how much of the texture colour the ink keeps

void vertex() {
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 hn = smooth_hull ? normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz) : vn;
	float facing = abs(vn.z);
	float wv = smooth_hull ? COLOR.g : 1.0;
	float w = width * wv * clamp(-vp.z, 0.6, 12.0) * mix(1.25, 0.5, facing);
	VERTEX = vp + hn * w;
	NORMAL = vn;
}

void fragment() {
	vec4 t = use_tex ? texture(albedo_tex, UV) : vec4(1.0);
	if (alpha_clip && t.a < 0.5) { discard; }
	ALBEDO = mix(color.rgb, color.rgb * 0.5 + t.rgb * t.rgb * 0.45, tint);
}
