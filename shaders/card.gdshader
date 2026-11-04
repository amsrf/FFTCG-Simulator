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

// TELEPORT PRESENTATION. Progress is a screen-door dissolve in card UV space:
// 0 is the normal card, 1 discards every pixel. Glow is a separate additive-ish
// brightening so the card can shine before/while it resolves. Defaults are
// neutral, so ordinary cards are untouched.
uniform float teleport_progress : hint_range(0.0, 1.0) = 0.0;
uniform float teleport_glow : hint_range(0.0, 1.0) = 0.0;
// 0 = the card is still a glowing silhouette; 1 = the artwork is visible.
// The destination stays at 0 until the build and glow beats finish, so the
// texture never flashes through a half-materialised card.
uniform float teleport_reveal : hint_range(0.0, 1.0) = 1.0;
// BSP depth for the block build. Every level can split a rectangle once, so
// the total is at most 2^depth pieces — but large pieces stop early, leaving
// coarse rectangles of different sizes instead of an even grid.
uniform float teleport_block_depth : hint_range(2.0, 7.0) = 7.0;
// Chance that a rectangle stops subdividing near the bottom of the tree. This
// is what makes the final sizes irregular rather than a balanced 2^depth tree;
// stopping only very late keeps the pieces small while still varying their size.
uniform float teleport_block_stop_chance : hint_range(0.0, 0.60) = 0.15;
// Group neighbouring blocks so they arrive as scattered clumps with gaps
// rather than as an even static threshold.
uniform float teleport_cluster_variation : hint_range(0.0, 0.40) = 0.24;
// Per-block jitter around the bottom-to-top arrival order.
uniform float teleport_scatter : hint_range(0.0, 0.45) = 0.28;
// TWO LAYERS. A pale-lavender underlayer starts at once and climbs slowly
// from the bottom. A white layer starts later but covers the same card faster,
// replacing the lavender blocks from below. Both finish on the last frame, so
// the completed silhouette is white and the lavender layer is underneath.
uniform vec4 teleport_hot_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 teleport_under_color : source_color = vec4(0.88, 0.72, 1.0, 1.0);
uniform float teleport_white_delay : hint_range(0.0, 0.90) = 0.32;
// The white overlay is a separate, coarser BSP. Its rectangles are larger than
// the lavender ones, so a single white block can cover several lavender tiles.
uniform float teleport_white_block_depth : hint_range(2.0, 7.0) = 6.0;
uniform float teleport_white_block_stop_chance : hint_range(0.0, 0.60) = 0.22;

float teleport_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One leaf of a deterministic BSP. `node` identifies the branch taken so far,
// so the same UV always resolves to the same rectangle and the whole card is
// partitioned exactly once. Splits always take the physically longer axis, so
// the leaves stay chunky instead of collapsing into thin slivers.
void teleport_rect(vec2 uv, float depth_limit, float stop_level, float stop_chance,
        float hash_offset, out vec2 rect_min, out vec2 rect_size, out vec2 node) {
    rect_min = vec2(0.0);
    rect_size = vec2(1.0);
    node = vec2(0.0);
    int max_depth = int(depth_limit);
    for (int i = 0; i < 7; i++) {
        if (i >= max_depth) {
            break;
        }
        float h = teleport_hash(node + vec2(float(i) * 1.37 + hash_offset, 5.19));
        if (float(i) >= stop_level && h < stop_chance) {
            break;
        }
        float h_axis = teleport_hash(node + vec2(11.3 + hash_offset, float(i) * 2.17));
        // Card UV is 1 x 1.4 on the mesh, so compare physical extents. This
        // keeps most leaves chunky rather than long thin strips.
        bool split_x = rect_size.x * 0.715 >= rect_size.y;
        if (abs(rect_size.x * 0.715 - rect_size.y) < 0.10) {
            split_x = h_axis < 0.5;
        }
        float ratio = mix(0.34, 0.66, fract(h * 6.2831 + h_axis));
        if (split_x) {
            if (uv.x < rect_min.x + rect_size.x * ratio) {
                rect_size.x *= ratio;
                node = node * 2.0 + vec2(0.0, 1.0);
            } else {
                rect_min.x += rect_size.x * ratio;
                rect_size.x *= (1.0 - ratio);
                node = node * 2.0 + vec2(1.0, 1.0);
            }
        } else {
            if (uv.y < rect_min.y + rect_size.y * ratio) {
                rect_size.y *= ratio;
                node = node * 2.0 + vec2(0.0, 0.0);
            } else {
                rect_min.y += rect_size.y * ratio;
                rect_size.y *= (1.0 - ratio);
                node = node * 2.0 + vec2(0.0, 1.0);
            }
        }
    }
}

void fragment() {
    // PIXEL DISSOLVE. Kept as discard rather than alpha blending: the card
    // stays opaque wherever it exists, which avoids transparent-card sorting
    // against the board and matches the blocky materialisation in the reference.
    // The block tint has to survive the glow/reveal beats, so evaluate the BSP
    // leaf whenever the teleport is visible, not only while something is being
    // discarded. A normal card (progress and glow both zero) skips this.
    vec3 block_color = teleport_hot_color.rgb;
    if (teleport_progress > 0.0001 || teleport_glow > 0.001) {
        vec2 rect_min;
        vec2 rect_size;
        vec2 node;
        teleport_rect(UV, teleport_block_depth, 6.0, teleport_block_stop_chance, 0.0,
            rect_min, rect_size, node);
        if (teleport_progress > 0.0001) {
            if (teleport_progress >= 0.999) {
                discard;
            }
            // BOTTOM-TO-TOP BUILD. Card UV y=1 is the bottom edge, so the
            // bottom blocks have the lowest arrival value and appear first.
            // The whole leaf is included or absent, keeping the pieces
            // rectangular; scatter/cluster only break up the horizontal rows.
            vec2 rect_uv = rect_min + rect_size * 0.5;
            vec2 cluster = floor(rect_uv * vec2(11.0, 15.0));
            float cluster_bias = (teleport_hash(cluster) - 0.5) * teleport_cluster_variation;
            float vertical = 1.0 - rect_uv.y;
            float arrival = clamp(
                vertical + (teleport_hash(node + vec2(41.7, 13.1)) - 0.5) * teleport_scatter + cluster_bias,
                0.0, 1.0);

            // WHITE OVERLAY. It is its own coarser BSP, so a white rectangle
            // covers several lavender tiles. Its arrival uses the same chaotic
            // bottom-to-top formula as the lavender layer, just delayed and
            // normalized faster.
            vec2 white_min;
            vec2 white_size;
            vec2 white_node;
            teleport_rect(UV, teleport_white_block_depth, 4.0, teleport_white_block_stop_chance, 19.7,
                white_min, white_size, white_node);
            vec2 white_uv = white_min + white_size * 0.5;
            vec2 white_cluster = floor(white_uv * vec2(11.0, 15.0));
            float white_cluster_bias = (teleport_hash(white_cluster + vec2(17.0, 31.0)) - 0.5)
                * teleport_cluster_variation;
            float white_arrival = clamp(
                1.0 - white_uv.y
                + (teleport_hash(white_node + vec2(59.1, 83.7)) - 0.5) * teleport_scatter
                + white_cluster_bias,
                0.0, 1.0);

            float built = 1.0 - teleport_progress;
            float white_built = clamp(
                (built - teleport_white_delay) / max(1.0 - teleport_white_delay, 0.001),
                0.0, 1.0);
            if (arrival > built) discard;
            block_color = (white_arrival <= white_built)
                ? teleport_hot_color.rgb
                : teleport_under_color.rgb;
        }
    }
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

    vec3 art = base * (1.0 - shade);
    // The build is pure silhouette. During the final reveal the artwork is
    // mixed in progressively as the glow falls, rather than popping on at 1.
    // `block_color` keeps the chosen tint while the glow brightens it.
    vec3 silhouette = block_color * (0.55 + teleport_glow * 0.85);
    vec3 shaded = mix(silhouette, art, teleport_reveal);
    if (teleport_reveal < 0.9999) {
        shaded = mix(shaded, block_color, teleport_glow * 0.20);
    }
    ALBEDO = shaded;
}