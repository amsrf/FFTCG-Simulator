shader_type spatial;
// The printed card has a glass side wall. The field tile has an opaque satin edge.
// Tinted by the card's element (instance uniform, one shared material), clearer face-on and brighter at grazing angles
// (fresnel), with a bright line where the wall meets the face and a fainter one at the bottom: the two bevels catching
// the light. Unshaded on purpose: the scene's single light points straight down, so a lit side wall is always dark.
//
// The mesh is built ONE unit deep (local y 0 .. -1) and scaled to the thickness, so local y is a 0..1 height.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(0.62, 0.78, 0.95, 1.0);
instance uniform bool field_edge = false;
uniform float body_alpha : hint_range(0.0, 1.0) = 0.38;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float top_line : hint_range(0.0, 3.0) = 1.4;
uniform float bottom_line : hint_range(0.0, 3.0) = 0.6;

varying float height;   // 0 at the face, 1 at the bottom

void vertex() {
	height = -VERTEX.y;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel_power);
	// Glass seen through its depth: darker toward the bottom, the tint deepening.
	vec3 body = mix(tint.rgb * 0.95 + vec3(0.12), tint.rgb * 0.35, height);
	float top = exp(-height / 0.12) * top_line;
	float bottom = exp(-(1.0 - height) / 0.1) * bottom_line;
	vec3 colour = body + vec3(1.0) * fresnel * 0.55 + mix(tint.rgb, vec3(1.0), 0.6) * (top + bottom) * 0.6;
	if (field_edge) {
		ALBEDO = mix(tint.rgb * 0.26, tint.rgb * 0.08, height) + vec3(0.04) * fresnel;
		ALPHA = 1.0;
	} else {
		ALBEDO = colour;
		ALPHA = clamp(body_alpha + fresnel * (rim_alpha - body_alpha) + (top + bottom) * 0.35, 0.0, 1.0);
	}
}
