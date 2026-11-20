// Surface zero of a field card uses vertex red for the bevel tone.
// UV stays in full-card space so the existing dissolve and contact shadows still line up.
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap;
uniform bool field_face = false;
uniform sampler2D field_art_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 field_band_color : source_color;
uniform vec4 field_art_rect;
uniform float field_band_fraction;
uniform sampler2D field_nameplate_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 field_nameplate_color : source_color;
uniform float field_nameplate_shadow = 0.0;
uniform vec4 field_cost_color : source_color;
uniform vec4 field_cost_rect; // Centre and half size in full-card UV.

vec3 sample_field_nameplate(vec2 uv, float tone, float inner_edge, float bevel_light) {
	// Reflect the printed grain to fill the strip without seams.
	vec2 grain_uv = 1.0 - abs(2.0 * fract(vec2(uv.x * 1.65, inner_edge * 1.56)) - 1.0);
	vec3 grain = texture(field_nameplate_texture, grain_uv).rgb;
	vec3 plate = mix(field_nameplate_color.rgb, grain, 0.62) * mix(0.66, 1.0, smoothstep(0.0, 0.5, tone))
		+ vec3(0.13) * bevel_light;
	// The crystal silhouette is ink on the same surface as the nameplate.
	vec2 p = abs(uv - field_cost_rect.xy) / max(field_cost_rect.zw, vec2(0.0001));
	float edge = max(p.x, p.y + p.x * 0.30);
	float aa = max(fwidth(edge) * 0.5, 0.0001);
	float ink = 1.0 - smoothstep(0.96 - aa, 0.96 + aa, edge);
	return mix(plate, field_cost_color.rgb, ink);
}

vec3 sample_card_face(vec2 uv, vec4 vertex_tone) {
	if (!field_face) {
		return texture(texture_albedo, uv).rgb;
	}
	float band_edge = min(uv.y, 1.0 - uv.y);
	if (band_edge <= field_band_fraction + 0.00001) {
		// Printed-mesh stand-ins and glass shards have no bevel tones. Use the band's flat colour there.
		float tone = mix(vertex_tone.r, 0.5, vertex_tone.b);
		float inner_edge = smoothstep(0.0, field_band_fraction, band_edge);
		float bevel_light = max(tone * 2.0 - 1.0, 0.0);
		if (uv.y < 0.5) {
			return sample_field_nameplate(uv, tone, inner_edge, bevel_light);
		}
		// The printed element stripe has a broad central highlight with darker ends.
		float from_center = abs(2.0 * uv.x - 1.0);
		float across = mix(1.30, 0.74, smoothstep(0.20, 1.0, from_center));
		vec3 satin = field_band_color.rgb * across * mix(0.52, 1.22, tone);
		return satin + vec3(0.29, 0.22, 0.17) * bevel_light * (0.15 + 0.70 * exp(-uv.x * 3.2))
			* mix(0.65, 1.0, inner_edge);
	}
	float art_height = 1.0 - 2.0 * field_band_fraction;
	vec2 art_uv = vec2(uv.x, clamp((uv.y - field_band_fraction) / art_height, 0.0, 1.0));
	float lip_shadow = 1.0 - 0.34 * exp(-art_uv.y * 48.0) - 0.12 * exp(-(1.0 - art_uv.y) * 62.0);
	vec3 portrait = texture(field_art_texture, field_art_rect.xy + art_uv * field_art_rect.zw).rgb * lip_shadow;
	// A narrow contact shadow keeps the joint visible even over a pale portrait.
	float seam = field_nameplate_shadow * (1.0 - smoothstep(0.004, 0.022, art_uv.y));
	return mix(portrait, vec3(0.024, 0.022, 0.024), seam);
}
