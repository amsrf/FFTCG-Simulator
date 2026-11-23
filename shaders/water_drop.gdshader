shader_type spatial;
// One droplet of the water splash (water_splash.gd): a round head at the FRONT of the quad (UV.x = 1, the direction of
// travel) tapering into a thin tail, with a white glint near the head. Colour and fade per instance (MultiMesh colour).
// Alpha-blended so it reads over the pale wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

varying vec4 drop_color;

void vertex() {
	drop_color = COLOR;
}

void fragment() {
	// The quad is about 1.2-1.8x as long as it is wide (water_splash.gd), so in UV the head is an ellipse that maps to a
	// round bead on screen. Head at the FRONT (UV.x = 1), a short faint trail behind it, a white glint on the head.
	float x = UV.x;
	float y = UV.y * 2.0 - 1.0;
	vec2 head_p = vec2((x - 0.68) / 0.32, y);
	float r = length(head_p);
	float head = 1.0 - smoothstep(0.80, 1.0, r);
	float trail = (1.0 - smoothstep(0.0, 0.35, abs(y))) * smoothstep(0.0, 0.5, x) * step(x, 0.68) * 0.35;
	float body = max(head, trail);
	// A rim darker than the middle reads as a lens of water, not a flat dot.
	float rim = smoothstep(0.45, 0.95, r) * head;
	float glint = 1.0 - smoothstep(0.0, 0.30, length(vec2((x - 0.78) / 0.10, (y + 0.35) / 0.30)));
	vec3 col = mix(drop_color.rgb, drop_color.rgb * 0.75, rim * 0.6);
	col = mix(col, vec3(1.0), clamp(glint, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(body * drop_color.a * mix(0.85, 1.0, rim), 0.0, 1.0);
}
