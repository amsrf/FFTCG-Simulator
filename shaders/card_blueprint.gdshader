shader_type spatial;
// THE CARD BLUEPRINT: a line drawing of a card (outer frame, inner frame, art window, text box, crystal emblem and
// construction lines running past the corners), drawn as additive light. Played cards leave as one and arrive as one
// (~/Desktop/Clips/play, frames 148-202): it fades in above the slot, sharpens, fills with white light, and the real
// card is there. Everything is measured in METRES from the card's centre, so line widths do not depend on the quad.
//
// The quad is a PlaneMesh (XZ plane, normal +Y) of `quad_size`; UV y = 0 is local -Z, the art's TOP, like the card.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 card_size = vec2(0.429, 0.6);
uniform vec2 quad_size = vec2(0.629, 0.8);
uniform vec4 line_color : source_color = vec4(0.55, 0.87, 0.98, 1.0);
uniform vec4 fill_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
// 0 = soft and faint (just appeared), 1 = crisp and bright (about to fill).
uniform float crisp : hint_range(0.0, 1.0) = 1.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// White light filling the card's silhouette.
uniform float fill : hint_range(0.0, 1.0) = 0.0;
// Noise dissolve, eaten from the bottom up with a glowing front (the departure). 0 = whole, 1 = gone.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float corner_radius = 0.03;
// Only the card's outline (the bottom of the slab the drawing will be), nothing inside it.
uniform bool outline_only = false;

float rounded_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float box(vec2 p, vec2 centre, vec2 half_size) {
	vec2 q = abs(p - centre) - half_size;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// A line of half-width `w` around distance `d`: a hard core plus a soft glow, both anti-aliased.
float line(float d, float w, float glow_w) {
	float ad = abs(d);
	float aa = fwidth(d) + 1e-5;
	float core = 1.0 - smoothstep(w, w + aa, ad);
	float halo = exp(-ad / max(glow_w, 1e-4)) * 0.45;
	return max(core, halo);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * quad_size;      // metres; -y is the top of the card
	vec2 h = card_size * 0.5;
	float w = mix(0.0075, 0.0028, crisp);
	float glow_w = mix(0.022, 0.008, crisp);

	float outer = rounded_rect(p, h, corner_radius);
	float lines = line(outer, w * 1.25, glow_w);
	if (!outline_only) {
	// Inner frame.
	lines = max(lines, 0.75 * line(rounded_rect(p, h - vec2(0.02), corner_radius * 0.6), w, glow_w));
	// Art window (upper ~55%) and text box (lower part).
	float art_top = -h.y + 0.055;
	float art_bottom = 0.06;
	lines = max(lines, 0.7 * line(box(p, vec2(0.0, (art_top + art_bottom) * 0.5),
		vec2(h.x - 0.04, (art_bottom - art_top) * 0.5)), w, glow_w));
	float text_top = art_bottom + 0.025;
	float text_bottom = h.y - 0.035;
	lines = max(lines, 0.55 * line(box(p, vec2(0.0, (text_top + text_bottom) * 0.5),
		vec2(h.x - 0.04, (text_bottom - text_top) * 0.5)), w, glow_w));
	// Two rule lines in the text box.
	for (int i = 1; i <= 2; i++) {
		float y = mix(text_top, text_bottom, float(i) / 3.0);
		float in_box = step(abs(p.x), h.x - 0.07);
		lines = max(lines, 0.35 * in_box * line(p.y - y, w * 0.7, glow_w * 0.6));
	}
	// The crystal emblem in the art window: a tall rhombus with its spine.
	vec2 e = p - vec2(0.0, (art_top + art_bottom) * 0.5);
	vec2 er = vec2(0.075, 0.12);
	float rhombus = (abs(e.x) / er.x + abs(e.y) / er.y - 1.0) * min(er.x, er.y) * 0.85;
	lines = max(lines, 0.9 * line(rhombus, w, glow_w));
	float spine = step(abs(e.y), er.y * 0.92) * line(e.x, w * 0.7, glow_w * 0.5);
	float waist = step(abs(e.x), er.x * 0.55) * line(e.y, w * 0.7, glow_w * 0.5);
	lines = max(lines, 0.6 * max(spine, waist));
	// Construction lines: the card's edge lines carried past its corners, fading with distance from the card.
	float reach = 0.1;
	float past_x = max(abs(p.x) - h.x, 0.0);
	float past_y = max(abs(p.y) - h.y, 0.0);
	float horizontal = line(abs(p.y) - h.y, w * 0.6, glow_w * 0.4) * (1.0 - smoothstep(0.0, reach, past_x))
		* step(0.001, past_x);
	float vertical = line(abs(p.x) - h.x, w * 0.6, glow_w * 0.4) * (1.0 - smoothstep(0.0, reach, past_y))
		* step(0.001, past_y);
	lines = max(lines, 0.5 * max(horizontal, vertical));

	}
	vec3 colour = line_color.rgb * lines * (0.55 + 0.75 * crisp);
	// A white-hot core on the crispest lines.
	colour += vec3(1.0) * pow(lines, 3.0) * 0.35 * crisp;

	if (outline_only) {
		ALBEDO = colour * intensity;
	} else {
	// The fill: white light inside the silhouette, brightest at the rim.
	float inside = 1.0 - smoothstep(-0.002, 0.002, outer);
	float rim = exp(outer / 0.03);
	colour = mix(colour, fill_color.rgb * (0.85 + 0.6 * rim), fill * inside);
	colour += fill_color.rgb * fill * exp(-max(outer, 0.0) / 0.035) * 0.8 * (1.0 - inside);

	// Dissolve: eaten from the bottom (high y) upward, ragged, with a glowing front.
	if (dissolve > 0.0) {
		float n = value_noise(p * 38.0) * 0.6 + value_noise(p * 9.0) * 0.4;
		float height = 1.0 - (p.y / quad_size.y + 0.5);   // 0 at the bottom, 1 at the top
		float threshold = dissolve * 1.25 - 0.12;
		float keep = height * 0.65 + n * 0.35;
		float alive = smoothstep(threshold - 0.02, threshold + 0.02, keep);
		float front = (1.0 - smoothstep(0.0, 0.06, abs(keep - threshold))) * step(0.001, dissolve);
		colour = colour * alive + line_color.rgb * front * 1.4 * step(abs(p.x), h.x) * step(abs(p.y), h.y);
	}

	ALBEDO = colour * intensity;
	}
}
