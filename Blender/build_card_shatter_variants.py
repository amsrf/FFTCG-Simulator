import bpy
import math
import random
from mathutils import Vector

# -----------------------------------------------------------------------------
# Ten fractured-card variants.
#
# Blender side is X/Y with the card face on +Z. The glTF exporter's Y-up
# conversion turns that into Godot's X/Z card face with normal +Y, matching
# card.tres. Each piece is a separate object whose origin is its own centroid,
# so the runtime shatter can spin each piece around itself.
# -----------------------------------------------------------------------------

WIDTH = 0.429
HEIGHT = 0.6
THICK = 0.006
RADIUS = 0.03
SEGMENTS = 8
PIECES = 10
VARIANTS = 10
SEED_BASE = 20261027
OUT_DIR = "C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/Blender"
OUT_BLEND = OUT_DIR + "/card_shatter_variants.blend"


def clean_poly(poly, eps=1e-7):
    out = []
    for p in poly:
        if not out or (p - out[-1]).length > eps:
            out.append(p)
    if len(out) > 1 and (out[0] - out[-1]).length <= eps:
        out.pop()
    return out


def signed_area(poly):
    a = 0.0
    for i in range(len(poly)):
        p = poly[i]
        q = poly[(i + 1) % len(poly)]
        a += p.x * q.y - q.x * p.y
    return a * 0.5


def rounded_rect():
    hw, hh = WIDTH * 0.5, HEIGHT * 0.5
    r = min(RADIUS, hw, hh)
    pts = []
    corners = [
        (hw - r, -hh + r, -math.pi * 0.5, 0.0),
        (hw - r, hh - r, 0.0, math.pi * 0.5),
        (-hw + r, hh - r, math.pi * 0.5, math.pi),
        (-hw + r, -hh + r, math.pi, math.pi * 1.5),
    ]
    for cx, cy, a0, a1 in corners:
        for i in range(SEGMENTS + 1):
            a = a0 + (a1 - a0) * i / SEGMENTS
            pts.append(Vector((cx + math.cos(a) * r, cy + math.sin(a) * r)))
    out = clean_poly(pts)
    if signed_area(out) < 0:
        out.reverse()
    return out


def clip_halfplane(poly, normal, offset):
    """Keep points with dot(normal, p) <= offset."""
    out = []
    n = len(poly)
    if n == 0:
        return out
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        da = normal.dot(a) - offset
        db = normal.dot(b) - offset
        if da <= 1e-9:
            out.append(a)
        if (da < -1e-9 and db > 1e-9) or (da > 1e-9 and db < -1e-9):
            t = da / (da - db)
            out.append(a.lerp(b, t))
    return clean_poly(out)


def polygon_centroid(poly):
    """Area centroid, not the average of the vertices.

    The average of a Voronoi cell's vertices can sit well away from the middle
    of an irregular cell, which makes the piece look like it is swinging around
    a corner instead of rotating around itself.
    """
    area = 0.0
    cx = 0.0
    cy = 0.0
    for i in range(len(poly)):
        p = poly[i]
        q = poly[(i + 1) % len(poly)]
        cross = p.x * q.y - q.x * p.y
        area += cross
        cx += (p.x + q.x) * cross
        cy += (p.y + q.y) * cross
    area *= 0.5
    if abs(area) < 1e-12:
        return Vector((sum(p.x for p in poly) / len(poly),
                       sum(p.y for p in poly) / len(poly)))
    return Vector((cx / (6.0 * area), cy / (6.0 * area)))


def seeds(rng):
    xs = [-0.16, -0.08, 0.0, 0.08, 0.16]
    ys = [-0.14, 0.14]
    pts = []
    for y in ys:
        for x in xs:
            pts.append(Vector((x + rng.uniform(-0.012, 0.012),
                               y + rng.uniform(-0.05, 0.05))))
    return pts


def voronoi_cells(outline, points):
    cells = []
    for i, s in enumerate(points):
        poly = list(outline)
        for j, q in enumerate(points):
            if i == j:
                continue
            n = q - s
            if n.length < 1e-9:
                continue
            mid = (s + q) * 0.5
            poly = clip_halfplane(poly, n, n.dot(mid))
            if len(poly) < 3:
                break
        cells.append(poly)
    return cells


def make_materials():
    card = bpy.data.materials.new("CardArt")
    card.use_nodes = True
    bsdf = card.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.45

    glass = bpy.data.materials.new("CardShardGlass")
    glass.use_nodes = True
    gb = glass.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (0.36, 0.78, 0.92, 1.0)
    gb.inputs["Metallic"].default_value = 0.0
    gb.inputs["Roughness"].default_value = 0.05
    # Blender material is only a placeholder; the runtime owns the glass look.
    return card, glass


def build_piece(name, poly, cx, cy, card_mat, glass_mat, collection):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    half_t = THICK * 0.5
    verts = []
    for p in poly:
        verts.append((p.x - cx, p.y - cy, +half_t))
    for p in poly:
        verts.append((p.x - cx, p.y - cy, -half_t))

    n = len(poly)
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    mesh.materials.append(card_mat)
    mesh.materials.append(glass_mat)

    uv = mesh.uv_layers.new(name="UVMap")
    for poly_index, face in enumerate(mesh.polygons):
        face.material_index = 0 if poly_index == 0 else 1
        for loop_index in range(face.loop_start, face.loop_start + face.loop_total):
            vi = mesh.loops[loop_index].vertex_index % n
            p = poly[vi]
            u = (p.x + WIDTH * 0.5) / WIDTH
            v_godot = (p.y + HEIGHT * 0.5) / HEIGHT
            # The exporter preserves this V in the GLB, so store Godot-space V.
            uv.data[loop_index].uv = (u, v_godot)

    obj = bpy.data.objects.new(name, mesh)
    obj.location = (cx, cy, 0.0)
    collection.objects.link(obj)
    return obj


def clear_objects():
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def export_variant(objects, path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    kwargs = dict(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError as exc:
        print("[card_shatter] full kwargs rejected: %s" % exc)
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB',
                                  use_selection=True, export_texcoords=True)


def make_variant(variant_index):
    seed = SEED_BASE + (variant_index - 1) * 7919
    outline = rounded_rect()
    for attempt in range(12):
        rng = random.Random(seed + attempt)
        cells = voronoi_cells(outline, seeds(rng))
        if len(cells) == PIECES and all(len(c) >= 3 for c in cells):
            return seed + attempt, cells
    raise RuntimeError("variant %d could not produce %d non-empty cells" %
                       (variant_index, PIECES))


clear_objects()
card_mat, glass_mat = make_materials()
all_objects = []
summary = []

for v in range(1, VARIANTS + 1):
    seed, cells = make_variant(v)
    coll = bpy.data.collections.new("Variant_%02d" % v)
    bpy.context.scene.collection.children.link(coll)
    objects = []
    for i, cell in enumerate(cells):
        centroid = polygon_centroid(cell)
        objects.append(build_piece("V%02d_CardPiece_%02d" % (v, i + 1),
                                   cell, centroid.x, centroid.y,
                                   card_mat, glass_mat, coll))
    all_objects.extend(objects)
    summary.append((v, seed, objects))

# Export before hiding the collections, so selection is straightforward.
for v, seed, objects in summary:
    path = "%s/card_shatter_%02d.glb" % (OUT_DIR, v)
    export_variant(objects, path)
    print("[card_shatter] variant=%02d seed=%d pieces=%d glb=%s" %
          (v, seed, len(objects), path))

# Keep one inspectable .blend. Variant 1 is visible; the rest are hidden but
# still present as collections the user can toggle in the Outliner.
for v, _seed, _objects in summary:
    coll = bpy.data.collections.get("Variant_%02d" % v)
    if coll is not None and v != 1:
        coll.hide_viewport = True
        coll.hide_render = True

bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("[card_shatter] variants=%d" % VARIANTS)
print("[card_shatter] blend=%s" % OUT_BLEND)
