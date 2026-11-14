// One dome of a board button (scripts/ui/disc_socket.gd). The button is a lens: two shallow domes joined at a
// bezel. Both domes wear a raised METAL BAND at their edge (`band_inner` out to the rim); inside it:
//
// * the gem dome (`crystal`) is the old GemButton's stone (shaders/gem_button.gdshader): light enters at the TOP
//   MIDDLE and the colour ramps from a pale crown through bright and mid tones to a deep bottom, with soft facet
//   planes and a darker rim. The ramp is built from `base_color`, so teal, red and violet gems share the look.
//   It carries an IMPRINT (the label or a symbol, drawn into a SubViewport) in white with a dark engraved outline.
// * the stone dome carries an engraved ring.
//
// Everything is projected straight down the dome's axis from the unit hemisphere's x/z, so it follows the curve and
// turns with the button. Local +z is screen-up for the local station, so "top" is +y in `face`.
//
// specular_disabled: the scene's one light points straight down, and a smooth dome mirrored it as a white blob.
// The gem's light is its own (emission) and the metal's shading is painted; nothing reflects the lamp.
shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

uniform vec4 base_color : source_color = vec4(0.1, 0.4, 0.4, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float roughness = 0.12;
uniform bool crystal = false;
// The gem ramp (gem_button.gdshader's numbers): where the crown and the mid tone end, how fast it darkens sideways
// and downward, how far from grey, and the soft facet planes.
uniform float crown_stop = 0.25;
uniform float mid_stop = 0.62;
uniform float side_spread = 0.75;
uniform float vertical_spread = 0.48;
uniform float saturation = 1.35;
uniform float facet_strength = 0.3;
uniform float facet_freq = 3.5;
// The metal band: from this fraction of the radius out to the rim (0 = no band).
uniform float band_inner = 0.84;
uniform vec4 band_color : source_color = vec4(0.82, 0.84, 0.88, 1.0);
uniform vec4 ink_color : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform sampler2D imprint : source_color, filter_linear_mipmap;
uniform bool use_imprint = false;
// The SETTING: the face inside the band is sunk below the band's lip, so the gem sits IN the metal rather than on
// it. `inset` is how far below the lip the gem's edge lies, in units of the dome's height. It must stay below the
// lip's height (0.54 at band_inner 0.84), or the sunk face crosses the button's middle plane and the OTHER face
// shows through it. `setting_wall` is the
// width of the band's inner wall, which the camera sees on the far side.
uniform float inset = 0.18;
uniform float gem_bulge = 0.6;
uniform float setting_wall = 0.03;
// How dark the setting's shadow on the gem's edge is. From this steep camera the gem's HEIGHT reads through this
// shading far more than through geometry: less shadow = a gem that sits higher.
uniform float setting_shadow = 0.35;
// The stone side: an engraved groove at this fraction of the radius (0 = none).
uniform float groove_radius = 0.0;
uniform vec4 groove_color : source_color = vec4(0.4, 0.3, 0.15, 1.0);

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

varying vec2 face;          // -1..1 across the dome, in the dome's own frame

void vertex() {
	face = VERTEX.xz;
	if (band_inner > 0.0) {
		// The dome is a unit hemisphere, so the band's lip sits at this height.
		float r = length(VERTEX.xz);
		float lip = sqrt(max(1.0 - band_inner * band_inner, 0.0));
		float gem_edge = band_inner - setting_wall;
		// Inside the wall the gem is its own shallow dome, starting `inset` below the lip.
		float gr = r / max(gem_edge, 1e-3);
		// `gem_bulge`: how far the gem's centre rises above its own edge — what makes it stand up in the setting.
		float gem_y = lip - inset + gem_bulge * (1.0 - gr * gr);
		float k = smoothstep(band_inner, gem_edge, r);
		VERTEX.y = mix(VERTEX.y, gem_y, k);
		NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), k * 0.7));
	}
}

// The gem inside the band, `g` normalised so the band's inner edge is radius 1.
vec3 gem_ramp(vec2 g) {
	vec3 base = base_color.rgb;
	vec3 top = mix(base, vec3(1.0), 0.82);
	vec3 upper = mix(base, vec3(1.0), 0.3) * 1.05;
	vec3 deep = base * 0.38;
	vec3 rim = base * 0.28;
	// Distance from the point the light enters: the top middle of the gem.
	float d = clamp(length(vec2(g.x * side_spread, (1.0 - g.y) * vertical_spread)), 0.0, 1.0);
	vec3 body = mix(top, upper, smoothstep(0.0, crown_stop, d));
	body = mix(body, base, smoothstep(crown_stop, mid_stop, d));
	body = mix(body, deep, smoothstep(mid_stop, 1.0, d));
	body = mix(vec3(dot(body, LUMA)), body, saturation);
	// Soft facet planes through the stone, multiplied in so they modulate the ramp.
	float facet = sin(dot(g, normalize(vec2(0.85, 1.0))) * facet_freq * PI);
	body *= 1.0 + facet_strength * facet * 0.35;
	// A darker rim inside the band: the gem's thickness.
	body = mix(body, rim, smoothstep(0.7, 1.0, length(g)) * 0.55);
	return body;
}

// The raised metal band: polished metal, painted rather than lit (specular is off). A rounded profile across it,
// a chrome-like split — bright on the upper half, dark on the lower, as a polished rim mirrors sky and ground —
// a thin bright crest, and dark grooves at both edges. `metal` is the band's own tint.
vec3 metal_band(vec2 p, float r, vec3 metal) {
	float t = clamp((r - band_inner) / max(1.0 - band_inner, 1e-3), 0.0, 1.0);
	float rounded = 0.5 + 0.5 * sin(t * PI);
	float up = p.y / max(r, 1e-3);
	float from_top = mix(0.45, 1.15, smoothstep(-0.6, 0.6, up));
	// The crest: a thin bright line along the band's middle, strongest where it faces up.
	from_top += 0.45 * pow(sin(t * PI), 10.0) * (0.5 + 0.5 * up);
	// The edge grooves are a few pixels wide on screen: widen them to at least a pixel (fwidth) so they never step.
	float aa = fwidth(t);
	float groove = smoothstep(0.0, 0.08 + aa, t) * smoothstep(1.0, 0.9 - aa, t);
	return metal * rounded * from_top * mix(0.25, 1.0, groove);
}

void fragment() {
	float r = length(face);
	vec3 albedo = base_color.rgb;
	float rough = roughness;
	vec3 emit = emission_color.rgb * emission_energy;
	float gem_edge = band_inner - setting_wall;
	// EVERY EDGE INSIDE THE FACE IS BLENDED OVER ONE PIXEL. MSAA only smooths triangle silhouettes; a boundary drawn by
	// the shader inside a triangle (gem -> metal, wall -> band, the groove) gets no help from it and stair-steps.
	// `px` is one screen pixel in face units.
	float px = max(fwidth(r), 1e-5);
	// The metal: the band itself, and the inner wall of the setting between the band's lip and the sunk face.
	float band_mix = band_inner > 0.0 ? smoothstep(gem_edge - px, gem_edge + px, r) : 0.0;
	bool in_band = band_mix >= 1.0;
	float up = face.y / max(r, 1e-3);
	if (crystal && !in_band) {
		vec3 c = gem_ramp(face / max(gem_edge, 1e-3));
		// The inner shadow: the setting's wall shades the gem's edge, most on the far side, where the rim stands
		// between the gem and the light.
		float shade = smoothstep(gem_edge - 0.1, gem_edge, r) * (0.55 + 0.45 * max(up, 0.0));
		c *= 1.0 - shade * setting_shadow;
		albedo = c * 0.25;
		emit = c * 1.1;
	}
	if (use_imprint && !in_band) {
		// Local -x is screen-right and +z screen-up for the local station, so u runs along -x and v down -z.
		vec2 uv = vec2(0.5 - face.x * 0.5, 0.5 - face.y * 0.5);
		float ink = texture(imprint, uv).a;
		// A dark rim around the ink, from four taps: the engraved edge that keeps the text legible on a bright gem.
		float o = 0.008;
		float near = max(max(texture(imprint, uv + vec2(o, 0.0)).a, texture(imprint, uv - vec2(o, 0.0)).a),
			max(texture(imprint, uv + vec2(0.0, o)).a, texture(imprint, uv - vec2(0.0, o)).a));
		float rim = clamp(near - ink, 0.0, 1.0);
		albedo *= 1.0 - rim * 0.7;
		emit *= 1.0 - rim * 0.75;
		albedo = mix(albedo, ink_color.rgb * 0.5, ink);
		emit = mix(emit, ink_color.rgb * 0.9, ink);
		rough = mix(rough, 0.35, ink);
	}
	if (groove_radius > 0.0 && !in_band) {
		// At least ~1.5 px wide, with a one-pixel soft edge: a thinner engraved line breaks into steps.
		float d = abs(r - groove_radius);
		float half_w = max(0.022, px * 0.75);
		float g = 1.0 - smoothstep(half_w - px, half_w + px, d);
		albedo = mix(albedo, groove_color.rgb, g);
		rough = mix(rough, 0.4, g);
		// The stone face is sunk in its setting too.
		albedo *= 1.0 - smoothstep(gem_edge - 0.16, gem_edge, r) * (0.55 + 0.45 * max(up, 0.0)) * 0.5;
	}
	if (band_mix > 0.0) {
		// The gem side wears polished silver metal, the stone side its station's metal (iron or bronze).
		vec3 metal = crystal ? band_color.rgb : groove_color.rgb;
		// The setting's inner wall: metal facing inward, in its own shadow; brightest on the far side, which is the
		// side of the wall that faces the camera.
		float w = clamp((r - gem_edge) / max(setting_wall, 1e-3), 0.0, 1.0);
		vec3 wall = metal * mix(0.12, 0.5, w) * (0.55 + 0.45 * max(up, 0.0));
		vec3 band = metal_band(face, r, metal);
		// The lip: a bright bevel where the band turns down into the setting.
		float t = (r - band_inner) / max(1.0 - band_inner, 1e-3);
		band += metal * 0.45 * (1.0 - smoothstep(0.0, 0.14, max(t, 0.0)));
		vec3 m = mix(wall, band, smoothstep(band_inner - px, band_inner + px, r));
		albedo = mix(albedo, m * 0.4, band_mix);
		emit = mix(emit, m * 0.85, band_mix);
		rough = mix(rough, 0.35, band_mix);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	EMISSION = emit;
}
