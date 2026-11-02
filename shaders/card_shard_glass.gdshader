shader_type spatial;

// Fake crystalline glass for the cut faces of a broken card. The Compatibility
// renderer has no screen-space refraction, so this uses a cool tint, a sharp
// Fresnel rim and a little emission instead. The front faces never use this
// material; they keep the card artwork.

render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 glass_tint : source_color = vec4(0.38, 0.82, 0.96, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.38;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.48;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_emission : hint_range(0.0, 3.0) = 0.65;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.05;
uniform float specular_value : hint_range(0.0, 1.0) = 0.85;

void fragment() {
    float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
    float fresnel = pow(1.0 - clamp(facing, 0.0, 1.0), fresnel_power);

    ALBEDO = glass_tint.rgb;
    METALLIC = 0.0;
    ROUGHNESS = roughness_value;
    SPECULAR = specular_value;
    EMISSION = glass_tint.rgb * fresnel * rim_emission;
    ALPHA = clamp(base_alpha + rim_alpha * fresnel, 0.0, 1.0);
}
