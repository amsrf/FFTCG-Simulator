shader_type spatial;
// The gem/stone of the button.
//
// THE RAMP AXIS IS GEOMETRY, NOT UV. An earlier version used UV.y and came out upside down: the
// reasoning went "the unwrap runs along Blender's +Y, the glTF +Y-up conversion sends that to -Z,
// screen-up is +Z, so UV.y = 0 is the top" — but Blender writes UVs V-up while the glTF exporter
// FLIPS V, so the axis was the opposite of the assumption. The mesh's own coordinates have no such
// convention to get wrong: Background carries no rotation, the buttons are unrotated, and the match
// camera's up axis is world +Z, so model +Z IS up on screen. tests/button_probe.tscn asserts that
// against the camera rather than trusting it. UVs are still used, but only for the HORIZONTAL axis,
// where their orientation is symmetric and cannot invert anything.
//
// THE ALBEDO SITS *UNDER* THE REFERENCE'S PIXELS, ON PURPOSE. references/button_idea_reference.png
// was sampled for its ramp, but those are FINISHED PIXELS — the result of that artist's lighting
// already applied. Using them as albedo means the game adds the board's ambient, this shader's own
// emission and the specular sheen ON TOP, so the gem always came out lighter and greyer. The stops
// are therefore darker and more saturated than the sampled pixels, `saturation` pushes them further
// from grey, and `ambient_occlusion` trims the ambient that does most of the whitening.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

group_uniforms stone;
// How much model-space height one full ramp covers. The stone's own mesh spans 0.826 of the model's
// face height, so it is set to that in gem_button_stone.tres; the probe asserts it against the real
// mesh extent, because a hard-coded span goes stale the moment the generator is re-run.
uniform float face_span = 1.0;

// The ramp, top to bottom. The reference's pixels are #EAFEFB, #6FD8D0, #2BA79E and #03332C; these
// are those colours taken DARKER and more saturated, because light is added on top of them.
uniform vec3 stone_top : source_color = vec3(0.88, 1.00, 0.97);
uniform vec3 stone_upper : source_color = vec3(0.26, 0.78, 0.72);
uniform vec3 stone_mid : source_color = vec3(0.055, 0.50, 0.45);
uniform vec3 stone_deep : source_color = vec3(0.005, 0.105, 0.09);
uniform vec3 rim_color : source_color = vec3(0.01, 0.16, 0.14);

// THE LIGHT ENTERS AT THE TOP MIDDLE. Brightness falls off with DISTANCE from that point — downward
// and out toward the ends alike — so the ends read darker than the middle and the white stays a
// pool at the top centre. This replaced a purely vertical ramp, which made the whole top row
// equally white.
uniform float crown_stop : hint_range(0.0, 1.0) = 0.25;
uniform float mid_stop : hint_range(0.0, 1.0) = 0.45;
// How fast it darkens: toward the left/right ends, and downward.
uniform float side_spread : hint_range(0.5, 4.0) = 1.9;
uniform float vertical_spread : hint_range(0.5, 3.0) = 1.0;

// Push every colour away from grey. 1.0 = exactly the ramp's colours, >1 = more vivid.
uniform float saturation : hint_range(0.0, 2.0) = 1.35;
// The thin specular line along the very top edge of the stone.
uniform float top_line : hint_range(0.0, 0.3) = 0.03;
uniform float line_boost : hint_range(0.0, 1.0) = 0.5;

// CRYSTAL. Facets are soft planes running through the stone, and a bright edge is what glass does at
// grazing angles — between them they read as crystal rather than as a smooth plastic dome. Both are
// deliberately subtle: they add structure, they do not repaint the gem.
uniform float facet_strength : hint_range(0.0, 1.0) = 0.30;
uniform float facet_freq : hint_range(1.0, 24.0) = 7.0;
uniform vec2 facet_dir = vec2(0.85, 1.0);
uniform float edge_glow : hint_range(0.0, 1.0) = 0.30;

// 0 = the lit stone, 1 = the reference's grey "unavailable" one (the same ramp, desaturated).
uniform float grey_mix : hint_range(0.0, 1.0) = 0.0;
// The LEVEL of the glow belongs to the button: lit, brighter on hover, almost out when disabled.
uniform float emission_strength : hint_range(0.0, 4.0) = 1.0;
uniform float roughness_value : hint_range(0.02, 1.0) = 0.10;
// Low: a gem has a tight highlight, not a broad white sheen. 0.9 here washed the green out.
uniform float sheen : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.5;
// Cuts the board's ambient on this surface. 1.0 = untouched.
uniform float ambient_occlusion : hint_range(0.0, 1.0) = 0.55;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

varying float v_up;

void vertex() {
	// 1 at the top of the button as the player sees it, 0 at the bottom.
	v_up = VERTEX.z / max(face_span, 0.001) + 0.5;
}

void fragment() {
	// 0 at the top, 1 at the bottom.
	float down = clamp(1.0 - clamp(v_up, 0.0, 1.0), 0.0, 1.0);
	// Distance from the point the light enters: the top middle of the gem.
	vec2 p = vec2((UV.x - 0.5) * side_spread, down * vertical_spread);
	float d = clamp(length(p), 0.0, 1.0);

	vec3 body = mix(stone_top, stone_upper, smoothstep(0.0, crown_stop, d));
	body = mix(body, stone_mid, smoothstep(crown_stop, mid_stop, d));
	body = mix(body, stone_deep, smoothstep(mid_stop, 1.0, d));
	// Away from grey, so the hue stays strong instead of drifting toward white.
	body = mix(vec3(dot(body, LUMA)), body, saturation);

	// Soft facet planes through the stone, multiplied in so they modulate the ramp rather than
	// laying a pattern over it.
	float facet = sin(dot(UV - vec2(0.5), normalize(facet_dir)) * facet_freq * 3.14159);
	body *= 1.0 + facet_strength * facet * 0.35;

	vec3 color = body;
	// The bright line along the top edge.
	float line = 1.0 - smoothstep(0.0, max(top_line, 0.001), d);
	color = mix(color, stone_top * 1.06, line * line_boost);

	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// A BRIGHT edge first — the tight grazing-angle sheen that glass has — then a darker rim a little
	// further in, which is what gives the gem its thickness.
	color += stone_top * pow(1.0 - ndv, 4.0) * edge_glow;
	color = mix(color, rim_color, pow(1.0 - ndv, 2.0) * rim_strength);

	// The grey state is the same ramp in monochrome, which is exactly how the reference draws its
	// unavailable button: same luminance structure, no hue. Applied last so it always wins.
	float grey = dot(color, LUMA);
	color = mix(color, vec3(grey) * 1.08, grey_mix);

	vec3 glow = mix(body, stone_top, line * line_boost);
	glow = mix(glow, vec3(dot(glow, LUMA)), grey_mix);

	ALBEDO = color;
	// Weighted to the TOP: the glow belongs to the lit crown, not to the whole stone. An even glow
	// lifted the mid and dark greens and was a second reason the gem read pale.
	EMISSION = glow * emission_strength * pow(down, 1.6);
	METALLIC = 0.0;
	ROUGHNESS = roughness_value;
	SPECULAR = sheen;
	AO = ambient_occlusion;
}
