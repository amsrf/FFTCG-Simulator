shader_type canvas_item;

uniform vec4 base_blue = vec4(0.2, 0.4, 1.0, 1.0); // Adjusted lighter blue
uniform vec4 strong_blue = vec4(0.0, 0.3, 0.9, 1.0); // Adjusted stronger blue
uniform float border_width : hint_range(0.0, 0.1) = 0.02; // Width of the border
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.5; // Intensity of the glow
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.0; // Speed of the pulsating glow
uniform float min_glow_intensity : hint_range(0.0, 1.0) = 0.2; // Minimum glow intensity to prevent vanishing
uniform float corner_radius : hint_range(0.0, 0.5) = 0.1; // Radius of the circular corners

void fragment() {
    vec2 uv = FRAGCOORD.xy / SCREEN_PIXEL_SIZE;
    vec2 size = TEXTURE_PIXEL_SIZE * SCREEN_PIXEL_SIZE;
    
    // Sample the texture
    vec4 color = texture(TEXTURE, UV);
    
    // Calculate the distance from the center of the texture
    vec2 center = vec2(0.5, 0.5); // Center of the texture
    float distance_from_center = distance(UV, center);
    
    // Calculate the radius of the circular border
    float max_radius = 0.6; // Maximum radius (half the texture size)
    float inner_radius = max_radius - border_width; // Inner radius of the border
    float outer_radius = max_radius; // Outer radius of the border
    
    // Smoothstep to create a smooth circular border
    float edge = smoothstep(inner_radius, outer_radius, distance_from_center);
    
    // Pulsating glow effect with a minimum threshold
    float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5; // Oscillates between 0.0 and 1.0
    float dynamic_glow_intensity = glow_intensity * max(pulse, min_glow_intensity);
    
    // Interpolate between light blue and strong blue based on the pulse value
    vec4 pulsating_blue = mix(base_blue, strong_blue, pulse);
    
    // Apply the border color and glow
    if (edge > 0.0) {
        COLOR = mix(color, pulsating_blue, dynamic_glow_intensity * edge);
    } else {
        COLOR = color;
    }
}