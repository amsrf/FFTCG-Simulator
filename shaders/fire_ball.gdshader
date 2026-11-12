shader_type spatial;
// The fireball of the fire burst (fire_burst.gd): a camera-facing quad. Everything is procedural: a disc whose edge is
// torn by noise that flows OUTWARD, coloured by a temperature ramp (white -> yellow -> orange -> red -> smoke). `age`
// 0..1 drives the whole life: the ball is white-hot and solid at 0, cools, and DISSIPATES FROM THE CENTRE OUT - a
// void opens in the middle and widens until the outer ring of fire and smoke frays away last. It never shrinks.
// Alpha-blended so the flame keeps its colour over the pale board (additive light washes out there).

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform float age = 0.0;
uniform float intensity = 1.0;
uniform float seed = 0.0;
uniform vec4 hot_color : source_color = vec4(1.0, 0.97, 0.80, 1.0);
uniform vec4 yellow_color : source_color = vec4(1.0, 0.78, 0.22, 1.0);
uniform vec4 orange_color : source_color = vec4(1.0, 0.40, 0.05, 1.0);
uniform vec4 red_color : source_color = vec4(0.72, 0.08, 0.03, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.32, 0.24, 0.20, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

vec3 ramp(float heat) {
	vec3 c = smoke_color.rgb;
	c = mix(c, red_color.rgb, smoothstep(0.10, 0.30, heat));
	c = mix(c, orange_color.rgb, smoothstep(0.30, 0.50, heat));
	c = mix(c, yellow_color.rgb, smoothstep(0.50, 0.70, heat));
	c = mix(c, hot_color.rgb, smoothstep(0.72, 0.92, heat));
	return c;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float ang = atan(p.y, p.x);
	// Polar noise: angular lobes, flowing outward with age (the radial term slides), plus a second fine layer.
	vec2 polar = vec2(cos(ang), sin(ang)) * 2.2 + vec2(seed * 0.37, seed * 0.91);
	float n = fbm(polar + vec2(0.0, -d * 3.0 + age * 3.5));
	float n2 = fbm(p * 4.5 + vec2(seed, age * 2.0));
	// The torn edge: the ball's radius wobbles with the lobes and keeps swelling with age (it never pulls back in).
	float radius = 0.52 + 0.38 * n + 0.12 * age;
	float body = 1.0 - d / max(radius, 0.05);
	float edge = smoothstep(0.0, 0.12, body);
	// DISSIPATION FROM THE CENTRE OUT, AS A GRADIENT. Transparency rises smoothly from the middle outward: a wide soft
	// band (`FADE_BAND`, in fractions of the radius) slides from inside the centre past the rim, so every point fades
	// from opaque to fully transparent over a good part of the life, the centre first and the outer edge last. Nothing
	// switches off: the band is wide and the noise only nudges it. `r` is the distance as a fraction of the torn radius.
	float r = d / max(radius, 0.05);
	const float FADE_BAND = 0.9;
	// LINEAR in age: an eased front lingered and then rushed through the rim, which read as a sudden vanish.
	float front = mix(-FADE_BAND, 1.05, clamp((age - 0.30) / 0.70, 0.0, 1.0));
	float clear = clamp((r + (n2 - 0.5) * 0.25 - front) / FADE_BAND, 0.0, 1.0);
	float alpha = edge * clear * clear * (3.0 - 2.0 * clear);
	// Temperature: hottest in the middle early on, cooling SLOWLY with age. The colour must outlast the fade: when the
	// ball cooled fast it turned to faint smoke before the transparency reached it, and the fire seemed to vanish.
	float heat = clamp(body * 1.1 + n2 * 0.35 + 0.15 - age * 0.55, 0.0, 1.0);
	heat = max(heat, (1.0 - smoothstep(0.0, 0.30, age)) * (1.0 - d * 0.9));
	vec3 col = ramp(heat);
	// Smoke is thinner than flame.
	float smoke = 1.0 - smoothstep(0.08, 0.32, heat);
	alpha *= mix(1.0, 0.65, smoke) * intensity;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0) * step(d, 1.0);
}
