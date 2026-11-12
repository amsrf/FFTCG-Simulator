shader_type spatial;
render_mode unshaded, cull_back;

// THE MATERIALISING CARD'S REAL CRYSTALS (card_crystallize.gd): tall quartz columns standing on the card.
//
// Every crystal is one unit mesh under an AFFINE instance transform (its lattice triangle as the footprint, its own
// height, a lean), so the mesh normals are useless: the facet normal is rebuilt per pixel from the surface itself,
// which is exact for flat faces under any shear. Unshaded, like every crystal here.
//
// The look is a cluster LIT FROM WITHIN (references: glowing quartz clusters): white-hot at the foot, the element's
// colour up the column, deeper at the tip; each flat face takes its own value so neighbours step across an edge; no
// drawn outlines. The key light comes from the upper left of the SCREEN under the board camera (screen-up is world
// +Z, screen-right is world -X).
//
// Mesh data: UV.x = height along the crystal (0 foot, 1 tip).

uniform vec4 tint : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform float exposure = 1.0;
/// Extra white-hot light (the glow beat before the crystals break).
uniform float heat : hint_range(0.0, 1.0) = 0.0;
/// How strong the light inside the cluster is.
uniform float inner_glow : hint_range(0.0, 2.0) = 1.0;

varying float crystal_height;

void vertex() {
    crystal_height = UV.x;
}

void fragment() {
    vec3 v_view = normalize(VIEW);
    vec3 n_view = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
    if (dot(n_view, v_view) < 0.0) { n_view = -n_view; }
    vec3 n = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
    vec3 v = normalize((INV_VIEW_MATRIX * vec4(v_view, 0.0)).xyz);
    vec3 r = reflect(-v, n);
    float facing = clamp(dot(n_view, v_view), 0.0, 1.0);

    vec3 deep = tint.rgb * vec3(0.30, 0.22, 0.24);
    vec3 hot = mix(tint.rgb, vec3(1.0, 0.94, 0.78), 0.72);
    vec3 key_dir = normalize(vec3(0.55, 0.55, 0.62));
    // The body: each facet one value from where it points - a soft step between neighbours, not a black/white jump.
    float lit = dot(n, key_dir);
    vec3 color = mix(deep, tint.rgb, smoothstep(-0.6, 0.9, lit));
    // Deeper toward the tip, where the light inside has the furthest to travel.
    color *= mix(1.0, 0.62, smoothstep(0.35, 1.0, crystal_height));
    // The light inside: hottest at the foot, seen best through a facet you look straight into.
    float glow = pow(1.0 - crystal_height, 1.6) * (0.55 + 0.45 * facing);
    color = mix(color, hot * 1.25, clamp(glow * inner_glow, 0.0, 1.0));
    // A polished face still catches the room: one soft highlight and a faint sheen at grazing angles.
    float key = pow(max(dot(r, key_dir), 0.0), 14.0);
    color += mix(tint.rgb, vec3(1.0), 0.65) * key * 0.55;
    color += tint.rgb * pow(1.0 - facing, 3.0) * 0.25;
    color = mix(color, hot * 1.5, heat * 0.55);
    ALBEDO = color * exposure;
}
