shader_type spatial;
// The gathering core of the fire burst and the detonation flash (fire_burst.gd). A camera-facing quad: a white-hot
// centre inside a warm halo, with four thin rays turning slowly so the charge reads as MAGIC gathering, not as a lamp.
// Alpha-blended, not additive: additive light washes out over the pale board wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.78, 1.0);
uniform float intensity = 1.0;
// Radius of the white core, in quad half-widths.
uniform float core_size = 0.16;
// 0 = no rays (the flash), 1 = full star rays (the charge).
uniform float rays = 1.0;
uniform float spin = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.4);
	float core = 1.0 - smoothstep(core_size * 0.45, core_size, d);
	float a = atan(p.y, p.x);
	float star = pow(abs(cos(a * 2.0 + spin)), 60.0) + pow(abs(cos(a * 2.0 - spin * 0.6 + 0.785)), 90.0) * 0.6;
	star *= pow(clamp(1.0 - d, 0.0, 1.0), 1.4) * rays;
	vec3 col = mix(glow_color.rgb, core_color.rgb, clamp(core + star * 0.8, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp((halo * 0.8 + core + star) * intensity, 0.0, 1.0) * step(d, 1.0);
}
