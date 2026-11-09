shader_type spatial;
// The card's printed name box, sampled from its own artwork and cut to the box's outline by a mask (card_name_badge.gd).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D card_texture : source_color, filter_linear_mipmap;
// The box's shape over the same crop (white = box), one per box style.
uniform sampler2D box_mask : filter_linear;
// The crop in the card image's UV: x, y, width, height.
uniform vec4 uv_rect = vec4(0.1399, 0.0267, 0.8392, 0.0833);

void fragment() {
	vec4 colour = texture(card_texture, uv_rect.xy + UV * uv_rect.zw);
	ALBEDO = colour.rgb;
	ALPHA = texture(box_mask, UV).r;
}
