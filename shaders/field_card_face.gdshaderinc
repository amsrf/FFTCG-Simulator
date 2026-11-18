// Surface zero of a field card uses vertex red for the bevel tone.
// UV stays in full-card space so the existing dissolve and contact shadows still line up.
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap;
uniform bool field_face = false;
uniform sampler2D field_art_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 field_band_color : source_color;
uniform vec4 field_art_rect;
uniform float field_band_fraction;

vec3 sample_card_face(vec2 uv, vec4 vertex_tone) {
	if (!field_face) {
		return texture(texture_albedo, uv).rgb;
	}
	float band_edge = min(uv.y, 1.0 - uv.y);
	if (band_edge <= field_band_fraction + 0.00001) {
		// Printed-mesh stand-ins and glass shards have no bevel tones. Use the band's flat colour there.
		float tone = mix(vertex_tone.r, 0.5, vertex_tone.b);
		float across = mix(1.16, 0.77, smoothstep(0.04, 0.90, uv.x));
		float inner_edge = smoothstep(0.0, field_band_fraction, band_edge);
		float bevel_light = max(tone * 2.0 - 1.0, 0.0);
		vec3 satin = field_band_color.rgb * across * mix(0.52, 1.22, tone);
		return satin + vec3(0.29, 0.22, 0.17) * bevel_light * (0.15 + 0.70 * exp(-uv.x * 3.2))
			* mix(0.65, 1.0, inner_edge);
	}
	float art_height = 1.0 - 2.0 * field_band_fraction;
	vec2 art_uv = vec2(uv.x, clamp((uv.y - field_band_fraction) / art_height, 0.0, 1.0));
	float lip_shadow = 1.0 - 0.34 * exp(-art_uv.y * 48.0) - 0.12 * exp(-(1.0 - art_uv.y) * 62.0);
	return texture(field_art_texture, field_art_rect.xy + art_uv * field_art_rect.zw).rgb * lip_shadow;
}
