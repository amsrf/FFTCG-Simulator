shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 2.0;
uniform vec4 crack_color : source_color = vec4(0.018, 0.014, 0.01, 1.0);
float hash(float p) { return fract(sin(p * 127.1 + seed * 31.7) * 43758.5453); }
float segment_distance(vec2 p, vec2 a, vec2 b) {
    vec2 edge = b - a;
    float t = clamp(dot(p - a, edge) / max(dot(edge, edge), 0.00001), 0.0, 1.0);
    return length(p - a - edge * t);
}
// Shared junctions connect radial fractures into irregular ground slabs.
vec2 junction(float sector, float ring) {
    float index = mod(sector, 10.0);
    float angle = index * 6.2831853 / 10.0 + (hash(index + 1.0) - 0.5) * 0.32;
    angle += (hash(index + ring * 19.0 + 5.0) - 0.5) * 0.18;
    float radius = 0.28 + ring * 0.205 + (hash(index + ring * 31.0 + 21.0) - 0.5) * 0.11;
    return vec2(cos(angle), sin(angle)) * radius;
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float radial_distance = 1.0;
    float cross_distance = 1.0;
    for (int i = 0; i < 10; i++) {
        float index = float(i);
        vec2 a = junction(index, 0.0);
        vec2 b = junction(index, 1.0);
        vec2 c = junction(index, 2.0);
        vec2 d = junction(index, 3.0);
        radial_distance = min(radial_distance, min(segment_distance(p, a, b),
            min(segment_distance(p, b, c), segment_distance(p, c, d))));
        cross_distance = min(cross_distance, segment_distance(p, b, junction(index + 1.0, 1.0)));
        // Gaps in the outer ring keep the perimeter broken rather than circular.
        if (hash(index + 150.0) > 0.24) {
            cross_distance = min(cross_distance, segment_distance(p, c, junction(index + 1.0, 2.0)));
        }
    }
    float width = mix(0.009, 0.003, smoothstep(0.35, 0.95, length(p)));
    float aa = max(fwidth(radial_distance), 0.001);
    float core = 1.0 - smoothstep(width, width + aa, radial_distance);
    float cross_core = 1.0 - smoothstep(width * 0.8, width * 0.8 + aa, cross_distance);
    float distance_to_crack = min(radial_distance, cross_distance);
    float soft_edge = (1.0 - smoothstep(width, width + 0.018, distance_to_crack)) * 0.20;
    // Lose contrast across the entire exposed ground, not just at the perimeter.
    float edge_fade = pow(1.0 - smoothstep(0.22, 0.99, length(p)), 1.3);
    ALBEDO = crack_color.rgb;
    ALPHA = max(max(core, cross_core) * 0.78, soft_edge) * edge_fade * opacity * crack_color.a;
}
