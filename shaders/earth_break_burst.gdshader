shader_type spatial;
// The light that ERUPTS with the Earth break's spike (earth_break_crystal.gd): an explosion of light at the spike's
// base that blasts mostly upward along it. Drawn on a camera-facing quad whose local +Y runs up the spike on screen.
// Additive (the Compatibility renderer has no bloom: this IS the bloom). Wide and white-hot at the bottom, where it
// has to bury the spike's base completely; a tapering plume of gold above it, with streaks shooting up.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 hot_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
uniform vec4 plume_color : source_color = vec4(1.0, 0.68, 0.22, 1.0);
uniform float intensity : hint_range(0.0, 6.0) = 1.0;
/// 0..1: how far up the quad the plume reaches (it shoots up with the spike).
uniform float reach : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i + seed), hash11(i + 1.0 + seed), f);
}

void fragment() {
	// x: -1..1 across, y: 0 at the bottom edge, 1 at the top (QuadMesh UV.y = 0 is its TOP edge).
	float x = UV.x * 2.0 - 1.0;
	float y = 1.0 - UV.y;
	// The blast: a hot round core low down (centred where the spike leaves the ground)...
	float core_y = 0.16;
	float core = exp(-(x * x) / 0.11 - pow((y - core_y) / 0.17, 2.0));
	// ...and a plume narrowing as it climbs.
	float width = mix(0.42, 0.05, smoothstep(0.05, 1.0, y));
	float plume = exp(-(x * x) / (width * width)) * smoothstep(0.0, 0.12, y) * (1.0 - smoothstep(reach * 0.85, reach, y));
	plume *= mix(1.0, 0.25, smoothstep(0.2, 1.0, y));
	// Streaks shooting up the plume, so it reads as a burst rather than a soft blob.
	float streaks = 0.70 + 0.30 * noise1(x * 9.0 - TIME * 0.0) * (0.6 + 0.4 * sin(y * 12.0 - TIME * 18.0 + x * 5.0));
	// Fade to nothing at the quad's sides and top.
	float edge = (1.0 - smoothstep(0.75, 1.0, abs(x))) * (1.0 - smoothstep(0.92, 1.0, y));
	float light = (core * 1.6 + plume * streaks) * edge;
	vec3 colour = mix(plume_color.rgb, hot_color.rgb, clamp(core * 1.3 + (1.0 - smoothstep(0.0, 0.45, y)) * 0.4, 0.0, 1.0));
	ALBEDO = colour * light * intensity;
	ALPHA = clamp(light * intensity, 0.0, 1.0);
}
