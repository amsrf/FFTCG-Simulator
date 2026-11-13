shader_type spatial;
// The PROTECT shell (scripts/vfx/protect_shell.gd): a card gained "cannot be broken". One camera-facing quad over the
// card draws an egg-shaped shell of hexagonal glass panels (gold rims, blue glass) closing around it, with a ragged
// outline of whole panels (no smooth oval), frost flaring on its outermost panels, comets orbiting it and two coloured motes drifting inside. Reference: frames 47-90 of
// the Protect clip (~/Desktop/Clips/protect).
//
// The hex grid lives on a SPHERE: a pixel's ellipse position is turned into longitude/latitude, and the grid is laid
// in that space, so cells squeeze toward the outline the way the reference's panels do. Every value that moves is a
// uniform written by the script (sample(t)), so a frozen frame is reproducible.
// QuadMesh UV.y = 0 is the TOP edge, so the shader works in q = (x, up).

render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glass_color : source_color = vec4(0.26, 0.44, 0.96, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.74, 0.22, 1.0);
uniform vec4 frost_color : source_color = vec4(0.88, 0.95, 1.0, 1.0);
// Seconds since the shell started (comets, drift, shimmer).
uniform float time = 0.0;
// 0..1: how many panels have formed. Panels form from the outline inward, in a scattered order.
uniform float build = 1.0;
// 0..1: the comets' visibility (they lead the build, then fade out once the shell is closed).
uniform float comets = 1.0;
// The frosty white flare on the outline (peaks once the shell has closed).
uniform float flare = 0.0;
// 0..1: the fade-out. Glass goes first, the gold rims linger, as in the reference's last frames.
uniform float fade = 0.0;
// Panels across the shell's longitude (half a sphere) — the reference shows ~6-7 across the front.
uniform float cells_across = 8.0;
// The shell's ellipse inside the quad, as a fraction of each half-side.
uniform float shell_extent = 1.0;
// The ragged outline: a panel is kept only if its centre is within edge_keep (+ up to edge_jitter, per panel) of the
// shell's centre, so the outermost ring is broken up and no panel is ever sliced by the oval.
uniform float edge_keep = 0.72;
uniform float edge_jitter = 0.18;

const float PI_ = 3.14159265;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Pointy-top hex grid: returns (local offset in the cell, cell id). Cells are 1 unit wide, rows sqrt(3)/2 apart.
vec4 hex_cell(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec4 c = floor(vec4(p, p - vec2(0.5, 0.8660254)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - c.xy * s, p - (c.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy) : vec4(h.zw, c.zw + 0.5);
}

// Hex "radius" of a local offset: 0.5 on the cell's edge.
float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.5, 0.8660254)), p.x);
}

// A comet orbiting on a tilted ellipse around the shell: a bright head with a tapering tail behind it.
float comet(vec2 q, float angle, float tilt, float squash, float radius, float tail) {
	float c = cos(tilt);
	float s = sin(tilt);
	vec2 o = vec2(c * q.x + s * q.y, -s * q.x + c * q.y);
	o.y /= squash;
	float r = length(o);
	float th = atan(o.y, o.x);
	float behind = mod(angle - th, 2.0 * PI_);      // 0 at the head, growing along the tail
	float across = abs(r - radius);
	float head = exp(-(pow(min(behind, 2.0 * PI_ - behind) * radius, 2.0) + across * across) / 0.0035);
	float t = clamp(behind / tail, 0.0, 1.0);
	float width = mix(0.055, 0.006, t);
	float body = behind < tail ? exp(-across * across / (width * width)) * pow(1.0 - t, 1.6) : 0.0;
	return head * 1.4 + body * 0.9;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	vec2 q = vec2(uv.x, -uv.y) / shell_extent;      // the shell's ellipse is the unit circle here
	float r = length(q);
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	float alive = 1.0 - fade;

	// --- the shell -----------------------------------------------------------------------------------------------
	if (r < 1.0) {
		float lat = asin(clamp(q.y, -0.999, 0.999));
		float ring = sqrt(max(1.0 - q.y * q.y, 1e-4));
		float lon = asin(clamp(q.x / ring, -0.999, 0.999));
		vec2 g = vec2(lon, lat) * (cells_across / PI_);
		vec4 h = hex_cell(g);
		float d = hex_dist(h.xy);
		vec2 id = h.zw;
		float rnd = hash1(id);
		// The panel's centre, back on the disc: its distance from the outline decides when it forms (edges first).
		vec2 centre_ll = id * vec2(1.0, 1.7320508) * (PI_ / cells_across);
		float cell_r = clamp(length(vec2(sin(centre_ll.x) * cos(centre_ll.y), sin(centre_ll.y))), 0.0, 1.0);
		// Drop whole panels near the outline, a random selection, so the silhouette is jagged hexes, not an oval.
		float keep = step(cell_r, edge_keep + edge_jitter * hash1(id + vec2(17.0, 3.0)));
		float start = 0.55 * (1.0 - cell_r) + 0.40 * rnd;
		float grow = smoothstep(start, start + 0.12, build);
		// A forming panel grows out of its own centre.
		float size = 0.5 * grow;
		if (keep > 0.5 && d < size) {
			float edge = size - d;                          // 0 on the panel's rim
			float gold = 1.0 - smoothstep(0.030, 0.060, edge);
			float bevel = smoothstep(0.03, 0.10, edge);
			// Glass: blue, brighter toward the top-left of each panel, a little brighter near the outline.
			float sheen = clamp(0.5 - h.x * 0.6 + h.y * 0.8, 0.0, 1.0);
			vec3 glass = glass_color.rgb * (0.50 + 0.55 * sheen) + vec3(0.55) * pow(sheen, 5.0);
			glass += frost_color.rgb * smoothstep(0.80, 1.0, r) * 0.25;
			float glass_a = (0.50 + 0.20 * smoothstep(0.6, 1.0, r)) * bevel * clamp(1.0 - fade * 1.6, 0.0, 1.0);
			// A flash as each panel lands.
			float land = smoothstep(start + 0.04, start + 0.12, build) * (1.0 - smoothstep(start + 0.12, start + 0.30, build));
			vec3 panel = mix(glass, rim_color.rgb * (1.1 + 0.4 * land), gold);
			float panel_a = mix(glass_a, 0.95 * (1.0 - fade * fade), gold);
			panel += frost_color.rgb * land * 0.6;
			// The frost: on the OUTERMOST surviving panels (the jagged outline), never on the oval, which would draw
			// back the full half-sphere the dropped panels removed. Faint once built, bright in the flare.
			float wisps = 0.65 + 0.35 * sin(atan(q.y, q.x) * 9.0 + time * 3.0) * sin(atan(q.y, q.x) * 5.0 - time * 2.1);
			float outer = smoothstep(0.42, 0.82, cell_r) * smoothstep(0.0, 0.25, edge);
			float frost = outer * (0.18 * smoothstep(0.3, 0.7, build) + flare * wisps * 0.85) * alive;
			panel = mix(panel, frost_color.rgb, clamp(frost, 0.0, 1.0));
			col = panel;
			alpha = max(max(panel_a, land * 0.5 * alive), clamp(frost, 0.0, 1.0));
		}
	}

	// --- comets orbiting the shell, and two coloured motes inside ------------------------------------------------
	float k = comets * 1.0;
	float cm = comet(q, 1.2 + time * 5.2, 0.35, 0.62, 0.90, 2.2)
		+ comet(q, 3.9 + time * 4.6, -0.55, 0.55, 0.92, 2.0)
		+ comet(q, 5.4 - time * 4.9, 1.45, 0.48, 0.86, 1.8);
	cm *= k;
	col = mix(col, vec3(1.0), clamp(cm, 0.0, 1.0));
	alpha = max(alpha, clamp(cm, 0.0, 1.0));
	vec2 orange_at = vec2(0.32 + 0.08 * sin(time * 1.3), -0.05 + 0.10 * cos(time * 1.1));
	vec2 cyan_at = vec2(-0.40 + 0.06 * cos(time * 1.7), -0.22 + 0.08 * sin(time * 1.4));
	float orange = exp(-dot(q - orange_at, q - orange_at) / 0.006);
	float cyan = exp(-dot(q - cyan_at, q - cyan_at) / 0.004);
	float motes = alive * smoothstep(0.0, 0.25, time);
	col = mix(col, vec3(1.0, 0.62, 0.18), clamp(orange * motes, 0.0, 1.0));
	col = mix(col, vec3(0.35, 0.85, 1.0), clamp(cyan * motes, 0.0, 1.0));
	alpha = max(alpha, clamp(max(orange, cyan) * motes * 0.9, 0.0, 1.0));

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
