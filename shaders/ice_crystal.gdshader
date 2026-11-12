shader_type spatial;
render_mode unshaded, cull_back;

// CUT CRYSTAL, NOT FROSTED GLASS.
//
// The first version ported a Blender Cycles ice material. Cycles gets its look from light bouncing INSIDE the volume,
// which no real-time renderer has, so the port came out as evenly lit blue plastic. A crystal reads as a crystal for
// four reasons, and each is faked directly here:
//
//   1. FACET CONTRAST   every flat face mirrors a different part of a (made-up) bright studio, so neighbours jump from
//                       near-white to deep blue across an edge. The mesh keeps flat normals for exactly this.
//   2. INNER FACETS     looking into a crystal you see its back faces and flaws, broken into angular patches. Two
//                       layers of stretched Voronoi cells, each tilted its own way, are sampled a little way INSIDE
//                       the surface along the bent view ray, so they slide against each other as the piece turns.
//   3. BRIGHT EDGES     a cut edge catches light. The mesh marks its hard edges in the vertex colour (see
//                       ice_projectile.gd), and they are drawn as thin highlights.
//   4. REFRACTION       each facet bends what is behind it by its own amount, so the background breaks at every edge.
//
// The scene's own lights are ignored (unshaded): the look has to hold on the dark board and in the grey demo alike.
// Values above 1.0 are deliberate — they are what the board's glow picks up.

uniform vec4 deep_color : source_color = vec4(0.015, 0.11, 0.36, 1.0);
uniform vec4 body_color : source_color = vec4(0.10, 0.50, 0.92, 1.0);
uniform vec4 bright_color : source_color = vec4(0.72, 0.93, 1.0, 1.0);
/// How many inner cells across the crystal, and how stretched along its length (a needle-like grain).
uniform float grain_scale = 12.0;
uniform float grain_stretch = 0.30;
/// How strongly each inner cell tilts away from the outer face. 0 = clear glass, 1 = shattered.
uniform float grain_tilt : hint_range(0.0, 1.0) = 0.70;
uniform float edge_brightness : hint_range(0.0, 3.0) = 1.0;
uniform float sparkle : hint_range(0.0, 4.0) = 2.4;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.07;
/// How much of the background shows through the dark parts.
uniform float transparency : hint_range(0.0, 1.0) = 0.42;
uniform float exposure = 1.0;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform bool show_interior = false;
uniform float materialize : hint_range(0.0, 1.0) = 1.0;
uniform vec3 mesh_origin = vec3(0.0);
varying vec3 ice_position;

vec3 hash33(vec3 p) {
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
    return fract(sin(p) * 43758.5453);
}
float noise3(vec3 p) {
    vec3 c = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash33(c).x, hash33(c + vec3(1,0,0)).x, f.x),
                   mix(hash33(c + vec3(0,1,0)).x, hash33(c + vec3(1,1,0)).x, f.x), f.y),
               mix(mix(hash33(c + vec3(0,0,1)).x, hash33(c + vec3(1,0,1)).x, f.x),
                   mix(hash33(c + vec3(0,1,1)).x, hash33(c + vec3(1,1,1)).x, f.x), f.y), f.z);
}

// Nearest Voronoi cell: xyz = that cell's own random direction, w = distance to the cell border (0 on a border).
vec4 grain(vec3 p) {
    // Sheared so the cells do not line up with the crystal's axis, then squashed so they run along it.
    p.xz += p.y * vec2(0.37, -0.23);
    p *= vec3(grain_scale, grain_scale * grain_stretch, grain_scale);
    vec3 base = floor(p);
    vec3 f = fract(p);
    float d1 = 8.0;
    float d2 = 8.0;
    vec3 id = vec3(0.0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            for (int z = -1; z <= 1; z++) {
                vec3 o = vec3(float(x), float(y), float(z));
                vec3 h = hash33(base + o);
                vec3 r = o + h - f;
                float d = dot(r, r);
                if (d < d1) { d2 = d1; d1 = d; id = h; } else if (d < d2) { d2 = d; }
            }
        }
    }
    return vec4(normalize(id * 2.0 - 1.0), sqrt(d2) - sqrt(d1));
}

// The made-up studio every facet mirrors: dark below, blue above, three hard lights and a pale band. World space, so
// the reflections travel across the crystal as it turns.
vec3 studio(vec3 r) {
    vec3 c = mix(deep_color.rgb, body_color.rgb, smoothstep(-0.55, 0.75, r.y));
    float key = pow(max(dot(r, normalize(vec3(0.35, 0.80, 0.45))), 0.0), 9.0);
    float fill = pow(max(dot(r, normalize(vec3(-0.75, 0.20, 0.45))), 0.0), 6.0);
    float back = pow(max(dot(r, normalize(vec3(0.15, -0.35, -0.90))), 0.0), 7.0);
    float side = pow(max(dot(r, normalize(vec3(-0.30, 0.55, -0.75))), 0.0), 8.0);
    float band = smoothstep(0.50, 0.75, sin(r.x * 4.0 + r.y * 6.0 - r.z * 3.0));
    c += bright_color.rgb * sparkle * (key + fill * 0.50 + back * 0.35 + side * 0.60);
    c += mix(body_color.rgb, bright_color.rgb, 0.5) * band * 0.50;
    return c;
}

void vertex() {
    ice_position = VERTEX + mesh_origin;
}

void fragment() {
    bool cut_face = COLOR.r > 0.5;
    if (!show_interior && cut_face) { discard; }
    float reveal_edge = (1.0 - materialize) * 1.85 - 0.10;
    float reveal_distance = ice_position.y - reveal_edge + (noise3(ice_position * 18.0) - 0.5) * 0.075;
    if (materialize <= 0.0 || reveal_distance < 0.0) { discard; }

    mat3 model = mat3(MODEL_MATRIX);
    vec3 n_view = normalize(NORMAL);
    vec3 v_view = normalize(VIEW);
    vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
    vec3 v_world = normalize((INV_VIEW_MATRIX * vec4(v_view, 0.0)).xyz);
    // World -> object by the transposed rotation (uniform scale only), so the grain is glued to the piece.
    vec3 n_obj = normalize(n_world * model);
    vec3 v_obj = normalize(v_world * model);
    float facing = clamp(dot(n_view, v_view), 0.0, 1.0);
    float fresnel = 0.06 + 0.94 * pow(1.0 - facing, 4.0);

    vec3 color;
    vec2 bend = n_view.xy;
    if (cut_face) {
        // A BROKEN face is rough and white, not cut: packed frost with a few glints.
        vec4 g = grain(ice_position * 2.5);
        vec3 rough_n = normalize(n_world + model * g.xyz * 0.8);
        color = mix(studio(reflect(-v_world, rough_n)), bright_color.rgb, 0.72) * (0.92 + 0.25 * g.w);
    } else {
        // 1. the outer face, a mirror.
        vec3 surface = studio(reflect(-v_world, n_world));
        // 2. two inner layers, each further along the view ray as it bends into the crystal.
        vec3 into = normalize(-v_obj - n_obj * 0.45);
        vec4 near = grain(ice_position + into * 0.05);
        vec4 far = grain((ice_position + into * 0.16) * 0.62 + vec3(3.1, 7.7, 1.3));
        vec3 near_n = normalize(mix(n_world, model * near.xyz, grain_tilt));
        vec3 far_n = normalize(mix(n_world, model * far.xyz, grain_tilt));
        vec3 inner = studio(reflect(-v_world, near_n)) * 0.75
            + studio(reflect(-v_world, far_n)) * mix(body_color.rgb, vec3(1.0), 0.35) * 0.60;
        // Flaws: a thin pale line where two near cells meet.
        float flaw = 1.0 - smoothstep(0.0, 0.035, near.w);
        inner += bright_color.rgb * flaw * 0.35;
        // 4. what is behind, bent by this facet and by its grain.
        bend += (VIEW_MATRIX * vec4(model * near.xyz, 0.0)).xy * 0.35;
        vec2 uv = clamp(SCREEN_UV - bend * refraction_strength, vec2(0.005), vec2(0.995));
        vec3 behind = texture(scene_color, uv).rgb * mix(body_color.rgb, vec3(1.0), 0.45);
        // Dark inner patches are the clear ones: that is where the background shows.
        float inner_light = clamp(dot(inner, vec3(0.333)), 0.0, 1.0);
        vec3 body = inner + behind * transparency * (1.0 - inner_light);
        color = mix(body, surface, fresnel);
        // 3. cut edges. COLOR.gba fall to 0 on the hard edges of this triangle only.
        float e = min(min(COLOR.g, COLOR.b), COLOR.a);
        float width = fwidth(e);
        float line = 1.0 - smoothstep(width * 0.2, width * 1.2, e);
        float bevel = exp(-e * 30.0);
        color += bright_color.rgb * edge_brightness * (line * 0.80 + bevel * 0.22) * (0.35 + 0.65 * inner_light + fresnel);
        // A cold rim so the silhouette never melts into a dark board.
        color += body_color.rgb * pow(1.0 - facing, 3.0) * 0.6;
    }
    // The conjuring front: a white-hot line where the crystal is still forming.
    color += vec3(0.35, 0.85, 1.0) * 2.5 * (1.0 - smoothstep(0.0, 0.075, reveal_distance)) * (1.0 - step(0.999, materialize));
    ALBEDO = color * exposure;
}
