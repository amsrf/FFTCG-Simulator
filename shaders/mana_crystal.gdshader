shader_type spatial;
// The mana crystal's BODY — surface 0, Material.001 — and nothing else.
//
// The black facet edges and the outer outline are the model's own second surface (Material.003), so nothing here
// draws lines. The script applies this with set_surface_override_material(0, ...), which leaves surface 1 exactly
// as it was exported.
//
// TWO STATES, EMPTY AND FILLED (`paid` runs 0..1 continuously, so paying FILLS the crystal and unpaying DRAINS it):
//   * OWED   - an EMPTY socket: a dark, desaturated, matte body with only a faint glow of the element's colour, rim
//              strongest where the faces turn away, and the model's black edges. It still says WHICH element is asked
//              for, but plainly not that it is there. (A flat 2D silhouette was tried and dropped for this.)
//   * PAID   - the full saturated gem, shiny, with the breathing glow. Red-paid-by-red is now dark-red -> ruby, which
//              the old "slightly brighter" cue could not show in a still.
//   * `flash` is a brief white burst the script fires at the moment of filling (the pop).
//
// A TRANSPARENT WILD CRYSTAL WAS TRIED AND REMOVED. It read as SMOKED glass, because the faces are genuinely shaded.
// The owed look keeps that idea - an empty slot - but as a dark opaque body, which sits well on the row's dark panel.
//
// NO ALPHA IS WRITTEN, so Godot treats this surface as fully opaque. Adding an ALPHA line here would make the
// whole body transparent, including its black edges' backdrop.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 tint : source_color = vec4(0.94, 0.95, 1.0, 1.0);
// 0 = owed (empty), 1 = paid (filled). Eased by the script, so it fills and drains rather than switching.
uniform float paid : hint_range(0.0, 1.0) = 0.0;
// The white burst at the moment of filling, 0..1.
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// The OWED look: how much of the element's colour the dark body keeps, and its faint coloured glow + rim.
uniform float owed_tint : hint_range(0.0, 1.0) = 0.2;
uniform float owed_glow : hint_range(0.0, 1.0) = 0.12;
uniform float owed_rim : hint_range(0.0, 2.0) = 0.55;

// How much the paid glow breathes, and at what rate.
uniform float pulse : hint_range(0.0, 1.0) = 0.16;
uniform float pulse_speed = 2.1;
// Per-crystal phase offset, so a row of paid crystals does not breathe in lockstep. Set by the script.
uniform float phase_offset = 0.0;

// Surface look, matching crystal.tscn's crystal so the two read as the same material family.
uniform float metallic_value : hint_range(0.0, 1.0) = 0.3;
uniform float specular_value : hint_range(0.0, 1.0) = 0.77;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.25;

// HOW STRONG THE PAID GLOW IS — and why it is not higher.
//
// Emission is added ON TOP of an already-lit albedo, so a bright colour has almost no headroom before its own glow
// erases its hue. At 1.7 the ICE crystal emitted enough light that all three of its channels clipped to white and
// it stopped being cyan at all. That is not a tuning miss: adding light to a lit surface cannot produce a strong
// glow without destroying the colour. A stronger one needs bloom, which adds light AROUND the surface — and this
// project's Compatibility renderer silently ignores Environment glow, so there is none available. See game.tscn.
uniform float emission_energy : hint_range(0.0, 4.0) = 0.85;

// CONTACT DARKENING, for a crystal set INTO something (the phase prism in its stone cradle): the surface dims as it
// goes down to WORLD height `occlusion_y`, over `occlusion_depth` metres above it, so the crystal fades into the hole
// instead of being cut off by a bright edge. Off by default (the payment row's crystals stand in the air).
uniform float occlusion_y = -1000.0;
uniform float occlusion_depth = 0.03;
uniform float occlusion_floor : hint_range(0.0, 1.0) = 0.25;
varying float world_y;

// A GRADIENT ACROSS A FACE, for meshes that carry it in their vertex colour (the phase prism writes COLOR.r = 0 on a
// face's top edge and 1 on its bottom edge): lighter at the top, darker at the bottom. Off by default; the payment
// row's model has no such colours.
uniform float gradient_amount : hint_range(0.0, 1.0) = 0.0;
uniform float gradient_top : hint_range(0.5, 2.0) = 1.15;
uniform float gradient_bottom : hint_range(0.0, 1.0) = 0.55;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Owed: near-black, keeping a little of the colour so the requirement is still readable.
	vec3 owed_albedo = mix(vec3(0.045), tint.rgb, owed_tint);
	ALBEDO = mix(owed_albedo, tint.rgb, paid);
	METALLIC = metallic_value * paid;
	// Matte while owed (no bright highlight to mistake for "lit"), the gem's shine once filled.
	SPECULAR = mix(0.2, specular_value, paid);
	ROUGHNESS = mix(0.7, roughness_value, paid);

	// Owed glow: faint, plus a rim on the faces turning away from the view, in the element's colour.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 owed_light = tint.rgb * (owed_glow + owed_rim * rim) * (1.0 - paid);
	// The paid glow only ever ADDS light, so a filled crystal is never darker than an owed one.
	float breathe = 1.0 + pulse * sin(TIME * pulse_speed + phase_offset);
	EMISSION = owed_light + tint.rgb * emission_energy * paid * breathe + vec3(1.0) * flash * 1.4;
	float contact = mix(occlusion_floor, 1.0, smoothstep(occlusion_y, occlusion_y + max(occlusion_depth, 1e-4), world_y));
	float shade = mix(1.0, mix(gradient_top, gradient_bottom, COLOR.r), gradient_amount);
	ALBEDO *= contact * shade;
	EMISSION *= contact * shade;
}
