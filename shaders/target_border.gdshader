shader_type spatial;

// Glow ring that hugs a card's rounded silhouette, drawn on a quad a little
// larger than the card itself (see Card._build_target_border()).
//
// Nothing is drawn INSIDE the silhouette, so the light always sits outside the
// card's edge and never washes over the artwork.
//
// BLENDING: alpha (`blend_mix`), not additive. Additive light *always* merges with
// whatever is behind it — that is what made the ring look washed out and white over
// bright artwork. Alpha blending lets the ring REPLACE the background, so its
// colour stays saturated and it reads as solid; `border_alpha` is the knob.
//
// This is the "the game is asking you to choose or target this card" cue. It is
// prompt-driven only: a normal playable card does NOT glow (see
// Hand.refresh_highlights() and Field.set_viable_targets()). The card the player
// has actually SELECTED gets the same ring in the "selected" colour (orange) —
// Card.set_selected_highlight().
//
// The model is deliberately CSS-like, because a ring needs an EDGE:
//   * `border_width`  == CSS `border-width`  — metres of SOLID ring at full
//                       strength from the card's edge outward.
//   * `border_color`  == CSS `border-color`
//   * `border_alpha`  == how opaque that ring is (1 = fully solid)
//   * `glow_width`    == CSS `box-shadow` blur — soft spill PAST the ring;
//                       0 gives a crisp ring with no spill.
//   * `glow_color` / `glow_alpha` == the spill's colour and opacity.
//
// TUNING: the values that matter are authored in
// shaders/target_border_material.tres — open that in the editor and every uniform
// below appears in the Inspector with sliders / colour pickers. The defaults here
// are only a fallback for a material-less use of this shader.
//
// Geometry note: the card mesh lies in the XZ plane (0.429 x 0.6, normal +Y),
// so UV is mapped to metres on those two axes and the rounded-rect SDF is
// evaluated in world units — that keeps the corner radius circular instead of
// being stretched by the card's aspect ratio.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

group_uniforms card;
// Card face size in metres. Set by Card from the mesh.
uniform vec2 card_size = vec2(0.429, 0.6);
// Room between the glow and the quad's edge. Card DERIVES this from
// border_width + glow_width and writes it back, so it is not a tuning knob — if
// it is too small the quad's edge crops the glow.
uniform float margin : hint_range(0.0, 1.0) = 0.2;
// Rounded-rect corner radius, in metres (must match the art's corner).
uniform float corner_radius : hint_range(0.0, 0.1) = 0.02;

group_uniforms border;
// THE THICKNESS KNOB (CSS border-width): metres of solid ring, measured outward
// from the card's edge. The card is 0.429 m wide, so 0.025 is ~6% of the width.
uniform float border_width : hint_range(0.0, 0.2) = 0.025;
// How soft the ring's outer edge is, in metres. Small = a crisp line.
uniform float border_feather : hint_range(0.0, 0.05) = 0.01;
uniform vec3 border_color : source_color = vec3(0.15, 0.45, 1.0);
// Opacity where the ring meets the CARD (its inner boundary): 1.0 = fully solid.
uniform float border_alpha : hint_range(0.0, 1.0) = 1.0;
// Opacity at the ring's OUTER boundary, so the ring thins as it moves away from
// the card instead of being a flat slab. The feather then takes it to zero.
// 0.8 makes the outer edge 20% transparent.
uniform float border_alpha_far : hint_range(0.0, 1.0) = 0.8;
// Brightness. Above 1.0 pushes the ring past its own colour toward white-hot.
uniform float border_gain : hint_range(0.0, 3.0) = 1.5;

group_uniforms halo;
// Soft spill PAST the ring (CSS box-shadow blur). `glow_width` is how far it
// reaches; 0 = a crisp ring with no spill.
uniform float glow_width : hint_range(0.0, 0.3) = 0.07;
uniform vec3 glow_color : source_color = vec3(0.08, 0.26, 1.0);
uniform float glow_alpha : hint_range(0.0, 1.0) = 0.5;

group_uniforms anim;
// Keeps the ring from aliasing where it meets the card edge.
uniform float edge_softness : hint_range(0.0, 0.02) = 0.0012;
// 0 = off. Driven by Card.set_highlight() for the fade, so do not tune it.
uniform float intensity : hint_range(0.0, 2.0) = 0.0;
// A quick, shallow shimmer — "live", not a light show. The cycle is
// 2*PI/pulse_speed (~1.4 s at 4.5).
uniform float pulse_speed : hint_range(0.0, 12.0) = 4.5;
// Depth of the BRIGHTNESS pulse. 1.0 = the ring fades out completely at the trough.
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;
// Depth of the WIDTH pulse, as a fraction of border_width. Allowed well past 1.0 so
// the ring can swell to several times its resting thickness.
uniform float pulse_width : hint_range(0.0, 3.0) = 0.18;
// Reference has a slightly brighter top edge. Signed; 0 = uniform.
uniform float top_bias : hint_range(-1.0, 1.0) = 0.0;

float sd_round_box(vec2 p, vec2 half_extent, float radius) {
	vec2 q = abs(p) - half_extent + vec2(radius);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

void fragment() {
	// Metres, centred on the quad: x across the card, y along its height.
	vec2 quad_size = card_size + vec2(margin) * 2.0;
	vec2 p = (UV - vec2(0.5)) * quad_size;

	// Signed distance to the card's rounded silhouette: > 0 outside it.
	float d = sd_round_box(p, card_size * 0.5, corner_radius);

	// Hard zero inside the card, ramping in just outside the edge.
	float softness = max(edge_softness, 0.00001);
	float outside = smoothstep(-softness, softness, d);
	float beyond = max(d, 0.0);

	// One wave drives both pulses: 0 = rest, 1 = fully swelled.
	float wave = 0.5 - 0.5 * cos(TIME * pulse_speed);
	// Width swells slightly; brightness swells with it (and dips at rest), so the
	// two never fight each other.
	float width_now = border_width * (1.0 + pulse_width * wave);
	float bright = 1.0 - pulse_amount * (1.0 - wave);

	// The ring: full strength from the card's edge out to width_now, then a
	// feather down to nothing. This is the CSS border-width.
	float feather = max(border_feather, 0.0005);
	float band = 1.0 - smoothstep(width_now - feather, width_now + feather, beyond);

	// Opacity falls off with DISTANCE from the card: fully solid where the ring
	// meets the edge, `border_alpha_far` where the feather takes over — so the
	// light thins as it moves outward instead of being a flat slab of colour.
	float across = clamp(beyond / max(width_now - feather, 0.0001), 0.0, 1.0);
	float band_alpha = mix(border_alpha, border_alpha_far, across);

	// Soft spill past the ring.
	float spill = max(beyond - width_now, 0.0);
	float halo = exp(-spill / max(glow_width, 0.0001));

	float alpha = max(band * band_alpha, halo * glow_alpha) * outside;
	// Trim before the quad's own edge. margin is sized to fit, so this only ever
	// removes the spill's last few percent.
	alpha *= 1.0 - smoothstep(margin * 0.75, margin, beyond);

	float height_axis = p.y / (card_size.y * 0.5);
	alpha *= 1.0 + top_bias * clamp(-height_axis, -1.0, 1.0);

	// Ring colour where the band is, spill colour outside it.
	ALBEDO = mix(glow_color, border_color, clamp(band, 0.0, 1.0)) * border_gain;
	ALPHA = clamp(alpha * intensity * bright, 0.0, 1.0);
}
