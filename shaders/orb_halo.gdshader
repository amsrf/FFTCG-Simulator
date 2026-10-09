shader_type spatial;
// A soft radial halo, drawn on a camera-facing quad behind the orb.
//
// WHY THIS EXISTS: an orb of light should read as a source — light spilling into the air around it — and the two
// things that would normally do that are both unavailable here. Environment glow (bloom) is ignored by
// gl_compatibility, and an emissive sphere only makes the sphere itself brighter. So the atmosphere is drawn: this
// quad fades from opaque at its centre to nothing at its rim, added on top of whatever is behind it.
//
// It also fixes the "perfect sphere" read in passing. A lit sphere has a hard silhouette, which looks like a ball no
// matter how bright it is; a soft falloff around it makes the same shape look like it is radiating.
//
// render_mode: additive (light adds, it does not occlude), unshaded (a light source is not lit by anything), and
// depth_draw_never because the halo must not write into the depth buffer.
//
// IT MUST DEPTH-TEST, THOUGH, and an earlier version did not. `depth_test_disabled` was added so the halo would not be
// clipped by the orb it surrounds, but it also makes the halo ignore the depth buffer entirely — so it drew straight
// over cards and anything else in front of it. A payment orb travelling to a card therefore stayed visible *through*
// the card it was supposed to disappear behind. Nothing is gained by disabling the test: the core sphere is
// transparent, so it writes no depth either, and the halo cannot be clipped by it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 halo_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.8;
// Higher is a tighter core with a longer, softer skirt.
uniform float falloff : hint_range(0.5, 8.0) = 2.6;
// A second, much wider and much fainter lobe, which is what stops the halo looking like a flat disc with a gradient.
uniform float skirt_amount : hint_range(0.0, 2.0) = 0.55;
uniform float skirt_falloff : hint_range(0.5, 8.0) = 1.1;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float core = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	float skirt = pow(clamp(1.0 - r, 0.0, 1.0), skirt_falloff) * skirt_amount;
	float a = clamp(core + skirt, 0.0, 1.0);
	ALBEDO = halo_color.rgb * intensity * a;
	ALPHA = a;
}
