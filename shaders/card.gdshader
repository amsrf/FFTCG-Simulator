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

// Full rounded-card silhouettes, traced in world space toward the camera.
// Four strongest nearby casters per receiver. Pixel depth rejects surfaces behind it.
uniform vec3 shadow_camera;
uniform vec3 shadow_direction = vec3(0.0, 1.0, 0.0);
uniform bool shadow_orthographic = false;
varying vec3 shadow_world;
uniform mat4 shadow_inverse;
uniform vec3 shadow_shape = vec3(0.2145, 0.3, 0.03);
uniform float shadow_strength = 0.0;
uniform float shadow_width = 0.02;
uniform mat4 shadow2_inverse;
uniform vec3 shadow2_shape = vec3(0.2145, 0.3, 0.03);
uniform float shadow2_strength = 0.0;
uniform float shadow2_width = 0.02;
uniform mat4 shadow3_inverse;
uniform vec3 shadow3_shape = vec3(0.2145, 0.3, 0.03);
uniform float shadow3_strength = 0.0;
uniform float shadow3_width = 0.02;
uniform mat4 shadow4_inverse;
uniform vec3 shadow4_shape = vec3(0.2145, 0.3, 0.03);
uniform float shadow4_strength = 0.0;
uniform float shadow4_width = 0.02;

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


void vertex() {
    shadow_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float card_silhouette_shadow(mat4 caster_inverse, vec3 shape, float strength, float softness) {
    if (strength <= 0.0) { return 0.0; }
    vec3 ray_world = shadow_orthographic ? shadow_direction : normalize(shadow_camera - shadow_world);
    vec3 point = (caster_inverse * vec4(shadow_world, 1.0)).xyz;
    vec3 ray = (caster_inverse * vec4(ray_world, 0.0)).xyz;
    if (abs(ray.y) < 0.00001) { return 0.0; }
    float travel = -point.y / ray.y;
    if (travel <= 0.00001) { return 0.0; }
    vec3 hit = point + ray * travel;
    float radius = min(shape.z, min(shape.x, shape.y));
    vec2 q = abs(hit.xz) - (shape.xy - vec2(radius));
    float distance_to_card = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float aa = max(fwidth(distance_to_card), 0.00001);
    float outside = smoothstep(-aa, aa, distance_to_card);
    float d = max(distance_to_card, 0.0);
    float soft = exp(-d / max(softness, 0.0001));
    float contact = exp(-d / max(softness * 0.22, 0.0001));
    return (contact * 0.42 + soft * 0.58) * outside * strength;
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

    float shade = card_silhouette_shadow(shadow_inverse, shadow_shape, shadow_strength, shadow_width);
    shade = max(shade, card_silhouette_shadow(shadow2_inverse, shadow2_shape, shadow2_strength, shadow2_width));
    shade = max(shade, card_silhouette_shadow(shadow3_inverse, shadow3_shape, shadow3_strength, shadow3_width));
    shade = max(shade, card_silhouette_shadow(shadow4_inverse, shadow4_shape, shadow4_strength, shadow4_width));
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