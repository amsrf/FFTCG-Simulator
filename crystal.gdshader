shader_type spatial;

void fragment() {
    // Define the two colors
    vec3 color1 = vec3(0.8784, 0.0667, 0.3725); // E0115F in RGB
    vec3 color2 = vec3(0.4980, 0.0980, 0.2157); // 7F1937 in RGB

    // Get the UV Y coordinate (0 at the bottom, 1 at the top)
    float gradient_factor = UV.y;

    // Mix the two colors based on the Y coordinate
    ALBEDO = mix(color1, color2, gradient_factor);

}