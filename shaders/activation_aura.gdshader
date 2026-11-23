shader_type spatial;
// THE CHARGING AURA of a field card whose ability is being paid for (scripts/cards/card_activation_fx.gd). A PlaneMesh
// in the card's own plane (child of HandMesh), larger than the card by `margin`. Meant to be EVIDENT from across the
// board, so it is dense and coloured rather than a pale smoke:
//   * a hot, nearly white CORE hugging the outline,
//   * a thick saturated BAND in the card's element colours (`color_a` / `color_b`, two hues that drift along the edge),
//   * licking TONGUES of flame-like noise flowing round the card and rising off it,
//   * a soft wide HAZE so the colour reads on the dark wood,
//   * and the flash's WAVE (`wave` 0..1, < 0 = none), a ring leaving the outline.
// Drawn only OUTSIDE the card (blend_mix there, opaque enough to be seen), so the art is never washed out.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec2 card_size = vec2(0.429, 0.6);
uniform float margin = 0.3;
uniform float corner_radius = 0.025;
uniform vec4 color_a : source_color = vec4(1.0, 0.38, 0.18, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform float intensity = 0.0;
// How far the dense band and the haze reach past the outline (card-local metres).
uniform float band_width = 0.055;
uniform float haze_width = 0.16;
uniform float wave = -1.0;
uniform float wave_reach = 0.24;
uniform float ring_width = 0.026;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.1 + 3.7) * 0.30 + noise2(p * 4.3 + 9.1) * 0.15;
}

void fragment() {
	vec2 full = card_size + vec2(margin * 2.0);
	vec2 p = (UV - 0.5) * full;
	vec2 half_card = card_size * 0.5;
	vec2 q = abs(p) - (half_card - vec2(corner_radius));
	float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;   // < 0 inside the card
	float outside = max(dist, 0.0);
	float is_out = smoothstep(-0.002, 0.002, dist);

	// The noise lives in card space and DRIFTS (toward the card's top, like rising flame, plus a slow cross drift). A
	// plain drift, never a per-pixel direction times TIME: that shears the noise more every second until it sparkles.
	float tongues = fbm(p * 17.0 + vec2(TIME * 0.35, -TIME * 1.6)) * 0.7 + fbm(p * 8.0 + vec2(-TIME * 0.6, -TIME * 0.9)) * 0.3;
	float flicker = fbm(p * 6.0 + vec2(-TIME * 1.1, TIME * 1.4));
	// Round the card, 0..1; only used through a whole number of cycles (continuous across its wrap).
	float around = atan(p.y, p.x) / 6.2831853 + 0.5;

	// The band's reach licks in and out with the tongues; the core stays tight on the outline.
	float reach = band_width * (0.65 + 0.9 * tongues);
	float band = exp(-pow(outside / max(reach, 0.001), 1.6));
	float core = exp(-pow(outside / 0.010, 1.4));
	float haze = exp(-outside / haze_width) * 0.45;
	float breathe = 0.85 + 0.15 * sin(TIME * 3.1);

	// Two hues drifting along the edge, brightened toward a white-hot core.
	float hue_mix = 0.5 + 0.5 * sin(around * 18.849 + TIME * 1.4 + flicker * 3.0);
	vec3 colour = mix(color_a.rgb, color_b.rgb, hue_mix);
	colour = mix(colour, vec3(1.0, 0.98, 0.92), core * 0.75);
	colour *= 1.0 + 0.35 * tongues;

	float density = (band * (0.75 + 0.25 * flicker) + core + haze) * breathe;

	float ring = 0.0;
	if (wave >= 0.0) {
		float at = wave * wave_reach;
		float thick = ring_width * mix(1.0, 0.45, wave);
		ring = exp(-pow((outside - at) / max(thick, 0.001), 2.0)) * pow(1.0 - wave, 1.4);
		colour = mix(colour, vec3(1.0), ring * 0.6);
	}

	// Nothing may reach the quad's own edge, or the square would show.
	vec2 edge = abs(UV - 0.5) * 2.0;
	float keep = 1.0 - smoothstep(0.88, 1.0, max(edge.x, edge.y));
	ALBEDO = colour;
	ALPHA = clamp((density * intensity + ring) * is_out * keep, 0.0, 1.0);
}
