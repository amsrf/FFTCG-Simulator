shader_type spatial;
// One of the three red swords of the power-up (power_up_burst.gd). The sword itself is a texture rasterised at
// runtime from an SVG (outline + translucent fill + soft outer stroke); this only tints it, fades it and gives it a
// white flash at birth. Alpha-blended, never additive: additive washes out over bright card art.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D sword_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 1.0;
// 0..1: how white the sword is (1 at the pop-in, gone within its appear time).
uniform float flash = 0.0;

void fragment() {
	vec4 t = texture(sword_tex, UV);
	ALBEDO = mix(t.rgb * tint.rgb, vec3(1.0, 0.92, 0.88), flash * 0.85);
	ALPHA = clamp(t.a * intensity, 0.0, 1.0);
}
