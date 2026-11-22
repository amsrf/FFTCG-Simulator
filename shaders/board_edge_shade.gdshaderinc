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

// THE SCREEN VIGNETTE (2026-11-22, after Artifact's board): the corners of the VIEW fall off on top of the world-space
// edge darkening above, so the eye stays on the play area and the scenery at the screen edges sinks into shadow.
// Board and river only (both include this): cards, the hand and UI are not darkened. Elliptical in screen space,
// corrected for the aspect so it is round-cornered rather than stretched.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_start : hint_range(0.0, 1.5) = 0.85;   // distance from the centre where it begins (1 = edge)
uniform float vignette_end : hint_range(0.5, 2.0) = 1.35;     // where it reaches full strength (corners ~1.25)

float board_vignette(vec2 screen_uv, vec2 viewport_size) {
	vec2 d = (screen_uv - 0.5) * 2.0;
	d.x *= mix(1.0, viewport_size.x / max(viewport_size.y, 1.0), 0.35);
	float r = length(d);
	return 1.0 - vignette_strength * smoothstep(vignette_start, vignette_end, r);
}
