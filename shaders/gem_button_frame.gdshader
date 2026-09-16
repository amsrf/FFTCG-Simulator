shader_type spatial;
// The metal frame of the gem button.
//
// WHY THIS IS A SHADER AND NOT A StandardMaterial3D: a flat mirror reflects exactly ONE direction,
// so a flat metal face under a smooth sky gradient comes back a single uniform colour — which is
// precisely what makes a technically-correct metal read as plastic. The reference gets its
// "polished and lit from above" look from a ramp an artist baked in, and no material value can put
// that on a flat plate.
//
// THE LIGHT ENTERS AT THE TOP MIDDLE, exactly as it does for the gem: brightness falls off with the
// distance from that point, downward and out toward the ends alike. The frame and the stone share the
// same planar UV space (both are unwrapped across the whole button), so "the top middle" means the
// same place on the same object for both — the stone and its bezel cannot disagree about where the
// light is. The frame darkens more gently than the gem, via its own `side_spread`.
//
// WHY THERE IS NO DARK WALL TINT ANY MORE. An earlier version mixed a dark `wall_tint` into the
// albedo on any surface that faced sideways, to keep the outer wall from going black. That is exactly
// backwards for a METAL: albedo TINTS the reflection, so a dark tint on a surface that already
// reflects the dark ground multiplies the two together and produces black — which is what turned the
// widened end bands of the bezel black while the narrower part beside them stayed light. The
// environment already darkens the bevel correctly; the only thing needed is a small EMISSION lift, so
// no part of the frame can collapse to pure black regardless of what it is reflecting.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

group_uniforms frame;
uniform float face_span = 1.0;
uniform float metalness : hint_range(0.0, 1.0) = 1.0;
// The ramp, light at the top middle. Keep the ends far apart — the probe asserts the top is brighter
// and that the bottom is not black.
uniform vec3 metal_top : source_color = vec3(0.90, 0.93, 0.98);
uniform vec3 metal_bottom : source_color = vec3(0.34, 0.36, 0.42);
// >1 steepens the falloff away from the light.
uniform float ramp_curve : hint_range(0.3, 4.0) = 1.6;
// The frame darkens MORE GENTLY than the gem does: it spans the whole capsule, so the ends are a long
// way from the centre and a large spread would take them to the darkest colour.
uniform float side_spread : hint_range(0.2, 3.0) = 1.2;
uniform float vertical_spread : hint_range(0.2, 3.0) = 1.0;
// Polished near the light, slightly satin away from it. The roughness change is half of what makes the
// ramp read as a curved, light-catching surface instead of a flat tint.
uniform float roughness_top : hint_range(0.02, 1.0) = 0.06;
uniform float roughness_bottom : hint_range(0.02, 1.0) = 0.34;
// The flooring that stops any part of the frame from going black. Small: it is insurance, not light.
uniform vec3 lift_color : source_color = vec3(0.30, 0.32, 0.38);
uniform float lift_strength : hint_range(0.0, 0.5) = 0.12;
// A little extra edge light so the silhouette keeps a bright metal line.
uniform float edge_boost : hint_range(0.0, 1.0) = 0.18;

varying float v_up;

void vertex() {
	// 1 at the top of the button as the player sees it, 0 at the bottom.
	v_up = VERTEX.z / max(face_span, 0.001) + 0.5;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	// 1 on the top face, 0 on a vertical wall, -1 underneath.
	float facing = n.y;
	float down = clamp(1.0 - clamp(v_up, 0.0, 1.0), 0.0, 1.0);

	// Distance from the point the light enters: the top middle of the button.
	vec2 p = vec2((UV.x - 0.5) * side_spread, down * vertical_spread);
	float d = clamp(length(p), 0.0, 1.0);
	// 0 at the light, 1 furthest from it.
	float ramp = pow(d, ramp_curve);

	// 0 only on the top face; 1 on anything seen edge-on or from below. Used for the roughness and the
	// lift only — NOT to darken the albedo, which would multiply the reflection into black.
	float outside = clamp(1.0 - facing, 0.0, 1.0);

	vec3 metal = mix(metal_top, metal_bottom, ramp);
	float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
	metal += edge_boost * fres;

	ALBEDO = metal;
	METALLIC = metalness;
	ROUGHNESS = mix(roughness_top, roughness_bottom, max(ramp, outside));
	EMISSION = lift_color * (lift_strength * max(ramp, outside));
	SPECULAR = 0.5;
}
