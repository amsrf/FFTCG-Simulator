shader_type spatial;
// The gold rim around the local player's wood slab while a held card would be played by a release
// (scripts/game/field_drop_zone.gd). A flat quad over the slab top: the light is a band centred on the slab's
// edge, spilling a little inward over the wood and further outward over the river/stone. Additive, so it can only
// brighten what is under it; the Compatibility renderer has no bloom, so this quad IS the glow.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec2 rect_half = vec2(4.01, 0.96);   // slab half-extents, metres (x, z)
uniform vec2 quad_half = vec2(4.31, 1.26);   // this quad's half-extents, metres
uniform float corner_radius = 0.06;
uniform float inner_width = 0.22;            // spill over the wood
uniform float outer_width = 0.16;            // spill past the edge
uniform float line_width = 0.025;            // the bright core on the edge itself
uniform vec4 glow_color : source_color = vec4(1.0, 0.74, 0.28, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.70, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * quad_half;
	float d = sd_round_box(p, rect_half, corner_radius);
	// Inside (d < 0) and outside (d > 0) fall off at their own rates.
	float w = d < 0.0 ? max(inner_width, 1e-4) : max(outer_width, 1e-4);
	float spill = exp(-abs(d) / w * 2.6);
	float core = 1.0 - smoothstep(0.0, max(line_width, 1e-4), abs(d));
	float pulse = 0.82 + 0.18 * sin(TIME * 4.2);
	vec3 col = glow_color.rgb * spill * 0.75 * pulse + core_color.rgb * core * 0.9;
	ALBEDO = col * intensity;
}
