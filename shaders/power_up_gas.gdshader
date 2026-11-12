shader_type spatial;
// The red gas of the power-up (power_up_burst.gd), and its streak lines. A camera-facing quad.
//   shape 0: a smoke puff — a soft round mask eaten by drifting value-noise fbm, dark crimson rim to a hot red core.
//   shape 1: a streak — a thin vertical line, bright at its head (top) and thinning to nothing at its tail.
// Alpha-blended: the gas must darken-and-redden the board and the card, not bleach them.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 rim_color : source_color = vec4(0.55, 0.02, 0.03, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.18, 0.10, 1.0);
uniform float intensity = 0.0;
uniform float seed = 0.0;
// 0..1 over the puff's life: scrolls and dissolves the noise.
uniform float age = 0.0;
uniform float shape = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (shape > 0.5) {
		// UV.y = 0 is the quad's TOP edge: the head is there.
		float along = UV.y;
		float across = abs(p.x);
		float body = (1.0 - smoothstep(0.15, 1.0, across)) * pow(1.0 - along, 1.6) * smoothstep(0.0, 0.08, along);
		ALBEDO = mix(core_color.rgb, vec3(1.0, 0.7, 0.6), (1.0 - along) * (1.0 - across) * 0.6);
		ALPHA = clamp(body * intensity, 0.0, 1.0);
	} else {
		float d = length(p);
		vec2 q = p * 1.6 + vec2(seed * 3.1, seed * 1.7) + vec2(0.0, age * 1.4);
		float n = fbm(q + fbm(q * 1.3 - age * 0.8) * 0.9);
		float mask = 1.0 - smoothstep(0.25, 1.0, d + (n - 0.5) * 0.55);
		// It thins into wisps as it ages instead of fading as one flat disc.
		float wisps = smoothstep(age * 0.55, age * 0.55 + 0.35, n);
		float dens = mask * wisps;
		ALBEDO = mix(rim_color.rgb, core_color.rgb, clamp(dens * 1.4 - 0.1 + (1.0 - d) * 0.3, 0.0, 1.0));
		ALPHA = clamp(dens * intensity, 0.0, 1.0);
	}
}
