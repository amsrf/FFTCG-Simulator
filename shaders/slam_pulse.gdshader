shader_type spatial;
// An expanding ring of light on the board: the impact pulse when a Character
// slams into its row. Additive because the Compatibility renderer has no bloom,
// so this is the only way the ring reads as emitted light.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 pulse_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ring_radius : hint_range(0.0, 1.5) = 0.10;
uniform float ring_width : hint_range(0.005, 0.30) = 0.055;
uniform float ring_strength : hint_range(0.0, 8.0) = 2.2;
uniform float core_strength : hint_range(0.0, 8.0) = 1.1;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float ring = exp(-pow((r - ring_radius) / max(ring_width, 0.001), 2.0)) * ring_strength;
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 2.6) * core_strength;
	float amount = clamp(ring + core, 0.0, 1.0) * fade;
	ALBEDO = (pulse_color.rgb * ring + core_color.rgb * core) * fade;
	ALPHA = amount;
}
