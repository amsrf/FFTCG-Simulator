"""THE BOARD GENERATOR: builds the whole board from assets/board/layout.json in one pass.

    blender --background --python Blender/build_board.py

Reads board_pit_stations/board_pit_stations.blend for what is already authored there (the pit and button HOUSINGS with
their rings and wells, the game camera, the lights, the materials, and the scenery pieces used as SCATTER SOURCES),
deletes all of its old scenery, and generates everything else fresh:

  * ONE continuous TERRAIN heightfield over the whole view: the floor sunk RAISE below the ledge, the curb band, the bank,
    the ledge with a little noise, the river channel, dips under the station wells and deck trays. No overlapping
    sheets, so no seams or steps. Forest grass on the opponent's half, basalt on the local half; on the volcanic side a
    lava sheet lies just under the ground and shows wherever the ground dips (smooth, natural boundaries).
  * ONE wood FLOOR per half, cut to the outline (named like the old slabs, so the seat-2 export keeps it fixed).
  * The stone CURB along the whole outline (also down both banks of the river channel) and the dark seam at its foot.
  * The DECK TRAYS (recessed wooden trays under the decks).
  * The RIVER: one plane through the channel and between the floors ('Continuous river', the animated river mesh).
  * SCATTER: the board's own rocks, plates, ground clumps and foliage, placed by rules: per biome (no moss on the
    volcanic side), with keep-out zones round the floor, the curb, the river, every station (and the phase marks round
    the coins), the deck trays and the life crystals. Positions are generated for one half and turned 180 degrees for the
    other, so the board is symmetric by construction; only the asset lists differ.

Writes board_rebuilt/board_rebuilt.blend + board_environment.png (export_board_to_godot.py exports it, both seats), and
assets/board/board_layout_baked.json: the ground height under every life crystal for BOTH seats (seat 2's board is
turned 180 degrees), which scripts/ui/life_crown.gd reads.

The stations themselves still come from the older stages (build_button_housing.py, build_pit_housing.py): moving one in
layout.json alone does not move its housing.
"""
import bpy, bmesh, os, json, math, random
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(HERE, 'board_rebuilt'); os.makedirs(OUT, exist_ok=True)
L = json.load(open(os.path.join(ROOT, 'assets', 'board', 'layout.json')))
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_pit_stations', 'board_pit_stations.blend'))
scene = bpy.context.scene

WOOD_TOP = L['wood_top']
RAISE = L['raise']
LEDGE = WOOD_TOP + RAISE                       # 0.165: the ledge, where the raised stations stand
RIVER_Z = -0.01
PIVOT_Y = -L['river']['center_z']              # Blender y of the seat-2 turn
R_LOCAL = -L['river']['local_floor_edge_z']    # Blender y of the local floor's river edge (-0.23)
R_OPP = -L['river']['opponent_floor_edge_z']   # (-0.35)
X0, X1, Y0, Y1, STEP = -7.6, 7.6, -4.0, 3.6, 0.05
rng = random.Random(2211)


def g2b(x, z):
    return Vector((x, -z))


def turned(p):
    return Vector((-p.x, 2 * PIVOT_Y - p.y))


def chaikin(points, rounds):
    for _ in range(rounds):
        out = [points[0]]
        for a, b in zip(points, points[1:]):
            out.append(a.lerp(b, 0.25)); out.append(a.lerp(b, 0.75))
        out.append(points[-1])
        points = out
    return points


def densify(points, step):
    out = []
    for a, b in zip(points, points[1:]):
        n = max(1, int((b - a).length / step))
        for k in range(n):
            out.append(a.lerp(b, k / n))
    out.append(points[-1])
    return out


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / max(e1 - e0, 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def noise(x, y, f=1.0, seed=0.0):
    """Smooth, cheap value noise from summed sines (deterministic, vectorised)."""
    return (np.sin(1.7 * f * x + 0.9 + seed) * np.sin(2.3 * f * y + 1.3 * seed) * 0.5 +
            np.sin(3.1 * f * x - 2.0 * f * y + seed) * 0.3 + np.sin(5.3 * f * x + 4.1 * f * y - seed) * 0.2)


# ----------------------------------------------------------------------------------------------- inventory
STATION = ('player ', 'opponent ')
FAMILIES = {
    'forest_low': ('Continuing forest ground', 'Mossy terrain', 'Bank moss'),
    'forest_tall': ('Layered foliage',),
    'volcanic_low': ('Basalt plate', 'Basalt rubble'),
    'volcanic_big': ('Fractured basalt mass', 'Large cooled lava mass'),
    'river_stone': ('Grouped river stone',),
}
WOOD_DECOR = ('Wood knot', 'Grain around knot', 'Slab grain accent')
sources = {k: [] for k in FAMILIES}
decor = []
stations = []
for o in scene.objects:
    if o.type not in {'MESH', 'CURVE'}:
        continue
    base = o.name.split('.')[0]
    if o.name.startswith(STATION):
        stations.append(o)
        continue
    if base in WOOD_DECOR:
        decor.append(o)
    for k, names in FAMILIES.items():
        if base in names:
            sources[k].append(o)
print('[Board] stations %d, decor %d, sources %s' % (len(stations), len(decor), {k: len(v) for k, v in sources.items()}))
for o in stations:
    o.location.z += RAISE
# The old slabs go now, so the new floors take their names (the seat-2 export keeps those names fixed) and nothing
# coplanar is left under them.
for o in list(scene.objects):
    if o.name.startswith(('Volcanic single wood slab', 'Forest single wood slab', 'Continuous river')):
        bpy.data.objects.remove(o, do_unlink=True)

# ----------------------------------------------------------------------------------------------- the outline
right = [g2b(x, z) for x, z in L['floor_outline_right_half']]
ctrl = right + [Vector((-p.x, p.y)) for p in reversed(right[:-1])]
OUT_LOCAL = chaikin(densify(ctrl, 0.35), 4)              # volcanic (local) floor's bank foot, Blender coords
OUT_OPP = [turned(p) for p in OUT_LOCAL]                 # the opponent's
if (R_OPP - turned(Vector((0, R_LOCAL))).y) ** 2 > 1e-4:
    print('[Board] note: opponent river edge %.3f vs turned local %.3f' % (R_OPP, turned(Vector((0, R_LOCAL))).y))


def floor_polygon(outline, river_y):
    """The floor's outline, closed along the river edge (the inside test and the floor mesh both use exactly this)."""
    pts = [p for p in outline if abs(p.x) <= 4.46]
    return pts + [Vector((pts[-1].x, river_y)), Vector((pts[0].x, river_y))]


FLOOR_LOCAL = floor_polygon(OUT_LOCAL, R_LOCAL)
FLOOR_OPP = floor_polygon(OUT_OPP, R_OPP)

dense = densify(OUT_LOCAL, 0.01) + densify(OUT_OPP, 0.01)
kd = KDTree(len(dense))
for i, p in enumerate(dense):
    kd.insert((p.x, p.y, 0.0), i)
kd.balance()


def inside(poly, px, py):
    res = np.zeros(px.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if a.y == b.y:
            continue
        cond = ((a.y > py) != (b.y > py)) & (px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x)
        res ^= cond
    return res


def dist_outline(px, py):
    flat_x, flat_y = px.ravel(), py.ravel()
    d = np.empty(flat_x.shape)
    for i in range(flat_x.size):
        d[i] = kd.find((float(flat_x[i]), float(flat_y[i]), 0.0))[2]
    return d.reshape(px.shape)


# ----------------------------------------------------------------------------------------------- deck trays
DECK_HALF = (L['deck_card'][0] * L['deck_world_scale'] * 0.5, L['deck_card'][1] * L['deck_world_scale'] * 0.5)


def tinted(src, name, factor):
    m = bpy.data.materials[src].copy(); m.name = name
    for node in m.node_tree.nodes:
        if node.type == 'VALTORGB':
            for el in node.color_ramp.elements:
                el.color = tuple(min(1.0, v * factor) for v in el.color[:3]) + (1,)
        elif node.type == 'BSDF_PRINCIPLED':
            c = node.inputs['Base Color'].default_value
            node.inputs['Base Color'].default_value = (min(1, c[0] * factor), min(1, c[1] * factor), min(1, c[2] * factor), 1)
    return m


def rounded_box(name, centre, size, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    o = bpy.context.object; o.name = name; o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = o.modifiers.new('Rounded', 'BEVEL'); mod.width = bevel; mod.segments = 4
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


tray_rim = tinted('Warm muted timber', 'Deck tray rim', 0.9)
tray_floor = tinted('Warm muted timber', 'Deck tray floor', 0.55)
trays = []
# CENTRED AS SEEN: the pile stands ~12 cm tall at full, so from this camera its top face lands up (and sideways) from its
# base on screen, more for the far deck. Each tray is centred where a mid-height of the pile (TRAY_SIGHT_HEIGHT) meets
# the ground along the camera's line of sight, with an EVEN rim all round; the recess grows by the shift so the base
# still fits. (A slim rim on the pit side plus no shift read as "the deck is not centred in its tray".)
TRAY_SIGHT_HEIGHT = 0.09
TRAY_RIM = 0.06
cam_pos = scene.camera.matrix_world.translation
for who in ('player', 'opponent'):
    gx, gy, gz = L['stations'][who]['deck']
    c = g2b(gx, gz)
    floor_z = gy - 0.006
    ray = Vector((c.x, c.y, gy)) - cam_pos
    shift = Vector((ray.x, ray.y)) * (TRAY_SIGHT_HEIGHT / abs(ray.z))
    centre = c + shift
    ihx = DECK_HALF[0] + 0.012 + abs(shift.x)
    ihy = DECK_HALF[1] + 0.012 + abs(shift.y)
    ohx, ohy = ihx + TRAY_RIM, ihy + TRAY_RIM
    top, base = floor_z + 0.066, floor_z - 0.20
    tray = rounded_box('%s deck tray' % who, (centre.x, centre.y, (top + base) * 0.5), (ohx * 2, ohy * 2, top - base), 0.035)
    tray.data.materials.append(tray_rim)
    cutter = rounded_box('cutter', (centre.x, centre.y, floor_z + 0.25), (ihx * 2, ihy * 2, 0.5), 0.02)
    cutter.data.materials.append(tray_floor)
    mod = tray.modifiers.new('Recess', 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'
    mod.object = cutter; mod.material_mode = 'TRANSFER'
    bpy.context.view_layer.objects.active = tray
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    trays.append((centre, ohx, ohy))
    print('[Board] %s deck tray shifted (%.3f, %.3f) to sit under the pile as seen' % (who, shift.x, shift.y))

# ----------------------------------------------------------------------------------------------- keep-out zones
wells = []
station_boxes = []
for o in stations:
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in bb), min(p.y for p in bb))); hi = Vector((max(p.x for p in bb), max(p.y for p in bb)))
    if ' ring ' in o.name:
        wells.append(((lo + hi) * 0.5, max(hi.x - lo.x, hi.y - lo.y) * 0.5))
    if 'housing' in o.name:
        station_boxes.append((lo, hi))
coins = [g2b(L['stations'][w]['forward'][0], L['stations'][w]['forward'][2]) for w in ('player', 'opponent')]
crystal_pts = []
for row in ('bottom', 'top'):
    for x, z in zip(L['life_crystals'][row]['x'], L['life_crystals'][row]['z']):
        crystal_pts.append(g2b(x, z))
CLEAR_R = L['life_crystals']['clear_radius']


def blocked(p, margin=0.0):
    """Is a scatter piece at p (Blender x, y) in a keep-out zone? Checked here AND where the seat-2 turn carries it."""
    for q in (p, turned(p)):
        for lo, hi in station_boxes:
            if lo.x - 0.08 - margin < q.x < hi.x + 0.08 + margin and lo.y - 0.08 - margin < q.y < hi.y + 0.08 + margin:
                return True
        for c, hx, hy in trays:
            if abs(q.x - c.x) < hx + 0.08 + margin and abs(q.y - c.y) < hy + 0.08 + margin:
                return True
        for c in coins:
            if (q - c).length < L['phase_marks_radius'] + margin:
                return True
        for c in crystal_pts:
            if (q - c).length < CLEAR_R + margin:
                return True
    return False


def station_distance(px, py):
    """Distance (Blender xy) to the nearest well, deck tray or station housing footprint, vectorised."""
    d = np.full(px.shape, 99.0)
    for c, r in wells:
        d = np.minimum(d, np.sqrt((px - c.x) ** 2 + (py - c.y) ** 2) - r)
    for c, hx, hy in trays:
        qx, qy = np.abs(px - c.x) - hx, np.abs(py - c.y) - hy
        d = np.minimum(d, np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0))
    for lo, hi in station_boxes:
        cx, cy, hx, hy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (hi.x - lo.x) / 2, (hi.y - lo.y) / 2
        qx, qy = np.abs(px - cx) - hx, np.abs(py - cy) - hy
        d = np.minimum(d, np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0))
    return d


# ----------------------------------------------------------------------------------------------- terrain
xs = np.arange(X0, X1 + 1e-9, STEP)
ys = np.arange(Y0, Y1 + 1e-9, STEP)
GX, GY = np.meshgrid(xs, ys)
in_local = inside(FLOOR_LOCAL, GX, GY)
in_opp = inside(FLOOR_OPP, GX, GY)
in_floor = in_local | in_opp
D = dist_outline(GX, GY)
channel = (GY > R_OPP - 0.02) & (GY < R_LOCAL + 0.02) & ~in_floor


def lava_amount(px, py, d):
    """0..1: how much LAVA shows here (the ground also dips by it). Smooth everywhere: fades out near the floor, the
    river side and every station. Only on the volcanic half."""
    # Every distance fade is WOBBLED by noise, so no lava edge ever traces a straight line (the housings' box footprints
    # otherwise cut pockets with straight sides).
    w = 0.22 * noise(px, py, 3.1, 5.3)
    return smoothstep(0.18, 0.35, noise(px, py, 1.3, 2.7)) * smoothstep(0.55, 0.85, d + w) \
        * smoothstep(PIVOT_Y + 0.5, PIVOT_Y + 0.8, py + w) * smoothstep(0.15, 0.45, station_distance(px, py) + w)


def ground(px, py, d, floor_mask, channel_mask, with_dip=True):
    h = LEDGE + 0.012 * noise(px, py, 2.0) + 0.035 * smoothstep(0.9, 2.6, d)
    bank = WOOD_TOP + (LEDGE - WOOD_TOP) * smoothstep(0.095, 0.24, d)
    h = np.where(d < 0.24, np.minimum(bank + 0.012 * noise(px, py, 2.0) * smoothstep(0.2, 0.3, d), h), h)
    h = np.where(d < 0.095, WOOD_TOP, h)
    if with_dip:
        h = h - 0.05 * lava_amount(px, py, d)
    h = np.where(floor_mask, WOOD_TOP - 0.03, h)
    h = np.where(channel_mask, -0.05, h)
    return h


H = ground(GX, GY, D, in_floor, channel)
# Dips under the open wells and inside the deck trays (the terrain must not show inside either).
for c, r in wells:
    H = np.where((GX - c.x) ** 2 + (GY - c.y) ** 2 < (r + 0.01) ** 2, -0.06, H)
for c, hx, hy in trays:
    H = np.where((np.abs(GX - c.x) < hx + 0.01) & (np.abs(GY - c.y) < hy + 0.01), np.minimum(H, 0.08), H)

ny, nx = GX.shape


def grid_mesh(name, Z, keep_face, material_for):
    verts = [(float(GX[j, i]), float(GY[j, i]), float(Z[j, i])) for j in range(ny) for i in range(nx)]
    faces, mats = [], []
    for j in range(ny - 1):
        for i in range(nx - 1):
            if not keep_face(j, i):
                continue
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))
            mats.append(material_for(j, i))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    for poly, m in zip(me.polygons, mats):
        poly.material_index = m
        poly.use_smooth = True
    ob = bpy.data.objects.new(name, me); scene.collection.objects.link(ob)
    return ob


def terrain_material(j, i):
    if channel[j, i] or channel[j + 1, i]:
        return 2                                   # the riverbed (dark), so no grass shows through the water
    return 0 if (GY[j, i] + GY[j + 1, i]) * 0.5 < PIVOT_Y else 1


terrain = grid_mesh('Board terrain', H, lambda j, i: True, terrain_material)
terrain.data.materials.append(bpy.data.materials['Continuous grassy soil'])
terrain.data.materials.append(bpy.data.materials['Basalt 0'])
terrain.data.materials.append(tinted('Basalt 0', 'Riverbed', 0.8))
# THE LAVA is part of the volcanic ground's material, blended in by a per-vertex 'lava' value (the same amount the
# ground dips by), so its edges follow a smooth contour. (A separate lava sheet under the ground left grid-cut edges.)
LAVA = lava_amount(GX, GY, D)
ca = terrain.data.color_attributes.new('lava', 'FLOAT_COLOR', 'POINT')
flat = LAVA.ravel()
for k, v in enumerate(flat):
    ca.data[k].color = (float(v), float(v), float(v), 1.0)


def volcanic_ground_material():
    m = bpy.data.materials.new('Volcanic ground'); m.use_nodes = True
    nt = m.node_tree; nodes = nt.nodes; links = nt.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new('ShaderNodeOutputMaterial')
    mix = nodes.new('ShaderNodeMixShader')
    attr = nodes.new('ShaderNodeAttribute'); attr.attribute_name = 'lava'; attr.attribute_type = 'GEOMETRY'
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.30; ramp.color_ramp.elements[1].position = 0.52
    coord = nodes.new('ShaderNodeTexCoord')
    nz = nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 3.0; nz.inputs['Detail'].default_value = 6.0
    bump = nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = 0.35
    basalt = nodes.new('ShaderNodeBsdfPrincipled')
    basalt.inputs['Base Color'].default_value = (0.030, 0.029, 0.034, 1); basalt.inputs['Roughness'].default_value = 0.85
    lava = nodes.new('ShaderNodeBsdfPrincipled')
    lava.inputs['Base Color'].default_value = (0.35, 0.025, 0.005, 1)
    lava.inputs['Emission Color'].default_value = (0.95, 0.16, 0.02, 1)
    glow = nodes.new('ShaderNodeMath'); glow.operation = 'MULTIPLY_ADD'
    glow.inputs[1].default_value = 0.55; glow.inputs[2].default_value = 0.22
    links.new(coord.outputs['Object'], nz.inputs['Vector'])
    links.new(nz.outputs['Fac'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], basalt.inputs['Normal'])
    links.new(nz.outputs['Fac'], glow.inputs[0])
    links.new(glow.outputs[0], lava.inputs['Emission Strength'])
    links.new(attr.outputs['Fac'], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], mix.inputs['Fac'])
    links.new(basalt.outputs['BSDF'], mix.inputs[1])
    links.new(lava.outputs['BSDF'], mix.inputs[2])
    links.new(mix.outputs['Shader'], out.inputs['Surface'])
    return m


terrain.data.materials[1] = volcanic_ground_material()

# ----------------------------------------------------------------------------------------------- the wood floors
def floor_mesh(name, poly, river_y):
    """One n-gon cut to the outline, made solid downward (Solidify): robust for a concave outline."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(p.x, p.y, WOOD_TOP) for p in poly], [], [list(range(len(poly)))])
    me.update()
    if me.polygons[0].normal.z < 0:
        me.polygons[0].flip()
    # The timber material maps its grain with GENERATED coordinates (the mesh's texture space). A flat n-gon has a box
    # of zero depth there, which broke the mapping (the floor rendered black): give it the old slab's texture space.
    ys = [p.y for p in poly]
    me.auto_texspace = False
    me.texspace_location = (0.0, (min(ys) + max(ys)) * 0.5, WOOD_TOP - 0.085)
    me.texspace_size = (4.30, (max(ys) - min(ys)) * 0.5, 0.145)
    me.materials.append(bpy.data.materials['Warm muted timber'])
    ob = bpy.data.objects.new(name, me); scene.collection.objects.link(ob)
    sol = ob.modifiers.new('Thickness', 'SOLIDIFY'); sol.thickness = 0.10; sol.offset = -1.0
    return ob


floor_mesh('Volcanic single wood slab', FLOOR_LOCAL, R_LOCAL)
floor_mesh('Forest single wood slab', FLOOR_OPP, R_OPP)

# ----------------------------------------------------------------------------------------------- the curb and seam
CURB_PROFILE = [(0.0, -0.012), (0.0, 0.050), (0.010, 0.063), (0.072, 0.066), (0.086, 0.056), (0.09, -0.012)]
CURB_BLOCK, CURB_JOINT, CREASE = 0.45, 0.012, 0.025


def outward_normals(pts, floor_poly):
    normals = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, len(pts) - 1)]
        t = (b - a).normalized()
        normals.append(Vector((t.y, -t.x)))
    # Orient so the normal leaves the floor: test the middle point.
    mid = len(pts) // 2
    probe = pts[mid] + normals[mid] * 0.05
    if inside(floor_poly, np.array([probe.x]), np.array([probe.y]))[0]:
        normals = [-n for n in normals]
    return normals


def curb(name, outline, floor_poly, material, seed):
    r = random.Random(seed)
    normals = outward_normals(outline, floor_poly)
    fine = []
    for i in range(len(outline) - 1):
        a, b = outline[i], outline[i + 1]
        n = max(1, int((b - a).length / 0.02))
        for k in range(n):
            t = k / n
            fine.append((a.lerp(b, t), normals[i].lerp(normals[i + 1], t).normalized()))
    fine.append((outline[-1], normals[-1]))
    bm = bmesh.new(); k = len(CURB_PROFILE)
    run, block, rise = 0.0, [], r.uniform(-0.004, 0.004)

    def close(block):
        if len(block) < 2:
            return
        for a, b in zip(block, block[1:]):
            for i in range(k):
                j = (i + 1) % k
                bm.faces.new((a[i], a[j], b[j], b[i]))
        bm.faces.new(list(reversed(block[0]))); bm.faces.new(block[-1])
    for idx, (p, n) in enumerate(fine):
        if idx:
            run += (p - fine[idx - 1][0]).length
        if run > CURB_BLOCK:
            close(block); block, run, rise = [], -CURB_JOINT, r.uniform(-0.004, 0.004)
        if run < 0:
            continue
        block.append([bm.verts.new((p.x + n.x * u, p.y + n.y * u, WOOD_TOP + z + (rise if z > 0 else 0)))
                      for u, z in CURB_PROFILE])
    close(block)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me); scene.collection.objects.link(ob)
    bev = ob.modifiers.new('Chipped edges', 'BEVEL'); bev.width = 0.004; bev.segments = 1; bev.limit_method = 'ANGLE'
    # The seam: a near-black strip on the floor side of the curb's foot.
    bm = bmesh.new(); rows = []
    for p, n in fine:
        rows.append([bm.verts.new((p.x + n.x * u, p.y + n.y * u, WOOD_TOP + 0.0015)) for u in (-CREASE, 0.004)])
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], a[1], b[1], b[0]))
    me = bpy.data.meshes.new(name + ' seam'); bm.to_mesh(me); bm.free()
    for poly in me.polygons:
        if poly.normal.z < 0:
            poly.flip()
    seam = bpy.data.materials.get('Floor crease') or bpy.data.materials.new('Floor crease')
    seam.use_nodes = True
    bsdf = seam.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (0.012, 0.010, 0.009, 1); bsdf.inputs['Roughness'].default_value = 1.0
    me.materials.append(seam)
    s_ob = bpy.data.objects.new(name + ' seam', me); scene.collection.objects.link(s_ob)
    return ob


curb('Board curb volcanic', OUT_LOCAL, FLOOR_LOCAL, tinted('Basalt 1', 'Curb basalt', 1.7), 31)
curb('Board curb forest', OUT_OPP, FLOOR_OPP, tinted('Forest housing stone', 'Curb forest stone', 0.78), 47)

# ----------------------------------------------------------------------------------------------- the river
bm = bmesh.new()
rv = [bm.verts.new(v) for v in ((X0, R_OPP - 0.06, RIVER_Z), (X1, R_OPP - 0.06, RIVER_Z),
                                 (X1, R_LOCAL + 0.06, RIVER_Z), (X0, R_LOCAL + 0.06, RIVER_Z))]
bm.faces.new(rv)
bmesh.ops.subdivide_edges(bm, edges=bm.edges, cuts=12, use_grid_fill=True)
me = bpy.data.meshes.new('Continuous river'); bm.to_mesh(me); bm.free()
for poly in me.polygons:
    if poly.normal.z < 0:
        poly.flip()
me.materials.append(bpy.data.materials['Teal river'])
scene.collection.objects.link(bpy.data.objects.new('Continuous river', me))

# ----------------------------------------------------------------------------------------------- scatter
def height_at(p):
    px, py = np.array([p.x]), np.array([p.y])
    d = dist_outline(px, py)
    fl = inside(FLOOR_LOCAL, px, py) | inside(FLOOR_OPP, px, py)
    ch = (py > R_OPP - 0.02) & (py < R_LOCAL + 0.02) & ~fl
    return float(ground(px, py, d, fl, ch)[0]), float(d[0]), bool(fl[0]), bool(ch[0])


placed = 0


def place(src, p, sink, scale):
    global placed
    ob = src.copy(); scene.collection.objects.link(ob)
    ob.rotation_euler = (src.rotation_euler.x, src.rotation_euler.y, rng.uniform(0, math.tau))
    ob.scale = src.scale * scale
    ob.location = src.location.copy()
    bpy.context.view_layer.update()
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    cx = sum(q.x for q in bb) / 8; cy = sum(q.y for q in bb) / 8
    zmin = min(q.z for q in bb); zmax = max(q.z for q in bb)
    h, _, _, _ = height_at(p)
    ob.location.x += p.x - cx; ob.location.y += p.y - cy
    ob.location.z += h - zmin - sink * (zmax - zmin)
    ob.name = 'Board scatter %s' % src.name.split('.')[0]
    placed += 1


# Positions for the LOCAL (volcanic) half on a jittered grid; the forest half gets the same positions turned.
for gy in np.arange(PIVOT_Y + 0.3, Y1, 0.30):
    for gx in np.arange(X0 + 0.1, X1, 0.30):
        p = Vector((gx + rng.uniform(-0.12, 0.12), gy + rng.uniform(-0.12, 0.12)))
        roll = rng.random()
        for half in ('volcanic', 'forest'):
            q = p if half == 'volcanic' else turned(p)
            h, d, fl, ch = height_at(q)
            if fl or ch or d < 0.30 or blocked(q):
                continue
            if half == 'volcanic':
                if d < 1.5 and roll < 0.55 and sources['volcanic_low']:
                    place(rng.choice(sources['volcanic_low']), q, 0.35, rng.uniform(0.85, 1.2))
                elif d > 0.9 and roll > 0.93 and sources['volcanic_big']:
                    place(rng.choice(sources['volcanic_big']), q, 0.3, rng.uniform(0.8, 1.05))
            else:
                if roll < 0.5 and sources['forest_low']:
                    place(rng.choice(sources['forest_low']), q, 0.3, rng.uniform(0.85, 1.2))
                elif d > 0.75 and roll > 0.82 and sources['forest_tall']:
                    place(rng.choice(sources['forest_tall']), q, 0.08, rng.uniform(0.9, 1.25))
# River stones along both banks of the channel, beyond the floors.
for gx in np.concatenate([np.arange(4.75, X1, 0.22), -np.arange(4.75, X1, 0.22)]):
    for y in (R_LOCAL + 0.14, R_OPP - 0.14):
        q = Vector((gx + rng.uniform(-0.05, 0.05), y + rng.uniform(-0.03, 0.03)))
        if sources['river_stone'] and not blocked(q) and rng.random() < 0.7:
            place(rng.choice(sources['river_stone']), q, 0.4, rng.uniform(0.8, 1.15))
print('[Board] scatter: %d pieces placed' % placed)

# ----------------------------------------------------------------------------------------------- clean up the old board
keep = set(stations)
for o in decor:
    p = Vector((sum((o.matrix_world @ Vector(c)).x for c in o.bound_box) / 8,
                sum((o.matrix_world @ Vector(c)).y for c in o.bound_box) / 8))
    _, d, fl, _ = height_at(p)
    if fl and d > 0.15:
        keep.add(o)
generated = ('Board ', 'Volcanic single wood slab', 'Forest single wood slab', 'Continuous river', 'player deck tray',
             'opponent deck tray')
removed = 0
for o in list(scene.objects):
    if o.type in {'MESH', 'CURVE'} and o not in keep and not o.name.startswith(generated):
        bpy.data.objects.remove(o, do_unlink=True)
        removed += 1
print('[Board] removed %d old scenery objects' % removed)

# ----------------------------------------------------------------------------------------------- crystal heights
def socket(p):
    hs = [height_at(p + Vector((math.cos(a), math.sin(a))) * r)[0]
          for r in (0.0, L['life_crystals']['sample_radius']) for a in np.linspace(0, math.tau, 8, endpoint=False)]
    return round(min(hs), 3), round(max(hs), 3)


baked = {'comment': 'Written by Blender/build_board.py: ground height (Godot y) round each life crystal, per seat '
                    '(seat 2 turns the board 180 degrees). [x, z, low, high].', 'life_crystal_sockets': {}}
for seat in (1, 2):
    rows = {}
    for row in ('bottom', 'top'):
        out = []
        for x, z in zip(L['life_crystals'][row]['x'], L['life_crystals'][row]['z']):
            p = g2b(x, z)
            lo, hi = socket(p if seat == 1 else turned(p))
            out.append([x, z, lo, hi])
        rows[row] = out
    baked['life_crystal_sockets'][str(seat)] = rows
json.dump(baked, open(os.path.join(ROOT, 'assets', 'board', 'board_layout_baked.json'), 'w'), indent=1)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_rebuilt.blend'))
R = scene.render
scene.cycles.samples = 40
R.use_border = False; R.use_crop_to_border = False
R.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: board rebuilt, export source saved to', OUT, flush=True)
