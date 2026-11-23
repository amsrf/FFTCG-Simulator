shader_type spatial;
// The baked board (board_environment.gd): the approved lighting is in the texture, so this is unshaded — the texture
// times `brightness`, times the edge darkening (board_edge_shade.gdshaderinc).
render_mode unshaded, cull_disabled;

#include "res://shaders/board_edge_shade.gdshaderinc"

uniform sampler2D appearance : source_color, filter_linear, repeat_disable;
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
// A LITTLE MORE LIGHT ON THE WOOD'S ENDS (2026-11-22): the baked key light falls from ~140 at the floor's centre to
// ~105-120 at its ends. A full evening-out (0.25) was too much ("not all the board"); this only softens the falloff. The floor is the only surface at exactly the wood's height (Godot y 0.065;
// the curb, bank and ledge all stand higher, the river lower), so a lift that grows toward the ends is applied there
// and nowhere else: the scenery and the corners keep their light.
uniform float wood_y = 0.065;
uniform float wood_lift : hint_range(0.0, 1.0) = 0.10;
uniform float wood_lift_from = 1.6;     // |x| in metres where the lift starts...
uniform float wood_lift_to = 4.2;       // ...and where it is full (the floor's ends)
varying vec2 world_xz;
varying float world_y;

void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_xz = w.xz;
	world_y = w.y;
}

void fragment() {
	vec3 base = texture(appearance, UV).rgb * brightness;
	vec3 scenery = base * board_edge_shade(world_xz) * board_vignette(SCREEN_UV, VIEWPORT_SIZE);
	float on_wood = 1.0 - smoothstep(0.002, 0.004, abs(world_y - wood_y));
	// The wood keeps the scenery's shading and only gains the gentle lift toward its ends.
	vec3 wood = scenery * (1.0 + wood_lift * smoothstep(wood_lift_from, wood_lift_to, abs(world_xz.x)));
	ALBEDO = mix(scenery, wood, on_wood);
}
