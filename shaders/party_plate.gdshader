shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

// The party plate: a rounded translucent panel under the members, with a brighter rim. `size` is the plane's size in
// metres, so the corner radius and rim stay the same width however many members the plate spans.
uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.2, 1.0);
uniform vec2 size = vec2(1.0, 1.0);
uniform float radius = 0.07;
uniform float rim = 0.014;
uniform float fill_alpha = 0.32;
uniform float rim_alpha = 0.9;

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = abs(p) - (size * 0.5 - radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float aa = fwidth(d);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float on_rim = 1.0 - smoothstep(-aa, aa, abs(d + rim * 0.5) - rim * 0.5);
	ALBEDO = tint.rgb;
	ALPHA = inside * mix(fill_alpha, rim_alpha, on_rim) * tint.a;
}
