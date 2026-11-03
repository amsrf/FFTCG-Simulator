shader_type spatial;

// The hot flash that sits on top of the card fragments for the first few frames
// of the shatter. The Compatibility renderer has no bloom, so the only way to
// make a burst read as light is to draw it: a white-hot core plus an expanding
// gold/cyan shock ring, both added on top of whatever is behind them.
//
// The quad is camera-facing and is driven by CardShards. `fade` is the only
// parameter that changes every frame; the ring radius is also animated there.

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.90, 1.0);
uniform vec4 ring_color : source_color = vec4(1.0, 0.58, 0.16, 1.0);
uniform float core_strength : hint_range(0.0, 8.0) = 3.2;
uniform float ring_strength : hint_range(0.0, 8.0) = 1.8;
uniform float ring_radius : hint_range(0.0, 1.5) = 0.25;
uniform float ring_width : hint_range(0.005, 0.30) = 0.045;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);

	// Broad white core, then a thin travelling shock ring. The core is
	// deliberately wider than the ring so the first frames read as a flash,
	// not as an outline.
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 2.4) * core_strength;
	float ring = exp(-pow((r - ring_radius) / max(ring_width, 0.001), 2.0)) * ring_strength;

	float amount = clamp(core + ring, 0.0, 1.0) * fade;
	ALBEDO = (core_color.rgb * core + ring_color.rgb * ring) * fade;
	ALPHA = amount;
}
