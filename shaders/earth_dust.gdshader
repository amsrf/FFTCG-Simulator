shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

uniform vec4 dust_color : source_color = vec4(0.88, 0.86, 0.81, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.95;
uniform float edge_softness : hint_range(0.01, 0.3) = 0.07;
varying float puff_phase;
varying float puff_age;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
               mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
    float angle = INSTANCE_CUSTOM.x;
    float c = cos(angle);
    float s = sin(angle);
    vec2 local = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y);
    vec3 world = MODEL_MATRIX[3].xyz
        + INV_VIEW_MATRIX[0].xyz * local.x * length(MODEL_MATRIX[0].xyz)
        + INV_VIEW_MATRIX[1].xyz * local.y * length(MODEL_MATRIX[1].xyz);
    VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
    puff_phase = angle * 2.3;
    puff_age = INSTANCE_CUSTOM.y;
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float angle = atan(p.y, p.x);
    float radius = 0.72 + 0.08 * sin(angle * 5.0 + puff_phase)
                        + 0.05 * sin(angle * 9.0 - puff_phase);
    float detail = noise(p * 3.4 + vec2(puff_phase, puff_age * 0.45));
    float distance_to_puff = length(p) - radius - (detail - 0.5) * 0.10;
    float edge = max(edge_softness, fwidth(distance_to_puff));
    float mask = 1.0 - smoothstep(-edge, edge, distance_to_puff);
    float volume = 0.84 + 0.16 * noise(p * 2.0 + vec2(puff_phase));
    ALBEDO = dust_color.rgb * COLOR.rgb * volume;
    ALPHA = mask * COLOR.a * dust_color.a * opacity;
}
