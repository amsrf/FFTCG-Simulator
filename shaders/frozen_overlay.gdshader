shader_type spatial;

// Frostbite-style frozen card overlay.
//
// This is a card-space effect, not world geometry: a single quad sits just
// above the card face and composites two original alpha masks additively.
// The centre of both masks is transparent so the card illustration stays
// readable underneath.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D frost_cracks : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D frost_outline : source_color, filter_linear_mipmap, repeat_disable;

// Artifact's persistent Frostbite overlay uses roughly RGB(119, 157, 196).
uniform vec4 crack_tint : source_color = vec4(0.55, 0.72, 0.92, 1.0);
uniform vec4 outline_tint : source_color = vec4(0.78, 0.90, 1.0, 1.0);

uniform float intensity : hint_range(0.0, 4.0) = 0.95;
uniform float crack_strength : hint_range(0.0, 5.0) = 1.00;
uniform float outline_strength : hint_range(0.0, 2.0) = 0.25;
// A very faint whole-card cold veil. Keep this low: the identity of the
// effect is the cracked rim, not a blue rectangle over the artwork.
uniform float surface_veil : hint_range(0.0, 0.25) = 0.015;
uniform float pulse_amount : hint_range(0.0, 0.3) = 0.045;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.8;
// Driven by Card._tween_frozen_spread(): 0 = no frost, 1 = final mask.
uniform float spread : hint_range(0.0, 1.0) = 1.0;
// How much to clear the name strip and rules box in their central columns,
// while leaving the side bands and corners frosted.
uniform float readability_clear : hint_range(0.0, 1.0) = 0.75;

// One frozen starting point. Each seed has its own delay and tempo, so the
// fronts arrive at different times instead of sweeping the card as one clean
// wave. progress is the global 0..1 spread.
float freeze_front(vec2 uv, vec2 seed, float delay, float rate, float progress) {
	float local = clamp((progress - delay) / max(1.0 - delay, 0.001), 0.0, 1.0);
	// Match the physical card aspect: width is 0.715 of height.
	float d = length(vec2((uv.x - seed.x) * 0.715, uv.y - seed.y));
	float wave = local * 1.95 * rate - d - 0.01;
	return smoothstep(0.0, 0.08, wave);
}

void fragment() {
	vec4 cracks = texture(frost_cracks, UV);
	vec4 outline = texture(frost_outline, UV);

	float crack_a = cracks.a * crack_strength;
	float outline_a = outline.a * outline_strength;
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed + UV.y * 9.0);

	// Named freezing origins around the card. Each starts later and spreads at
	// its own tempo, so the rim freezes in overlapping crystalline patches.
	float t = clamp(spread, 0.0, 1.0);
	float reveal = 0.0;
	reveal = max(reveal, freeze_front(UV, vec2(0.02, 0.02), 0.00, 1.10, t)); // top-left
	reveal = max(reveal, freeze_front(UV, vec2(0.98, 0.02), 0.12, 0.95, t)); // top-right
	reveal = max(reveal, freeze_front(UV, vec2(0.02, 0.50), 0.06, 1.20, t)); // mid-left
	reveal = max(reveal, freeze_front(UV, vec2(0.98, 0.50), 0.20, 0.90, t)); // mid-right
	reveal = max(reveal, freeze_front(UV, vec2(0.02, 0.98), 0.08, 1.05, t)); // bottom-left
	reveal = max(reveal, freeze_front(UV, vec2(0.98, 0.98), 0.16, 1.15, t)); // bottom-right

	// Keep the card name banner and the rules box legible. UV.y = 0 is the top
	// of the card texture and UV.y = 1 is the bottom. The side bands and the
	// corners stay fully frosted, so the frozen state is still obvious.
	float central_x = smoothstep(0.08, 0.22, UV.x)
		* (1.0 - smoothstep(0.78, 0.92, UV.x));
	float top_band = 1.0 - smoothstep(0.02, 0.19, UV.y);
	// The rules box stays clear; the very bottom power/damage readout may frost over.
	float bottom_band = smoothstep(0.58, 0.72, UV.y) * (1.0 - smoothstep(0.82, 0.94, UV.y));
	float ui_zone = max(top_band, bottom_band) * central_x;
	float readability = 1.0 - readability_clear * ui_zone;

	vec3 color = crack_tint.rgb * crack_a;
	color += outline_tint.rgb * outline_a;
	color += crack_tint.rgb * surface_veil;
	color *= readability * reveal;

	// Additive output: ALPHA is deliberately 1 so the glow does not get
	// double-attenuated by the blend mode.
	ALBEDO = color * intensity * pulse;
	ALPHA = 1.0;
}
