// The glow on a board button's ring (scripts/ui/disc_socket.gd): an additive annulus laid over the baked iron ring,
// lit on hover and flashed on a press. The Compatibility renderer has no bloom, so this quad IS the glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 0.8, 1.0);
uniform float intensity = 0.0;
// In UV units of the quad (0.5 = the quad's edge).
uniform float ring_radius = 0.4;
uniform float core_width = 0.02;
uniform float spill_width = 0.08;

void fragment() {
	float r = length(UV - vec2(0.5));
	float d = abs(r - ring_radius);
	float core = 1.0 - smoothstep(0.0, max(core_width, 1e-4), d);
	float spill = exp(-d / max(spill_width, 1e-4));
	// The spill must be gone before the quad's edge, or the quad shows as a lit square.
	float window = 1.0 - smoothstep(ring_radius + (0.5 - ring_radius) * 0.35, 0.5, r);
	float a = intensity * (core * 0.9 + spill * 0.6) * window;
	// blend_add adds ALBEDO * ALPHA, so the colour stays pure and the strength rides on alpha.
	ALBEDO = glow_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
