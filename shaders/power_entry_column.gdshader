shader_type spatial;
// The light column of the power entry (power_entry_burst.gd): a camera-facing beam standing on the card that just
// landed and rising UP THE SCREEN (UV.y = 1 is its foot), bright and white at the core, the card's element colour at
// its sides, fading toward its top. `rise` (0..1) is how far up it reaches.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float intensity = 1.0;
uniform float rise = 1.0;

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float up = 1.0 - UV.y;   // 0 at the foot, 1 at the top
	float reach = max(rise, 0.001);
	float body = (1.0 - smoothstep(0.55, 1.0, x)) * (1.0 - smoothstep(reach * 0.55, reach, up));
	float core = (1.0 - smoothstep(0.0, 0.45, x)) * (1.0 - smoothstep(0.0, reach * 0.8, up));
	vec3 col = mix(mix(tint.rgb, vec3(1.0), 0.25), vec3(1.0, 0.98, 0.9), clamp(core, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp((body * 0.55 + core * 0.45) * intensity, 0.0, 1.0);
}
