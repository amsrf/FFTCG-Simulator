shader_type spatial;
// THE TOP OF A PIT (scripts/game/pit.gd): the Break Zone / Removed pile seen from above, after the Master Duel
// graveyard/banish pits (~/Desktop/Clips/pits frame 62). One opaque disc, everything painted in polar coordinates:
//   r 1.00 .. RIM      the housing: dark slate with three neon rings in the pit's colour
//   RIM .. WELL        a bevelled lip, lit on its outer edge and falling into shadow
//   WELL .. 0          the well: near-black, darker toward the centre, with a slow faint smoke in the pit's colour
// Opaque on purpose: a card sinking into the pit passes through this disc and is CLIPPED by it, which is what reads
// as "pulled into the hole". Unshaded, so the rings keep their colour under the top-down light.
render_mode unshaded, cull_disabled;

uniform vec4 ring_color : source_color = vec4(0.18, 0.40, 1.0, 1.0);
uniform vec4 housing_color : source_color = vec4(0.10, 0.12, 0.16, 1.0);
// Where the lip starts and where the well starts, as a fraction of the radius.
uniform float rim = 0.66;
uniform float well = 0.54;
// Three rings: centres and half-width, fractions of the radius.
uniform vec3 ring_radii = vec3(0.73, 0.82, 0.91);
uniform float ring_half_width = 0.018;
uniform float smoke_strength : hint_range(0.0, 1.0) = 0.8;
// 0..1, raised by Pit.flare(): the rings flash brighter while a card goes in.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	if (r > 1.0) {
		discard;
	}
	float aa = fwidth(r) * 1.5 + 1e-4;
	float ang = atan(d.y, d.x);
	vec3 col = housing_color.rgb;

	// HOUSING: a faint radial sheen so the drum top is not a flat cut-out, and a lit outer edge.
	col *= 0.85 + 0.25 * smoothstep(rim, 1.0, r);
	col = mix(col, housing_color.rgb * 2.0, smoothstep(0.955, 0.99, r) * (1.0 - smoothstep(0.99, 1.0, r)));

	// THE RINGS: dashed neon arcs (each ring has its own few gaps), a hot core plus a soft spill. mix(), never +=.
	float glow = 1.0 + 0.8 * pulse;
	for (int i = 0; i < 3; i++) {
		float c = ring_radii[i];
		float dist = abs(r - c);
		float seg = fract(ang / 6.28318 * 5.0 + float(i) * 0.37);
		float dash = smoothstep(0.0, 0.02, seg) * (1.0 - smoothstep(0.86, 0.9, seg));
		float core = (1.0 - smoothstep(ring_half_width - aa, ring_half_width + aa, dist)) * dash;
		float spill = exp(-dist * dist / (2.0 * 0.028 * 0.028)) * 0.45 * dash;
		col = mix(col, ring_color.rgb * 0.5, clamp(spill * glow, 0.0, 1.0));
		col = mix(col, min(ring_color.rgb * (1.0 + 0.4 * pulse), vec3(1.0)), core);
	}

	// THE LIP: a pale slate bevel between the rings and the well, lit on its outer edge and shadowed as it drops.
	if (r < rim) {
		float k = clamp((r - well) / max(rim - well, 1e-4), 0.0, 1.0);
		vec3 lip_light = vec3(0.30, 0.36, 0.40);
		vec3 lip_dark = vec3(0.08, 0.09, 0.11);
		col = mix(lip_dark, lip_light, smoothstep(0.0, 0.85, k));
		col = mix(col, housing_color.rgb, smoothstep(0.9, 1.0, k));
	}

	// THE WELL: charcoal, darker toward its wall (the wall is in shadow under the lip), with slow smoke turning in it.
	if (r < well) {
		float depth = r / well;
		vec3 dark = mix(vec3(0.13, 0.13, 0.16), vec3(0.035, 0.035, 0.05), smoothstep(0.25, 1.0, depth));
		vec2 swirl = vec2(cos(ang + TIME * 0.35 + r * 3.0), sin(ang + TIME * 0.35 + r * 3.0)) * r * 2.4;
		float s = fbm(swirl * 1.6 + vec2(TIME * 0.12, -TIME * 0.09));
		float core = 1.0 - smoothstep(0.0, well * 0.8, r);
		float smoke = smoothstep(0.35, 0.8, s) * core * smoke_strength * (1.0 + pulse);
		col = mix(dark, ring_color.rgb * 0.8, clamp(smoke, 0.0, 1.0));
	}
	ALBEDO = col;
}
