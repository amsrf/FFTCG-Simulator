shader_type spatial;
// One spark thrown off a lightning hit (lightning_aftermath.gd): an additive streak, hot in the middle, pointed at
// both ends. Colour and fade come per instance (MultiMesh colour); the quad's long axis is UV.x.

render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying vec4 spark_color;

void vertex() {
	spark_color = COLOR;
}

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float along = 1.0 - abs(UV.x * 2.0 - 1.0);
	float body = pow(across, 1.6) * smoothstep(0.0, 0.55, along);
	float core = pow(across, 5.0) * smoothstep(0.1, 0.8, along);
	ALBEDO = (spark_color.rgb + vec3(core) * 0.9) * 2.2;
	ALPHA = clamp(body * spark_color.a, 0.0, 1.0);
}
