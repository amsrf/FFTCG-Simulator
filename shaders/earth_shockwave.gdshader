shader_type spatial;
// The ring the Earth column throws out along the board when it hits a card (earth_totem_cue.gd).
//
// Alpha-blended, not additive: the board is pale wood, and added light disappears on it. The ring is a pale dusty
// front with a thin dark line just behind it, so it has contrast on the light board and on dark card art alike.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 front_color : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.16, 0.10, 0.05, 1.0);
uniform float ring_radius : hint_range(0.0, 1.0) = 0.3;
uniform float ring_width : hint_range(0.005, 0.30) = 0.06;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
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
	return mix(hash11(i), hash11(i + 1.0), f);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	// Kicked-up dust, not a compass circle: the front is a little uneven and its density varies around the ring.
	float ragged = (noise1(angle * 9.0 + seed) - 0.5) * ring_width * 0.5;
	float density = 0.70 + 0.30 * noise1(angle * 5.0 + seed * 3.0 + 11.0);
	float d = r - ring_radius - ragged;
	float front = exp(-pow(d / max(ring_width, 0.001), 2.0));
	// Soft dust trailing inside the front, and a dark line hugging its inner edge.
	float trail = smoothstep(-ring_width * 4.0, 0.0, d) * (1.0 - step(0.0, d)) * 0.35;
	float shadow = exp(-pow((d + ring_width * 1.5) / max(ring_width * 0.80, 0.001), 2.0));
	float edge_fade = 1.0 - smoothstep(0.90, 0.99, r);
	float light = clamp(front + trail, 0.0, 1.0) * density;
	float dark = shadow * 0.85 * (1.0 - front);
	ALBEDO = mix(shadow_color.rgb, front_color.rgb, clamp(light / max(light + dark, 0.001), 0.0, 1.0));
	ALPHA = clamp(light * 1.0 + dark, 0.0, 1.0) * strength * fade * edge_fade;
}
