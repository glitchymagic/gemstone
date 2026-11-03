shader_type spatial;
// Remix lighting, the disc's additive stage surfaces (light shafts, glows).
render_mode blend_add, depth_draw_never, cull_disabled;
#define ALPHA_OUT ALPHA = t.a
#include "res://shaders/remix_stage.gdshaderinc"
