"""Fill the board out to the screen edges, and carry the river past them.

The stage after build_pit_housing.py: reads board_pit_stations/board_pit_stations.blend (never modified) and writes
board_edges/board_edges.blend + board_edges/board_environment.png, which export_board_to_godot.py exports.

WHY: the scenery stopped at x +-5.0..5.2 (Blender), but the game camera (frame 9.6, fov 22, elevation 67) sees the
ground out to x +-4.9 beside the river and +-5.4 in the far corners, so the background showed through at the left and
right edges and the river ran into nothing (2026-11-22, compared against Artifact's board, which never shows an edge).

WHAT: per side, beyond |x| = SKIRT_FROM:
  * forest soil on the forest half and lava on the volcanic half (the board's own materials), out to |x| = SKIRT_TO
    (21:9 sees ~7.0 at the far edge);
  * the river continued across the same width, named 'Continuous river ...' so the exporter puts it in the river mesh
    (the animated river shader), with river stones and bank moss along both banks;
  * linked copies of the board's own foliage, mossy terrain and basalt plates scattered on the new ground (seeded).
The seat-2 export turns everything that is not the wood about the river's centre, so these swap biomes with the rest.

    blender --background --python Blender/extend_board_edges.py
"""
import bpy, os, random, math
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_edges'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_pit_stations', 'board_pit_stations.blend'))
scene = bpy.context.scene
rng = random.Random(2211)

SKIRT_FROM = 4.85        # |x| where the new ground starts (under the old edge scenery, which covers the seam)
SKIRT_TO = 7.6
RIVER_Y = (-1.00, 0.42)  # the river's band (Blender y); forest is y < -1.0, volcanic y > 0.42
FOREST_Y = (-8.0, RIVER_Y[0])
VOLCANIC_Y = (RIVER_Y[1], 4.8)
FOREST_Z, RIVER_Z, VOLCANIC_Z = 0.045, -0.012, -0.02


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        raise SystemExit('missing material %r' % name)
    return m


def plane(name, x0, x1, y0, y1, z, material, cuts=12):
    """A flat grid (subdivided so the camera-projected texture has vertices to land on)."""
    verts, faces = [], []
    nx, ny = cuts, max(2, int(cuts * abs(y1 - y0) / max(abs(x1 - x0), 1e-3)))
    for j in range(ny + 1):
        for i in range(nx + 1):
            verts.append((x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny, z))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    # Faces point up (Blender +Z): the exporter reverses the winding for Godot like every other board mesh.
    if me.polygons[0].normal.z < 0:
        for p in me.polygons:
            p.flip()
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me); scene.collection.objects.link(ob)
    return ob


def family(prefix, max_dim=None):
    out = [o for o in scene.objects if o.type == 'MESH' and o.name.split('.')[0] == prefix]
    if max_dim is not None:
        out = [o for o in out if max(o.dimensions.x, o.dimensions.y) <= max_dim]
    if not out:
        raise SystemExit('no objects in family %r' % prefix)
    return out


def scatter(sources, count, xs, ys, scale=(0.8, 1.25), name='Edge'):
    """Linked copies of the board's own pieces, at random spots on the new ground. Their height is kept (each source
    already sits at the right depth for its kind)."""
    placed = []
    for k in range(count):
        src = rng.choice(sources)
        ob = src.copy()                 # linked: shares the mesh, keeps modifiers and materials
        scene.collection.objects.link(ob)
        side = 1 if k % 2 == 0 else -1
        target = Vector((side * rng.uniform(*xs), rng.uniform(*ys)))
        ob.rotation_euler = (src.rotation_euler.x, src.rotation_euler.y, rng.uniform(0, math.tau))
        s = rng.uniform(*scale)
        ob.scale = src.scale * s
        ob.location = src.location.copy()
        # Place by the piece's BOUNDING-BOX centre, not its origin: some pieces carry their offset in the mesh.
        local_c = sum((Vector(c) for c in src.bound_box), Vector()) / 8.0
        xf = Matrix.LocRotScale(ob.location, ob.rotation_euler.to_quaternion(), ob.scale)
        world_c = xf @ local_c
        ob.location.x += target.x - world_c.x
        ob.location.y += target.y - world_c.y
        ob.name = '%s %s' % (name, src.name.split('.')[0])
        placed.append(ob)
    return placed


soil = mat('Continuous grassy soil')
lava = mat('Red fissures')
river = mat('Teal river')

for side, tag in ((1, 'R'), (-1, 'L')):
    x0, x1 = side * SKIRT_FROM, side * SKIRT_TO
    lo, hi = min(x0, x1), max(x0, x1)
    plane('Edge forest ground %s' % tag, lo, hi, FOREST_Y[0], FOREST_Y[1], FOREST_Z, soil)
    plane('Edge volcanic ground %s' % tag, lo, hi, VOLCANIC_Y[0], VOLCANIC_Y[1], VOLCANIC_Z, lava)
    # Starts a little INSIDE the old river's end so the two overlap rather than leave a slit.
    rx0, rx1 = side * 4.95, side * SKIRT_TO
    plane('Continuous river edge %s' % tag, min(rx0, rx1), max(rx0, rx1), RIVER_Y[0], RIVER_Y[1], RIVER_Z, river, cuts=10)

# Forest: ground clumps first (low), then foliage and mossy terrain on top.
scatter(family('Continuing forest ground'), 46, (5.0, 7.4), (-7.6, -1.3), name='Edge forest')
scatter(family('Mossy terrain'), 26, (5.0, 7.3), (-6.5, -1.4), name='Edge forest')
scatter(family('Layered foliage'), 22, (5.3, 7.3), (-6.5, -1.6), (0.9, 1.3), name='Edge forest')
# Volcanic: basalt plates and rubble over the lava, leaving fissures between them.
scatter(family('Basalt plate'), 40, (5.0, 7.4), (0.75, 4.6), name='Edge volcanic')
scatter(family('Basalt rubble'), 18, (5.0, 7.4), (0.7, 4.4), name='Edge volcanic')
# Banks: stones along both edges of the new river, moss on the forest bank.
stones = family('Grouped river stone')
for bank_y in (RIVER_Y[0] + 0.04, RIVER_Y[1] - 0.04):
    scatter(stones, 14, (5.0, 7.4), (bank_y - 0.06, bank_y + 0.06), (0.8, 1.2), name='Edge bank')
scatter(family('Bank moss'), 10, (5.0, 7.4), (RIVER_Y[0] - 0.08, RIVER_Y[0] + 0.02), name='Edge bank')

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_edges.blend'))

R = scene.render
for o in scene.objects:
    if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
        o.hide_render = True
scene.cycles.samples = 40
R.use_border = False; R.use_crop_to_border = False
R.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: board edges filled, export source saved to', OUT, flush=True)
