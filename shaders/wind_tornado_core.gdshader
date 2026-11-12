shader_type spatial;
// Tornado mesh B (Desktop/Clips/tornado_4.mp4, step 3): the SAME mesh as the smoke, drawn ADDITIVELY. Its own
// scroll phase, a strong fresnel that keeps only the part facing the camera (a bright streaky core), and a
// faded base ("hide the base using depth fade" - done by height here, the floor is not in a depth texture
// under Compatibility). Added on top of the translucent smoke.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/wind_tornado.gdshaderinc"

uniform vec3 core_color : source_color = vec3(0.80, 1.0, 0.88);
uniform float core_strength = 1.1;
uniform float core_fresnel = 2.6;   // higher = thinner bright core

void vertex() {
	v_floor = UV2.x;
	tornado_vertex(VERTEX, NORMAL, TANGENT, BINORMAL, UV, UV2.x);
}

void fragment() {
	vec2 uv = UV + (wind_texture(UV, 0.43) - 0.5) * uv_distort * vec2(1.0, 0.7);
	float h = wind_texture(uv, 0.0);
	float streak = wind_texture(uv, 0.61);
	// Glow only where smoke remains, so the voids stay empty instead of filling with light.
	float body = smoothstep(0.05, 0.4, wind_density(uv, h, v_floor));
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float centre = pow(facing, core_fresnel);
	float base = smoothstep(0.12, 0.45, v_floor);
	float glow = smoothstep(0.35, 0.95, streak) * body * centre * base * opacity * core_strength;
	ALBEDO = core_color * glow;
	ALPHA = 1.0;
}
