shader_type spatial;
// The gem/stone of the button.
//
// What this has to fake: the reference stone is a translucent cabochon, lit from within, with a
// fresnel rim. Godot's `transmission` (refraction) is Forward+ only and this project runs
// gl_compatibility, so a real glass shader is unavailable. Instead the read is built from:
//   * a vertical gradient — dark at the bottom, bright a little ABOVE centre (the reference's
//     "lit from within" look comes mostly from this, not from the highlights);
//   * emission modulated by the same gradient, so the centre glows and the edges stay deep;
//   * a fresnel term that darkens and saturates the silhouette, which is what sells "thick
//     glass" without any actual transmission.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

group_uniforms stone;
uniform vec3 stone_deep : source_color = vec3(0.02, 0.155, 0.165);
uniform vec3 stone_bright : source_color = vec3(0.30, 0.90, 0.84);
uniform vec3 rim_color : source_color = vec3(0.04, 0.30, 0.32);
// 0 = a dead grey stone (the reference's unlit/disabled state), the default = the lit one.
uniform float emission_strength : hint_range(0.0, 4.0) = 1.1;
uniform float roughness_value : hint_range(0.02, 1.0) = 0.12;
uniform float sheen : hint_range(0.0, 1.0) = 0.85;
// Where the bright zone sits, in UV. 0.5 = dead centre, <0.5 = above centre.
uniform float bright_centre = 0.42;
// How wide the bright zone is: 0 = one hot pixel, 1 = the whole face.
uniform float bright_spread : hint_range(0.05, 2.0) = 1.15;
// How much of the rim the fresnel term darkens.
uniform float rim_strength : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	// Distance from the bright point, with the vertical axis stretched so the gradient reads as
	// a glow rather than a circle.
	float dx = (UV.x - 0.5) * 1.6;
	float dy = UV.y - bright_centre;
	float d = clamp(length(vec2(dx, dy)) * bright_spread, 0.0, 1.0);
	float core = pow(1.0 - d, 1.7);

	// Thick glass darkens at grazing angles.
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

	vec3 inner = mix(stone_deep, stone_bright, core);
	ALBEDO = mix(inner, rim_color, fres * rim_strength);
	EMISSION = inner * emission_strength * (0.30 + 0.70 * core);
	METALLIC = 0.0;
	ROUGHNESS = roughness_value;
	SPECULAR = sheen;
}
