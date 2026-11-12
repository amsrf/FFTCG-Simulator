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
// CRYSTAL TILES. The squares are drawn as small cut gems in the card's element colour instead of flat white/lavender:
// each white-layer rectangle is four facets meeting at an off-centre peak, every facet catching the (made-up) light at
// its own angle, with bright creases and borders. The lavender underlayer is the same, darker. Off = the plain squares.
uniform bool teleport_crystal = false;
uniform vec4 teleport_crystal_tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);
// Build direction for both layers: true fills from the card's top edge down, false from the bottom up.
uniform bool teleport_build_from_top = true;
// CRYSTAL TRIANGLES. With teleport_crystal on, the card is composed of triangles instead of BSP rectangles: a jittered
// lattice (shared corners, so the triangles tile the card exactly, but no two are alike), each cell split along a random
// diagonal. Two lattices, as with the squares: a FINE lavender-tinted underlayer that starts at once and climbs slowly,
// and a COARSER element-tinted layer that starts later, climbs faster and catches up, so it is what the finished
// silhouette shows (and what CardCrystallize breaks into shards - it rebuilds the same lattice on the CPU, which is why
// the lattice uses the integer tri_pcg hash: identical on the GPU and in GDScript).
uniform int teleport_tri_cols : hint_range(2, 16) = 8;
uniform int teleport_tri_rows : hint_range(2, 22) = 11;
uniform int teleport_white_tri_cols : hint_range(2, 16) = 5;
uniform int teleport_white_tri_rows : hint_range(2, 22) = 7;
// How far each lattice corner wanders from its grid point, in cells. Edge corners slide only along the card edge.
uniform float teleport_tri_jitter : hint_range(0.0, 0.40) = 0.30;
// Each triangle GROWS out from its peak to its edges over this fraction of the build (instead of popping in whole),
// flashing as it lands.
uniform float teleport_tri_grow : hint_range(0.01, 0.60) = 0.38;

// PCG2D (Jarzynski and Olano): integer-only, so card_crystallize.gd reproduces it bit for bit.
uvec2 tri_pcg(uvec2 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    v.x += v.y * 1664525u;
    v.y += v.x * 1664525u;
    v = v ^ (v >> 16u);
    return v;
}

vec2 tri_rand(int x, int y, int salt) {
    uvec2 h = tri_pcg(uvec2(uint(x + 4096 * salt), uint(y)));
    return vec2(h) / 4294967295.0;
}

vec2 tri_vertex(int i, int j, int cols, int rows, int salt) {
    vec2 jit = (tri_rand(i, j, salt) - 0.5) * 2.0 * teleport_tri_jitter;
    if (i == 0 || i == cols) { jit.x = 0.0; }
    if (j == 0 || j == rows) { jit.y = 0.0; }
    return (vec2(float(i), float(j)) + jit) / vec2(float(cols), float(rows));
}

vec3 tri_bary(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 v0 = b - a;
    vec2 v1 = c - a;
    vec2 v2 = p - a;
    float d = v0.x * v1.y - v1.x * v0.y;
    float l1 = (v2.x * v1.y - v1.x * v2.y) / d;
    float l2 = (v0.x * v2.y - v2.x * v0.y) / d;
    return vec3(1.0 - l1 - l2, l1, l2);
}

// The lattice triangle containing `uv`: its corners, the pixel's barycentrics and an id (cell * 2 + half, row).
// Jitter < half a cell, so it is always in the 3x3 cells around the pixel's grid cell; the triangle with the largest
// minimum barycentric is the one that contains it (or, on a hairline crack, the nearest).
void tri_locate(vec2 uv, int cols, int rows, int salt, out vec2 a, out vec2 b, out vec2 c, out vec3 bary,
        out vec2 id) {
    ivec2 base = ivec2(floor(uv * vec2(float(cols), float(rows))));
    float best = -1e9;
    a = vec2(0.0); b = vec2(0.0); c = vec2(0.0); bary = vec3(0.0); id = vec2(0.0);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int cx = base.x + dx;
            int cy = base.y + dy;
            if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) { continue; }
            vec2 v00 = tri_vertex(cx, cy, cols, rows, salt);
            vec2 v10 = tri_vertex(cx + 1, cy, cols, rows, salt);
            vec2 v01 = tri_vertex(cx, cy + 1, cols, rows, salt);
            vec2 v11 = tri_vertex(cx + 1, cy + 1, cols, rows, salt);
            bool diag = tri_rand(cx, cy, salt + 7).x < 0.5;
            for (int k = 0; k < 2; k++) {
                vec2 p0 = diag ? v00 : (k == 0 ? v00 : v10);
                vec2 p1 = diag ? (k == 0 ? v10 : v11) : (k == 0 ? v10 : v11);
                vec2 p2 = diag ? (k == 0 ? v11 : v01) : v01;
                vec3 l = tri_bary(uv, p0, p1, p2);
                float m = min(l.x, min(l.y, l.z));
                if (m > best) {
                    best = m;
                    a = p0; b = p1; c = p2; bary = l;
                    id = vec2(float(cx * 2 + k), float(cy));
                }
            }
        }
    }
}

// When a triangle arrives (0..1 of the build): ordered by height, broken up by per-triangle scatter and by clusters
// of neighbours arriving together - ordered chaos, as with the squares.
float tri_arrival(vec2 centre, vec2 id, int salt) {
    float vertical = teleport_build_from_top ? centre.y : 1.0 - centre.y;
    vec2 cl = floor(centre * vec2(5.0, 7.0));
    float cluster_bias = (tri_rand(int(cl.x), int(cl.y), salt + 31).x - 0.5) * teleport_cluster_variation;
    float scatter = (tri_rand(int(id.x), int(id.y), salt + 13).x - 0.5) * teleport_scatter;
    return clamp(vertical + scatter + cluster_bias, 0.0, 1.0);
}

// The triangle's off-centre peak, as barycentrics (the same per triangle wherever it is evaluated).
vec3 tri_peak(vec2 id, int salt) {
    vec2 r = tri_rand(int(id.x), int(id.y), salt + 21) - 0.5;
    return vec3(1.0 / 3.0) + vec3(r.x, r.y, -r.x - r.y) * 0.30;
}

// 0 on the triangle's border, 1 at its peak: how far "in" the pixel is. Growth reveals q >= 1 - grown.
float tri_depth(vec3 l, vec2 id, int salt) {
    vec3 q = l / tri_peak(id, salt);
    return min(q.x, min(q.y, q.z));
}

// One gem triangle: three facets meeting at an off-centre peak, each catching the light at its own angle, with
// bright creases and border. Barycentric trick: with the peak at barycentric m, the pixel is on the facet facing the
// edge opposite the corner with the smallest l_i / m_i, and that ratio is 0 on the border, 1 at the peak.
vec3 crystal_tri(vec2 a, vec2 b, vec2 c, vec3 l, vec2 id, int salt, vec3 normal, vec3 view, vec3 tint) {
    vec3 m = tri_peak(id, salt);
    vec3 q = l / m;
    int f = (q.x <= q.y && q.x <= q.z) ? 0 : ((q.y <= q.z) ? 1 : 2);
    float q1 = f == 0 ? q.x : (f == 1 ? q.y : q.z);
    float q2 = f == 0 ? min(q.y, q.z) : (f == 1 ? min(q.x, q.z) : min(q.x, q.y));
    vec2 peak = m.x * a + m.y * b + m.z * c;
    vec2 mid = f == 0 ? (b + c) * 0.5 : (f == 1 ? (a + c) * 0.5 : (a + b) * 0.5);
    vec2 out_dir = normalize((mid - peak) * vec2(1.0, 1.4) + vec2(1e-5));   // physical: the card is 1 x 1.4
    vec2 slope = vec2(out_dir.x, -out_dir.y);                               // UV y runs down, view y up
    vec2 lean = (tri_rand(int(id.x), int(id.y), salt + 23) - 0.5) * 0.8;
    vec3 n = normalize(normal + vec3(slope * 0.70 + lean * 0.40, 0.0));
    vec3 rv = reflect(-view, n);
    float key = pow(max(dot(rv, normalize(vec3(0.45, 0.55, 0.70))), 0.0), 10.0);
    float fill = pow(max(dot(rv, normalize(vec3(-0.65, 0.25, 0.70))), 0.0), 5.0);
    float rim = pow(max(dot(rv, normalize(vec3(0.05, -0.75, 0.65))), 0.0), 7.0);
    vec3 deep = tint * 0.18;
    vec3 bright = mix(tint, vec3(1.0), 0.70);
    vec3 col = mix(deep, tint * 0.85, clamp(0.5 + 0.5 * rv.y + 0.35 * rv.x, 0.0, 1.0));
    col += bright * (key * 1.8 + fill * 0.55 + rim * 0.45);
    // Facets are a touch brighter toward the peak, so each triangle reads as raised.
    col *= mix(0.85, 1.12, clamp(q1, 0.0, 1.0));
    float crease = q2 - q1;
    float line = max(1.0 - smoothstep(0.0, fwidth(crease) * 1.2, crease),
        1.0 - smoothstep(0.0, fwidth(q1) * 1.4, q1));
    // Only a hint of the creases: these triangles are the floor under the real crystals (card_crystallize.gd),
    // and drawn outlines there read as white wire between them.
    col += bright * line * 0.10;
    return col;
}

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
    bool block_under = false;
    float tri_flash = 0.0;
    if (teleport_crystal && (teleport_progress > 0.0001 || teleport_glow > 0.001)) {
        vec2 la; vec2 lb; vec2 lc; vec3 ll; vec2 lid;
        tri_locate(UV, teleport_tri_cols, teleport_tri_rows, 1, la, lb, lc, ll, lid);
        vec2 wa; vec2 wb; vec2 wc; vec3 wl; vec2 wid;
        tri_locate(UV, teleport_white_tri_cols, teleport_white_tri_rows, 2, wa, wb, wc, wl, wid);
        if (teleport_progress > 0.0001) {
            if (teleport_progress >= 0.999) {
                discard;
            }
            float arrival = tri_arrival((la + lb + lc) / 3.0, lid, 1);
            float white_arrival = tri_arrival((wa + wb + wc) / 3.0, wid, 2);
            float built = 1.0 - teleport_progress;
            // The element layer starts late and is normalised faster, so it catches up by the end.
            float white_built = clamp((built - teleport_white_delay) / max(1.0 - teleport_white_delay, 0.001),
                0.0, 1.0);
            // Grow from the peak outward rather than pop in: a pixel appears once the growth passes its depth.
            // Arrivals are squeezed into the first (1 - grow) of the build, so even the last triangle has its full
            // growth time and is whole when the build ends. Eased: quick to sprout, settling into its edges.
            float squeeze = 1.0 - teleport_tri_grow;
            float grown = smoothstep(0.0, 1.0, clamp((built - arrival * squeeze) / teleport_tri_grow, 0.0, 1.0));
            if (tri_depth(ll, lid, 1) < 1.0 - grown) discard;
            float white_grown = smoothstep(0.0, 1.0,
                clamp((white_built - white_arrival * squeeze) / teleport_tri_grow, 0.0, 1.0));
            block_under = tri_depth(wl, wid, 2) < 1.0 - white_grown;
            tri_flash = 1.0 - (block_under ? grown : white_grown);
        }
        vec3 nrm = normalize(NORMAL);
        vec3 eye = normalize(VIEW);
        block_color = block_under
            ? crystal_tri(la, lb, lc, ll, lid, 1, nrm, eye,
                mix(teleport_crystal_tint.rgb, teleport_under_color.rgb, 0.55)) * 0.62
            : crystal_tri(wa, wb, wc, wl, wid, 2, nrm, eye, teleport_crystal_tint.rgb);
        // A landing flash: bright while a triangle is still growing, gone once it is whole.
        block_color += mix(teleport_crystal_tint.rgb, vec3(1.0), 0.6) * tri_flash * tri_flash * 0.9;
    } else if (teleport_progress > 0.0001 || teleport_glow > 0.001) {
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
            float vertical = teleport_build_from_top ? rect_uv.y : 1.0 - rect_uv.y;
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
                (teleport_build_from_top ? white_uv.y : 1.0 - white_uv.y)
                + (teleport_hash(white_node + vec2(59.1, 83.7)) - 0.5) * teleport_scatter
                + white_cluster_bias,
                0.0, 1.0);

            float built = 1.0 - teleport_progress;
            float white_built = clamp(
                (built - teleport_white_delay) / max(1.0 - teleport_white_delay, 0.001),
                0.0, 1.0);
            if (arrival > built) discard;
            block_under = white_arrival > white_built;
            block_color = block_under
                ? teleport_under_color.rgb
                : teleport_hot_color.rgb;
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
    vec3 silhouette = teleport_crystal
        ? block_color * (0.85 + teleport_glow * 0.75)
        : block_color * (0.55 + teleport_glow * 0.85);
    vec3 shaded = mix(silhouette, art, teleport_reveal);
    if (teleport_reveal < 0.9999) {
        shaded = mix(shaded, block_color, teleport_glow * 0.20);
    }
    ALBEDO = shaded;
}