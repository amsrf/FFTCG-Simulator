shader_type spatial;

// 3D targeting arrow (MTG Arena style): an additive ribbon of light with a bright
// core and a soft halo, plus an animated flow running along its length.
//
// WIDTH SCALING HAPPENS HERE, but every DIRECTION comes from the CPU. The mesh is
// built at unit (stub) width and each vertex carries:
//   COLOR.a  = t, the position along the arc, 0 at the source and 1 at the target
//   COLOR.rgb= the sampled SIDE vector, remapped into 0..1 (see below)
//   UV.y     = 0 on one edge, 1 on the other
// so this shader never re-derives a tangent, never touches screen-space derivatives,
// and never looks at neighbouring UVs. That is deliberate: geometry-dependent
// directions recomputed per-fragment (dFdx/dFdy, tangent from UV neighbours) are what
// pinches and twists a ribbon through a bend.
//
// WHY COLOR IS REMAPPED: Godot stores vertex COLOR as 8-bit UNSIGNED normalized, so a
// side vector with a negative component would be clamped to 0 and the ribbon would
// deform. The CPU bakes side * 0.5 + 0.5 and this shader decodes it back. The 8-bit
// quantisation is ~0.4 degrees of direction error, which at these widths is well under
// a millimetre.
//
// TUNING: the look is authored in shaders/target_arc_material.tres (open it in the
// editor and every uniform below gets a slider or colour picker). BallisticArrow
// duplicates it: once for the shaft and once for the head, and the head copy is given
// thin_width == thick_width == edge_stub so the head keeps its real baked geometry.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

group_uniforms width;
// Half-widths, in metres: the vertex is pushed this far along the side vector, so the
// ribbon's full width is twice these numbers.
uniform float thin_width : hint_range(0.0, 0.3) = 0.018;
uniform float thick_width : hint_range(0.0, 0.5) = 0.075;
// Where the growth starts and finishes, as positions along the arc (0 = source,
// 1 = target). Smoothstep between them, so the widening is a ramp, never a step.
uniform float grow_start : hint_range(0.0, 1.0) = 0.35;
uniform float grow_end : hint_range(0.0, 1.0) = 0.75;
// The mesh is baked with this stub so its triangles are not degenerate before the
// scale above is applied, and the CPU subtracts the same stub here. Must match
// BallisticArrow.edge_stub.
uniform float edge_stub : hint_range(0.0, 0.05) = 0.001;

group_uniforms glow;
// Saturated, not white: under additive blending the GREEN channel is what turns a blue
// beam white, because the light is summed with whatever is behind it.
uniform vec3 glow_color : source_color = vec3(0.10, 0.42, 1.0);
uniform vec3 core_color : source_color = vec3(0.78, 0.93, 1.0);
// Fraction of the half-width taken by the solid core, across UV.y.
uniform float core_ratio : hint_range(0.0, 1.0) = 0.32;
uniform float halo_falloff : hint_range(0.02, 1.0) = 0.5;
// Overall brightness. With blend_add this is the strength of the light being added.
uniform float intensity : hint_range(0.0, 4.0) = 1.15;

group_uniforms flow;
// Animated energy travelling from the source to the target.
uniform float flow_speed = 0.55;
uniform float flow_scale = 4.0;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	// Position along the arc, baked by the CPU.
	float t = COLOR.a;
	// Decode the side vector (remapped into 0..1 by the CPU) and normalise defensively
	// so a zero vector can never produce NaN.
	vec3 raw = COLOR.rgb * 2.0 - 1.0;
	vec3 side = raw / max(length(raw), 0.0001);

	float w = mix(thin_width, thick_width, smoothstep(grow_start, grow_end, t));
	// UV.y < 0.5 is one edge of the ribbon, >= 0.5 the other.
	float edge_sign = (UV.y < 0.5) ? 1.0 : -1.0;

	// The baked geometry already sits at +/- edge_stub, so subtracting the stub here
	// makes the final offset exactly +/- w.
	VERTEX += side * (w - edge_stub) * edge_sign;
}

void fragment() {
	// x: 0 along the centre of the ribbon, 1 at its outer edges.
	float x = abs(UV.y * 2.0 - 1.0);

	// A solid core with a soft halo around it: this is what reads as a tube of light
	// rather than a flat coloured band.
	float core = 1.0 - smoothstep(core_ratio * 0.6, max(core_ratio, 0.001), x);
	float halo = exp(-max(x - core_ratio, 0.0) / max(halo_falloff * max(1.0 - core_ratio, 0.001), 0.001));
	float shape = max(core, halo);

	// Flow: a travelling wave along the arc, brightening as it goes.
	float wave = 0.5 + 0.5 * sin((UV.x - TIME * flow_speed) * flow_scale * 6.2831853);
	float lit = 1.0 - flow_strength + flow_strength * wave;

	vec3 col = mix(glow_color, core_color, clamp(core, 0.0, 1.0));

	// Additive: the result is dst + ALBEDO * ALPHA, so the shape lives in ALBEDO and
	// ALPHA stays at 1 for a full-strength beam.
	ALBEDO = col * shape * lit * intensity;
	ALPHA = 1.0;
}
