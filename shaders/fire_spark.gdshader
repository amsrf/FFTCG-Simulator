shader_type spatial;
// One mote of the fire burst (fire_burst.gd): the magic sparks that spiral IN to the card before the blast, and the
// embers thrown OUT by it. A streak with a white-hot core, pointed at both ends. Colour and fade come per instance
// (MultiMesh colour); the quad's long axis is UV.x.
// Alpha-blended, not additive: additive light all but vanishes over the pale board wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

varying vec4 spark_color;

void vertex() {
	spark_color = COLOR;
}

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float along = 1.0 - abs(UV.x * 2.0 - 1.0);
	float body = pow(across, 1.3) * smoothstep(0.0, 0.6, along);
	float core = pow(across, 3.0) * smoothstep(0.2, 0.9, along);
	ALBEDO = mix(spark_color.rgb, vec3(1.0, 0.97, 0.85), clamp(core * 1.2, 0.0, 1.0));
	ALPHA = clamp(body * 1.4 * spark_color.a, 0.0, 1.0);
}
