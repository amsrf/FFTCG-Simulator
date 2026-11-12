shader_type spatial;
// A ring on the board for the fire burst (fire_burst.gd), level with the card faces. Used twice:
//   the CHARGE ring: a circle of dashes (`dashes` > 0) closing in on the card while the sparks gather;
//   the SHOCKWAVE: a ragged ring of flame racing outward at the detonation (`dashes` = 0).
// Alpha-blended, with a darker scorched inner line, so it reads over the pale wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.90, 0.55, 1.0);
uniform float ring_radius = 0.5;
uniform float ring_width = 0.05;
uniform float intensity = 1.0;
uniform float seed = 0.0;
// Number of dashes around the ring (0 = a continuous, noise-torn ring).
uniform float dashes = 0.0;
uniform float spin = 0.0;

float hash(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = atan(p.y, p.x) / 6.28318 + 0.5;
	float tear = noise1(a * 23.0 + seed) * 0.6 + noise1(a * 61.0 + seed * 1.7) * 0.4;
	float width = ring_width * mix(0.55, 1.35, tear);
	float off = (d - ring_radius) / max(width, 0.001);
	float band = exp(-off * off);
	// The bright front is the OUTER edge; a scorched dark line trails inside it.
	float front = exp(-pow((d - ring_radius - width * 0.25) / max(width * 0.45, 0.001), 2.0));
	float scorch = exp(-pow((d - ring_radius + width * 1.3) / max(width * 0.8, 0.001), 2.0)) * (1.0 - band);
	float mask = 1.0;
	if (dashes > 0.0) {
		float f = fract(a * dashes + spin);
		mask = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.55, 0.65, f));
		scorch = 0.0;
	} else {
		band *= mix(0.45, 1.0, tear);
	}
	vec3 col = mix(ring_color.rgb, hot_color.rgb, clamp(front, 0.0, 1.0));
	col = mix(col, vec3(0.10, 0.03, 0.02), clamp(scorch * 0.8, 0.0, 1.0));
	float alpha = (band * mask + scorch * 0.45) * intensity;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0) * (1.0 - smoothstep(0.96, 1.0, d));
}
