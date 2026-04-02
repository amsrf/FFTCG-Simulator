shader_type spatial;

uniform sampler2D texture_albedo : source_color;
uniform bool effect_enabled = false;
void fragment() {
    // Get the original color from the albedo texture
    vec4 original_color = texture(texture_albedo, UV);

    // If UV y coordinate is greater than 0.8, make it black
    if (effect_enabled && UV.y > 0.875) {
        ALBEDO = vec3(0.1);
    } else {
        ALBEDO = original_color.rgb;

    }
}