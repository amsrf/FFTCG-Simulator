shader_type spatial;
// A blood crystal of the Chaos life crown (scripts/ui/life_crown.gd).
//
// FACETED BY GEOMETRY: the mesh carries one flat normal per triangle (Blender/build_life_crown.py), so every facet
// takes its own shade from the sky and the downward key light. Nothing here re-derives a normal.
//
// THE GLOW COMES FROM BELOW, like the reference: the cup lights the crystal, so emission is strongest at the foot
// (local height 0) and fades toward the tip, with a rim where facets turn away. It is MIXED into a dark albedo, not
// stacked on a bright one: emission on top of a lit bright red clips to orange-white (see mana_crystal.gdshader).
// Compatibility has no bloom; the halo quad behind each crystal (life_crystal_halo.gdshader) is the outer glow.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 body : source_color = vec4(0.42, 0.015, 0.03, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.07, 0.06, 1.0);
uniform float glow_energy : hint_range(0.0, 4.0) = 1.1;
uniform float foot_glow : hint_range(0.0, 4.0) = 1.4;
uniform float rim_glow : hint_range(0.0, 4.0) = 0.9;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.18;
uniform float specular_value : hint_range(0.0, 1.0) = 0.8;
// The white flash before it bursts, 0..1 (life_crown.gd drives it).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 0 = a dead, empty-looking stone (unused today; kept for a restore fade), 1 = alive.
uniform float alive : hint_range(0.0, 1.0) = 1.0;

varying float height;

void vertex() {
	// The crystal mesh is 1.0 tall with its foot at the origin (before the socket's scale).
	height = clamp(VERTEX.y, 0.0, 1.0);
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	float foot = pow(1.0 - height, 2.2);
	vec3 e = glow.rgb * (glow_energy * 0.35 + foot * foot_glow + rim * rim_glow);
	ALBEDO = mix(body.rgb * 0.25, body.rgb, alive);
	EMISSION = mix(e * 0.08, e, alive) * 0.5;
	ALBEDO = mix(ALBEDO, vec3(1.0), flash);
	EMISSION += vec3(1.0, 0.75, 0.7) * flash * 1.5;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.15;
}
