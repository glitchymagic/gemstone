shader_type spatial;
// Remix lighting, the disc's translucent (src alpha / inverse src alpha) stage surfaces.
render_mode blend_mix, depth_draw_never;
#define ALPHA_OUT ALPHA = t.a
#include "res://shaders/remix_stage.gdshaderinc"
