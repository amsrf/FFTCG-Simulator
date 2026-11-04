shader_type spatial;
// The card-plane half of the lightning hit: a white-hot core, a travelling
// shock ring and a handful of radial forks.
//
// This is a horizontal PlaneMesh laid on the card, so the ring reads as light
// spreading across the playmat. Artifact's per-card damage composite uses a
// blue-white flare plus a dark edge vignette; this keeps the flare and the
// forked sparks, but draws them procedurally and leaves the card readable.

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.34, 0.06, 0.88, 1.0);
uniform vec4 arc_color : source_color = vec4(0.30, 0.04, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.93, 0.87, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 2.15;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float ring_radius : hint_range(0.0, 1.5) = 0.10;
uniform float ring_width : hint_range(0.005, 0.30) = 0.050;
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);

	// The ring is not a perfect circle: warp its radius with angle noise.
	float angle = atan(p.y, p.x);
	float warp = (noise1(angle * 7.0 + seed * 9.0) - 0.5) * 0.018
		+ (noise1(angle * 17.0 + TIME * 7.0 + seed * 4.0) - 0.5) * 0.004;
	float ring_d = abs(r - ring_radius - warp);
	float ring = exp(-pow(ring_d / max(ring_width, 0.001), 2.0));
	float hot_ring = exp(-pow(ring_d / max(ring_width * 0.34, 0.001), 2.0));
	float shock = exp(-pow((r - ring_radius * 0.62) / 0.10, 2.0)) * 0.24;

	// Broad flash on the card itself, hottest for the first few frames.
	float core = exp(-pow(r / 0.14, 2.0)) * flash;
	float hotspot = exp(-pow(r / 0.052, 2.0)) * flash;
	float glow = exp(-r * 2.4) * 0.26;

	// Radial forks. Each sector gets its own length and angular jitter, and the
	// line is thinned by distance from the sector centre.
	float forks = 0.0;
	float sectors = 9.0;
	float sector_angle = (angle + 3.14159265) / 6.2831853 * sectors;
	float sector = floor(sector_angle);
	float angular = abs(fract(sector_angle) - 0.5) * 6.2831853 / sectors;
	float fork_len = 0.28 + 0.42 * hash11(sector + seed * 5.7);
	float fork_width = 0.006 + 0.010 * hash11(sector * 2.3 + seed * 11.0);
	float fork_line = 1.0 - smoothstep(fork_width, fork_width + 0.010, angular * max(r, 0.001));
	float fork_range = smoothstep(0.10, 0.20, r) * (1.0 - smoothstep(fork_len - 0.03, fork_len, r));
	float flicker = 0.55 + 0.45 * hash11(sector * 7.1 + floor(TIME * 34.0) + seed * 3.0);
	forks = fork_line * fork_range * flicker * (0.7 + 0.5 * hash11(sector * 3.7 + seed));

	// Hot micro-crackles around the impact point, so the first frames do not
	// look like a clean vector ring.
	float crackle = pow(noise1(angle * 13.0 + r * 20.0 + TIME * 21.0 + seed * 7.0), 6.0)
		* exp(-r * 4.0);

	// The quad is square, so fade everything radially before its edge. Without
	// this the expanding ring hits the plane boundary and reads as an invisible
	// square rather than a circular wave dissipating into the board.
	float edge_fade = 1.0 - smoothstep(0.80, 0.98, r);
	float mask = clamp((ring * 0.95 + hot_ring * 0.45 + shock * 0.32 + core * 0.95
		+ hotspot * 0.95 + glow * 0.72 + forks * 0.55 + crackle * 0.45) * fade * edge_fade, 0.0, 1.0);
	vec3 colour = core_color.rgb * (core * 1.45 + hotspot * 1.35 + hot_ring * 0.30)
		+ arc_color.rgb * (ring * 1.18 + hot_ring * 1.05 + shock * 0.62 + forks * 1.05 + crackle * 1.35)
		+ tint.rgb * (glow * 0.86 + shock * 0.30);
	ALBEDO = colour * intensity;
	ALPHA = mask;
}
