shader_type spatial;
// An expanding ring of light: the impact shockwave when a card absorbs a payment orb.
//
// Deliberately the same family as the orb's halo — additive, unshaded, radial, drawn on a quad over whatever is behind
// it — but an ANNULUS instead of a disc. That difference carries the meaning: a filled halo says "there is light here";
// a ring says "something hit here, and it is spreading".
//
// CLIPPED TO THE CARD'S SILHOUETTE, not to the quad. The ring must not spill past the card's edge, and a quad the
// shape of the card would both make the ring an ellipse and cut it off along straight lines — visibly wrong at the
// card's rounded corners. So the quad is SQUARE, covering the card's longer side, and a rounded-rectangle SDF masks
// the ring to the card's actual outline. `card_half` is the card's half-extents in quad units, which is what makes the
// mask the card's shape rather than the quad's.
//
// The radius is a uniform rather than a shader-side animation so the caller can tween it, which keeps the timing in one
// place next to the punch that accompanies it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 2.0;
// Distance from the impact point, in the same units as card_half: 0 at the centre, card_half at the card's edge.
uniform float ring_radius : hint_range(0.0, 1.0) = 0.06;
uniform float ring_width : hint_range(0.002, 0.4) = 0.05;
uniform float edge_softness : hint_range(0.001, 0.2) = 0.02;
// The card's half-width and half-height, in quad units. The mask is built from this.
uniform vec2 card_half = vec2(0.36, 0.5);
uniform float corner_radius : hint_range(0.0, 0.4) = 0.06;

// The usual rounded-box signed distance, in 2D.
float sd_round_box(vec2 p, vec2 half_extent, float radius) {
	vec2 d = abs(p) - (half_extent - vec2(radius));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

void fragment() {
	// -0.5 .. 0.5 across the square quad, so the ring is a true circle on the card rather than an ellipse.
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	float band = 1.0 - smoothstep(ring_width, ring_width + edge_softness, abs(r - ring_radius));
	// The card's own outline: anything outside it contributes nothing, so the ring is cut by the silhouette instead of
	// by the quad.
	float inside = 1.0 - smoothstep(-0.004, 0.004, sd_round_box(p, card_half, corner_radius));
	// Fade out as it nears the edge, so the ring is spent rather than truncated.
	float spent = 1.0 - smoothstep(0.7, 1.0, r / max(max(card_half.x, card_half.y), 0.001));
	float a = clamp(band * inside * spent, 0.0, 1.0);
	ALBEDO = ring_color.rgb * intensity * a;
	ALPHA = a;
}
