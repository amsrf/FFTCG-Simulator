"""Give each deck its own place: a recessed wooden tray built into the board, like Artifact's deck trays.

The stage after extend_board_edges.py: reads board_edges/board_edges.blend (never modified) and writes
board_deck_cradles/board_deck_cradles.blend + board_environment.png, which export_board_to_godot.py exports.

WHY (2026-11-22): the decks lay straight on the rocks / grass of the corners and read as "weirdly on top of things".
A stone deck station was tried earlier and removed at the user's request; this is WOOD (the board's own timber), a
low rim round the pile with the floor at the deck's base, so the bottom of the pile sits inside the tray.

WHERE: the deck centres are game.tscn's Player/Deck (3.64, 0.07, -1.95) and Opponent/Deck (-3.64, 0.07, 2.55) in Godot,
i.e. Blender (x, -z). The deck is a card (0.429 x 0.6) at DECK_WORLD_SCALE 1.4, portrait along Godot z. Move a deck in
game.tscn and move it here, then re-run this and the export (both seats). The seat-2 export turns the board about
(0, -0.30), which carries the player's tray exactly onto the opponent's deck and back, so both are built here.

The tray stops at the Break Zone pit housing beside it (inner edge x 3.31): RIM_PIT keeps that side slim.

    blender --background --python Blender/build_deck_cradles.py
"""
import bpy, os
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_deck_cradles'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_edges', 'board_edges.blend'))
scene = bpy.context.scene

DECKS = {'player': (3.64, 1.95), 'opponent': (-3.64, -2.55)}   # Blender x, y
DECK_HALF = (0.429 * 1.4 * 0.5, 0.6 * 1.4 * 0.5)                # (x, y) half extents of the pile
CLEARANCE = 0.012          # gap between the pile and the rim's inner wall
RIM = 0.10                 # rim thickness on the three OUTER sides (wide enough to read round the pile)
RIM_PIT = 0.035            # rim on the side facing the centre, where the Break Zone pit housing stands
FLOOR_Z = 0.064            # the tray floor, just under the deck's base (Godot y 0.07)
RIM_TOP = 0.13             # the rim stands this high: the lower part of the pile sits inside the tray
BASE_Z = -0.14             # the tray's foot, sunk into the terrain
BEVEL = 0.035


def rounded_box(name, centre, size, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    o = bpy.context.object
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = o.modifiers.new('Rounded corners', 'BEVEL')
    mod.width = bevel
    mod.segments = 4
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


def darker(src_name, new_name, factor):
    m = bpy.data.materials[src_name].copy()
    m.name = new_name
    if m.node_tree:
        for node in m.node_tree.nodes:
            if node.type == 'VALTORGB':
                for el in node.color_ramp.elements:
                    el.color = tuple(v * factor for v in el.color[:3]) + (1,)
            elif node.type == 'BSDF_PRINCIPLED':
                c = node.inputs['Base Color'].default_value
                node.inputs['Base Color'].default_value = (c[0] * factor, c[1] * factor, c[2] * factor, 1)
    return m


# The board's own warm timber for the rim (the near-black 'Dark timber edge' vanished against the rocks), and a darker
# floor so the recess reads as a recess.
rim_mat = darker('Warm muted timber', 'Deck tray rim', 0.9)
floor_mat = darker('Warm muted timber', 'Deck tray floor', 0.55)

KEEP = ('Forest single wood slab', 'Volcanic single wood slab', 'Diorama', 'Continuous', 'Unified', 'Volcanic ground',
        'Solid dark terrain', 'Edge forest ground', 'Edge volcanic ground', 'player ', 'opponent ', 'Deck proxy',
        'Layout card', 'Card face', 'Camera')

for who, (cx, cy) in DECKS.items():
    ihx, ihy = DECK_HALF[0] + CLEARANCE, DECK_HALF[1] + CLEARANCE
    out = 1.0 if cx > 0 else -1.0                 # +x points away from the board's centre for this deck
    x_in, x_out = cx - out * (ihx + RIM_PIT), cx + out * (ihx + RIM)
    ox0, ox1 = min(x_in, x_out), max(x_in, x_out)
    ohx, ohy = (ox1 - ox0) * 0.5, ihy + RIM
    ocx = (ox0 + ox1) * 0.5
    # Clear the small scenery standing where the tray goes (rocks, foliage, plates), so nothing pokes through it.
    removed = 0
    for o in list(scene.objects):
        if o.type not in {'MESH', 'CURVE'} or o.name.startswith(KEEP):
            continue
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        lo = Vector((min(p.x for p in bb), min(p.y for p in bb), min(p.z for p in bb)))
        hi = Vector((max(p.x for p in bb), max(p.y for p in bb), max(p.z for p in bb)))
        if max(hi.x - lo.x, hi.y - lo.y) > 1.6 or hi.z < FLOOR_Z - 0.04:
            continue
        if hi.x > ocx - ohx - 0.04 and lo.x < ocx + ohx + 0.04 and hi.y > cy - ohy - 0.04 and lo.y < cy + ohy + 0.04:
            bpy.data.objects.remove(o, do_unlink=True)
            removed += 1
    tray = rounded_box('%s deck tray' % who, (ocx, cy, (BASE_Z + RIM_TOP) * 0.5),
                       (ohx * 2, ohy * 2, RIM_TOP - BASE_Z), BEVEL)
    tray.data.materials.append(rim_mat)
    cutter = rounded_box('%s deck tray cutter' % who, (cx, cy, FLOOR_Z + 0.25), (ihx * 2, ihy * 2, 0.5), BEVEL * 0.6)
    cutter.data.materials.append(floor_mat)
    cut = tray.modifiers.new('Recess', 'BOOLEAN')
    cut.operation = 'DIFFERENCE'
    cut.solver = 'EXACT'
    cut.object = cutter
    cut.material_mode = 'TRANSFER'
    bpy.context.view_layer.objects.active = tray
    bpy.ops.object.modifier_apply(modifier=cut.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    # A soft top edge on the rim.
    soft = tray.modifiers.new('Soft rim', 'BEVEL')
    soft.width = 0.006
    soft.segments = 2
    soft.limit_method = 'ANGLE'
    bpy.ops.object.modifier_apply(modifier=soft.name)
    print('[DeckCradles] %s tray at (%.2f, %.2f): outer %.2f x %.2f, removed %d scenery pieces' % (
        who, cx, cy, ohx * 2, ohy * 2, removed))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_deck_cradles.blend'))

R = scene.render
for o in scene.objects:
    if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
        o.hide_render = True
scene.cycles.samples = 40
R.use_border = False; R.use_crop_to_border = False
R.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: deck trays built, export source saved to', OUT, flush=True)
