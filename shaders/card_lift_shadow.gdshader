shader_type spatial;
// THE SHADOW A LIFTED CARD CASTS ON THE BOARD (card_damage_fx.gd). A soft dark rounded rectangle on a quad that stays
// at the card's resting height while the card's mesh rises; `strength` follows the height, so it is invisible at rest.
// Alpha-mixed, never additive: a shadow darkens what is under it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec2 card_size = vec2(0.429, 0.6);
// How far the quad reaches past the card on every side, in metres. Must be >= softness or the blur is cropped.
uniform float margin = 0.12;
uniform float corner = 0.025;
uniform float softness = 0.03;
uniform float strength = 0.0;

float rounded_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 quad = card_size + vec2(2.0 * margin);
	vec2 p = (UV - vec2(0.5)) * quad;
	float d = rounded_rect(p, card_size * 0.5, corner);
	// smoothstep with equal edges is undefined in GLSL: keep the width above zero.
	float s = max(softness, 0.001);
	ALBEDO = vec3(0.0);
	ALPHA = clamp(strength, 0.0, 1.0) * (1.0 - smoothstep(-s, s, d));
}
