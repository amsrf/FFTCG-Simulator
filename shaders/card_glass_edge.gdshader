shader_type spatial;
// The printed card (card format) has a thin opaque card-stock edge. The field tile has an opaque satin edge.
// The field edge is tinted by the card's element (instance uniform, one shared material). Unshaded on purpose: the scene's single light points straight down, so a lit side wall is always dark.
//
// The mesh is built ONE unit deep (local y 0 .. -1) and scaled to the thickness, so local y is a 0..1 height.
// OPAQUE (no blend_mix / depth_draw_never, which were for the old glass): both styles are ALPHA 1, and a transparent
// wall that writes no depth is only sorted per object, so a deck's stacked walls cut into each other in steps.
render_mode unshaded, cull_disabled, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(0.62, 0.78, 0.95, 1.0);
instance uniform bool field_edge = false;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;

varying float height;   // 0 at the face, 1 at the bottom
varying float cap;      // 1 on the bottom cap, 0 on the side wall

void vertex() {
	height = -VERTEX.y;
	cap = step(0.5, -NORMAL.y);
}

void fragment() {
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel_power);
	if (field_edge) {
		ALBEDO = mix(tint.rgb * 0.26, tint.rgb * 0.08, height) + vec3(0.04) * fresnel;
	} else {
		// The card format shows no bottom cap: opaque, it would cover the card BACK of a face-down card (the deck).
		if (cap > 0.5) {
			discard;
		}
		// The card format is plain, opaque card stock: no glass (user's call). A light neutral edge that matches the card
		// back's silver frame (a dark brown version blended into the wooden board), a touch darker toward the bottom so
		// the two faces still read apart.
		ALBEDO = mix(vec3(0.80, 0.78, 0.74), vec3(0.58, 0.56, 0.53), height) + vec3(0.05) * fresnel;
	}
}
