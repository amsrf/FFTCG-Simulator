shader_type spatial;
// The card's printed cost crystal, sampled from its own artwork and cut to the crystal's hexagon (card_cost_badge.gd).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D card_texture : source_color, filter_linear_mipmap;
// The crop in the card image's UV: x, y, width, height.
uniform vec4 uv_rect = vec4(0.042, 0.0067, 0.1096, 0.1517);
// The same crop in image pixels (the hexagon below is measured in them).
uniform vec2 crop_px = vec2(47.0, 91.0);
// Soft edge, in image pixels.
uniform float edge_px = 1.0;

void fragment() {
	vec4 colour = texture(card_texture, uv_rect.xy + UV * uv_rect.zw);
	// THE HEXAGON, in crop pixels: centre column 23.5, sides 22 px out, tips 2 px from the top and bottom of the crop,
	// slanted edges from the tips to the shoulders 16 px lower (higher) at the sides.
	vec2 p = UV * crop_px;
	float half_width = 22.0;
	float dx = abs(p.x - crop_px.x * 0.5);
	float side = half_width - dx;
	float slope = 16.0 / half_width;
	float top = p.y - (2.0 + dx * slope);
	float bottom = (crop_px.y - 2.0 - dx * slope) - p.y;
	float inside = min(side, min(top, bottom));
	ALBEDO = colour.rgb;
	ALPHA = smoothstep(-edge_px * 0.5, edge_px, inside);
}
