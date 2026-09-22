shader_type spatial;
// A Fresnel rim glow — bright where the surface turns away from the viewer, so it reads as light wrapping the edge
// of a shape rather than as paint on its faces.
//
// APPLIED TO A SHELL, NOT TO A RING. The material is put on a COPY of the crystal's own mesh scaled slightly up, so
// the glow follows the real silhouette at every angle, including while the crystal spins. An earlier attempt drew
// the cards' selection ring — a rounded RECTANGLE — on a billboard quad, which meant a rectangle drawn around a
// faceted shape: its top edge kept landing inside the crystal, and the crystal's point stuck out. Only the bottom
// and lower sides ever showed, at any margin, because the ring was never the shape it was outlining. A shell
// cannot have that failure mode.
//
// blend_add: the glow ADDS light, so it can never darken the crystal behind it and needs no sorting against it.
// depth_draw_never: it is light, not matter, so it stays out of the depth buffer.
render_mode blend_add, cull_back, unshaded, depth_draw_never;

uniform vec4 aura_color : source_color = vec4(0.62, 0.45, 1.0, 1.0);
uniform float rim_power : hint_range(0.1, 8.0) = 3.0;
uniform float intensity : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 12.0) = 2.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	// 1 where the surface faces us, 0 where it turns away. Both NORMAL and VIEW are in view space in Godot, with
	// VIEW pointing from the fragment back towards the camera, so this dot is the cosine of the viewing angle.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// The complement, raised to a power: low powers give a haze over the whole surface, high powers squeeze the
	// light into a tight rim. 3.0 is a soft glow that still reads as an edge.
	float rim = pow(1.0 - facing, rim_power);

	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed);
	float glow = rim * intensity * pulse;

	ALBEDO = aura_color.rgb * glow;
	// Note: with `unshaded` the engine ignores EMISSION, since ALBEDO is already the final colour. It is set here
	// because it costs nothing, reads as intent, and is what a bloom pass would be looking for if this project ever
	// moves off the Compatibility renderer — see game.tscn.
	EMISSION = aura_color.rgb * glow;
	// Additive blending scales what gets added by ALPHA, so this — not `intensity` — is what finally decides how
	// much light lands on screen.
	ALPHA = clamp(rim * aura_color.a * pulse, 0.0, 1.0);
}
