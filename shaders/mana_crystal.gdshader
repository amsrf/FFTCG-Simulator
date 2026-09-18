shader_type spatial;
// The mana crystal's BODY — surface 0, Material.001 — and nothing else.
//
// The black facet edges and the outer outline are the model's own second surface (Material.003), so nothing here
// draws lines. The script applies this with set_surface_override_material(0, ...), which leaves surface 1 exactly
// as it was exported.
//
// TWO STATES:
//   * UNPAID — flat colour and no glow. Red for a fire requirement, WHITE for the wild "any colour" slots.
//   * PAID   — the same colour plus a glow. A wild crystal paid by a red source turns red and lights up; paid by a
//              wild source it stays white and lights up.
//
// A TRANSPARENT WILD CRYSTAL WAS TRIED AND REMOVED. The idea was that an unfilled slot ought to look empty, and it
// did read as glass — the model's own edges showed through it, which was rather nice — but it also came out as
// SMOKED glass rather than clear, because the faces are genuinely shaded and therefore darkened. Meanwhile the row
// already has a strong "not yet paid" signal in the flat-versus-glowing contrast. Back to white.
//
// NO ALPHA IS WRITTEN, so Godot treats this surface as fully opaque. Adding an ALPHA line here would make the
// whole body transparent, including its black edges' backdrop.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 tint : source_color = vec4(0.94, 0.95, 1.0, 1.0);
// 0 = unpaid, 1 = paid. Set by the script from `lit`; the glow keys off this.
uniform float paid : hint_range(0.0, 1.0) = 0.0;

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

void fragment() {
	ALBEDO = tint.rgb;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	ROUGHNESS = roughness_value;

	// The glow, only when paid, and only ever ADDING light — so a paid crystal is brighter and more saturated but
	// never darker than the same crystal unpaid, whichever way the light falls.
	float breathe = 1.0 + pulse * sin(TIME * pulse_speed + phase_offset);
	EMISSION = tint.rgb * emission_energy * paid * breathe;
}
