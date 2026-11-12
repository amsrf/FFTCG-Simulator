shader_type spatial;
// Tornado mesh A: translucent smoke (Desktop/Clips/tornado_4.mp4, step 3), plus the step-4 lightning.
// Two-sided with large voids (Desktop/Clips/green_tornado_3.mp4): through the holes you see the INNER wall,
// drawn darker, which is what makes it read as wind wrapping round rather than a solid distorting tube.
// Unshaded on purpose: lit here in VIEW space, so the smoke reads the same in the demo and under the game's
// straight-down DirectionalLight (which would leave a vertical column flat and dark).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/wind_tornado.gdshaderinc"

uniform vec3 light_color : source_color = vec3(0.94, 1.0, 0.96);
uniform vec3 shadow_color : source_color = vec3(0.30, 0.47, 0.43);
uniform vec3 glint_color : source_color = vec3(0.92, 1.0, 0.96);
uniform float bump = 2.4;
uniform float fresnel_soft = 0.6;   // facing ratio at which the surface becomes fully opaque
uniform float density = 0.9;
uniform float inner_shade = 0.62;  // inner wall brightness, seen through the voids
// Only the innermost layer shows its inner wall; the outer shells draw their outward side only, so the three
// layers stay in back-to-front order (render_priority) instead of a far wall painting over a near one.
uniform bool two_sided = true;
// The floor skirt faces the camera head-on, so the fresnel never thins it; this keeps it translucent.
uniform float skirt_density = 0.6;
uniform float glint_strength = 3.0;
uniform float glint_amount : hint_range(0.0, 1.0) = 0.24;
// Key light direction in VIEW space (x right, y up, z toward the camera): upper left, slightly in front.
uniform vec3 light_dir = vec3(-0.55, 0.70, 0.45);

void vertex() {
	v_floor = UV2.x;
	tornado_vertex(VERTEX, NORMAL, TANGENT, BINORMAL, UV, UV2.x);
}

// Step 4: lightning. Voronoi cell borders ("curvature" + threshold), the domain wobbled by UV noise so the
// lines kink, scrolled around the mesh faster than the smoke, then most of it subtracted by a second
// scrolled noise so only short sparks survive. Returns (core, glow).
vec2 lightning(vec2 uv) {
	float gs = uv.x + uv.y * twist * 1.3 + age * spin_speed * 1.7;
	vec2 p = vec2(gs * 6.0, uv.y * 10.0 - age * 2.0);
	p += (vec2(vnoise(p * 1.7, 10.2), vnoise(p * 1.7 + 9.1, 10.2)) - 0.5) * 0.55;
	vec2 f = voronoi(p, 6.0);
	float gap = f.y - f.x;
	float core = 1.0 - smoothstep(0.0, 0.035, gap);
	float glow = 1.0 - smoothstep(0.0, 0.22, gap);
	float keep = smoothstep(1.0 - glint_amount, 1.0 - glint_amount * 0.3,
		vnoise(vec2(gs * 4.0 + 0.37, uv.y * 6.0 - age * 3.1), 4.0));
	return vec2(core, glow * glow) * keep;
}

void fragment() {
	// The distortion noise wobbles the UVs (tornado_4 step 3) so the streaks ripple.
	vec2 uv = UV + (wind_texture(UV, 0.43) - 0.5) * uv_distort * vec2(1.0, 0.7);
	float h = wind_texture(uv, 0.0);

	// Wind texture -> normal (step 2's "normal create") by finite differences, then lighting.
	float e = 0.004;
	float hu = wind_texture(uv + vec2(e, 0.0), 0.0) - h;
	float hv = wind_texture(uv + vec2(0.0, e), 0.0) - h;
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 bumped = normalize(n - bump * 0.012 / e * (hu * normalize(TANGENT) + hv * normalize(BINORMAL)));
	float diffuse = dot(bumped, normalize(light_dir)) * 0.5 + 0.5;   // half-lambert: shaded, never black
	float tone = clamp(diffuse * 0.85 + (h - 0.5) * 0.9, 0.0, 1.0);

	// Voids: what is left after the cut, ramped from fully transparent (green_tornado_3's colour ramp).
	float d = wind_density(uv, h, v_floor);
	float body = smoothstep(0.0, 0.22, d);
	// Thin parts near a hole's rim are paler wisps, the dense middle carries the shading.
	vec3 colour = mix(shadow_color, light_color, smoothstep(0.15, 0.95, tone));
	colour = mix(light_color * 0.9, colour, smoothstep(0.0, 0.35, d));
	if (!FRONT_FACING) {
		colour *= inner_shade;
	}

	// Fresnel hides the silhouette (step 3).
	float facing = abs(dot(n, normalize(VIEW)));
	float edge = smoothstep(0.05, fresnel_soft, facing);
	float skirt = mix(skirt_density, 1.0, smoothstep(0.04, 0.3, v_floor));
	float alpha = density * skirt * body * edge * opacity * (FRONT_FACING ? 1.0 : (two_sided ? 0.8 : 0.0));

	vec2 bolt = lightning(UV) * edge * opacity * body * smoothstep(0.2, 0.5, v_floor);
	if (!FRONT_FACING) {
		bolt *= 0.0;
	}
	ALBEDO = colour + glint_color * (bolt.x * glint_strength + bolt.y * 0.8);
	ALPHA = clamp(max(alpha, max(bolt.x, bolt.y * 0.6)), 0.0, 1.0);
}
