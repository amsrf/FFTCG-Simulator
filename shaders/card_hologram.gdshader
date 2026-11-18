shader_type spatial;
// THE PLAYED CARD TURNING INTO A HOLOGRAM where it was cast (~/Desktop/Clips/play, frames 148-163): its art drains to
// a translucent tint of `tint`, with scan lines and a brighter rim, then dissolves from the bottom up with a glowing
// front. Drawn on a copy of the card's face mesh, so UV is the card's own (y = 1 is the bottom edge).
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.55, 0.87, 0.98, 1.0);
// 0 = the printed card, 1 = fully a hologram.
uniform float holo : hint_range(0.0, 1.0) = 0.0;
// 0 = whole, 1 = gone.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float time_offset = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec4 art = texture(texture_albedo, UV);
	float luma = dot(art.rgb, vec3(0.299, 0.587, 0.114));
	float scan = 0.75 + 0.25 * sin((UV.y * 140.0 - (TIME + time_offset) * 9.0));
	vec2 edge = min(UV, 1.0 - UV);
	float rim = exp(-min(edge.x, edge.y) / 0.035);
	vec3 ghost = tint.rgb * (0.35 + 0.9 * luma) * scan + tint.rgb * rim * 0.9;
	vec3 colour = mix(art.rgb, ghost, holo);
	float alpha = art.a * mix(1.0, 0.62 + 0.3 * rim, holo);

	float n = value_noise(UV * vec2(26.0, 36.0)) * 0.6 + value_noise(UV * 7.0) * 0.4;
	float height = 1.0 - UV.y;
	float threshold = dissolve * 1.25 - 0.12;
	float keep = height * 0.65 + n * 0.35;
	float alive = smoothstep(threshold - 0.02, threshold + 0.02, keep);
	float front = (1.0 - smoothstep(0.0, 0.05, abs(keep - threshold))) * step(0.001, dissolve);
	colour += tint.rgb * front * 1.6;
	alpha = max(alpha * alive, front * 0.9);
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = colour;
	ALPHA = alpha;
}
