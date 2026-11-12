shader_type spatial;
// The broken card's last two frames (card_destroy_burst.gd): its own artwork on its own mesh, washed to white
// (`whiten`) and faded out (`fade`) while the script swells it. The rules have already moved the real card to the
// Break Zone; this is the picture of it popping.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap;
uniform vec4 flash_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float whiten = 0.0;
uniform float fade = 1.0;

void fragment() {
	vec4 art = texture(texture_albedo, UV);
	// Brighter toward the rim, so the card reads as bursting with light rather than simply turning pale.
	vec2 e = abs(UV * 2.0 - 1.0);
	float rim = smoothstep(0.55, 1.0, max(e.x, e.y));
	ALBEDO = mix(art.rgb, flash_color.rgb, clamp(whiten * (0.85 + 0.15 * rim), 0.0, 1.0));
	ALPHA = clamp(fade, 0.0, 1.0);
}
