// THE BOARD'S EDGE DARKENING (board_environment.gd): full brightness over the play area, falling off toward the rim so
// the eye goes to the cards. Shared by the board (board_surface.gdshader) and the river (board_river.gdshader), which
// crosses the whole width and must darken exactly like the wood beside it. WORLD xz, so both seats agree.
uniform vec2 focus_centre = vec2(0.0, 0.29);   // the play area's centre (the river), metres (x, z)
uniform vec2 focus_half = vec2(1.9, 1.25);     // full-brightness rounded rect, half-extents
uniform float focus_corner = 0.9;
uniform float edge_falloff = 1.8;              // metres past the rect to reach full darkening
uniform float edge_darkness : hint_range(0.0, 1.0) = 0.5;

float board_edge_shade(vec2 world_xz) {
	vec2 q = abs(world_xz - focus_centre) - focus_half + vec2(focus_corner);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - focus_corner;
	return 1.0 - edge_darkness * smoothstep(0.0, max(edge_falloff, 1e-4), d);
}
