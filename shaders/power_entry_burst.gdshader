shader_type spatial;
// THE POWER ENTRY BURST (power_entry_burst.gd; ~/Desktop/Clips/entry 45-62), on a camera-facing quad centred on the
// card that just landed: a soft glowing RING (and a fainter one inside it) with a translucent haze filling it, and
// white SPEED LINES radiating out through it, re-dealt every frame (`seed`) like the reference's drawn impact lines.
// Coloured by the card's element (`tint`), cored in white. Alpha-blended: additive washes out over the pale wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float ring_radius = 0.45;
uniform float ring_width = 0.06;
uniform float inner_radius = 0.3;
uniform float ring_alpha = 1.0;
uniform float haze_alpha = 0.35;
uniform float streak_inner = 0.25;
uniform float streak_outer = 0.9;
uniform float streak_alpha = 1.0;
uniform float seed = 0.0;

float hash(float x) {
	return fract(sin(x * 91.3458 + seed * 13.17) * 47453.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = atan(p.y, p.x) / 6.28318 + 0.5;
	// Rings: a bright band, a softer one inside, and the haze between the card and the ring.
	float band = exp(-pow((d - ring_radius) / max(ring_width, 0.002), 2.0));
	float inner = exp(-pow((d - inner_radius) / max(ring_width * 0.8, 0.002), 2.0)) * 0.55;
	float haze = smoothstep(ring_radius + ring_width, ring_radius - ring_width * 2.0, d) * haze_alpha;
	// Speed lines: 64 angular cells, about two thirds of them carry a thin wedge that starts and ends at its own radius
	// and narrows outward.
	float cells = 64.0;
	float cell = floor(a * cells);
	float within = fract(a * cells) - 0.5;
	float present = step(0.34, hash(cell));
	float r0 = streak_inner * mix(0.75, 1.15, hash(cell + 3.1));
	float r1 = streak_outer * mix(0.65, 1.05, hash(cell + 7.7));
	float along = clamp((d - r0) / max(r1 - r0, 0.001), 0.0, 1.0);
	float half_width = mix(0.36, 0.05, along) * mix(0.6, 1.0, hash(cell + 11.3));
	float wedge = (1.0 - smoothstep(half_width * 0.6, half_width, abs(within)))
		* step(r0, d) * step(d, r1) * smoothstep(0.0, 0.15, along) * present;
	vec3 glow = mix(tint.rgb, vec3(1.0), 0.35);
	vec3 col = mix(glow, vec3(1.0, 0.98, 0.92), clamp(band * 0.6 + wedge, 0.0, 1.0));
	float alpha = max(max(band, inner) * ring_alpha + haze * ring_alpha, wedge * streak_alpha * 0.95);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0) * (1.0 - smoothstep(0.96, 1.0, d));
}
