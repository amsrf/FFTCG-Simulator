import bpy
import bmesh
import math
import random
from mathutils import Vector

# -----------------------------------------------------------------------------
# Card fracture asset.
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
OUT_BLEND = "C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/Blender/card_shatter.blend"
OUT_GLB = "C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-On-Godot/Blender/card_shatter.glb"
SEED = 20261027

rng = random.Random(SEED)


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
    # Bottom-right, top-right, top-left, bottom-left: CCW.
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


def seeds():
    xs = [-0.16, -0.08, 0.0, 0.08, 0.16]
    ys = [-0.14, 0.14]
    pts = []
    for y in ys:
        for x in xs:
            pts.append(Vector((x + rng.uniform(-0.012, 0.012),
                               y + rng.uniform(-0.05, 0.05))))
    assert len(pts) == PIECES
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


def make_material():
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
    # Keep the Blender material opaque; the runtime glass shader owns transparency.
    return card, glass


def build_piece(name, poly, cx, cy, card_mat, glass_mat):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    half_t = THICK * 0.5
    verts = []
    for p in poly:
        verts.append((p.x - cx, p.y - cy, +half_t))
    for p in poly:
        verts.append((p.x - cx, p.y - cy, -half_t))

    n = len(poly)
    faces = []
    # Front (+Z), back (-Z), then the cut side walls.
    faces.append(tuple(range(n)))
    faces.append(tuple(range(2 * n - 1, n - 1, -1)))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))

    mesh.from_pydata(verts, [], faces)
    mesh.update()

    mesh.materials.append(card_mat)
    mesh.materials.append(glass_mat)

    # UVs: front and back use absolute card coordinates. glTF flips Blender V;
    # this V makes Godot receive the same mapping as card.tres.
    uv = mesh.uv_layers.new(name="UVMap")
    for poly_index, face in enumerate(mesh.polygons):
        face.material_index = 0 if poly_index == 0 else 1
        for loop_index in range(face.loop_start, face.loop_start + face.loop_total):
            vi = mesh.loops[loop_index].vertex_index % n
            p = poly[vi]
            u = (p.x + WIDTH * 0.5) / WIDTH
            v_godot = (p.y + HEIGHT * 0.5) / HEIGHT  # Blender Y is -Godot Z.
            # The exporter preserves this V in the GLB (verified from the exported
            # TEXCOORD_0 data), so store the Godot-space V directly.
            uv.data[loop_index].uv = (u, v_godot)

    obj = bpy.data.objects.new(name, mesh)
    obj.location = (cx, cy, 0.0)
    bpy.context.collection.objects.link(obj)
    return obj


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def export():
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
    kwargs = dict(
        filepath=OUT_GLB,
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
        bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB',
                                  use_selection=True, export_texcoords=True)


clear_scene()
outline = rounded_rect()
points = seeds()
cells = voronoi_cells(outline, points)
if len(cells) != PIECES or any(len(c) < 3 for c in cells):
    raise RuntimeError("fracture did not produce %d non-empty cells: %s" %
                       (PIECES, [len(c) for c in cells]))

card_mat, glass_mat = make_material()
objects = []
for i, cell in enumerate(cells):
    cx = sum(p.x for p in cell) / len(cell)
    cy = sum(p.y for p in cell) / len(cell)
    objects.append(build_piece("CardPiece_%02d" % (i + 1), cell, cx, cy,
                               card_mat, glass_mat))

bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
export()

print("[card_shatter] pieces=%d" % len(objects))
print("[card_shatter] blend=%s" % OUT_BLEND)
print("[card_shatter] glb=%s" % OUT_GLB)
for obj in objects:
    print("[card_shatter] %s origin=(%.4f, %.4f) verts=%d mats=%d" % (
        obj.name, obj.location.x, obj.location.y,
        len(obj.data.vertices), len(obj.data.materials)))
