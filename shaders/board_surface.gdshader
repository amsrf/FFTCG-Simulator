shader_type spatial;
// The baked board (board_environment.gd): the approved lighting is in the texture, so this is unshaded — the texture
// times `brightness`, times the edge darkening (board_edge_shade.gdshaderinc).
render_mode unshaded, cull_disabled;

#include "res://shaders/board_edge_shade.gdshaderinc"

uniform sampler2D appearance : source_color, filter_linear, repeat_disable;
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	ALBEDO = texture(appearance, UV).rgb * brightness * board_edge_shade(world_xz);
}
