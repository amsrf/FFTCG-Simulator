shader_type spatial;
// Tornado base waves (Desktop/Clips/green_tornado_3.mp4, "base_waves"): a shallow bowl ring at the floor,
// spawned repeatedly by wind_tornado.gd. Each one swells outward and up, turns, and dissolves, textured with
// T_FirePanningCyl45 panning around it - torn wisps, never a solid band.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D wisp_tex : hint_default_black, repeat_enable, filter_linear_mipmap;  // T_FirePanningCyl45
uniform vec3 light_color : source_color = vec3(0.94, 1.0, 0.96);
uniform vec3 shadow_color : source_color = vec3(0.45, 0.62, 0.56);
uniform float life : hint_range(0.0, 1.0) = 0.5;   // 0 = just spawned, 1 = gone
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float spin = 0.0;                          // turns, advanced by the script
uniform float seed = 0.0;

void fragment() {
	// The texture's flames are vertical strokes: lay that axis AROUND the ring so they become curling arcs
	// (a swirl), not petals pointing outward. UV.x goes once around (x2, seamless), UV.y inner -> outer rim.
	vec2 p = vec2(UV.y * 0.55 + life * 0.2 + seed, UV.x * 2.0 + spin + seed * 0.37);
	vec4 wisp = texture(wisp_tex, p);
	float strength = wisp.a * (0.35 + wisp.r * 0.9);
	// Eats away from the thin parts as it ages, so it dissolves into wisps instead of fading evenly.
	float cut = smoothstep(life * 0.75, life * 0.75 + 0.25, strength);
	float rims = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));
	float fade = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.55, 1.0, life));
	ALBEDO = mix(shadow_color, light_color, clamp(wisp.r * 1.2, 0.0, 1.0));
	ALPHA = clamp(cut * strength * rims * fade * opacity * 0.75, 0.0, 1.0);
}
