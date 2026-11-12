shader_type canvas_item;
// The "EX BURST" title (scripts/vfx/ex_burst_reveal.gd). Drawn on a Label whose font colour is WHITE and outline
// BLACK, so the incoming COLOR says which is which: the fill becomes a vertical gold gradient with a shine band
// sweeping across it, the outline a deep brown. After Clips/damage_trigger frames 194+ ("Critical Trigger").

uniform vec4 top_color : source_color = vec4(1.0, 0.99, 0.80, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.86, 0.28, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.86, 0.50, 0.06, 1.0);
uniform vec4 outline_color : source_color = vec4(0.22, 0.10, 0.02, 1.0);
/// The label's size in its own pixels, to normalise the glyph positions.
uniform vec2 label_size = vec2(800.0, 160.0);
/// 0..1 across the label: where the shine band is (outside 0..1 = no shine).
uniform float shine = -1.0;

varying vec2 pos;

void vertex() {
	pos = VERTEX / label_size;
}

void fragment() {
	float fill = clamp(COLOR.r, 0.0, 1.0);
	float y = clamp(pos.y, 0.0, 1.0);
	vec3 gold = y < 0.5 ? mix(top_color.rgb, mid_color.rgb, y * 2.0) : mix(mid_color.rgb, bottom_color.rgb, (y - 0.5) * 2.0);
	float s = (pos.x + (0.5 - pos.y) * 0.35 - shine) / 0.07;
	gold = mix(gold, vec3(1.0), exp(-s * s) * 0.85);
	COLOR = vec4(mix(outline_color.rgb, gold, fill), COLOR.a);
}
