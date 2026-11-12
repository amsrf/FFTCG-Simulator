shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float opacity = 1.0;
uniform float phase = 0.0;
uniform bool mist = false;

void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float radius = length(p);
    float cloud = 0.75 + 0.13 * sin(p.x * 13.0 + phase) * sin(p.y * 11.0 - phase * 0.7)
        + 0.12 * sin(p.x * 23.0 + p.y * 17.0 + phase * 1.3);
    float haze = pow(max(0.0, 1.0 - radius), 2.0);
    float core = exp(-dot(p, p) * 32.0);
    ALBEDO = mist ? vec3(0.83, 0.94, 1.0) : mix(vec3(0.06, 0.50, 1.0), vec3(0.85, 0.98, 1.0), core);
    ALPHA = opacity * (mist ? haze * cloud : haze * 0.65 + core * 0.7);
}
