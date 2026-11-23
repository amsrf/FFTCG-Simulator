shader_type spatial;
// One ripple of the water splash (water_splash.gd), lying flat on the deck top. A bright crest at `ring_radius` with a
// pale trough just inside it, wobbling a little round the circle so it reads as water rather than a drawn circle.
// Alpha-blended (additive washes out over the pale wood), drawn after the board (render_priority set by the script).

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 water_color : source_color = vec4(0.32, 0.58, 1.0, 1.0);
uniform vec4 crest_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform float ring_radius = 0.5;
uniform float ring_width = 0.05;
uniform float intensity = 1.0;
uniform float seed = 0.0;

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
	// A gentle wobble of the radius (wraps cleanly: 9 and 14 cells round the circle).
	float wobble = (noise1(fract(a) * 9.0 + seed) - 0.5) * 0.6 + (noise1(fract(a) * 14.0 + seed * 1.9) - 0.5) * 0.4;
	float w = max(ring_width, 0.002);
	float r = ring_radius + wobble * w * 0.9;
	float crest = exp(-pow((d - r) / w, 2.0));
	float trough = exp(-pow((d - r + w * 1.8) / (w * 1.4), 2.0)) * (1.0 - crest);
	vec3 col = mix(water_color.rgb, crest_color.rgb, clamp(crest * 0.85, 0.0, 1.0));
	float alpha = (crest + trough * 0.35) * intensity;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0) * (1.0 - smoothstep(0.94, 1.0, d));
}
