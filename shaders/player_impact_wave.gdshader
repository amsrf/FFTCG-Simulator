shader_type spatial;
// The impact at the defending player's EDGE (clash_cinematic.gd, _edge_wave): a ring that races outward across a
// WIDE, flat camera-facing quad, so in the screen it is a flattened ellipse spreading along the screen's edge, with a
// soft core that fills it at first. `progress` 0..1 drives the whole thing; it is gone at 1.
//
// Additive and unshaded: the Compatibility renderer has no bloom, so the light is drawn. Width-driven edges are
// guarded with max(w, eps): smoothstep/exp with a zero width is undefined here (see AGENTS.md).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 wave_color : source_color = vec4(1.0, 0.84, 0.52, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 8.0) = 2.2;
uniform float thickness : hint_range(0.01, 0.5) = 0.11;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float grow = 1.0 - pow(1.0 - progress, 3.0);
	float radius = mix(0.08, 0.92, grow);
	float w = max(thickness * (1.0 - 0.55 * progress), 0.005);
	float ring = exp(-pow((r - radius) / w, 2.0));
	float core = pow(clamp(1.0 - r / max(radius, 0.001), 0.0, 1.0), 2.0) * (1.0 - smoothstep(0.0, 0.45, progress));
	float fade = (1.0 - progress) * (1.0 - progress);
	float edge = 1.0 - smoothstep(0.9, 1.0, r);
	float a = clamp((ring + core * 0.8) * fade * edge, 0.0, 1.0);
	vec3 col = mix(wave_color.rgb, hot_color.rgb, clamp(ring * (1.0 - progress), 0.0, 1.0));
	ALBEDO = col * intensity * a;
	ALPHA = a;
}
