shader_type spatial;
// The TRIBUTE burst (scripts/vfx/tribute_cue.gd): an effect put a card from the field into the Break Zone without
// breaking it. One camera-facing quad centred on the card's slot draws, after ~/Desktop/Clips/tribute frames 23-37:
//   * a warm orb charging on the card, with a thin vertical light streak through it (23-25);
//   * a white BLOOM that pops out of it as the card leaves (26-27);
//   * a hot core inside a RING that expands outward (28-32);
//   * the ring breaking into separate arc slashes that keep travelling and fade, with sparkles (33-37).
// Every value that moves is a uniform written by the script (sample(t)), so a frozen frame is reproducible.
// Distances are in CARD HEIGHTS from the centre; `half_extent` is the quad's half-size in the same unit.
// QuadMesh UV.y = 0 is the TOP edge, so the shader works in q = (x, up).

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.94, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.90, 0.42, 1.0);
uniform vec4 ring_color : source_color = vec4(1.0, 0.97, 0.78, 1.0);
uniform float half_extent = 1.4;
uniform float seed = 0.0;
uniform float time = 0.0;
// The charging orb / the core left after the bloom.
uniform float core_intensity = 0.0;
uniform float core_radius = 0.1;
// 0..1 through the arcs' life: how far they have travelled and thinned.
uniform float ring_life = 0.0;
// The vertical light streak while it charges.
uniform float beam = 0.0;
// The white bloom disc.
uniform float bloom_intensity = 0.0;
uniform float bloom_radius = 0.3;
// The expanding ring, and how far it has broken into arcs (0 whole, 1 gone).
uniform float ring_intensity = 0.0;
uniform float ring_radius = 0.4;
uniform float ring_width = 0.05;
uniform float sparkle = 0.0;

const float PI_ = 3.14159265;
const int SPARKLES = 16;
// Each arc covers ARC_FILL of its third of the circle (the rest is the gap); ARC_ROTATION turns the set (turns).
const float ARC_FILL = 0.72;
const float ARC_ROTATION = 0.08;

float hash1(float n) {
	return fract(sin(n * 127.1 + seed * 31.7) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Three octaves: broad wander plus the fine notches of a torn edge.
float fbm(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.1 + 3.7) * 0.28 + noise2(p * 4.3 + 7.1) * 0.17;
}

// Smooth 1D noise around the circle: `a` in turns (0..1), periodic with `cells` cells.
float ring_noise(float a, float cells, float salt) {
	float x = a * cells;
	float i = floor(x);
	float f = fract(x);
	float h0 = hash1(mod(i, cells) + salt);
	float h1 = hash1(mod(i + 1.0, cells) + salt);
	return mix(h0, h1, f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0) * half_extent;
	float r = length(q);
	float a = atan(q.y, q.x) / (2.0 * PI_) + 0.5;
	vec3 col = vec3(0.0);

	// ORB / CORE: a white-hot centre inside a warm halo.
	float core = exp(-pow(r / max(core_radius, 0.001), 2.0));
	float halo = exp(-pow(r / max(core_radius * 2.4, 0.001), 2.0));
	// A shimmer rippling outward through the orb. Radial only: an angular term drew a pinwheel once the core faded.
	float churn = 0.9 + 0.1 * sin(r * 40.0 - time * 14.0);
	col += core_color.rgb * core * core_intensity * churn * 1.4;
	col += glow_color.rgb * halo * core_intensity * 0.55;

	// BEAM: a thin vertical streak through the card, brightest at the centre.
	float beam_line = exp(-pow(q.x / 0.012, 2.0)) * exp(-pow(q.y / 0.75, 2.0));
	float beam_soft = exp(-pow(q.x / 0.05, 2.0)) * exp(-pow(q.y / 0.6, 2.0)) * 0.35;
	col += mix(glow_color.rgb, core_color.rgb, 0.6) * (beam_line + beam_soft) * beam;

	// BLOOM: a soft white disc, slightly ragged, with a brighter rim.
	float wobble = (ring_noise(a, 9.0, 3.0) - 0.5) * 0.08 * bloom_radius;
	float edge = bloom_radius + wobble;
	float disc = smoothstep(edge, edge * 0.82, r);
	float rim = exp(-pow((r - edge * 0.9) / (0.08 * bloom_radius + 0.01), 2.0));
	col += core_color.rgb * (disc * 0.85 + rim * 0.6) * bloom_intensity;

	// RING: THREE identical, evenly spaced, smooth arcs on one circle. Each is a symmetric crescent (fat in the middle,
	// tapering to both tips). They are born thick, travel outward with the ring and LOSE THICKNESS as they go, never
	// length: the width is the arc's fixed profile scaled down by one factor, so it stays as long as it was born.
	float ar = fract(a - ARC_ROTATION);
	float centre_r = ring_radius;
	float cell = ar * 3.0;
	float u = fract(cell) / ARC_FILL;
	float prof = u <= 1.0 ? pow(sin(PI_ * u), 0.6) : 0.0;
	float thin = pow(max(1.0 - ring_life, 0.0), 1.3);
	float w = ring_width * prof * thin;
	float d = abs(r - centre_r);
	// Hard edge, a whisper of glow (the reference's stroke is crisp).
	// GUARDED: in a gap w is exactly 0, and smoothstep(0, 0, d) is undefined in GLSL - it drew grainy NaN wedges.
	float has = step(0.0002, w);
	float wg = max(w, 0.0002);
	float stroke = (1.0 - smoothstep(wg * 0.72, wg, d)) * has;
	float halo_r = exp(-pow(d / (wg * 2.2), 2.0)) * 0.18 * has;
	col += mix(glow_color.rgb, ring_color.rgb, 0.85) * (stroke + halo_r) * ring_intensity * 1.35;
	// Inner soft fill on the arcs' inside, like the reference's light filling the ring; fades as they travel.
	float inner = smoothstep(ring_radius, ring_radius * 0.5, r) * smoothstep(0.0, ring_radius * 0.6, r) * 0.12;
	col += glow_color.rgb * inner * ring_intensity * (1.0 - ring_life);

	// SPARKLES: small four-point stars scattered around the ring, twinkling.
	if (sparkle > 0.0) {
		for (int i = 0; i < SPARKLES; i++) {
			float fi = float(i);
			float ang = hash1(fi * 3.1) * 2.0 * PI_;
			float rad = mix(0.25, 1.15, hash1(fi * 5.7));
			vec2 c = vec2(cos(ang), sin(ang)) * rad;
			vec2 d = abs(q - c);
			float tw = 0.5 + 0.5 * sin(time * mix(10.0, 22.0, hash1(fi * 9.3)) + fi * 2.0);
			float size = mix(0.018, 0.04, hash1(fi * 1.9));
			float star = exp(-d.x / (size * 0.12)) * exp(-d.y / size) + exp(-d.y / (size * 0.12)) * exp(-d.x / size);
			star += exp(-dot(q - c, q - c) / (size * size * 0.05)) * 0.8;
			col += core_color.rgb * star * tw * sparkle;
		}
	}

	// Nothing reaches the quad's edge (the ring's widest point stays well inside it).
	col *= smoothstep(half_extent, half_extent * 0.9, r);
	ALBEDO = min(col, vec3(4.0));
	ALPHA = 1.0;
}
