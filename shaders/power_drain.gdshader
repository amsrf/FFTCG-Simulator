shader_type spatial;
// The power DRAIN (power_down_drain.gd). A camera-facing quad.
//   shape 0: a spark - a soft streak, bright head at the quad's TOP (UV.y = 0 is local +Y), thinning to nothing at
//            its tail.
//   shape 1: an orb - a solid lilac-white ball in a halo. The impact flash, and the orbs that burst out.
// The palette is the obsidian sword's: violet-magenta glow, lilac-white cores.
// Alpha-blended, never additive: additive light washes the card art behind it to white.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 mote_color : source_color = vec4(0.74, 0.30, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.97, 0.90, 1.0, 1.0);
uniform float intensity = 0.0;
uniform float shape = 0.0;
// Orb only: 0..1, a white flash over the whole orb (the moment it bursts).
uniform float flash = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (shape < 0.5) {
		float head = 1.0 - UV.y;
		float across = abs(p.x);
		// Edges always ascending: smoothstep with e0 >= e1 is undefined in GLSL (and drew nothing here).
		float body = (1.0 - smoothstep(0.15, 1.0, across)) * pow(head, 1.2) * (1.0 - smoothstep(0.88, 1.0, head));
		ALBEDO = mix(mote_color.rgb, core_color.rgb, head * head * (1.0 - across));
		ALPHA = clamp(body * intensity, 0.0, 1.0);
	} else {
		float d = length(p);
		// A solid white-hot ball (most of the quad) in a gold halo that fades to the quad's edge.
		float core = 1.0 - smoothstep(0.30, 0.46, d);
		float halo = exp(-d * 2.6) * (1.0 - smoothstep(0.7, 1.0, d));
		vec3 col = mix(mote_color.rgb, core_color.rgb, clamp(core + flash, 0.0, 1.0));
		ALBEDO = col;
		ALPHA = clamp((core + halo * 0.9) * intensity, 0.0, 1.0);
	}
}
