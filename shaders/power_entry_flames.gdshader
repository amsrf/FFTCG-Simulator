shader_type spatial;
// The flames on the card's long edges after a power entry (power_entry_burst.gd; ~/Desktop/Clips/entry 50-62): a quad
// lying ON the card, wider than it, with flickering tongues licking outward from its left and right edges and
// climbing toward the card's top (UV.y = 0). In the card's element colour, white where they leave the edge.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.55, 0.45, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float time = 0.0;
// Where the card's edge is in this quad, as |u| (the quad is wider than the card).
uniform float edge = 0.8;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 s = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), s.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), s.x), s.y);
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float v = UV.y;
	// Tongues: noise scrolling toward the top, stretched along the edge.
	float n = noise(vec2(x * 7.0 + (UV.x < 0.5 ? 0.0 : 17.0), v * 9.0 + time * 7.0));
	float n2 = noise(vec2(x * 15.0, v * 21.0 + time * 11.0));
	float reach = (0.05 + 0.16 * n + 0.06 * n2) * mix(1.0, 0.55, v);
	float out_of_edge = x - edge;
	float flame = smoothstep(-0.05, 0.0, out_of_edge) * (1.0 - smoothstep(reach * 0.55, reach, out_of_edge));
	// Stronger toward the top, thinning out at the bottom, gone past the card's ends.
	flame *= smoothstep(1.0, 0.75, v) * smoothstep(0.0, 0.06, v);
	float hot = 1.0 - smoothstep(0.0, reach * 0.45, abs(out_of_edge));
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(hot * 0.75, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(flame * intensity * (0.65 + 0.35 * n2), 0.0, 1.0);
}
