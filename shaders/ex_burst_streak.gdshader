shader_type canvas_item;
// The light streak the "EX BURST" title rides in on (scripts/vfx/ex_burst_reveal.gd): a thin white-gold line with a
// soft gold glow, drawn left to right (`reveal`) with a fading tail, then dimming (`intensity`). Additive.
render_mode blend_add;

uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.82, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.15, 1.0);
uniform float reveal = 0.0;
uniform float intensity = 1.0;

void fragment() {
	float v = UV.y * 2.0 - 1.0;
	float core = exp(-v * v / 0.004);
	float glow = exp(-v * v / 0.12);
	// Brightest at the head, fading back along the tail; nothing beyond the head.
	float behind = reveal - UV.x;
	float head = behind >= 0.0 ? mix(0.35, 1.0, exp(-behind / 0.25)) : 0.0;
	float ends = smoothstep(0.0, 0.08, UV.x) * (1.0 - smoothstep(0.92, 1.0, UV.x));
	vec3 c = core_color.rgb * core * 1.4 + glow_color.rgb * glow * 0.55;
	COLOR = vec4(c * head * ends * intensity, 1.0);
}
