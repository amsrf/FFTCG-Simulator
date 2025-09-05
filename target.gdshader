shader_type spatial;

uniform vec4 overlay_color = vec4(1.0, 0.5, 0.0, 0.0);
uniform float overlay_strength = 0.0;

void fragment() {
    vec4 base_color = texture(TEXTURE, UV) * COLOR;
    
    // Apply overlay
    vec3 blended = mix(base_color.rgb, overlay_color.rgb, overlay_color.a * overlay_strength);
    float alpha = base_color.a;
    
    ALBEDO = blended;
    ALPHA = alpha;
}