shader_type spatial;
// One element badge: a circular disc with the element's glyph drawn on top of it.
//
// Unshaded on purpose — a cost indicator is UI that happens to live in the 3D world, so it should
// read the same wherever it floats rather than picking up the board's lighting and going dim over a
// dark card. cull_disabled so it renders whichever way it is turned, which matters because the
// billboarding that will keep it facing the player is not wired up yet.
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

// The glyph, straight from assets/elements/<element>.png — square, 256 px, glyph centred, produced by
// tools/build_element_icons.gd. Linear filtering with mipmaps so it stays smooth when the badge is
// small on screen.
uniform sampler2D element_icon : filter_linear_mipmap;
// The disc the glyph sits on, and the thin accent ring around it. The ring is what makes a row of
// these read as a set while still being distinguishable at a glance.
uniform vec4 disc_color : source_color = vec4(0.035, 0.040, 0.055, 1.0);
uniform vec4 ring_color : source_color = vec4(0.85, 0.87, 0.92, 1.0);
// Ring thickness, as a fraction of the disc's radius.
uniform float ring_width : hint_range(0.0, 0.3) = 0.055;
// How much of the disc the glyph fills, as a fraction of the radius. Above ~0.8 the glyph's corners
// start reaching the rim.
uniform float icon_scale : hint_range(0.2, 1.0) = 0.78;
// Anti-aliasing width for both the rim and the ring, in radius units.
uniform float edge_softness : hint_range(0.0, 0.05) = 0.010;
// A soft inner darkening under the glyph, so it sits IN the disc instead of looking pasted on. Off by
// default: the numeral's disc is meant to be FLAT white with black ink on it, and any shading there reads
// as a 3D button instead. It costs nothing for the element icons, which have no disc to shade.
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
// 0 draws the glyph ALONE, with no disc behind it; 1 draws the disc. The element icons are used exactly as
// they are, so they set this to 0 — a numeral still needs a disc (black ink on white), so it sets 1.
uniform float disc_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// UV runs 0..1 over the quad. p is centred and measured in units of the disc's radius, so
	// r == 1.0 is exactly the disc's edge — which is what makes all the numbers below readable.
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);

	float edge = max(edge_softness, 0.0005);
	float disc = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, r);
	float ring = smoothstep(1.0 - ring_width - edge, 1.0 - ring_width + edge, r) * disc;

	// The glyph's square maps onto p in [-icon_scale, icon_scale]. Two things are needed outside it, and
	// getting only one of them was a visible bug: the sampler must not reach round to the opposite edge
	// of the texture (the clamp), and the result must not be DRAWN at all (the mask). Clamping alone
	// pins every pixel beyond the square to the texture's edge column and smears whatever the icon has
	// there around the inside of the rim — which showed up as pale tabs at 3 and 9 o'clock on the fire
	// badge, since that is where the square's horizontal extremes meet the rim.
	vec2 q = p / max(icon_scale, 0.001);
	float inside = 1.0 - smoothstep(0.98, 1.0, max(abs(q.x), abs(q.y)));
	vec4 glyph = texture(element_icon, clamp(q * 0.5 + vec2(0.5), vec2(0.0), vec2(1.0)));

	// disc_amount = 0 means the glyph is drawn ALONE: the element icons are used exactly as they are, so the
	// icon's own alpha is what shows. A numeral does need a disc behind it (black ink on white), so numeral
	// mode sets this to 1. The vignette is gated by it too, or it would darken a bare glyph toward a rim
	// that is no longer being drawn.
	float glyph_a = glyph.a * inside;
	vec3 col = mix(disc_color.rgb, ring_color.rgb, ring);
	col *= 1.0 - vignette * disc_amount * smoothstep(0.35, 1.0, r) * (1.0 - ring);
	col = mix(col, glyph.rgb, glyph_a);

	ALBEDO = col;
	ALPHA = mix(glyph_a, disc, disc_amount);
}
