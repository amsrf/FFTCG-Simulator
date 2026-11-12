shader_type spatial;
// WHAT THE BOLT LEAVES IN THE GROUND (lightning_aftermath.gd): a fissure burnt into the playmat around the struck card.
//
// Jagged cracks run out from the impact point, each with a side fork. They open outward in the first tenth of a
// second (`grow`), glow white-violet with current still crawling along them while `heat` falls, and stay behind as
// dark charred lines with a soot halo until `opacity` takes them away. A flat PlaneMesh at the card's face, drawn
// OVER the card (no depth test: the struck card recoils upward and would otherwise poke through it).

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 arc_color : source_color = vec4(0.42, 0.10, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.93, 0.87, 1.0, 1.0);
uniform vec4 char_color : source_color = vec4(0.030, 0.022, 0.045, 1.0);
uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;

const int BRANCHES = 8;
const int JOINTS = 7;

float hash(float p) {
	return fract(sin(p * 127.1 + seed * 31.7) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 edge = b - a;
	float t = clamp(dot(p - a, edge) / max(dot(edge, edge), 0.00001), 0.0, 1.0);
	return length(p - a - edge * t);
}

vec2 turned(vec2 v, float angle) {
	return vec2(v.x * cos(angle) - v.y * sin(angle), v.x * sin(angle) + v.y * cos(angle));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Broken ground does not crack in ruled lines: wobble the plane a little before measuring.
	vec2 q = p + (vec2(noise2(p * 13.0), noise2(p * 13.0 + 7.3)) - 0.5) * 0.045;
	float d = 1.0;
	for (int b = 0; b < BRANCHES; b++) {
		float branch = float(b);
		// Each crack WALKS outward: its heading is knocked a little further off at every joint.
		float heading = branch * 6.2831853 / float(BRANCHES) + (hash(branch + 1.0) - 0.5) * 0.60;
		float step_length = (0.50 + 0.42 * hash(branch + 40.0)) / float(JOINTS);
		vec2 from = vec2(cos(heading), sin(heading)) * 0.03;
		for (int j = 1; j <= JOINTS; j++) {
			float joint = float(j);
			heading += (hash(branch * 7.0 + joint * 13.0 + 3.0) - 0.5) * 0.50;
			vec2 dir = vec2(cos(heading), sin(heading));
			// Keep it travelling outward however it wanders.
			dir = normalize(dir + normalize(from) * 1.4);
			vec2 to = from + dir * step_length;
			d = min(d, segment_distance(q, from, to));
			// Short forks split off some joints and die out.
			if (hash(branch * 3.0 + joint * 5.0 + 60.0) > 0.58) {
				float side = hash(branch + joint + 80.0) > 0.5 ? 1.0 : -1.0;
				vec2 tip = to + turned(dir, side * (0.6 + 0.5 * hash(branch + joint * 2.0 + 90.0)))
					* step_length * (0.7 + 0.8 * hash(branch + joint * 3.0 + 100.0));
				d = min(d, segment_distance(q, to, tip) + 0.004);
			}
			from = to;
		}
	}
	// Opening outward from the impact.
	float opened = 1.0 - smoothstep(grow * 1.05 - 0.06, grow * 1.05, r);
	// A real gap at the centre, a hairline at the tips.
	float width = mix(0.013, 0.003, smoothstep(0.08, 0.92, r));
	float aa = max(fwidth(d), 0.0008);
	float line = (1.0 - smoothstep(width, width + aa, d)) * opened;
	float soot = (1.0 - smoothstep(width, width + 0.040, d)) * opened;
	// A small burn mark at the strike point itself.
	float scorch = exp(-r * r / 0.012) * 0.45;
	// The current left in the cracks: crawling outward, brightest near the impact.
	float crawl = 0.60 + 0.40 * sin(r * 30.0 - TIME * 14.0 + noise2(p * 4.0) * 9.0);
	float hot = heat * crawl * (1.0 - 0.45 * smoothstep(0.0, 0.9, r));
	float glow = exp(-d / 0.020) * opened * hot;
	float edge_fade = 1.0 - smoothstep(0.85, 0.99, r);

	vec3 burnt = char_color.rgb;
	vec3 live = mix(arc_color.rgb, core_color.rgb, clamp(line * hot * 1.8, 0.0, 1.0)) * 1.7;
	float liveness = clamp(max(line * hot * 1.6, glow * 1.2), 0.0, 1.0);
	ALBEDO = mix(burnt, live, liveness);
	ALPHA = clamp(max(max(line * 0.90, soot * 0.38 + scorch), glow), 0.0, 1.0) * edge_fade * opacity;
}
