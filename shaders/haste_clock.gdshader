shader_type spatial;
// The HASTE clock (scripts/vfx/haste_clock.gd): an ephemeral golden clock face drawn on one camera-facing quad over a
// card. Everything is a line distance field in the quad's own UV space, so there are no textures:
//   outer ring + cross-hair notches at 12/3/6/9, a dial ring with 12 hour and 60 minute ticks, a band of blocks that
//   turns against the hands, an inner ring, a hub, and two hands with chevron arrow tips whose sweep leaves a trail.
// Every value that moves is a uniform written by the script (sample(t)), so a frozen frame is reproducible.
// QuadMesh UV.y = 0 is the TOP edge, so the clock works in q = (x, up).

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 hot_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.40, 0.05, 1.0);
uniform float intensity = 1.0;
// 0..1: how much of the dial has been drawn, sweeping clockwise from 12 o'clock.
uniform float reveal = 1.0;
// Hand angles in TURNS, clockwise from 12 (any value; only the fraction matters).
uniform float minute_hand = 0.0;
uniform float hour_hand = 0.0;
// Rotation of the block band, in turns (counter to the hands).
uniform float band_spin = 0.0;
// A brief white-hot flash on every line.
uniform float flare = 0.0;
uniform float line_width = 0.013;
uniform float glow_width = 0.06;

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance from (r, turn) to the nearest of `n` radial ticks spanning r0..r1, offset by `phase` turns.
float ticks(float r, float turn, float n, float r0, float r1, float phase) {
	float k = (turn - phase) * n;
	float off = (k - floor(k + 0.5)) / n;          // turns to the nearest tick
	float along = abs(off) * TAU * r;               // arc length to it
	float across = max(max(r0 - r, r - r1), 0.0);   // outside the tick's radial span
	return length(vec2(along, across));
}

vec2 rot(vec2 p, float turns) {
	float a = turns * TAU;
	float c = cos(a);
	float s = sin(a);
	// Clockwise rotation by `turns` maps the hand's direction onto +y.
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// A hand pointing along +y in its local frame, with a chevron arrow tip.
float hand(vec2 q, float turns, float len, float tip) {
	vec2 h = rot(q, turns);
	float d = seg(h, vec2(0.0, -0.06), vec2(0.0, len));
	d = min(d, seg(h, vec2(0.0, len + tip), vec2(-tip * 0.8, len - tip * 0.4)));
	d = min(d, seg(h, vec2(0.0, len + tip), vec2(tip * 0.8, len - tip * 0.4)));
	return d;
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(q);
	// Turns clockwise from 12 o'clock, 0..1.
	float turn = fract(atan(q.x, q.y) / TAU + 1.0);

	// The dial draws itself on clockwise; a soft leading edge.
	float drawn = smoothstep(reveal + 0.002, reveal - 0.03, turn) * step(0.001, reveal);
	drawn = max(drawn, step(0.999, reveal));

	// --- the dial (revealed) ------------------------------------------------------------------------------------
	float dial = abs(r - 0.80);                                            // outer ring
	dial = min(dial, abs(r - 0.70) + 0.004);                               // dial ring, a touch thinner
	dial = min(dial, abs(r - 0.34) + 0.004);                               // inner ring
	dial = min(dial, ticks(r, turn, 12.0, 0.58, 0.70, 0.0));               // hour ticks
	dial = min(dial, ticks(r, turn, 60.0, 0.645, 0.70, 0.0) + 0.005);      // minute ticks
	dial = min(dial, ticks(r, turn, 4.0, 0.72, 0.90, 0.0));                // cross-hair notches through the ring

	// The block band: 36 slots, two arcs of blocks, turning against the hands.
	float bturn = fract(turn - band_spin);
	float slot = fract(bturn * 36.0);
	float arcs = smoothstep(0.02, 0.05, abs(fract(bturn * 2.0) - 0.5) - 0.12);
	float block_in = step(0.2, slot) * step(slot, 0.8) * step(0.835, r) * step(r, 0.885) * arcs;
	float block = block_in * 0.75;

	// --- the hands (appear once half the dial is drawn) -----------------------------------------------------------
	float hands_on = smoothstep(0.35, 0.6, reveal);
	float hd = min(hand(q, minute_hand, 0.56, 0.07), hand(q, hour_hand, 0.38, 0.06));
	hd = min(hd, max(r - 0.035, 0.0));                                     // hub
	// The minute hand's sweep trail: a wedge lagging behind it, fading with angle.
	float lag = fract(minute_hand - turn);
	float trail = exp(-lag * 9.0) * smoothstep(0.60, 0.20, r) * step(0.05, r) * 0.38 * hands_on;

	// --- lines -> light ---------------------------------------------------------------------------------------------
	float w = line_width;
	float core = exp(-pow(dial / w, 2.0)) * drawn + exp(-pow(hd / (w * 1.25), 2.0)) * hands_on;
	float glow = exp(-dial / glow_width) * drawn * 0.80 + exp(-hd / glow_width) * hands_on * 0.85;
	core = clamp(core + block * drawn, 0.0, 1.0);
	// A warm haze inside the outer ring, and the whole thing faded before the quad's edge.
	float haze = smoothstep(0.82, 0.0, r) * 0.16 * drawn;
	float edge = smoothstep(1.0, 0.90, r);

	vec3 col = mix(glow_color.rgb, hot_color.rgb, clamp(core * 1.2 + trail * 0.4, 0.0, 1.0));
	col = mix(col, vec3(1.0), clamp(flare * core, 0.0, 1.0));
	float a = clamp(core + glow + trail + haze + flare * glow * 0.6, 0.0, 1.0) * edge * intensity;
	ALBEDO = col;
	ALPHA = a;
}
