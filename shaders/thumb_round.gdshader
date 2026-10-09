shader_type canvas_item;
// Rounds the corners of whatever is drawn with it, gives the bottom edge the CSS "3D button" treatment,
// and lights a blue aura around the border while the card is hovered.
//
// A TextureRect/TextureButton has no corner radius of its own — Godot's rounded corners come from
// StyleBoxFlat, which only exists for panels and buttons with a background, not for a raw image. So the
// shape is cut in the fragment shader instead, the same rounded-rect distance field the card's targeting
// ring and the absorb shockwave use.
//
// `dist` is the signed distance to that rounded rect: negative inside, zero on the edge, positive outside.
// EVERY SIZE HERE IS IN UV, so it is a FRACTION of the image rather than pixels. That is what lets the same
// values look right on a 190 px thumbnail and a 363 px preview. The trade-off is that a corner is
// elliptical rather than circular on a non-square image, which at these radii is invisible.

uniform float radius : hint_range(0.0, 0.5) = 0.06;
// Widened by a hair so the edge is anti-aliased rather than stair-stepped.
uniform float softness : hint_range(0.0001, 0.02) = 0.004;

// The bottom line: a THIN, HARD, ABSOLUTE BLACK line hugging the bottom of the ROUNDED outline — the CSS
// "3d button" trick, matched to references/black.png where it is a single solid row of black, and where it
// curves with the card's corner rather than running straight across.
//
// `edge_depth` is measured INWARD FROM THE OUTLINE, not up from the bottom of the image. That is the whole
// difference between a line that follows the corner and one that the corner mask merely chops off.
//
// Strength 1.0 on black makes the multiply below drive the line to zero, so it really is absolute black
// rather than a darkening of the art, and the softness is small enough that its inner edge is a hard line.
uniform float edge_depth : hint_range(0.0, 0.2) = 0.004;
uniform float edge_strength : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.0005, 0.05) = 0.002;
uniform vec4 edge_colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// A hairline all the way round, so the card is separated from what is behind it at the sides and top
// too, where there is no line. Kept weak: the art already carries its own frame.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;

// The HOVER AURA: a glow in from the border while the pointer is over the card.
//
// It cannot spill OUTSIDE the quad — the TextureRect is exactly the art — so it lights the card's own
// border from within instead. That matches the ring the match draws on a card you may pick, so hovering in
// the editor and "this is targetable" in a game read as the same idea.
//
// `hover` is a float rather than a bool so it can be faded in and out instead of snapping on.
uniform float hover : hint_range(0.0, 1.0) = 0.0;
uniform vec4 aura_colour : source_color = vec4(0.15, 0.45, 1.0, 1.0);
uniform float aura_width : hint_range(0.0, 0.3) = 0.05;
uniform float aura_strength : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec2 p = UV - vec2(0.5);
	vec2 half_extent = vec2(0.5) - vec2(radius);
	vec2 d = abs(p) - half_extent;
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;

	// Inside the rounded rect = 1, outside = 0.
	float inside = 1.0 - smoothstep(-softness, softness, dist);

	// The line follows the OUTLINE, not the horizontal, so its width stays constant around the corner.
	float inward = -dist;

	// It belongs on the BOTTOM of the outline only: the flat stretch, plus a little way around the two
	// bottom corners. The corner radius is 0.06 UV, so the flat run ends at UV.y ~ 0.94 — starting the fade
	// at 0.82 keeps the line off the sides while still turning the corner slightly.
	float bottom_weight = smoothstep(0.82, 0.96, UV.y);
	float line = (1.0 - smoothstep(edge_depth, edge_depth + edge_softness, inward)) * bottom_weight * inside;

	// The rim is the sliver between a slightly narrower shape and the shape itself.
	float narrower = 1.0 - smoothstep(-softness, softness + 0.012, dist);
	float rim = clamp(inside - narrower, 0.0, 1.0);

	// The aura is strongest exactly on the edge and fades inward over `aura_width`.
	float aura = (1.0 - smoothstep(0.0, aura_width, inward)) * inside * hover;

	// The line and the rim DARKEN rather than replace: a light card and a dark card then shade by the same
	// amount instead of both converging on one flat colour, which is what painting edge_colour directly does.
	vec3 darken = edge_colour.rgb;
	COLOR.rgb *= 1.0 - line * edge_strength * (1.0 - darken);
	COLOR.rgb *= 1.0 - rim * rim_strength * (1.0 - darken);

	// The aura is MIXED, not added. Adding a bright blue to an already-bright card clips the channel and
	// washes the border to white — the trap this project has hit with every additive glow so far.
	COLOR.rgb = mix(COLOR.rgb, aura_colour.rgb, aura * aura_strength);

	COLOR.a *= inside;
}
