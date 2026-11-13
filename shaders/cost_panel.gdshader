shader_type spatial;
// The mana-cost row's backing panel (scripts/ui/crystal_cost.gd): a rounded black window, semi-transparent, behind
// the crystals so they read against any card art. Sizes are in METRES (the quad's own size is passed in), so the
// corner radius and edge stay the same however many crystals the row holds.
// QuadMesh UV.y = 0 is the TOP edge; the rectangle is symmetric, so that does not matter here.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec2 panel_size = vec2(1.0, 0.4);
uniform float corner_radius = 0.06;
uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);
// A thin, faint rim so the window has an edge on dark art too.
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.16);
uniform float rim_width = 0.006;
// Antialiasing width, metres.
uniform float soft = 0.004;

void fragment() {
	vec2 p = (UV - 0.5) * panel_size;
	vec2 half_size = panel_size * 0.5;
	vec2 q = abs(p) - (half_size - vec2(corner_radius));
	float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;   // < 0 inside
	float inside = 1.0 - smoothstep(-soft, 0.0, dist);
	float rim = (1.0 - smoothstep(rim_width - soft, rim_width, -dist)) * inside;
	vec4 c = mix(fill_color, rim_color, rim * rim_color.a / max(rim_color.a, 0.001));
	ALBEDO = c.rgb;
	ALPHA = mix(fill_color.a, max(fill_color.a, rim_color.a), rim) * inside;
}
