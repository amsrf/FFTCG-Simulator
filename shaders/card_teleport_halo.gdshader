shader_type spatial;
// Additive halo that sits around a card during the teleport presentation.
// It is deliberately outside the card silhouette: the inside of the card is
// masked out, so this never washes out the artwork it is revealing.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 halo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Card half-extent in the quad's UV-derived coordinate space. The card is
// centred in a quad HALO_SCALE times its size, so this is 1 / HALO_SCALE.
uniform vec2 card_half = vec2(0.645, 0.645);
uniform float halo_width : hint_range(0.01, 0.40) = 0.11;
// Fade to zero at the card edge. Without this the additive halo is brightest
// exactly on the silhouette and reads as a crisp white border around a card
// that has not materialised yet.
uniform float inner_fade : hint_range(0.001, 0.20) = 0.06;
uniform float intensity : hint_range(0.0, 4.0) = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 d = abs(p) - card_half;
	// Positive outside the card, negative inside. `outside` is the distance
	// beyond the nearest card edge, in the same units as p.
	float outside = max(d.x, d.y);
	if (outside <= 0.0) {
		discard;
	}
	float edge_fade = smoothstep(0.0, max(inner_fade, 0.001), outside);
	float falloff = exp(-max(outside - inner_fade, 0.0) / max(halo_width, 0.001));
	float ring = edge_fade * falloff;
	vec3 col = halo_color.rgb;
	float amount = ring * intensity;
	ALBEDO = col * amount;
	ALPHA = clamp(amount, 0.0, 1.0);
}
