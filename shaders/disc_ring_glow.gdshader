// The glow on a board button's ring (scripts/ui/disc_socket.gd): an additive annulus laid over the baked iron ring,
// lit on hover and flashed on a press. The Compatibility renderer has no bloom, so this quad IS the glow.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 glow_color : source_color = vec4(0.2, 0.9, 0.8, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float intensity = 0.0;
// In UV units of the quad (0.5 = the quad's edge).
uniform float ring_radius = 0.4;
uniform float core_width = 0.02;
uniform float spill_width = 0.08;
// Fade inward before the plane crosses the curved face of the priority coin.
uniform float inner_spill_limit = 0.0;

void fragment() {
	float r = length(UV - vec2(0.5));
	float d = abs(r - ring_radius);
	float core = (1.0 - smoothstep(0.0, max(core_width, 1e-4), d)) * step(1e-4, core_width);
	float spread = d / max(spill_width, 1e-4);
	// A ring with zero spill keeps its brightness inside the core.
	float spill = spill_width > 0.0 ? exp(-spread) : core;
	// The spill must be gone before the quad's edge, or the quad shows as a lit square.
	float window = 1.0 - smoothstep(ring_radius + (0.5 - ring_radius) * 0.35, 0.5, r);
	float a = intensity * (core * 0.9 + spill * 0.6) * window;
	if (inner_spill_limit > 0.0) {
		a *= smoothstep(ring_radius - inner_spill_limit, ring_radius - inner_spill_limit * 0.38, r);
	}
	// blend_add adds ALBEDO * ALPHA, so the colour stays pure and the strength rides on alpha.
	ALBEDO = mix(glow_color.rgb, core_color.rgb, core_color.a * core);
	ALPHA = clamp(a, 0.0, 1.0);
}
