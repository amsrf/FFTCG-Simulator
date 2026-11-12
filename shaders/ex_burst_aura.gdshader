shader_type spatial;
// EX BURST reveal on a damage card (scripts/vfx/ex_burst_reveal.gd): a gold aura hugging the card's outline, a light
// running round it, and PULSES - bands that leave the outline and expand outward as they fade. One quad, larger than
// the card, lying just above its face; everything is measured in card-face units from the card's rounded outline, so
// the aura has the same width on every side. After Clips/damage_trigger frames 194+.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.55, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.70, 0.12, 1.0);
uniform vec2 card_size = vec2(0.429, 0.6);
uniform float corner = 0.022;
uniform float intensity : hint_range(0.0, 4.0) = 0.0;
uniform float glow_width = 0.045;
/// Up to two pulses: how far beyond the outline each band is, and its strength.
uniform float pulse_a = 0.0;
uniform float pulse_a_alpha = 0.0;
uniform float pulse_b = 0.0;
uniform float pulse_b_alpha = 0.0;
uniform float pulse_width = 0.012;

varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

float band(float d, float at, float alpha) {
	float x = (d - at) / pulse_width;
	return exp(-x * x) * alpha * step(-0.005, d);
}

void fragment() {
	vec2 q = abs(local) - (card_size * 0.5 - corner);
	// Signed distance to the rounded outline: negative inside the card.
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	// The bright gold line ON the outline, and a soft glow spilling outward (barely inward, so the art stays readable).
	float rim = exp(-abs(d) / 0.0035);
	float glow = d > 0.0 ? exp(-d / glow_width) : exp(d / 0.010) * 0.35;
	// A light running round the edge.
	float angle = atan(local.y, local.x);
	float run = 0.65 + 0.9 * pow(0.5 + 0.5 * sin(angle * 2.0 - TIME * 4.5), 6.0);
	vec3 aura = rim_color.rgb * rim * 1.7 * run + glow_color.rgb * glow * 0.95;
	vec3 pulses = mix(glow_color.rgb, rim_color.rgb, 0.6) * (band(d, pulse_a, pulse_a_alpha) + band(d, pulse_b, pulse_b_alpha));
	ALBEDO = aura * intensity + pulses;
}
