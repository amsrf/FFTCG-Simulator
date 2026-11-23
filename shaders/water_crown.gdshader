shader_type spatial;
// The burst at the heart of the water splash (water_splash.gd), on a camera-facing quad: a sheet of water flung out
// in uneven jets round a hollowing centre, its edge breaking into foam. `spread` (0..1) is how far the sheet has
// opened; `hollow` (0..1) how much of the middle has drained; `intensity` fades it all.
// Alpha-blended so it reads over the pale wood.

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec4 water_color : source_color = vec4(0.32, 0.58, 1.0, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.98, 1.0, 1.0);
uniform float spread = 1.0;
uniform float hollow = 0.0;
uniform float intensity = 1.0;
uniform float seed = 0.0;

float hash(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = fract(atan(p.y, p.x) / 6.28318 + 0.5);
	// Jets: the sheet's reach varies round the circle (wrapping: 11 and 23 cells), sharpened into spikes.
	float jets = noise1(a * 11.0 + seed) * 0.65 + noise1(a * 23.0 + seed * 2.3) * 0.35;
	jets = pow(jets, 1.6);
	float reach = spread * mix(0.45, 0.95, jets);
	float edge = smoothstep(reach, reach - 0.10, d);
	// The middle drains as the sheet opens: what is left is a ragged ring.
	float inner = hollow * reach * 0.78;
	float ring = edge * smoothstep(inner - 0.06, inner + 0.06, d);
	// Foam where the sheet breaks: its outer lip, the jets' tips, and a speckle that grows with the hollowing.
	float lip = exp(-pow((d - reach + 0.05) / 0.05, 2.0));
	float tips = lip * smoothstep(0.55, 0.9, jets);
	float speck = step(0.80, hash(floor(UV.x * 44.0) * 7.1 + floor(UV.y * 44.0) * 13.7 + seed));
	// Fresh impact (no hollow yet) is white water; it clears as the sheet drains.
	float fresh = 1.0 - hollow;
	float foam = clamp(lip * 0.95 + tips * 0.5 + speck * 0.4 * ring * hollow + fresh * 0.45, 0.0, 1.0);
	vec3 col = mix(water_color.rgb, foam_color.rgb, foam);
	// The sheet is mostly CLEAR water (the deck shows through it); the foam is what reads.
	float alpha = ring * mix(0.16, 0.95, clamp(lip + tips * 0.5 + fresh * 0.35, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(alpha * intensity, 0.0, 1.0);
}
