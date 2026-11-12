shader_type spatial;
// One crystal shard of the destroy burst (card_destroy_burst.gd), in the broken card's element colour (COLOR.rgb).
// A long, sharp, irregular kite: its tips are the quad's top and bottom (UV.y), its side corners move per instance
// (INSTANCE_CUSTOM.x/.y), so no two shards share an outline. It is drawn as two FACETS split by a bright ridge;
// INSTANCE_CUSTOM.z is the tumble (1 = the left facet faces the light, 0 = the right one), so as the shard flips the
// lit facet swaps sides - that glint is what makes it read as crystal and not as paper. COLOR.a is its fade.
// Alpha-blended, with a dark rim and a white edge glint, so it reads over the pale board wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

varying vec4 shard_color;
varying vec3 shard_custom;

void vertex() {
	shard_color = COLOR;
	shard_custom = INSTANCE_CUSTOM.xyz;
}

// How far inside the kite's outline a point is, along x, at height y. Corners: top (0, 1), bottom (0, -1),
// and a side corner at (+-1, corner_y).
float side_edge(float y, float corner_y) {
	return y > corner_y ? (1.0 - y) / (1.0 - corner_y) : (y + 1.0) / (corner_y + 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float yl = shard_custom.x * 0.9 - 0.45;
	float yr = shard_custom.y * 0.9 - 0.45;
	float left = p.x < 0.0 ? 1.0 : 0.0;
	float edge = left > 0.5 ? side_edge(p.y, yl) + p.x : side_edge(p.y, yr) - p.x;
	float inside = smoothstep(0.0, 0.06, edge) * step(abs(p.y), 1.0);

	float tumble = shard_custom.z;
	float lit = mix(1.0 - tumble, tumble, left);
	vec3 deep = shard_color.rgb * 0.62;
	vec3 bright = mix(shard_color.rgb, vec3(1.0), 0.28);
	vec3 col = mix(deep, bright, lit);
	// A soft gradient along the shard: light pools toward one tip.
	col = mix(col, bright, smoothstep(0.2, 1.0, p.y) * 0.35);
	// The ridge between the facets, and a glint running along the lit edge.
	float ridge = exp(-pow(p.x / 0.06, 2.0));
	float glint = (1.0 - smoothstep(0.0, 0.10, edge)) * lit;
	col = mix(col, vec3(1.0), clamp(ridge * 0.55 + glint * 0.7, 0.0, 1.0));
	// A thin dark outline where the glint is not.
	col = mix(col * 0.55, col, smoothstep(0.0, 0.08, edge) + glint);
	ALBEDO = col;
	ALPHA = clamp(inside * shard_color.a * mix(0.82, 1.0, lit + ridge), 0.0, 1.0);
}
