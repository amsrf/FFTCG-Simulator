"""The Chaos life crown's pieces: a rock collar (+ its ember seam) and the blood crystal grown out of it.

    blender --background --python Blender/build_life_crown.py                     # rebuild from the saved crystal
    blender --background --python Blender/build_life_crown.py -- --fbx <file.fbx> # re-import + decimate the source

The crystals BELONG TO THE BOARD: seven grow out of the volcanic stones along the local edge. WHERE they stand (world
x/z, the rock heights under them, their size and lean) is data in scripts/ui/life_crown.gd, sampled from the board
mesh; this script only makes the shapes, normalised, and writes them for Godot:

    assets/life_crown/life_crown.bin    STONE collar, GEM ember seam, CRYSTAL (no import cache)
    Blender/life_crown/life_crown.blend  to hand-edit
    Blender/life_crown/preview.png       Cycles preview (one collar + crystal)
    Blender/life_crown/blood_crystal.blend  the decimated source crystal (the 30 MB Meshy FBX is not kept in the repo)

Blender X right, Z up, -Y toward the viewer; the exporter writes Godot (x, z, -y).
"""
import bpy, bmesh, os, sys, math, struct
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(HERE, 'life_crown')
BIN_DIR = os.path.join(ROOT, 'assets', 'life_crown')
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(BIN_DIR, exist_ok=True)
CRYSTAL_BLEND = os.path.join(OUT_DIR, 'blood_crystal.blend')

BG = (0.03, 0.028, 0.035, 1)
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if '--grey' in argv: BG = (0.35, 0.35, 0.37, 1)
FBX = argv[argv.index('--fbx') + 1] if '--fbx' in argv else None

# ---------------------------------------------------------------- layout (centre crystal height = 1)
# (x, z) of each socket's BASE for the right half (index 0 = centre), crystal scale, outward lean in degrees.
COLLAR_SIDES = 9
CRYSTAL_FACES = 900          # decimation target for the source crystal

STONE, GEM, CRYSTAL = 0, 1, 2
METAL = STONE   # the exporter's name for material 0


# ---------------------------------------------------------------- source crystal
def load_crystal():
    if FBX:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=FBX)
        src = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
        bpy.context.view_layer.objects.active = src
        src.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        d = src.modifiers.new('planar', 'DECIMATE'); d.decimate_type = 'DISSOLVE'; d.angle_limit = math.radians(3)
        bpy.ops.object.modifier_apply(modifier='planar')
        tri = src.modifiers.new('tri', 'TRIANGULATE'); bpy.ops.object.modifier_apply(modifier='tri')
        faces = len(src.data.polygons)
        if faces > CRYSTAL_FACES:
            d = src.modifiers.new('collapse', 'DECIMATE'); d.ratio = CRYSTAL_FACES / faces
            bpy.ops.object.modifier_apply(modifier='collapse')
        # Normalise: foot at the origin, 1.0 tall, centred in x/y.
        ws = [v.co.copy() for v in src.data.vertices]
        lo = Vector((min(v.x for v in ws), min(v.y for v in ws), min(v.z for v in ws)))
        hi = Vector((max(v.x for v in ws), max(v.y for v in ws), max(v.z for v in ws)))
        h = hi.z - lo.z
        centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        for v in src.data.vertices:
            v.co = (v.co - centre) / h
        src.name = 'BloodCrystal'
        src.data.name = 'BloodCrystal'
        src.data.materials.clear()
        for m in list(bpy.data.materials):
            bpy.data.materials.remove(m)
        for img in list(bpy.data.images):
            bpy.data.images.remove(img)
        print('[LifeCrown] crystal decimated to %d faces' % len(src.data.polygons))
        bpy.ops.wm.save_as_mainfile(filepath=CRYSTAL_BLEND)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(CRYSTAL_BLEND) as (data_from, data_to):
        data_to.meshes = ['BloodCrystal']
    return data_to.meshes[0]


# ---------------------------------------------------------------- materials (preview only; Godot has its own)
def material(name, colour, metallic, rough, emit=None, strength=0.0, transmission=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*colour, 1)
    b.inputs['Metallic'].default_value = metallic
    b.inputs['Roughness'].default_value = rough
    if emit:
        b.inputs['Emission Color'].default_value = (*emit, 1)
        b.inputs['Emission Strength'].default_value = strength
    if transmission:
        b.inputs['Transmission Weight'].default_value = transmission
    return m


MATS = {}


def assign(obj, mid):
    obj.data.materials.clear()
    obj.data.materials.append(MATS[mid])
    obj['mat'] = mid


# ---------------------------------------------------------------- frame pieces
def mesh_obj(name, verts, faces, mid, smooth=False):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces)
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    me.update()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons: p.use_smooth = smooth
    assign(ob, mid)
    return ob


def collar():
    """ONE rock collar, normalised: radius 1 at its foot (z 0), height 1, a slight recess on top where the crystal
    grows out. Irregular (seeded jitter) so it reads as hewn basalt. Godot scales it per socket (x/z = radius,
    y = from the lowest rock under it to just above the highest, so it never floats)."""
    import random
    rnd = random.Random(7)
    n = COLLAR_SIDES
    jit = [1.0 + rnd.uniform(-0.14, 0.14) for _ in range(n)]
    ztj = [rnd.uniform(-0.07, 0.07) for _ in range(n)]
    rings = [(0.0, 1.0, 0.0), (0.55, 0.93, 0.5), (1.0, 0.74, 1.0), (0.93, 0.50, 0.6)]  # (z, radius, top jitter)
    verts, faces = [], []
    for z, r, tj in rings:
        for k in range(n):
            a = 2 * math.pi * k / n
            verts.append((r * jit[k] * math.cos(a), r * jit[k] * math.sin(a), z + ztj[k] * tj))
    for ri in range(len(rings) - 1):
        for k in range(n):
            j = (k + 1) % n
            faces.append((ri * n + k, ri * n + j, (ri + 1) * n + j, (ri + 1) * n + k))
    centre = len(verts); verts.append((0, 0, 0.86))
    last = (len(rings) - 1) * n
    for k in range(n):
        faces.append((last + k, last + (k + 1) % n, centre))
    faces.append(tuple(range(n))[::-1])
    mesh_obj('Collar', verts, faces, STONE)
    # The ember seam: a thin glowing ring where the crystal leaves the rock, just inside the recess.
    ev, ef = [], []
    for k in range(n):
        a = 2 * math.pi * k / n
        for r in (0.36, 0.52):
            ev.append((r * jit[k] * math.cos(a), r * jit[k] * math.sin(a), 0.90 + ztj[k] * 0.6))
    for k in range(n):
        j = (k + 1) % n
        ef.append((2 * k, 2 * j, 2 * j + 1, 2 * k + 1))
    mesh_obj('Ember', ev, ef, GEM)


def build():
    crystal_mesh = load_crystal()
    MATS[STONE] = material('Basalt', (0.16, 0.15, 0.15), 0.0, 0.9)
    MATS[GEM] = material('Ember', (0.6, 0.02, 0.03), 0.0, 0.15, (1.0, 0.12, 0.04), 4.0)
    MATS[CRYSTAL] = material('Blood', (0.5, 0.01, 0.02), 0.0, 0.12, (0.9, 0.02, 0.03), 0.8)
    collar()
    ob = bpy.data.objects.new('Crystal', crystal_mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (0, 0, 0.8)
    ob.scale = (0.7, 0.7, 1.0)
    ob['mat'] = CRYSTAL
    ob.data.materials.clear(); ob.data.materials.append(MATS[CRYSTAL])


def export_bin():
    """LCR1: mesh count, then per mesh: material id, vertex count, index count, verts (pos3 normal3), indices;
    then socket count and per socket a 3x4 transform (basis columns x,y,z then origin) + scale. All Godot axes.
    Frame pieces are merged by material; crystals are exported ONCE (one mesh, flat normals) - the sockets place it."""
    deps = bpy.context.evaluated_depsgraph_get()
    g = lambda v: (v.x, v.z, -v.y)
    groups = {METAL: ([], []), GEM: ([], [])}
    crystal = ([], [])
    done_crystal = False
    for o in bpy.context.scene.objects:
        if o.type != 'MESH':
            continue
        mid = int(o.get('mat', METAL))
        if mid == CRYSTAL:
            if done_crystal:
                continue
            done_crystal = True
            target, mw, flat = crystal, Matrix.Identity(4), True
        else:
            target, mw, flat = groups[mid], o.matrix_world, mid == GEM
        ev = o.evaluated_get(deps); me = ev.to_mesh(); me.calc_loop_triangles()
        nm = mw.to_3x3().inverted().transposed()
        verts, idx = target
        for tri in me.loop_triangles:
            fn = (nm @ tri.normal).normalized()
            for li in reversed(tri.loops):   # Godot faces are clockwise seen from the front
                loop = me.loops[li]
                p = mw @ me.vertices[loop.vertex_index].co
                n = fn if (flat or not tri.use_smooth) else (nm @ loop.normal).normalized()
                idx.append(len(verts)); verts.append((*g(p), *g(n)))
        ev.to_mesh_clear()
    meshes = [(METAL, groups[METAL]), (GEM, groups[GEM]), (CRYSTAL, crystal)]
    socks = sorted([o for o in bpy.context.scene.objects if o.name.startswith('Socket')], key=lambda o: o.name)
    path = os.path.join(BIN_DIR, 'life_crown.bin')
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sI', b'LCR1', len(meshes)))
        for mid, (verts, idx) in meshes:
            f.write(struct.pack('<III', mid, len(verts), len(idx)))
            for v in verts: f.write(struct.pack('<6f', *v))
            f.write(struct.pack('<%dI' % len(idx), *idx))
        f.write(struct.pack('<I', len(socks)))
        for e in socks:
            m = e.matrix_world.normalized()
            cols = [g(m.col[0].xyz), g(m.col[2].xyz), tuple(-c for c in g(m.col[1].xyz))]
            f.write(struct.pack('<13f', *cols[0], *cols[1], *cols[2], *g(m.translation), float(e['scale'])))
    print('[LifeCrown] wrote %s: metal %d tris, gem %d, crystal %d, %d sockets' % (
        path, len(groups[METAL][1]) // 3, len(groups[GEM][1]) // 3, len(crystal[1]) // 3, len(socks)))


def preview():
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'; scn.cycles.samples = 64; scn.cycles.device = 'CPU'
    scn.render.resolution_x = 900; scn.render.resolution_y = 800
    scn.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new('w'); scn.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = BG
    # Lights for REFLECTIONS: big soft cards above and to the sides, outside the frame.
    for name, loc, size, power in [('Top', (0, -2.0, 3.5), 4, 900), ('Left', (-4, -2.5, 0.5), 2, 350),
                                   ('Right', (4, -2.5, 0.8), 2, 300)]:
        ld = bpy.data.lights.new(name, 'AREA'); ld.size = size; ld.energy = power
        lo = bpy.data.objects.new(name, ld); scn.collection.objects.link(lo); lo.location = loc
        lo.rotation_euler = (Vector((0, 0, -0.1)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); scn.collection.objects.link(cam)
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 3.4
    cam.location = (0, -6, 2.4); cam.rotation_euler = (math.radians(68), 0, 0)
    scn.camera = cam
    scn.render.filepath = os.path.join(OUT_DIR, 'preview.png')
    bpy.ops.render.render(write_still=True)


build()
export_bin()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, 'life_crown.blend'))
if '--no-preview' not in argv:
    preview()
