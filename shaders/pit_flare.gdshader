shader_type spatial;
// THE PIT'S SWALLOW FLARE (Pit.flare()): after a card has gone in, bright crescents in the pit's colour whirl round
// the rim and fade (~/Desktop/Clips/pits frames 105-115). Additive and flat on the pit's top. `t` runs 0..1 over the
// flare's life and is the only animated input, so a demo can freeze any moment.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 flare_color : source_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform float t : hint_range(0.0, 1.0) = 0.0;
// The pit's outer radius as a fraction of this quad's half-size (the quad is bigger than the pit, so the
// crescents can spill past the rim).
uniform float pit_radius = 0.72;
uniform float seed = 0.0;

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d) / pit_radius;
	float ang = atan(d.y, d.x);
	// Life: a fast rise, a long fade.
	float life = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.35, 1.0, t));
	// The band sits on the rim and swells outward a little as it lives.
	float centre = 0.86 + 0.16 * t;
	float width = 0.10 + 0.10 * (1.0 - t);
	float band = exp(-pow((r - centre) / width, 2.0));
	// Four crescents, whirling: thick in the middle of each arc, thin at its ends, with a gap between arcs.
	float spin = ang * 4.0 / 6.28318 + seed + t * 1.6;
	float arc = fract(spin);
	float crescent = smoothstep(0.0, 0.25, arc) * (1.0 - smoothstep(0.55, 0.92, arc));
	// A hot inner edge on each crescent, and a faint full ring underneath so the arcs read as one swirl.
	float hot = exp(-pow((r - centre + width * 0.45) / (width * 0.35), 2.0)) * crescent;
	float glow = band * (0.25 + 0.95 * crescent) + 0.9 * hot;
	// A brief bloom filling the mouth at the very start.
	float mouth = (1.0 - smoothstep(0.0, 0.7, r)) * (1.0 - smoothstep(0.0, 0.25, t)) * 0.6;
	vec3 col = flare_color.rgb * (glow + mouth) + vec3(1.0) * hot * 0.35;
	ALBEDO = col * life;
}
