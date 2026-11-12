shader_type spatial;
// The Earth break's spike (earth_break_crystal.gd): a tall, thin, translucent amber pyramid that rises through the card.
// Reference: Clips/impale2 frames 137-168 - BLAZING white-gold at the base, translucent amber up the body, DARK
// red-orange at the tip. Alpha-blended (a dark tip cannot be drawn by adding light), both faces drawn, no depth
// written; light bands stream up the lower, glowing part. Mesh data: UV.y = height along the spike (0 base, 1 tip).
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

/// The glowing base, the translucent amber body, and the dark tip.
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.58, 1.0);
uniform vec4 body_color : source_color = vec4(1.0, 0.60, 0.16, 1.0);
uniform vec4 tip_color : source_color = vec4(0.32, 0.05, 0.02, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
/// 0..1: how much of the crystal is lit, from its base up (the tip ignites last).
uniform float reach : hint_range(0.0, 1.0) = 1.0;
/// 0..1: how much of it has VANISHED, from its top down (the descent), with a ragged, glowing front.
uniform float vanish : hint_range(0.0, 1.0) = 0.0;
/// Nothing is drawn below this world height: the card's face. The crystal's foot is under the card and must never
/// show, not even once the card has gone.
uniform float cut_y = -100.0;
/// ... and it fades in over this many metres above that, so it has no visible bottom end.
uniform float fade_in = 0.2;
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

varying float height;
varying vec3 world_position;

void vertex() {
	height = UV.y;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash11(dot(i, vec2(1.0, 57.0)));
	float b = hash11(dot(i + vec2(1.0, 0.0), vec2(1.0, 57.0)));
	float c = hash11(dot(i + vec2(0.0, 1.0), vec2(1.0, 57.0)));
	float d = hash11(dot(i + vec2(1.0, 1.0), vec2(1.0, 57.0)));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	if (world_position.y < cut_y) {
		discard;
	}
	// The vanishing front comes down from the top: ragged, and glowing white just below where it eats the crystal.
	float ragged = (noise2(vec2(world_position.x * 18.0 + world_position.z * 11.0, height * 9.0 + seed)) - 0.5) * 0.10;
	float front = (1.06 - vanish * 1.12) - height + ragged;
	if (vanish > 0.0 && front < 0.0) {
		discard;
	}
	float front_glow = vanish > 0.0 ? 1.0 - smoothstep(0.0, 0.07, front) : 0.0;
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float facing = abs(dot(n, v));
	// Base -> body -> tip. The lowest fifth is below the ground, so the visible part starts at height ~0.2.
	float glow_zone = 1.0 - smoothstep(0.20, 0.50, height);
	float dark_zone = smoothstep(0.55, 0.98, height);
	vec3 colour = mix(body_color.rgb, core_color.rgb, glow_zone);
	colour = mix(colour, tip_color.rgb, dark_zone);
	// A glassy rim: the grazing edges of each face read a little deeper and redder than looking straight in.
	colour = mix(colour * vec3(0.85, 0.55, 0.40), colour, smoothstep(0.10, 0.60, facing));
	// Light streaming up the glowing lower part only; the dark tip stays still.
	float bands = 0.80 + 0.20 * sin(height * 26.0 - TIME * 15.0 + seed);
	float flicker = 0.92 + 0.08 * hash11(floor(TIME * 24.0) + seed);
	float shimmer = mix(1.0, bands * flicker, 1.0 - dark_zone);
	// Opaque glow at the base, translucent amber in the body, denser again at the dark tip; a little denser at rims.
	float body = mix(0.92, 0.42, smoothstep(0.20, 0.55, height)) + 0.36 * dark_zone + 0.12 * (1.0 - facing);
	float lit = 1.0 - smoothstep(reach - 0.08, reach, height);
	float base_fade = smoothstep(cut_y, cut_y + fade_in, world_position.y);
	// Where it comes out it dissolves into the burst of light (earth_break_burst.gdshader) that buries its base.
	colour = mix(vec3(1.0, 0.97, 0.86), colour, smoothstep(cut_y, cut_y + fade_in * 2.5, world_position.y));
	colour = mix(colour, vec3(1.0, 0.97, 0.88), front_glow * 0.8);
	ALBEDO = colour * intensity * shimmer;
	ALPHA = clamp((body * lit + front_glow * 0.5) * base_fade, 0.0, 1.0);
}
