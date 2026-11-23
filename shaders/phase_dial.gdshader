shader_type spatial;
// The phase marks carved into the wood around a big priority button (scripts/ui/phase_dial.gd): seven symbols on
// one arc centred on the button, and the current phase's mark lit. Everything
// is drawn from signed distance fields in the dial's local XZ plane (metres), so it stays crisp at any zoom.
// The wood itself is not sampled: the carving DARKENS the floor and the shaded wall, and LIGHTENS the lit wall.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

const int MARKS = 7;
uniform float arc_radius = 0.56;
// Screen angle (degrees, counter-clockwise from screen-right) of the first and last mark.
uniform float first_angle = 120.0;
uniform float last_angle = 20.0;
uniform float active_slot = 0.0;
// The symbols below are drawn at 1.0; the dial scales them up.
uniform float icon_scale = 1.6;
uniform float active_glow = 1.0;
// From the top-left of the screen, in the dial's (x, z): screen-left is local +x, screen-up is local +z.
const vec2 KEY_DIR = vec2(0.7071, 0.7071);
const vec3 GLOW = vec3(1.0, 0.72, 0.34);

varying vec2 plane_point;

void vertex() {
	plane_point = VERTEX.xz;
}

float mark_angle(int i) {
	return radians(mix(first_angle, last_angle, float(i) / float(MARKS - 1)));
}

vec2 mark_centre(int i) {
	float a = mark_angle(i);
	return arc_radius * vec2(-cos(a), sin(a));
}

float sd_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float sd_segment(vec2 p, vec2 a, vec2 b, float radius) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - radius;
}

// Symbols in screen-upright coordinates: s.x to the right, s.y up, metres.
float sd_symbol(int i, vec2 s) {
	if (i == 0 || i == 6) {
		// Active / Draw and End: a small dot.
		return length(s) - 0.011;
	}
	if (i == 1 || i == 5) {
		// Main 1 and Main 2: a card.
		return sd_box(s, vec2(0.020, 0.027), 0.005);
	}
	if (i == 2) {
		// Attack: a sword, blade up-right.
		float blade = sd_segment(s, vec2(-0.011, -0.011), vec2(0.024, 0.024), 0.0075);
		float guard = sd_segment(s, vec2(-0.024, 0.000), vec2(0.000, -0.024), 0.0050);
		float grip = sd_segment(s, vec2(-0.011, -0.011), vec2(-0.024, -0.024), 0.0045);
		float pommel = length(s - vec2(-0.028, -0.028)) - 0.0065;
		return min(min(blade, guard), min(grip, pommel));
	}
	if (i == 3) {
		// Block: a shield (flat top, pointed bottom).
		// Straight sides down to y 0.004, then tapering to a point at the bottom (y -0.030).
		float half_width = 0.023 * clamp((s.y + 0.030) / 0.034, 0.0, 1.0);
		return max(abs(s.x) - half_width, max(s.y - 0.026, -0.030 - s.y)) * 0.8;
	}
	// Damage: a burst.
	float a = atan(s.y, s.x);
	float spikes = pow(0.5 + 0.5 * cos(8.0 * a + 0.4), 2.0);
	return (length(s) - (0.016 + 0.014 * spikes)) * 0.75;
}

// The nearest mark's distance at a point, and which mark it is.
float marks_sd(vec2 p, out int which) {
	float best = 1e3;
	which = 0;
	for (int i = 0; i < MARKS; i++) {
		vec2 c = mark_centre(i);
		vec2 s = vec2(-(p.x - c.x), p.y - c.y);
		float d = sd_symbol(i, s / icon_scale) * icon_scale;
		if (d < best) {
			best = d;
			which = i;
		}
	}
	return best;
}


void fragment() {
	vec2 p = plane_point;
	int which;
	float d_marks = marks_sd(p, which);
	float d = d_marks;
	// The outward normal of the carving's edge, from the distance field.
	float e = 0.0015;
	int unused;
	vec2 grad = vec2(marks_sd(p + vec2(e, 0.0), unused) - d, marks_sd(p + vec2(0.0, e), unused) - d);
	vec2 n = grad / max(length(grad), 1e-6);
	float aa = max(fwidth(d), 0.0004);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	// The wall: a band just inside the edge. A carved wall faces INTO the cut, so the side whose outward normal
	// points away from the light is the lit one.
	float wall = inside * smoothstep(-0.0052, -0.0040, d);
	float lit = clamp(-dot(n, KEY_DIR), 0.0, 1.0);
	float shade = clamp(dot(n, KEY_DIR), 0.0, 1.0);

	vec3 colour = vec3(0.0);
	float alpha = inside * 0.52;                                   // the floor: darker wood
	alpha += wall * shade * 0.30;                                  // the shaded wall: darker still
	colour = mix(colour, vec3(1.0, 0.86, 0.66), wall * lit);       // the lit wall: a warm highlight
	alpha = mix(alpha, 0.30, wall * lit);

	// The current phase's mark glows softly: a warm fill and a faint halo around it.
	if (which == int(active_slot + 0.5) && d_marks < 0.018) {
		float in_mark = 1.0 - smoothstep(-aa, aa, d_marks);
		float fill = in_mark * active_glow;
		float halo = (1.0 - smoothstep(0.0, 0.018, d_marks)) * (1.0 - in_mark) * active_glow;
		colour = mix(colour, GLOW, max(fill, halo));
		alpha = max(alpha, max(fill * 0.92, halo * 0.35));
	}
	ALBEDO = colour;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
