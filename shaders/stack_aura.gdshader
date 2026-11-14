shader_type spatial;
// The TOP-OF-STACK aura and its RESOLVE PULSE (scripts/cards/card_stack_aura.gd), after ~/Desktop/Clips/stack_activate
// frames 24-50. A PlaneMesh in the card's own plane (child of HandMesh, so it tilts and grows with the card), larger
// than the card by `margin`. Two rectangles, both measured from the card's rounded outline:
//   1. THE AURA  - a soft, smoky white-lavender rim hugging the outline (`intensity`), breathing gently. Standing on
//                  the top card of the stack; it flares during the pulse.
//   2. THE WAVE  - a second rounded rectangle launched from the outline that GROWS outward and FADES with distance
//                  (`wave` 0..1 is its progress; < 0 means none).
// MIX, not additive: additive washes card art out to white.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec2 card_size = vec2(0.429, 0.6);
// How far the quad reaches past the card on each side (metres, card-local). Must exceed wave_reach + ring_width.
uniform float margin = 0.3;
uniform float corner_radius = 0.025;
uniform vec4 aura_color : source_color = vec4(0.93, 0.90, 1.0, 1.0);
// 1. The aura's strength (0..1) and its reach outside the card, metres.
uniform float intensity = 0.0;
uniform float glow_width = 0.032;
// How much the face itself brightens at full intensity.
uniform float face_lift = 0.10;
// 2. The wave: progress 0..1 (< 0 = off), how far it travels from the outline, and its thickness.
uniform float wave = -1.0;
uniform float wave_reach = 0.24;
uniform float ring_width = 0.022;

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

void fragment() {
	vec2 full = card_size + vec2(margin * 2.0);
	vec2 p = (UV - 0.5) * full;
	vec2 half_card = card_size * 0.5;
	vec2 q = abs(p) - (half_card - vec2(corner_radius));
	float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;   // < 0 inside the card
	float outside = max(dist, 0.0);
	float is_out = step(0.0, dist);

	// 1. THE AURA: brightest at the edge, gone within a few centimetres; smoke wobbles its reach and carves soft gaps.
	vec2 sp = p * 14.0;
	float smoke = noise2(sp + vec2(0.0, -TIME * 1.6)) * 0.6 + noise2(sp * 2.3 + vec2(TIME * 0.9, -TIME * 2.2)) * 0.4;
	float reach = glow_width * (0.8 + 0.4 * smoke);
	float breathe = 0.88 + 0.12 * sin(TIME * 2.4);
	float aura = exp(-pow(outside / max(reach, 0.001), 1.4)) * is_out * mix(0.6, 1.0, smoke) * intensity * breathe;

	// 2. THE WAVE: a rounded rectangle at distance wave * wave_reach from the outline, thinning and fading as it goes.
	float ring = 0.0;
	if (wave >= 0.0) {
		float at = wave * wave_reach;
		float thick = ring_width * mix(1.0, 0.45, wave);
		ring = exp(-pow((outside - at) / max(thick, 0.001), 2.0)) * is_out * pow(1.0 - wave, 1.6);
	}

	float face = (1.0 - is_out) * face_lift * intensity;
	// Neither rectangle may reach the quad's own edge, or the square would show.
	vec2 edge = abs(UV - 0.5) * 2.0;
	float keep = 1.0 - smoothstep(0.9, 1.0, max(edge.x, edge.y));
	ALBEDO = aura_color.rgb;
	ALPHA = clamp((aura * 0.85 + ring * 0.9) * keep + face, 0.0, 1.0);
}
