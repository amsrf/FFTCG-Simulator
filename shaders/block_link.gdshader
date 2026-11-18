shader_type spatial;
// THE BLOCK LINK (scripts/vfx/block_link.gd), after the reference clip (Clips/arrow3, frames 71-120): a clean targeting
// line — a thin white-hot core with a soft pink-red glow around it. No noise and no distortion: the SHAPE never moves.
// What animates is the visible span [draw_from, draw_to]: a spark draws it from the attacker (draw_to grows, the tip
// burning brightest), it holds, then it is erased from the back (draw_from grows, a soft fade at the tail).
//   UV.x = along the curve (0 attacker -> 1 blocker), UV.y = across the ribbon.
// Additive (light). DEPTH-TESTED on purpose: the line ends BELOW the blocker's face, so the opaque card hides that
// last stretch and the arc reads as plunging INTO the card rather than stopping on it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.58, 0.62, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.07, 0.20, 1.0);
uniform float draw_from : hint_range(0.0, 1.0) = 0.0;
uniform float draw_to : hint_range(0.0, 1.0) = 1.0;
// Overall fade (the hold's end dims it a little as it is erased).
uniform float fade : hint_range(0.0, 1.0) = 1.0;
// The core's half-width and the glow's reach, as fractions of the ribbon's half-width.
uniform float core_width : hint_range(0.01, 1.0) = 0.16;
uniform float glow_reach : hint_range(0.05, 1.0) = 0.55;
uniform float glow_strength : hint_range(0.0, 3.0) = 1.15;
uniform float intensity : hint_range(0.0, 4.0) = 1.4;

void fragment() {
	float t = UV.x;
	if (t > draw_to + 0.0001 || t < draw_from - 0.0001) {
		discard;
	}
	float e = abs(UV.y * 2.0 - 1.0);
	float core = 1.0 - smoothstep(core_width, core_width * 1.9, e);
	float glow = exp(-pow(e / glow_reach, 2.0)) * glow_strength;
	// Pinker and dimmer where it leaves the attacker, whiter and brighter where it lands.
	float along = mix(0.55, 1.0, smoothstep(0.0, 1.0, t));
	// The tip glows while it is drawing; the tail fades softly while it is erased.
	float front = draw_to < 1.0 ? exp(-pow((draw_to - t) / 0.05, 2.0)) * 1.4 : 0.0;
	float tail = draw_from > 0.0 ? smoothstep(draw_from, draw_from + 0.15, t) : 1.0;
	float ends = smoothstep(0.0, 0.05, t) * tail * fade;
	float k = ends * along * intensity;
	vec3 col = core_color.rgb * core * (1.0 + front) + glow_color.rgb * glow * (1.0 + front);
	ALBEDO = col * k;
	ALPHA = clamp((core + glow) * ends, 0.0, 1.0);
}
