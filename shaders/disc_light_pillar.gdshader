// The light rising off a board button's ring while it is hovered or pressed (scripts/ui/disc_socket.gd): an open
// cylinder standing on the ring, brightest at the foot and fading to nothing at the top, with soft vertical streaks
// drifting upward. Additive, so it only brightens; the Compatibility renderer has no bloom, so this IS the glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.85, 1.0);
uniform float intensity = 0.0;
uniform float height = 0.4;          // the cylinder's height, metres (its origin is its centre)
uniform float streaks = 9.0;         // vertical light streaks around the ring
uniform float rise_speed = 0.35;

varying float v_h;
varying float v_angle;

void vertex() {
	v_h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);    // 0 at the ring, 1 at the top
	v_angle = atan(VERTEX.z, VERTEX.x);
}

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	// Falls off with height (squared, so it reads as light thrown upward, not a solid tube).
	float fall = (1.0 - v_h) * (1.0 - v_h);
	// Soft streaks: a few brighter bands around the ring that breathe and drift up.
	float a = v_angle / 6.2831853 * streaks;
	float band = 0.5 + 0.5 * sin(a * 6.2831853 + sin(TIME * 0.7 + floor(a)) * 1.5);
	float drift = 0.75 + 0.25 * sin((v_h - TIME * rise_speed) * 18.0 + hash(floor(a)) * 6.28);
	float lit = fall * mix(0.55, 1.0, band * drift);
	// No hard foot line: fade the first few millimetres in.
	lit *= smoothstep(0.0, 0.04, v_h);
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(intensity * lit * 0.55, 0.0, 1.0);
}
