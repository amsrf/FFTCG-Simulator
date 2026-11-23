shader_type spatial;
render_mode unshaded, cull_back;

const float COIN_RADIUS = 0.292;
const vec3 METAL_LIGHT = vec3(0.30, 0.85, 0.43);
const float ROMAN_STEM_OFFSET = 0.164;
const int SECOND_MAIN_STAMP = 1;
const int CROSSED_SWORDS_STAMP = 2;
const int CROSS_STAMP = 3;  // the Cancel coins: an X of two chamfered bars
uniform int component = 0;
uniform bool use_imprint = false;
uniform int stamp_kind = 0;
uniform sampler2D imprint : filter_linear_mipmap, repeat_disable;
uniform vec2 ruby_radial_range;
uniform float ruby_glow = 0.0;
uniform float brass_inner_radius = 0.229;
uniform float cap_crown_y;
uniform sampler2D brushed_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D brushed_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D leather_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leather_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D leather_roughness : filter_linear_mipmap, repeat_enable;
// The Cosmos coin: the Chaos coin's colours swapped one for one: 1 ruby -> teal, 2 bronze cylinder -> bright brown
// wood, 3 gold rim -> ivory/beige, 4 brown centre -> brown, 5 gold swords -> ivory/beige. Glow ring unchanged.
uniform bool cosmos = false;
const float CAP_RIM_RADIUS = 0.284;  // priority_coin.gd CAP_RADIUS: the rim's outer edge
const float COSMOS_LIGHT_ANGLE = 0.68;  // local angle whose side is the screen top-left from the board camera (measured)
varying vec3 local_point;
varying vec3 world_normal;

void vertex() {
	local_point = VERTEX;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}

float crystal(vec2 p) {
	vec2 q = abs(p);
	return min(0.242 - q.x, (0.47 - q.y - 0.58 * q.x) / 1.15);
}

vec2 sword_coordinates(vec2 p) {
	return vec2(p.x + p.y, p.x - p.y) * 0.70710678;
}

float sword_distance(vec2 p) {
	vec2 q = sword_coordinates(p);
	float tip = (0.590 - q.x - 1.50 * abs(q.y)) * 0.555;
	float blade = min(min(0.322 + q.x, 0.099 - abs(q.y)), tip);
	float guard = min(0.150 - abs(q.y), 0.050 - abs(q.x + 0.322));
	float grip = min(0.045 - abs(q.y), 0.115 - abs(q.x + 0.438));
	float pommel = min(0.066 - abs(q.y), 0.047 - abs(q.x + 0.542));
	return max(max(blade, guard), max(grip, pommel));
}

vec3 stamp_tone(vec3 gold) {
	// Cosmos stamps are light wood, like the reference's swords; Chaos keeps its gold.
	if (!cosmos) {
		return gold;
	}
	return vec3(1.0, 0.82, 0.60) * dot(gold, vec3(0.30, 0.59, 0.11)) * 1.50;
}

float sword_stamp_distance(vec2 p, bool rear) {
	float front = sword_distance(p);
	if (rear) {
		// Keep the reference's clear separation at the crossing.
		return min(sword_distance(vec2(-p.x, p.y)), -front - 0.029);
	}
	return front;
}

float stamp_distance(vec2 p) {
	if (stamp_kind == SECOND_MAIN_STAMP) {
		vec2 q = vec2(abs(abs(p.x) - ROMAN_STEM_OFFSET), abs(p.y));
		float stem = 0.060 - q.x;
		float serif = min(0.122 - q.x, stem + (q.y - 0.315) * 0.75);
		float chamfer = (0.524 - q.x - q.y) * 0.7071;
		return min(max(stem, serif), min(0.434 - q.y, chamfer));
	}
	if (stamp_kind == CROSS_STAMP) {
		vec2 q = sword_coordinates(p);
		float bar_a = min(0.105 - abs(q.y), (0.62 - abs(q.x) - 0.6 * abs(q.y)));
		float bar_b = min(0.105 - abs(q.x), (0.62 - abs(q.y) - 0.6 * abs(q.x)));
		return max(bar_a, bar_b);
	}
	return crystal(p);
}

vec3 stamp_relief(vec3 face, vec3 gold, float d, float aa, float bevel_light, float bevel_width, float top) {
	float mark = smoothstep(-aa, aa, d);
	float wall = clamp(smoothstep(-0.015 - aa, -0.015 + aa, d) - mark, 0.0, 1.0);
	float inset = smoothstep(bevel_width - aa, bevel_width + aa, d);
	// Cosmos stamps are carved light wood: a soft bevel and no dark outline (Chaos keeps its dark cut edge).
	vec3 cut_edge = mix(gold * (cosmos ? 0.72 : 0.24), stamp_tone(vec3(0.94, 0.73, 0.42)), bevel_light);
	face *= 1.0 - wall * top * (cosmos ? 0.06 + 0.10 * (1.0 - bevel_light) : 0.20 + 0.35 * (1.0 - bevel_light));
	return mix(face, mix(cut_edge, gold, inset), mark * top);
}

vec3 sword_stamp(vec3 face, vec2 p, bool rear, float top) {
	float d = sword_stamp_distance(p, rear);
	float aa = max(fwidth(d) * 0.58, 0.002);
	float slope = sword_stamp_distance(p + vec2(0.018, 0.021), rear) - d;
	float bevel_light = smoothstep(-0.018, 0.018, slope);
	vec2 q = sword_coordinates(rear ? vec2(-p.x, p.y) : p);
	float blade_facet = 1.0 - smoothstep(-aa, aa, q.y);
	float hilt_facet = 0.45 + 0.43 * smoothstep(-0.034, 0.034, q.x + 0.322);
	float facet = mix(hilt_facet, blade_facet, smoothstep(-0.272 - aa, -0.272 + aa, q.x));
	if (cosmos) {
		facet = mix(0.55, facet, 0.45);   // a gentle ridge, not metal facets
	}
	vec3 gold = mix(vec3(0.49, 0.32, 0.14), vec3(0.84, 0.64, 0.35), facet);
	if (cosmos) {
		// Light wood grain running along each sword.
		float grain_line = grain(vec2(q.x * 6.0, q.y * 80.0) + (rear ? 7.0 : 0.0));
		gold *= 0.86 + 0.24 * grain_line;
	}
	return stamp_relief(face, stamp_tone(gold) * (rear ? 0.90 : 1.0), d, aa, bevel_light, 0.014, top);
}

float facet_tone(float index) {
	return fract(sin(index * 12.98 + 21.71) * 4375.13);
}

vec3 ruby_setting(float radius) {
	float angle = atan(local_point.z, local_point.x);
	float span = ruby_radial_range.y - ruby_radial_range.x;
	float u = (radius - ruby_radial_range.x) / span;
	float aa = max(fwidth(radius) / span, 0.002);
	float sector = (angle / TAU + 0.5) * 15.0;
	float index = floor(sector);
	float x = abs(fract(sector) - 0.5);
	float inner_cut = 0.52 - x * 0.62;
	float outer_cut = 0.64 + x * 0.58;
	float facet = facet_tone(mod(index + step(0.5, fract(sector)), 15.0));
	float inner = smoothstep(inner_cut - aa, inner_cut + aa, u);
	float outer = smoothstep(outer_cut - aa, outer_cut + aa, u);
	float face = mix(0.24 + 0.55 * facet, 0.43 + 0.49 * facet_tone(index + 17.0), inner);
	face = mix(face, 0.16 + 0.48 * facet, outer);
	float edge = exp(-abs(u - inner_cut) / 0.027) + 0.6 * exp(-abs(u - outer_cut) / 0.022);
	float light = 0.5 + 0.5 * cos(angle - 2.25);
	vec3 ruby = mix(vec3(0.19, 0.052, 0.083), vec3(0.66, 0.072, 0.17), face * (0.54 + 0.46 * light));
	float flash = pow(max(cos(angle - 2.22 + 0.33 * u), 0.0), 12.0) * (0.10 + 0.90 * facet);
	ruby += vec3(0.45, 0.24, 0.24) * flash * (0.27 + 0.73 * inner) * (1.0 - 0.78 * outer);
	ruby += vec3(0.37, 0.12, 0.15) * edge * pow(light, 4.0) * (0.25 + 0.75 * facet);
	ruby += vec3(0.63, 0.53, 0.51) * pow(max(cos(angle - 2.22 + 0.42 * u), 0.0), 32.0)
		* exp(-abs(u - inner_cut - 0.10) / 0.085);
	ruby += vec3(0.18, 0.023, 0.036) * exp(-6.0 * u);
	// The stone transmits the hover light through its facets, strongest along their cut edges.
	vec3 transmitted = vec3(0.51, 0.065, 0.092) * (0.50 + 0.65 * face);
	transmitted += vec3(0.24, 0.13, 0.13) * edge;
	return ruby + ruby_glow * transmitted;
}

vec3 wood_setting(float r, vec3 n, vec3 eye) {
	// Varnished wood bent into a ring (the reference): the grain runs around it, broad bands plus a few dark streak
	// lines that wander a little, a soft varnish shine, and the side away from the light darker.
	vec2 direction = local_point.xz / r;
	float angle = atan(direction.y, direction.x);
	float wander = grain(vec2(angle * 5.0, r * 60.0)) * 2.0;
	float bands = grain(vec2(angle * 3.0, r * 650.0 + wander * 4.0));
	float streak = smoothstep(0.80, 0.97, fract(r * 160.0 + wander)) * (0.6 + 0.4 * grain(vec2(angle * 22.0, r * 90.0)));
	// Reference: a golden orange, lit about (205,130,60) sRGB, with darker brown streaks.
	vec3 wood = mix(vec3(0.38, 0.16, 0.040), vec3(0.66, 0.29, 0.075), 0.25 + 0.75 * bands);
	// Streaks only on the top face: on the inner wall the radius is constant and they turn into vertical planks.
	wood = mix(wood, vec3(0.16, 0.060, 0.015), streak * 0.70 * smoothstep(0.55, 0.90, n.y));
	float facing = 0.5 + 0.5 * cos(angle - 2.25);
	float lit = max(dot(n, normalize(METAL_LIGHT)), 0.0);
	wood *= (0.70 + 0.40 * lit) * (0.78 + 0.32 * facing);
	vec3 reflected = reflect(-eye, n);
	float varnish = pow(max(dot(reflected, normalize(METAL_LIGHT)), 0.0), 30.0);
	float sheen = pow(max(dot(reflected, normalize(vec3(0.44, 0.70, 0.56))), 0.0), 8.0);
	return wood + vec3(0.30, 0.20, 0.12) * varnish + vec3(0.07, 0.045, 0.025) * sheen;
}

vec3 teal_crystal(vec3 ruby) {
	// The Cosmos ring is the Chaos ruby itself, same cut, facets, sparkle and hover glow, recoloured teal: the ruby's
	// dominant red carries its light and becomes green/blue; its small green becomes the red.
	return vec3(ruby.g + 0.05 * ruby.r, 0.78 * ruby.r, 0.72 * ruby.r);
}

vec3 bronze_setting(vec3 n, vec3 eye) {
	vec3 reflected = reflect(-eye, n);
	float panel = smoothstep(-0.22, 0.89, dot(reflected, normalize(vec3(0.5, 0.7, 0.6))));
	float band = pow(max(0.0, dot(reflected, normalize(vec3(-0.5, 0.55, 0.65)))), 7.0);
	float glint = pow(max(0.0, dot(reflected, normalize(METAL_LIGHT))), 13.0);
	vec3 bronze = mix(vec3(0.19, 0.144, 0.117), vec3(0.38, 0.29, 0.22), panel);
	bronze += vec3(0.13, 0.11, 0.09) * band + vec3(0.09, 0.074, 0.054) * glint;
	if (cosmos) {
		float radius = length(local_point.xz);
		if (radius < 0.33) {
			// 2: the bronze cylinder is the bright brown wood, its inner wall darkening with depth like the bronze.
			return wood_setting(radius, n, eye) * (1.0 - clamp((0.085 - local_point.y) * 13.0, 0.0, 0.83));
		}
		// The outer lip is the thin cream stone rim around the jade, (161,139,115) in the reference.
		float mottle = grain(local_point.xz * 90.0 + 5.0) * 0.6 + grain(local_point.xz * 320.0) * 0.4;
		bronze = mix(vec3(0.30, 0.22, 0.15), vec3(0.58, 0.44, 0.30), 0.35 + 0.55 * panel) * (0.90 + 0.18 * mottle);
	}
	return bronze * (1.0 - clamp((0.085 - local_point.y) * 13.0, 0.0, 0.83));
}

vec3 sample_brushed_metal(vec2 direction, float radius, float radial_offset, vec2 tiling) {
	// Wrap the brush lines around the coin without sampling across the angular seam.
	float angular_tiling = tiling.x / TAU;
	vec2 uv = vec2(atan(direction.y, direction.x) * angular_tiling, (radius - radial_offset) * tiling.y);
	vec2 angular_gradient = vec2(-direction.y, direction.x) * angular_tiling / max(radius, 0.0001);
	vec2 uv_dx = vec2(dot(angular_gradient, dFdx(local_point.xz)), dFdx(radius) * tiling.y);
	vec2 uv_dy = vec2(dot(angular_gradient, dFdy(local_point.xz)), dFdy(radius) * tiling.y);
	vec2 relief = textureGrad(brushed_normal, uv, uv_dx, uv_dy).rg * 2.0 - 1.0;
	return vec3(relief, textureGrad(brushed_roughness, uv, uv_dx, uv_dy).r);
}

vec3 brushed_world_normal(vec3 n, vec2 around, mat3 model_basis, vec2 relief) {
	vec3 tangent = normalize(model_basis * vec3(around.x, 0.0, around.y));
	vec3 radial = normalize(cross(n, tangent));
	return normalize(n + relief.x * tangent + relief.y * radial);
}

vec3 brass_setting(float r, vec3 n, vec3 eye, mat3 model_basis, float fine) {
	if (cosmos) {
		// 3: the gold rim is ivory / beige stone (the reference): faint veins, and a bevel catching the light on
		// both edges, stronger on the side facing it.
		vec2 q = local_point.xz;
		float mottle = grain(q * 150.0 + 9.0) * 0.6 + grain(q * 520.0) * 0.4;
		float lit = max(dot(n, normalize(vec3(0.48, 0.60, 0.64))), 0.0);
		vec3 ivory = mix(vec3(0.32, 0.25, 0.175), vec3(0.62, 0.50, 0.36), 0.30 + 0.60 * lit) * (0.92 + 0.14 * mottle);
		// Veins: thin wandering lines where a warped noise crosses its middle value.
		float warp = grain(q * 40.0 + 3.0);
		float vein_field = grain(q * 95.0 + vec2(warp * 3.0, -warp * 2.0));
		float vein = 1.0 - smoothstep(0.0, 0.030, abs(vein_field - 0.5));
		ivory *= 1.0 - 0.22 * vein * smoothstep(0.35, 0.65, grain(q * 18.0 + 21.0));
		// Bevels: a soft highlight just inside each edge.
		float aa = max(fwidth(r), 0.0005);
		float inner_bevel = 1.0 - smoothstep(0.0, 0.006 + aa, r - brass_inner_radius);
		float outer_bevel = 1.0 - smoothstep(0.0, 0.005 + aa, CAP_RIM_RADIUS - r);
		float facing = 0.5 + 0.5 * cos(atan(q.y, q.x) - 2.25);
		ivory += vec3(0.20, 0.17, 0.13) * (inner_bevel + outer_bevel) * (0.35 + 0.65 * facing);
		return ivory;
	}
	vec2 direction = local_point.xz / r;
	vec3 metal = sample_brushed_metal(direction, r, brass_inner_radius, vec2(6.0, 3.75));
	float roughness = metal.z;
	float wear = smoothstep(0.24, 0.60, roughness);
	vec2 around = vec2(-direction.y, direction.x);
	vec3 reflected = reflect(-eye, brushed_world_normal(n, around, model_basis, metal.xy * 0.16));
	float facing = max(dot(n, normalize(METAL_LIGHT)), 0.0);
	float panel = pow(max(dot(reflected, normalize(vec3(0.44, 0.70, 0.56))), 0.0), 6.0);
	float glint = pow(max(dot(reflected, normalize(METAL_LIGHT)), 0.0), mix(33.0, 13.0, roughness));
	vec3 brass = mix(vec3(0.18, 0.09, 0.027), vec3(0.58, 0.38, 0.12), facing);
	brass += vec3(0.42, 0.32, 0.15) * panel
		+ vec3(0.32, 0.24, 0.116) * glint * mix(1.42, 0.64, wear);
	float aa = max(fwidth(r), 0.0005);
	float bevel = 1.0 - smoothstep(0.002, 0.007 + aa, r - brass_inner_radius);
	brass += vec3(0.20, 0.16, 0.085) * bevel * (0.16 + 0.84 * max(panel, glint));
	float groove = 1.0 - smoothstep(0.0005, 0.0026, abs(r - 0.277));
	return brass * (0.96 + fine * 0.04) * mix(1.06, 0.90, wear) * (1.0 - groove * 0.45);
}

vec3 slate_inset(vec2 p, vec3 n, vec3 half_angle) {
	// 4: the Cosmos centre, flat dark brown stone: a slow mottling, no leather bumps and no cracks (the user
	// removed them). Reference (sRGB) about (65,58,50).
	float mottle = grain(p * 6.0 + 4.0) * 0.6 + grain(p * 22.0) * 0.4;
	vec3 slate = mix(vec3(0.20, 0.175, 0.150), vec3(0.31, 0.275, 0.235), mottle);
	float raking_light = max(dot(n, normalize(vec3(0.48, 0.60, 0.64))), 0.0);
	float sheen = pow(max(dot(n, half_angle), 0.0), 20.0);
	return slate * (0.56 + 0.64 * raking_light) + vec3(0.040, 0.037, 0.033) * sheen;
}

vec3 leather_inset(vec2 p, vec3 n, vec3 half_angle, mat3 model_basis) {
	if (cosmos) {
		return slate_inset(p, n, half_angle);
	}
	vec2 uv = p * 0.52 + vec2(0.5);
	vec3 albedo = texture(leather_albedo, uv).rgb;
	vec2 relief = texture(leather_normal, uv).rg * 2.0 - 1.0;
	float roughness = texture(leather_roughness, uv).r;

	vec3 tangent = -normalize(model_basis[0]);
	tangent -= n * dot(n, tangent);
	tangent /= max(length(tangent), 0.0001);
	vec3 bitangent = cross(n, tangent);
	vec3 surface = normalize(n + 0.20 * (relief.x * tangent + relief.y * bitangent));
	float raking_light = max(dot(surface, normalize(vec3(0.48, 0.60, 0.64))), 0.0);
	float sheen = pow(max(dot(surface, half_angle), 0.0), mix(34.0, 9.0, roughness));
	return albedo * (0.56 + 0.64 * raking_light) + vec3(0.105, 0.10, 0.093) * sheen;
}

vec3 coin_surface(vec2 p, vec3 n, vec3 eye, mat3 model_basis, float key, float fine, float patina) {
	float radius = length(p);
	float r = length(local_point.xz);
	float top = smoothstep(0.002, 0.020, local_point.y);
	vec2 direction = r > 0.0001 ? local_point.xz / r : vec2(1.0, 0.0);
	float angle = atan(direction.y, -direction.x);
	float lighting = 0.77 + 0.23 * p.y - 0.08 * p.x;
	vec3 blackened = mix(vec3(0.065, 0.058, 0.050), vec3(0.139, 0.117, 0.086), patina * 0.26);
	blackened *= (lighting + fine * 0.07) * 0.965;
	blackened *= 1.0 - 0.32 * smoothstep(0.68, 0.89, radius);
	vec3 half_angle = normalize(eye + normalize(METAL_LIGHT));
	float reflection = max(dot(n, half_angle), 0.0);
	blackened += vec3(0.18, 0.167, 0.142) * pow(reflection, 12.22)
		+ vec3(0.074, 0.069, 0.058) * pow(reflection, 41.4);
	float shoulder = smoothstep(0.89, 0.99, radius);
	float reeding = 0.83 + 0.17 * smoothstep(-0.5, 0.7, sin(angle * 88.0));
	vec3 metal = mix(blackened, blackened * reeding * 0.71, shoulder);
	float seat = smoothstep(0.242, 0.255, r) * (1.0 - smoothstep(0.284, 0.292, r));
	metal *= (1.0 - 0.70 * seat * top) * mix(0.62, 1.0, top);
	float inset_face = top * (1.0 - smoothstep(brass_inner_radius, brass_inner_radius + 0.005, r));
	vec3 leather = leather_inset(p, n, half_angle, model_basis);
	leather *= mix(1.0, 0.66, smoothstep(brass_inner_radius - 0.020, brass_inner_radius, r));
	vec3 face = mix(metal, leather, inset_face);

	// The shared Confirm disc still shows wording when a specific choice is offered.
	if (use_imprint) {
		vec2 uv = vec2(0.5 + 0.5 * p.x, 0.5 - 0.5 * p.y);
		float ink = texture(imprint, uv).a;
		return mix(face * (0.66 + 0.34 * key), vec3(1.0, 0.94, 0.82), ink * top);
	}
	if (stamp_kind == CROSSED_SWORDS_STAMP) {
		// Project the stamp onto the tangent plane so the dome cannot bow either blade in the board view.
		vec3 view_ray = normalize(inverse(model_basis) * eye);
		float lift = (cap_crown_y - local_point.y) * smoothstep(0.25, 0.60, view_ray.y);
		vec2 plane = local_point.xz + view_ray.xz * lift / max(view_ray.y, 0.25);
		vec2 swords = vec2(-plane.x, plane.y) / (COIN_RADIUS * 1.10);
		face = sword_stamp(face, swords, true, inset_face);
		face = sword_stamp(face, swords, false, inset_face);
		return face * (0.66 + 0.34 * key);
	}

	float d = stamp_distance(p);
	float aa = max(fwidth(d), 0.002);
	float bevel_light = smoothstep(-0.020, 0.020, stamp_distance(p + vec2(0.022, 0.026)) - d);
	float facet_x = p.x - 0.032;
	if (stamp_kind == SECOND_MAIN_STAMP) {
		facet_x = p.x - sign(p.x) * ROMAN_STEM_OFFSET - 0.012;
	}
	float face_left = 1.0 - smoothstep(-aa, aa, facet_x);
	float end_facet = smoothstep(-aa, aa, abs(p.y) + 0.31 * abs(facet_x) - 0.32);
	if (stamp_kind == CROSS_STAMP) {
		// Each bar is chiselled along its length: the half toward the light is the bright facet.
		vec2 q = sword_coordinates(p);
		facet_x = abs(q.y) < abs(q.x) ? q.y : -q.x;
		face_left = 1.0 - smoothstep(-aa, aa, facet_x);
		end_facet = 0.0;
	}
	vec3 stamp = mix(vec3(0.48, 0.31, 0.125), vec3(0.68, 0.48, 0.23), face_left);
	stamp = mix(stamp, mix(vec3(0.37, 0.23, 0.093), vec3(0.76, 0.56, 0.28),
		smoothstep(-0.22, 0.22, p.y)), end_facet);
	stamp = stamp_tone(stamp) * (0.90 + 0.12 * fine);
	stamp += vec3(0.105, 0.078, 0.042) * pow(max(dot(n, half_angle), 0.0), 14.0);
	face = stamp_relief(face, stamp, d, aa, bevel_light, 0.030, top);
	return face * (0.66 + 0.34 * key);
}

void fragment() {
	vec2 p = vec2(-local_point.x, local_point.z) / COIN_RADIUS;
	float r = length(local_point.xz);
	vec3 n = normalize(world_normal);
	vec3 world_point = (MODEL_MATRIX * vec4(local_point, 1.0)).xyz;
	vec3 eye = normalize(INV_VIEW_MATRIX[3].xyz - world_point);
	float key = clamp(dot(n, normalize(vec3(0.32, 0.86, 0.42))), 0.0, 1.0);
	float fine = grain(p * vec2(340.0, 76.0) + 30.0);
	float patina = grain(p * 11.0 + 70.0);
	if (component == 1) {
		ALBEDO = cosmos ? teal_crystal(ruby_setting(r)) : ruby_setting(r);
	} else if (component == 2) {
		ALBEDO = brass_setting(r, n, eye, mat3(MODEL_MATRIX), fine);
	} else if (component == 3) {
		ALBEDO = bronze_setting(n, eye);
	} else {
		ALBEDO = coin_surface(p, n, eye, mat3(MODEL_MATRIX), key, fine, patina);
	}
	if (cosmos) {
		// Overall light (the reference): the whole coin brighter toward the light, darker on the far side.
		vec2 toward_light = vec2(cos(COSMOS_LIGHT_ANGLE), sin(COSMOS_LIGHT_ANGLE));
		float across = clamp(dot(local_point.xz / 0.38, toward_light), -1.0, 1.0);
		ALBEDO *= 1.0 + 0.18 * across;
	}
}
