shader_type spatial;
// Inverted-hull ink outline (next_pass of the toon material).
render_mode unshaded, cull_front, depth_draw_opaque;
uniform float thickness = 0.018;
uniform vec4 color : source_color = vec4(0.06, 0.04, 0.09, 1.0);
void vertex() {
	VERTEX += NORMAL * thickness;
}
void fragment() {
	ALBEDO = color.rgb;
}
