shader_type spatial;
// THE GHOST OF THE SLOT A HELD CARD WILL LAND IN (scripts/game/field_slot_ghost.gd), after Artifact's summon slots:
// a card-sized rounded outline in the field-drop gold, a thin inner line, a faint fill and a soft glow past the edge,
// with a light band climbing it. `intensity` fades the whole thing; `armed` (a release now would play the card) takes
// it from a faint hint to a bright, pulsing slot. Additive (no bloom under Compatibility, so the quad IS the glow).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec2 card_half = vec2(0.257, 0.36);   // the landing card's half-extents, metres (x, z)
uniform vec2 quad_half = vec2(0.40, 0.50);    // this quad's half-extents, metres
uniform float corner_radius = 0.025;
uniform float line_width = 0.012;
uniform float inner_inset = 0.035;
uniform float inner_line_width = 0.005;
uniform float glow_width = 0.07;
uniform vec4 glow_color : source_color = vec4(1.0, 0.74, 0.28, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.70, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float armed : hint_range(0.0, 1.0) = 0.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * quad_half;
	float d = sd_round_box(p, card_half, corner_radius);
	// Width-driven edges: keep every smoothstep width above zero (equal edges are undefined in GLSL).
	float line = 1.0 - smoothstep(0.0, max(line_width, 1e-4), abs(d));
	float inner = 1.0 - smoothstep(0.0, max(inner_line_width, 1e-4), abs(d + inner_inset));
	float outside = step(0.0, d);
	float glow = outside * exp(-d / max(glow_width, 1e-4) * 2.4);
	float fill = 1.0 - step(0.0, d);
	// A light band climbing the slot (UV.y = 1 is the near edge, toward the hand), like the play's line drawing.
	float climb = fract(TIME * 0.55);
	float band = fill * exp(-pow((1.0 - UV.y - climb) * 9.0, 2.0));
	float pulse = mix(1.0, 0.80 + 0.20 * sin(TIME * 4.2), armed);
	float bright = mix(0.28, 1.0, armed);
	vec3 col = core_color.rgb * (line * 0.95 + inner * 0.35)
		+ glow_color.rgb * (glow * 0.55 + fill * mix(0.03, 0.14, armed) + band * mix(0.05, 0.16, armed));
	ALBEDO = col * bright * pulse * intensity;
}
