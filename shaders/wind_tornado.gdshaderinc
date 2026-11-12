// Shared by the two tornado meshes (Desktop/Clips/tornado_4.mp4, step 3 "mix it"):
//   wind_tornado.gdshader       mesh A, translucent smoke with relief
//   wind_tornado_core.gdshader  mesh B, the SAME mesh with an additive shader (bright core streaks)
// Both deform identically, so the core always sits inside the smoke.

uniform float age = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// 0 = solid, 1 = fully eroded (forms at the start, tears apart at the end).
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

uniform float twist = 3.6;          // turns the streaks make from the floor rim to the top
uniform float spin_speed = 1.5;     // pattern revolutions per second
uniform float rise_speed = 0.45;
uniform float advection = 0.35;
uniform float uv_distort = 0.05;    // the normal texture distorting the UVs (step 3)

// Perlin WPO (step 3): the column is NOT a uniform tube. Its cross-section bulges and pinches at different
// heights, is out of round, and the bulges travel upward; the whole axis snakes.
uniform float section_var = 0.62;   // log-scale variance: exp(+-) so pinches are as strong as bulges
// Dedicated waists: a slow noise band that squeezes the whole ring (round, not out-of-round) and climbs the
// column, so a thin neck travels up between bulges. pinch_depth is the fraction removed at its tightest.
uniform float pinch_depth = 0.55;
uniform float pinch_freq = 2.6;     // ~waists per column height (x0.5 cycles of the climbing wave)
uniform float snake = 0.16;         // axis wander, object units
uniform float sway = 0.06;

// Lean toward the camera's screen-up (set from the active camera by wind_tornado.gd); see wind_tornado.gd.
uniform vec3 lean_axis = vec3(1.0, 0.0, 0.0);
uniform float lean_angle = 0.0;
uniform float bend_height = 0.45;

varying float v_floor;   // 0 at the floor, 1 at the top (object height fraction)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Value noise that wraps in x with an integer period, so nothing has a seam around the column.
float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	float a = hash(vec2(x0, i.y));
	float b = hash(vec2(x1, i.y));
	float c = hash(vec2(x0, i.y + 1.0));
	float d = hash(vec2(x1, i.y + 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, float period) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * vnoise(p, period);
		p *= 2.0;
		period *= 2.0;
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// Voronoi, wrapped in x. Returns (F1, F2) distances.
vec2 voronoi(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = i + g;
			vec2 o = hash2(vec2(mod(c.x, period), c.y));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(vec2(d1, d2));
}

// Textures from the second reference (Desktop/Clips/green_tornado_3.mp4), set by wind_tornado.gd.
uniform sampler2D wind_tex : hint_default_white, repeat_enable, filter_linear_mipmap;     // T_VFX_WindNoise1
uniform sampler2D distort_tex : hint_default_white, repeat_enable, filter_linear_mipmap;  // T_Noise1_nk
uniform sampler2D cells_tex : hint_default_white, repeat_enable, filter_linear_mipmap;    // T_Noise_HU85k
// How much of the surface is cut away. Wind is NOT a solid sheet: green_tornado_3 subtracts a gradient from
// the panned noise and ramps the rest from fully transparent, so large holes open through the funnel.
uniform float void_amount : hint_range(0.0, 1.0) = 0.26;
// Buildup: the funnel exists only below this height fraction (ragged front), growing from the floor.
uniform float reveal : hint_range(0.0, 1.2) = 1.2;
// Layers: the funnel is drawn as three close shells (wind_tornado.gd). The radius scale is applied HERE,
// before the snake and the bend, so the shells stay concentric however the column leans. Each layer reads
// the textures at its own phase and speed so their holes do not line up.
uniform float layer_scale = 1.0;
uniform float layer_phase = 0.0;
uniform float layer_speed = 1.0;

// Spiral texture coordinates: x wraps twice around (integer, so the texture tiles seamlessly), the twist
// makes the pattern follow the spiral, and it pans around and up over time.
vec2 spiral_uv(vec2 uv, float speed, float phase) {
	speed *= layer_speed;
	return vec2(uv.x * 2.0 + uv.y * twist + age * spin_speed * speed + phase + layer_phase,
		uv.y * 1.6 - age * rise_speed * speed + layer_phase * 0.7);
}

// Step 2 of tornado_4 (wind texture + advection), done with green_tornado_3's textures: the main wind noise,
// its UVs distorted by a second, slower cloud noise.
float wind_texture(vec2 uv, float phase) {
	vec2 p = spiral_uv(uv, 1.0, phase);
	vec2 bend = texture(distort_tex, p * vec2(0.5, 0.35) + vec2(age * 0.07, -age * 0.18)).rg - 0.5;
	return texture(wind_tex, p + bend * advection).r;
}

// Density after the voids: > 0 where smoke remains. Mixes in the cellular noise (moving slower, other phase)
// so holes are rounded pockets as well as streaks, then subtracts the void amount, the dissolve and the
// end fades.
float wind_density(vec2 uv, float h_tex, float v_floor_frac) {
	vec2 p = spiral_uv(uv, 0.6, 0.37);
	float cells = texture(cells_tex, p * vec2(0.8, 0.6)).r;
	float d = h_tex * 0.72 + cells * 0.38;
	float ends = smoothstep(0.0, 0.30, uv.y) * (1.0 - smoothstep(0.75, 1.0, uv.y));
	// Ragged growth front: the funnel is torn off above `reveal`.
	float front = smoothstep(0.0, 0.10, reveal - v_floor_frac + (h_tex - 0.5) * 0.18);
	return (d - void_amount - dissolve * 0.75) * front - (1.0 - ends) * 0.6;
}

// Deforms the swept tube (object space) and bends it toward the camera. Call from vertex().
void tornado_vertex(inout vec3 v, inout vec3 n, inout vec3 t, inout vec3 b, vec2 uv, float h) {
	float above_floor = smoothstep(0.02, 0.22, h);
	// Out-of-round, height-varying sections that climb over time: two octaves, low frequency in height.
	float big = vnoise(vec2(uv.x * 2.0 + age * 0.35, h * 3.0 - age * 0.9), 2.0) - 0.5;
	float small = vnoise(vec2(uv.x * 3.0 - age * 0.6, h * 7.0 - age * 1.6), 3.0) - 0.5;
	// Multiplicative, so a thin neck (x0.55) is as easy to reach as a wide belly (x1.8).
	float section = exp(section_var * (big * 1.6 + small * 0.7) * above_floor);
	// Waists: shared by every layer (no layer_phase), so the shells pinch together and stay concentric.
	// A climbing wave guarantees a neck is always somewhere on the column; noise warps its spacing and
	// depth so the waists are irregular rather than evenly stacked rings.
	float warp = vnoise(vec2(0.0, h * 1.7 - age * 0.5), 1.0) - 0.5;
	float wave = 0.5 + 0.5 * sin(6.2832 * (h * pinch_freq * 0.5 - age * 0.38) + warp * 3.5);
	float depth = 0.6 + 0.8 * vnoise(vec2(5.0, h * 1.3 - age * 0.4), 1.0);
	section *= 1.0 - clamp(pinch_depth * depth, 0.0, 0.8) * smoothstep(0.55, 1.0, wave) * above_floor;
	v.xz *= section * layer_scale;
	// Snaking axis: the centre of each section wanders, more the higher it is.
	float yy = h * 2.2 - age * 0.55;
	vec2 wander = vec2(vnoise(vec2(0.0, yy), 1.0), vnoise(vec2(0.0, yy + 17.0), 1.0)) - 0.5;
	v.xz += wander * 2.0 * snake * smoothstep(0.0, 0.6, h);
	v.xz += vec2(sin(h * 2.6 + age * 2.1), cos(h * 2.0 + age * 1.7)) * sway * h * h;

	// Bend toward screen-up: each ring turns about the floor centre by an angle growing with height.
	float phi = lean_angle * smoothstep(0.02, bend_height, v.y);
	vec3 k = normalize(lean_axis);
	float c = cos(phi);
	float s = sin(phi);
	v = v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
	n = n * c + cross(k, n) * s + k * dot(k, n) * (1.0 - c);
	t = t * c + cross(k, t) * s + k * dot(k, t) * (1.0 - c);
	b = b * c + cross(k, b) * s + k * dot(k, b) * (1.0 - c);
}
