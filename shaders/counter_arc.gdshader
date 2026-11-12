shader_type spatial;
// One electric arc of the COUNTERED malfunction (scripts/vfx/counter_cue.gd): a ribbon strip lying on the card face.
// The CPU bakes UV.x = position along the arc (0..1) and UV.y = across the ribbon (0..1); this only paints it.
// Additive (the Compatibility renderer has no bloom): a white-hot core inside a violet glow, after references
// Clips/negate2 frames 128+.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.96, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.62, 0.40, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	float v = UV.y * 2.0 - 1.0;
	float core = exp(-v * v / 0.02);
	float glow = exp(-v * v / 0.22);
	// The arc fizzles out at both ends instead of stopping square.
	float ends = smoothstep(0.0, 0.10, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	vec3 colour = glow_color.rgb * glow * 0.75 + core_color.rgb * core * 1.5;
	ALBEDO = colour * ends * intensity;
}
