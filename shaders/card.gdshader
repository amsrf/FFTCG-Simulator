shader_type spatial;

// UNSHADED, DELIBERATELY. A card is artwork, not a surface: it should show the colours in the scan, not those
// colours multiplied by whatever the board's light and ambient happen to be doing. Lit, cards read washed out
// and pale beside the same card shown as a plain 2D texture in the hover preview — which is exactly how this
// was spotted.
//
// Nothing is lost by it. The meshes are still solid geometry, so tilt, overlap and stacking order are read from
// the shapes rather than from shading, and a card is the one thing on this board that is meant to be looked AT
// rather than lit. The trade is explicit: if the board ever wants cards to sit IN the light, delete this line.
render_mode unshaded;

uniform sampler2D texture_albedo : source_color;
uniform bool effect_enabled = false;

// ARTIFICIAL CARD-DEPTH SHADOW. Every overlapping card shades the one BELOW it along the edge where
// the upper card ends. This is not lighting: the shadow is deliberately constant, independent of
// the board light, and only darkens the covered card's own texture. Hand computes `shadow_edge`
// from the overlap and only turns it on for cards that are actually covered.
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float shadow_side = 1.0;          // +1: upper card is to the RIGHT; -1: to the LEFT
uniform float shadow_edge : hint_range(0.0, 1.0) = 0.0;
// The upper card is rotated independently of the lower one, so its edge is not a vertical
// line in the lower card's UV space. `shadow_slope` is du/dv; without it the shadow stays
// parallel to the LOWER card's edge and drifts away from the upper edge as it goes up.
uniform float shadow_slope = 0.0;
// The card mesh itself has rounded corners. A straight edge line would run through the
// corner and leave the shadow detached there, so the edge also curls inward over the last
// `shadow_corner_v` of the card height, by `shadow_corner_u` of its width.
uniform float shadow_corner_u = 0.0;
uniform float shadow_corner_v = 0.0;
uniform float shadow_width : hint_range(0.001, 0.30) = 0.055;

void fragment() {
    vec4 original_color = texture(texture_albedo, UV);
    vec3 base = original_color.rgb;
    if (effect_enabled && UV.y > 0.875) {
        base = vec3(0.1);
    }

    // Distance from the upper card's edge, going INWARD along the covered card. Negative means
    // the pixel is underneath the upper card and is not visible, so it receives no shadow.
    float edge_x = shadow_edge + shadow_slope * (UV.y - 0.5);
    // Rounded-corner curl. At the card middle the shift is zero; at either end it reaches
    // the corner radius and follows the quarter-ellipse of the upper card's silhouette.
    if (shadow_corner_v > 0.0001) {
        float q_top = clamp((shadow_corner_v - UV.y) / shadow_corner_v, 0.0, 1.0);
        float q_bottom = clamp((UV.y - (1.0 - shadow_corner_v)) / shadow_corner_v, 0.0, 1.0);
        float q = max(q_top, q_bottom);
        if (q > 0.0) {
            float shift = shadow_corner_u * (1.0 - sqrt(max(0.0, 1.0 - q * q)));
            edge_x += (shadow_side >= 0.0 ? shift : -shift);
        }
    }
    float d = shadow_side >= 0.0 ? edge_x - UV.x : UV.x - edge_x;
    // ANALYTIC EDGE ANTI-ALIASING. A hard `step(0.0, d)` puts the darkest part of the shadow
    // exactly on the upper card's rasterised silhouette, so any half-pixel mismatch between
    // the computed edge and that silhouette reads as a jagged seam. fwidth() gives the UV
    // change per screen pixel, so fading across one pixel hides the seam without making the
    // contact shadow visibly softer.
    float aa = max(fwidth(d), 0.00001);
    float visible = smoothstep(-aa, aa, d);
    float soft = exp(-d / max(shadow_width, 0.0001));
    float contact = exp(-d / max(shadow_width * 0.22, 0.0001));
    float shade = (contact * 0.42 + soft * 0.58) * visible * shadow_strength;
    shade = clamp(shade, 0.0, 0.82);

    ALBEDO = base * (1.0 - shade);
}