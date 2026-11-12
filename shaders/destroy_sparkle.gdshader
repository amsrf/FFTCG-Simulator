shader_type spatial;
// One twinkle of the destroy burst (card_destroy_burst.gd): a four-point star with a soft core, scattered among the
// confetti as the burst settles. Colour and fade per instance (COLOR); the script pulses the instance's scale.
// Alpha-blended, with a warm halo under a white star so it reads over the pale board wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

varying vec4 sparkle_color;

void vertex() {
	sparkle_color = COLOR;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 q = abs(p);
	// Two thin diamonds crossed: the long rays of the star.
	float rays = max(
		(1.0 - smoothstep(0.0, 0.10 * (1.0 - q.x), q.y)) * (1.0 - q.x),
		(1.0 - smoothstep(0.0, 0.10 * (1.0 - q.y), q.x)) * (1.0 - q.y));
	float r = length(p);
	float core = 1.0 - smoothstep(0.05, 0.22, r);
	float halo = pow(clamp(1.0 - r, 0.0, 1.0), 3.0) * 0.45;
	vec3 col = mix(sparkle_color.rgb, vec3(1.0), clamp(core + rays * 0.8, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp((rays + core + halo) * sparkle_color.a, 0.0, 1.0);
}
