shader_type spatial;
// SUMMONING SICKNESS: soft dark circular pulses rippling OUTWARD from the card's centre
// (scripts/cards/sickness_overlay.gd; reference Clips/sick, an Arena creature with summoning sickness).
// Translucent smoky rings, born at the centre, growing out past the edges (the card's outline clips them); a new one
// starts before the last has gone, so one or two are in flight. They tint the art without hiding it.
// A card-aligned PlaneMesh in the card's own plane (like the frozen overlay), so UV maps the card face: `card_size`
// gives the aspect, so the rings are true circles on the card, not ovals.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec2 card_size = vec2(0.429, 0.6);
uniform vec4 wave_color : source_color = vec4(0.03, 0.01, 0.06, 1.0);
// Peak darkness of a wave (0..1). The fades write this through `intensity`.
uniform float strength = 0.34;
uniform float intensity = 1.0;
// Seconds for one ring to travel from the centre to the corners.
uniform float travel_seconds = 2.4;
// Rings in flight across that distance.
uniform float waves = 1.6;
uniform float time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 + 9.1) * 0.1;
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	vec2 q = (UV - 0.5) * card_size;
	// Distance from the centre, 0 there and 1 at the card's corners: true circles (q is in metres, not UV).
	float radial = length(q) / length(half_size);

	// Smoke: the wave front wobbles and its body is broken up, drifting slowly.
	vec2 sp = q / half_size.x;
	float wobble = (fbm(sp * 2.2 + vec2(time * 0.07, -time * 0.05)) - 0.5) * 0.16;
	float body = mix(0.55, 1.0, fbm(sp * 3.4 - vec2(time * 0.11, time * 0.04)));

	// Rings travelling OUTWARD: a crest sits where phase is a whole number, r = (m + time * k) / waves, which GROWS
	// with time, so each crest moves away from the centre.
	float phase = (radial + wobble) * waves - time * (waves / max(travel_seconds, 0.01));
	float crest = 0.5 + 0.5 * cos(6.28318 * phase);
	float band = pow(crest, 2.2);

	// Each ring swells out of the centre and thins away toward the corners.
	float envelope = smoothstep(0.0, 0.15, radial) * (1.0 - smoothstep(0.65, 1.0, radial));

	float a = band * envelope * body * strength * intensity;
	ALBEDO = wave_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
