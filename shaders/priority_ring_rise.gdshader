shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec4 glow_color : source_color;
uniform float ring_radius;
uniform float slice_weight;
uniform float intensity = 0.0;
varying vec2 radial_point;
varying float height_fraction;

void vertex() {
	radial_point = VERTEX.xz;
	height_fraction = INSTANCE_CUSTOM.r;
}

void fragment() {
	float h = height_fraction;
	float radius = length(radial_point);
	float distance_to_shell = radius - (ring_radius + 0.105 * h);
	float width = mix(0.014, 0.080, h);
	float offset = distance_to_shell / width;
	float density = exp(-0.5 * offset * offset) * pow(1.0 - h, 1.4);
	float angle = atan(radial_point.y, radial_point.x);
	float rays = 0.72 + 0.18 * cos(9.0 * angle + 0.12 * sin(TIME)) + 0.10 * cos(17.0 * angle + 0.8);
	ALBEDO = glow_color.rgb;
	ALPHA = intensity * density * rays * 1.28 * slice_weight;
}
