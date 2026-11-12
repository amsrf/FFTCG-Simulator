shader_type spatial;
// One swirl of the destroy burst (card_destroy_burst.gd). A camera-facing quad that is two things over its life:
//   CURLS  (`curl`)   three wispy white strokes spiralling outward around the centre, turning with `spin`;
//   BUBBLE (`bubble`) the curls opening into a large translucent shell: a faint fill, a bright rim and a highlight.
// The script crossfades `curl` into `bubble` and fades `intensity`, so the wind gust visibly becomes the bubble.
// Alpha-blended, with a pale-cyan body under a white core, so white still reads over the pale board wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float curl = 1.0;
uniform float bubble = 0.0;
uniform float spin = 0.0;
uniform float seed = 0.0;


float hash(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);

	// CURLS: each stroke is a piece of an outward spiral. `s` runs 0..1 along the stroke; its radius grows with s,
	// and it tapers to nothing at both ends, which is what makes it read as a gust and not as a ring.
	float strokes = 0.0;
	float cores = 0.0;
	for (int j = 0; j < 3; j++) {
		float fj = float(j);
		float offset = hash(seed + fj * 3.1) * TAU;
		float span = 0.55 + 0.25 * hash(seed + fj * 5.7);
		float s = fract((a + spin * (1.0 + 0.3 * fj) + offset) / TAU);
		float ring_r = (0.30 + 0.20 * fj) * (0.70 + 0.55 * s);
		float wisp = 0.65 + 0.35 * noise1(s * 18.0 + seed + fj * 11.0);
		float width = (0.035 + 0.035 * s) * wisp;
		float d = (r - ring_r) / width;
		float taper = smoothstep(0.0, 0.12, s) * (1.0 - smoothstep(span * 0.55, span, s));
		strokes += exp(-d * d) * taper * wisp;
		cores += exp(-d * d * 6.0) * taper;
	}

	// BUBBLE: a soft fill, a rim brightening toward the edge, and a crescent highlight at the upper left.
	float shell = pow(smoothstep(0.70, 0.96, r), 2.0) * (1.0 - smoothstep(0.96, 1.0, r));
	float fill = (1.0 - smoothstep(0.90, 1.0, r)) * 0.05;
	vec2 hl = p - vec2(-0.38, 0.40);
	float highlight = exp(-dot(hl, hl) * 14.0) * 0.40 * step(r, 1.0);
	float swirl_in_shell = exp(-pow((r - 0.78 - 0.08 * sin(a * 3.0 + spin * 2.0)) / 0.05, 2.0))
		* (0.4 + 0.6 * noise1(a * 2.0 + seed)) * 0.65;

	float curl_alpha = clamp(strokes, 0.0, 1.0) * curl;
	float bubble_alpha = clamp(shell * 0.62 + fill + highlight + swirl_in_shell, 0.0, 1.0) * bubble;
	float core = clamp(cores * curl + (highlight + shell * 0.7 + swirl_in_shell) * bubble, 0.0, 1.0);
	ALBEDO = mix(tint_color.rgb, core_color.rgb, core);
	ALPHA = clamp(max(curl_alpha, bubble_alpha) * intensity, 0.0, 1.0) * (1.0 - smoothstep(0.97, 1.0, r));
}
