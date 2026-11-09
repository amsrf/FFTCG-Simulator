shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D baked_appearance : source_color, filter_linear, repeat_disable;
uniform float flow_direction = 1.0;
uniform float flow_speed : hint_range(0.0, 0.3) = 0.18;
uniform float ripple_strength : hint_range(0.0, 0.25) = 0.075;
uniform float streak_strength : hint_range(0.0, 1.0) = 0.38;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.48;
uniform float river_center_z = 0.29;
uniform float still_bank_width : hint_range(0.0, 0.06) = 0.014;
// Fixed time is useful for comparing shader frames in a rendering harness.
uniform float preview_time = -1.0;
varying vec2 river_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
// Stable elongated marks move with the current instead of pulsing in place.
float flow_marks(vec2 p, vec2 cell_size, vec2 radius, float density) {
	vec2 cell = floor(p / cell_size);
	vec2 local = fract(p / cell_size) - 0.5;
	vec2 jitter = vec2(hash(cell + 17.0), hash(cell + 39.0)) - 0.5;
	vec2 centre = jitter * 0.28;
	vec2 offset = (local - centre) * cell_size;
	float size = mix(0.65, 1.0, hash(cell + 71.0));
	float ellipse = length(offset / (radius * size));
	float shape = 1.0 - smoothstep(0.60, 1.0, ellipse);
	return shape * step(1.0 - density, hash(cell + 93.0));
}
void vertex() {
	river_position = VERTEX.xz;
}
void fragment() {
	float clock = preview_time >= 0.0 ? preview_time : TIME;
	vec2 p = river_position;
	// Fixed in board space: all animation fades out before the visible banks.
	// The pools widen beyond the wooden platforms, matching the authored river.
	float pool_opening = smoothstep(3.8, 4.1, abs(p.x));
	float half_width = 0.115 + max(0.0, abs(p.x) - 3.25) * 0.34
		- 0.04 * (1.0 - pool_opening);
	float centre = river_center_z - 0.018 * sin(p.x * 2.5);
	float bank_distance = half_width - abs(p.y - centre);
	float moving_centre = smoothstep(still_bank_width, still_bank_width + 0.028, bank_distance);
	float travel = clock * flow_speed * flow_direction;
	float a = noise(vec2((p.x - travel) * 3.5, p.y * 34.0));
	float b = noise(vec2((p.x - travel * 0.63) * 6.0, p.y * 57.0 + 9.0));
	float shimmer = (a * 0.65 + b * 0.35 - 0.5) * ripple_strength;
	float foam = smoothstep(0.77, 0.94, a) * smoothstep(0.59, 0.85, b);
	vec2 current = vec2(p.x - travel, p.y);
	current.y += 0.009 * sin(current.x * 3.0);
	float streaks = flow_marks(current, vec2(0.95, 0.072), vec2(0.32, 0.007), 0.60);
	float side_pools = smoothstep(3.55, 4.25, abs(p.x));
	float patches = flow_marks(current + vec2(12.3, 3.7),
		vec2(0.85, 0.19), vec2(0.23, 0.035), 0.48);
	// Irregular edges keep the larger side-pool marks from reading as solid ovals.
	patches *= smoothstep(0.25, 0.68, noise(current * vec2(17.0, 70.0)));
	float stone_x = sign(p.x) * 4.36;
	float stone_z = river_center_z - flow_direction * 0.18;
	float downstream = (p.x - stone_x) * flow_direction;
	float wake_length = smoothstep(0.04, 0.14, downstream)
		* (1.0 - smoothstep(0.30, 0.65, downstream));
	float wake_width = 1.0 - smoothstep(0.025, 0.075, abs(p.y - stone_z));
	float entrance_wake = wake_length * wake_width
		* smoothstep(0.48, 0.76, noise(current * vec2(20.0, 65.0)));
	vec3 base = texture(baked_appearance, UV).rgb;
	vec3 still_water = base * mix(0.66, 1.0, moving_centre);
	vec3 movement = base * shimmer * 2.0
		+ vec3(0.10, 0.25, 0.23) * (shimmer + foam * 0.18)
		+ vec3(0.28, 0.55, 0.49) * streaks * streak_strength
		+ vec3(0.38, 0.62, 0.55) * (patches * side_pools + entrance_wake * 0.7) * foam_strength;
	ALBEDO = max(vec3(0.0), still_water + movement * moving_centre);
}
