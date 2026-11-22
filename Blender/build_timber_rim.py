"""Frame the play area with a raised timber rail, like the rail round Artifact's board.

The stage after build_deck_cradles.py: reads board_deck_cradles/board_deck_cradles.blend (never modified) and writes
board_timber_rim/board_timber_rim.blend + board_environment.png, which export_board_to_godot.py exports.

WHY (2026-11-22): the two wood slabs ended in plain square cuts and met the forest and rocks along hard straight lines;
Artifact's floor sits inside a rounded wooden rail, which is most of what makes it read as a crafted table.

SHAPE: the board is TWO slabs with the river crossing between them, so each slab gets a U-shaped rail: round its FAR
long edge and both short ends, rounded at the two far corners, open (capped) where the river passes. The rail's inner
edge is the slab's edge and it stands OUTSIDE the slab, so the play area keeps every centimetre. A rounded, domed
profile, RAIL_TOP above the board (the slab top is 0.065), sunk into the terrain below.

The wood never turns for seat 2, and neither does the rail: export_board_to_godot.py lists 'Timber rim' with the
fixed prefixes. The top life crystals stand at the forest slab's far edge, so their sampled rock heights
(scripts/ui/life_crown.gd SOCKET_SETS "top") were re-sampled after this stage.

    blender --background --python Blender/build_timber_rim.py
"""
import bpy, bmesh, os, math
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_timber_rim'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_deck_cradles', 'board_deck_cradles.blend'))
scene = bpy.context.scene

SLAB_X = 4.30                 # the slabs' short ends (|x|), from widen_board.py
FOREST = (-2.19, -0.35)       # forest slab: rail line y, river edge y. NOT the slab's -2.32: the forest's grass bank
                              # lies over the slab's last ~15 cm, so the rail is drawn in to cover that strip
VOLCANIC = (1.72, -0.23)      # volcanic slab: far edge y, river edge y
W = 0.14                      # rail width, from the slab edge outward
CORNER_R = 0.24               # radius of the rail's inner edge round the far corners
RAIL_TOP = 0.105              # crown of the rail (board slab top is 0.065)
INNER_TOP = 0.085             # the rail's inner wall, where it meets the wood
FOOT = -0.12                  # sunk into the terrain
OVERLAP = 0.05                # the rail starts this far INSIDE the slab edge (the slab's bevel rounds it inward)
STEPS_ARC = 10


def path(far_y, river_y):
    """(point, outward normal) along the rail's inner edge: river end of the -x side, round the far corner, along the
    far edge, round the other corner, to the river end of the +x side."""
    s = 1.0 if far_y > river_y else -1.0          # +1: the far edge is +y (volcanic); -1: forest
    pts = []
    cy = far_y - s * CORNER_R
    # -x side, from the river to the corner
    for t in (0.0, 1.0):
        y = river_y + (cy - river_y) * t
        pts.append((Vector((-SLAB_X, y, 0)), Vector((-1, 0, 0))))
    # corner at -x
    cx = -SLAB_X + CORNER_R
    for k in range(1, STEPS_ARC):
        a = math.pi - s * (math.pi / 2) * k / STEPS_ARC
        n = Vector((math.cos(a), math.sin(a), 0))
        pts.append((Vector((cx, cy, 0)) + n * CORNER_R, n))
    # far edge
    for t in (0.0, 1.0):
        x = cx + (SLAB_X - CORNER_R - cx) * t
        pts.append((Vector((x, far_y, 0)), Vector((0, s, 0))))
    # corner at +x
    cx2 = SLAB_X - CORNER_R
    for k in range(1, STEPS_ARC):
        a = (math.pi / 2) * s * (1 - k / STEPS_ARC)
        n = Vector((math.cos(a), math.sin(a), 0))
        pts.append((Vector((cx2, cy, 0)) + n * CORNER_R, n))
    for t in (0.0, 1.0):
        y = cy + (river_y - cy) * t
        pts.append((Vector((SLAB_X, y, 0)), Vector((1, 0, 0))))
    return pts


# The cross-section: (offset outward from the inner edge, height). Inner wall, a domed crown, outer wall, foot.
PROFILE = [(-OVERLAP, FOOT), (-OVERLAP, INNER_TOP - 0.01), (0.012, INNER_TOP), (0.035, RAIL_TOP - 0.006),
           (W * 0.5, RAIL_TOP), (W - 0.035, RAIL_TOP - 0.008), (W - 0.01, RAIL_TOP - 0.03), (W, RAIL_TOP - 0.06),
           (W + 0.006, FOOT)]


def rail(name, far_y, river_y, material):
    bm = bmesh.new()
    rings = []
    for p, n in path(far_y, river_y):
        ring = [bm.verts.new(p + n * u + Vector((0, 0, z))) for u, z in PROFILE]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(len(PROFILE) - 1):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
        bm.faces.new((a[-1], a[0], b[0], b[-1]))     # the underside
    bm.faces.new(list(reversed(rings[0])))            # end caps at the river
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    # Crisp the ridge lines a little while keeping the crown smooth.
    mod = ob.modifiers.new('Edge split', 'EDGE_SPLIT')
    mod.split_angle = math.radians(50)
    return ob


def tinted(src, name, factor):
    m = bpy.data.materials[src].copy()
    m.name = name
    for node in m.node_tree.nodes:
        if node.type == 'VALTORGB':
            for el in node.color_ramp.elements:
                el.color = tuple(v * factor for v in el.color[:3]) + (1,)
        elif node.type == 'BSDF_PRINCIPLED':
            c = node.inputs['Base Color'].default_value
            node.inputs['Base Color'].default_value = (c[0] * factor, c[1] * factor, c[2] * factor, 1)
    return m


def in_band(o):
    """Is this piece of edge decoration sitting where the rail goes (its centre within the rail's footprint)?"""
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    c = sum(bb, Vector()) / 8.0
    size = max(max(p.x for p in bb) - min(p.x for p in bb), max(p.y for p in bb) - min(p.y for p in bb))
    if size > 1.0:
        return False
    for far_y, river_y in (FOREST, VOLCANIC):
        lo_y, hi_y = min(far_y, river_y), max(far_y, river_y)
        s = 1.0 if far_y > river_y else -1.0
        # short ends
        if lo_y - 0.05 <= c.y <= hi_y + 0.05 and SLAB_X - 0.15 <= abs(c.x) <= SLAB_X + W + 0.04:
            return True
        # far edge
        d = (c.y - far_y) * s
        if -0.08 <= d <= W + 0.06 and abs(c.x) <= SLAB_X + W:
            return True
    return False


rim_mat = tinted('Warm muted timber', 'Timber rim', 0.82)
KEEP = ('Forest single wood slab', 'Volcanic single wood slab', 'Diorama', 'Continuous', 'Unified', 'Volcanic ground',
        'Solid dark terrain', 'Edge forest ground', 'Edge volcanic ground', 'player ', 'opponent ', 'Deck proxy',
        'Layout card', 'Card face', 'Camera', 'Slab edge split', 'Slab grain accent', 'Wood knot', 'Grain around knot',
        'Forest side rim', 'Volcanic side rim')
removed = 0
for o in list(scene.objects):
    if o.type in {'MESH', 'CURVE'} and not o.name.startswith(KEEP) and in_band(o):
        bpy.data.objects.remove(o, do_unlink=True)
        removed += 1

rails = [rail('Timber rim forest', FOREST[0], FOREST[1], rim_mat),
         rail('Timber rim volcanic', VOLCANIC[0], VOLCANIC[1], rim_mat)]

# THE STATIONS SIT IN THE RAIL, NOT UNDER IT: the pit and button wells straddle the slab edges, and a rail across them
# cut every circle in half. Each well ring becomes a cylinder that is cut out of the rails (the housing stone around
# it is taller than the rail, so the rail simply disappears into it).
cutters = []
for o in list(scene.objects):
    if o.type == 'MESH' and o.name.startswith(('player ', 'opponent ')) and ' ring ' in o.name:
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        cx = (max(p.x for p in bb) + min(p.x for p in bb)) * 0.5
        cy = (max(p.y for p in bb) + min(p.y for p in bb)) * 0.5
        r = max(max(p.x for p in bb) - min(p.x for p in bb), max(p.y for p in bb) - min(p.y for p in bb)) * 0.5 + 0.015
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=1.0, location=(cx, cy, 0.0))
        cutters.append(bpy.context.object)
for ob in rails:
    bpy.context.view_layer.objects.active = ob
    for c in cutters:
        mod = ob.modifiers.new('Well', 'BOOLEAN')
        mod.operation = 'DIFFERENCE'
        mod.solver = 'EXACT'
        mod.object = c
        bpy.ops.object.modifier_apply(modifier=mod.name)
for c in cutters:
    bpy.data.objects.remove(c, do_unlink=True)
print('[TimberRim] two U rails built (W %.2f, crown %.3f), %d edge pieces removed, %d wells cut out' % (
    W, RAIL_TOP, removed, len(cutters)))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_timber_rim.blend'))
R = scene.render
for o in scene.objects:
    if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
        o.hide_render = True
scene.cycles.samples = 40
R.use_border = False; R.use_crop_to_border = False
R.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: timber rim built, export source saved to', OUT, flush=True)
