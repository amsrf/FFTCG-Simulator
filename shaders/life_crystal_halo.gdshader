shader_type spatial;
// The outer glow of a life crystal: a soft additive ellipse on a quad behind it. Compatibility ignores Environment
// glow, so light AROUND a surface has to be drawn (same reason as the teleport halo and the shatter flash).
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 colour : source_color = vec4(1.0, 0.08, 0.06, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 0.9;
// Grows with the burst's flash: brighter and tighter at 1.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

// BILLBOARD, keeping the node's scale: the life crystals stand in world space on the board, and the burst animates
// its flash quad's scale, so the quad must turn to the camera without losing its size.
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	vec3 c = mix(colour.rgb, vec3(1.0, 0.8, 0.75), flash * 0.6);
	ALBEDO = c * a * intensity * (1.0 + flash * 2.5);
}
