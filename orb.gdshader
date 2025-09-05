// (ShaderMaterial on the orb)
shader_type spatial;
render_mode blend_add;
uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.2, 1.0); // Gold/yellow
uniform float pulse_speed = 2.0;

void vertex() {
    // Optional: Add subtle wobble or pulse
    float pulse = sin(TIME * pulse_speed) * 0.1 + 1.0;
    VERTEX *= pulse;
}

void fragment() {
    ALBEDO = glow_color.rgb;
    EMISSION = glow_color.rgb * 2.0; // Boost glow
}