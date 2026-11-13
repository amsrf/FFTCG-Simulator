shader_type spatial;
// One half of the "cannot block" shield (scripts/vfx/shield_tear.gd). Drawn like the power-up swords
// (power_up_sword.gdshader): the art is a texture rasterised at runtime from an SVG (soft glow stroke + translucent fill +
// bright outline); this only fades it and gives it a white flash. Alpha-blended, never additive: additive washes out over
// bright card art.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D piece_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float intensity = 1.0;
// 0..1: how white the piece is (as it settles, and as it gives way).
uniform float flash = 0.0;

void fragment() {
	vec4 t = texture(piece_tex, UV);
	ALBEDO = mix(t.rgb, vec3(0.92, 0.97, 1.0), flash * 0.85);
	ALPHA = clamp(t.a * intensity, 0.0, 1.0);
}
