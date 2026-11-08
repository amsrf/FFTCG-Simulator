shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

// Tutorial palette in sRGB; source_color converts it for the renderer.
uniform vec4 frost_color : source_color = vec4(0.831373, 0.929412, 1.0, 1.0);
uniform vec4 clear_color : source_color = vec4(0.317647, 0.674510, 1.0, 1.0);
uniform float frost_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float clear_roughness : hint_range(0.0, 1.0) = 0.2;
uniform float noise_scale = 15.0;
uniform float noise_roughness = 0.8;
uniform float ramp_white = 0.751;
uniform float curve_peak_x = 0.5025;
uniform float curve_peak_y = 0.6821;
uniform float ice_ior = 1.5;
uniform float ambient_fill : hint_range(0.0, 0.5) = 0.22;
uniform float frost_contrast : hint_range(0.0, 1.0) = 0.25;
uniform float blue_tint_strength : hint_range(0.0, 1.0) = 0.45;
uniform float refraction_strength : hint_range(0.0, 0.04) = 0.008;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform bool show_interior = false;
uniform vec3 mesh_origin = vec3(0.0);
varying vec3 ice_position;

float hash3(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float noise3(vec3 p) {
    vec3 c = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(c), hash3(c + vec3(1,0,0)), f.x),
                   mix(hash3(c + vec3(0,1,0)), hash3(c + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash3(c + vec3(0,0,1)), hash3(c + vec3(1,0,1)), f.x),
                   mix(hash3(c + vec3(0,1,1)), hash3(c + vec3(1,1,1)), f.x), f.y), f.z);
}
float frost_mix(vec3 p) {
    float total = 0.0;
    float weights = 0.0;
    float weight = 1.0;
    // Base octave + ten levels of detail; screen footprint filters tiny octaves.
    float footprint = max(length(dFdx(p)), length(dFdy(p)));
    for (int octave = 0; octave < 11; octave++) {
        float visibility = 1.0 - smoothstep(0.25, 0.75, footprint);
        total += mix(0.5, noise3(p), visibility) * weight;
        weights += weight;
        weight *= noise_roughness;
        p *= 2.0;
        footprint *= 2.0;
    }
    float x = clamp(total / weights / ramp_white, 0.0, 1.0);
    // Smooth arch approximation to Blender's automatic RGB Curve handles.
    float t = x < curve_peak_x ? x / curve_peak_x : (1.0 - x) / (1.0 - curve_peak_x);
    return curve_peak_y * (2.0 * t - t * t);
}
void vertex() {
    ice_position = VERTEX + mesh_origin;
}
void fragment() {
    if (!show_interior && COLOR.r > 0.5) { discard; }
    // Cycles scatters light through the volume; this renderer needs a softer
    // surface mask to avoid turning the same noise into painted white blotches.
    float clear_mix = mix(0.56, frost_mix(ice_position * noise_scale), frost_contrast);
    vec3 tint = mix(frost_color.rgb, clear_color.rgb, clear_mix * blue_tint_strength);
    float rough = mix(frost_roughness, clear_roughness, clear_mix);
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float f0 = pow((ice_ior - 1.0) / (ice_ior + 1.0), 2.0);
    float fresnel = f0 + (1.0 - f0) * pow(1.0 - facing, 5.0);
    vec2 uv = clamp(SCREEN_UV - NORMAL.xy * refraction_strength, vec2(0.005), vec2(0.995));
    vec3 clear_background = texture(scene_color, uv).rgb;
    vec2 blur = vec2(0.003 * rough);
    vec3 frosted_background = (texture(scene_color, uv + vec2(blur.x,0)).rgb
        + texture(scene_color, uv - vec2(blur.x,0)).rgb
        + texture(scene_color, uv + vec2(0,blur.y)).rgb
        + texture(scene_color, uv - vec2(0,blur.y)).rgb) * 0.25;
    // Compatibility approximation of Cycles' two transmissive BSDFs.
    float transmitted = mix(0.08, 0.28, clear_mix) * (1.0 - fresnel);
    EMISSION = mix(frosted_background, clear_background, clear_mix) * mix(vec3(1), tint, 0.35) * transmitted;
    EMISSION += frost_color.rgb * ambient_fill;
    ALBEDO = tint * (1.0 - transmitted);
    ROUGHNESS = rough;
    METALLIC = 0.0;
    SPECULAR = f0 / 0.08;
    ALPHA = 1.0;
}
