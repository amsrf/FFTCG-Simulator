shader_type spatial;
// A single camera-facing lightning channel dropping into a target.
//
// The quad is oriented by the cue so its bottom edge sits on the card and its
// local +Y points up the screen. Everything is procedural: a jagged main
// channel, four branches, a bright descending head, and a crackling bottom
// flare. Additive because the Compatibility renderer has no bloom.
//
// Artifact's Thundergod's Wrath uses a bolt sprite that fades in for 0.1 s,
// lives 0.4 s and fades over 0.2 s, with a separate blue-white impact flare.
// This shader keeps that beat but draws the shape instead of sampling a texture.

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.34, 0.06, 0.88, 1.0);
uniform vec4 arc_color : source_color = vec4(0.42, 0.06, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.93, 0.87, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.45;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;

uniform float bolt_width : hint_range(0.0005, 0.05) = 0.0042;
uniform float glow_width : hint_range(0.005, 0.20) = 0.060;
uniform float branch_strength : hint_range(0.0, 2.0) = 1.0;

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
	return mix(hash11(i), hash11(i + 1.0), f);
}

// X position of the main channel at height y (0 = card, 1 = top of quad).
// The path converges to the card centre at the bottom, then wanders upward.
float path_x(float y) {
	float n = noise1(y * 3.2 + seed * 11.0) * 0.50
		+ noise1(y * 7.1 + seed * 17.0) * 0.28
		+ noise1(y * 15.3 + seed * 23.0) * 0.14;
	float wander = (n - 0.46) * 0.72;
	wander *= smoothstep(0.0, 0.24, y);
	// Quantise the high-frequency jitter: the bolt should crackle, not wobble.
	float tick = floor(TIME * 32.0 + seed * 7.0);
	float jitter = (hash11(tick * 1.7 + floor(y * 18.0)) - 0.5) * 0.014
		+ (noise1(y * 41.0 + seed * 31.0) - 0.5) * 0.022;
	// Pin the final few centimetres to the card centre. Without this the main
	// channel can land a couple of pixels off even though the impact quad is
	// centred, which reads as a near-miss.
	jitter *= smoothstep(0.02, 0.16, y);
	return clamp(0.5 + wander + jitter, 0.015, 0.985);
}

float line_mask(float d, float width, float aa) {
	return 1.0 - smoothstep(width, width + aa, d);
}

void fragment() {
	// QuadMesh maps UV.y = 0 to its local +Y (screen-up) edge and UV.y = 1 to
	// its lower edge. Work in "0 = card, 1 = top" space so the path converges
	// and the impact pool sit on the card, not on the top of the quad.
	float y = 1.0 - UV.y;
	// reveal 0 = the head is at the top, reveal 1 = it has reached the card.
	float head = 1.0 - reveal;
	float reveal_mask = smoothstep(head - 0.035, head + 0.010, y);
	// Do not let the top edge end as a hard cut against the HUD; let it dissolve
	// as if it came from above the screen.
	reveal_mask *= 1.0 - smoothstep(0.88, 0.995, y);

	float x = path_x(y);
	float d = abs(UV.x - x);
	float aa = max(fwidth(d) * 1.5, 0.0006);

	float width_mod = 0.78 + 0.44 * noise1(y * 12.0 + seed * 3.0);
	float core = line_mask(d, bolt_width * width_mod, aa);
	float inner_glow = exp(-pow(d / max(bolt_width * 3.1, 0.0001), 2.0));
	float glow = exp(-pow(d / max(glow_width, 0.0001), 2.0));
	float halo = exp(-pow(d / max(glow_width * 2.4, 0.0001), 2.0));

	// Four short forks. Each starts on the main channel at a seeded height and
	// leaves at a different angle, thinning as it travels.
	float branch = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float by = 0.12 + hash11(seed * 1.37 + fi * 7.13) * 0.74;
		float length_y = 0.045 + hash11(seed * 2.11 + fi * 3.71) * 0.13;
		float direction = hash11(seed * 5.31 + fi * 2.17) > 0.5 ? 1.0 : -1.0;
		float reach = (0.030 + hash11(seed * 3.73 + fi * 5.19) * 0.070) * direction;
		float bx = path_x(by);
		float ty = (y - by) / max(length_y, 0.001);
		float in_segment = step(0.0, ty) * step(ty, 1.0);
		float wobble = (noise1(y * 38.0 + fi * 13.0 + seed * 7.0) - 0.5) * 0.018 * ty;
		float branch_x = bx + reach * ty + wobble;
		float bd = abs(UV.x - branch_x);
		float bcore = line_mask(bd, bolt_width * 0.62, aa);
		float bglow = exp(-pow(bd / max(glow_width * 0.55, 0.0001), 2.0));
		float taper = (1.0 - ty * 0.55) * in_segment;
		branch += (bcore * 1.35 + bglow * 0.55) * taper;
	}
	branch *= branch_strength;

	// The descending head gets its own hot point so the strike reads as motion
	// even in the few frames before the channel reaches the card.
	float descend = 1.0 - smoothstep(0.97, 1.0, reveal);
	float tip = exp(-pow((y - head) / 0.028, 2.0)) * descend;

	// A shallow pool of light where the channel meets the card.
	float bx2 = (UV.x - 0.5) * 2.1;
	float by2 = y * 1.45;
	float base = exp(-(bx2 * bx2 + by2 * by2) * 11.0) * (1.0 - smoothstep(0.10, 0.34, y));

	float flicker = 0.82 + 0.18 * hash11(floor(TIME * 40.0) + seed * 19.0);

	float mask = (core * 1.25 + inner_glow * 0.80 + glow * 0.55 + halo * 0.28
		+ branch * 0.95 + tip * 3.5 + base * 1.05) * reveal_mask;
	mask = clamp(mask * fade, 0.0, 1.0);

	vec3 colour = core_color.rgb * (core * 0.90 + tip * 1.55 + base * 0.70)
		+ arc_color.rgb * (inner_glow * 1.40 + glow * 1.18 + halo * 0.48 + branch * 1.20)
		+ tint.rgb * (glow * 0.50 + halo * 0.65);
	ALBEDO = colour * intensity * fade * flicker;
	ALPHA = mask;
}
