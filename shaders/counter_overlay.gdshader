shader_type spatial;
// The countered card's face (scripts/vfx/counter_cue.gd), a quad lying just above it. Two jobs:
//  * the malfunction flicker: a faint violet `tint` at a low `fill`
//  * the death: the card turns SOLID cyan (`fill` 1) and a crack network spreads out from its centre (`crack_reach`).
// The cracks are the edges of the SAME Voronoi cells the shards are cut from (`sites`), so the card breaks along
// exactly the lines that were drawn on it. After Clips/die frames 32+.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.30, 0.98, 1.0, 1.0);
uniform vec4 crack_color : source_color = vec4(0.90, 1.0, 1.0, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 0.0;
/// Card-face units from the centre: the cracks show inside this radius.
uniform float crack_reach = 0.0;
uniform float crack_width = 0.0035;
uniform vec2 card_size = vec2(0.429, 0.6);
uniform float corner = 0.022;
uniform int site_count = 0;
uniform vec2 sites[64];

// Mesh-local position on the face (x across, z along). Taken from VERTEX, not UV, so it is in the same frame the
// shards are cut in, whatever the plane's UV convention.
varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

void fragment() {
	vec2 q = abs(local) - (card_size * 0.5 - corner);
	float rounded = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	float mask = 1.0 - smoothstep(-0.0015, 0.0, rounded);
	float d1 = 1e9;
	float d2 = 1e9;
	vec2 s1 = vec2(0.0);
	vec2 s2 = vec2(0.0);
	for (int i = 0; i < 64; i++) {
		if (i >= site_count) {
			break;
		}
		float d = distance(local, sites[i]);
		if (d < d1) {
			d2 = d1;
			s2 = s1;
			d1 = d;
			s1 = sites[i];
		} else if (d < d2) {
			d2 = d;
			s2 = sites[i];
		}
	}
	// Exact distance to the bisector between the two nearest sites = distance to the crack.
	float edge = site_count > 1 ? abs(dot(local - (s1 + s2) * 0.5, normalize(s2 - s1))) : 1.0;
	float reveal = 1.0 - smoothstep(crack_reach - 0.03, crack_reach, length(local));
	float crack = (1.0 - smoothstep(crack_width * 0.5, crack_width, edge)) * reveal;
	ALBEDO = mix(tint.rgb, crack_color.rgb, crack);
	ALPHA = clamp(fill + crack * fill, 0.0, 1.0) * mask;
}
