"""Build the gem button (capsule bezel with a set stone) and export it for Godot.

Run:
  "/c/Program Files/Blender Foundation/Blender 4.4/blender.exe" --background --python Blender/build_gem_button.py

Outputs, all into Blender/:
  gem_button.blend              the editable source
  gem_button.glb                what Godot imports
  gem_button_front.png          near-front view: proportions
  gem_button_three_quarter.png  3/4 view: the dome and the material

Everything is PARAMETRIC: the numbers below are the whole design, so tuning is one edit and one
re-run.

Design notes, each one paid for:
  * The frame is a BEZEL — a pocket is cut in it and the stone is SET in the pocket, its dome
    rising to just below the rim. A plate with the stone sunk into it hides the stone completely,
    because metal shows the environment and a solid top face reflects as one continuous surface.
  * The outline is a STADIUM (a true pill). EVERY ring is an offset stadium — stadium(hw+d, hh+d)
    is the exact outward offset of stadium(hw, hh) — so rings correspond point-for-point and the
    swept wall cannot fold. An earlier version pushed each point along its own RADIUS instead,
    which is not the normal on the straights: it skewed the band and threw spikes at the ends.
  * The rim is one continuous quarter-round from the pocket's top edge outward and down; that
    curved band is the geometry that draws the bright top highlight and the dark lower band.
  * A metal surface shows the ENVIRONMENT, so the lighting is built for reflections, not for
    illumination: one large bright emissive card BEHIND and ABOVE (a top face's reflection points
    up and away from the camera, so a light placed in front is invisible to it and the face
    mirrors black), one weak front fill, and a near-black world everywhere else. That contrast is
    the chrome banding.

Built Z-up; the glTF exporter's +Y-up conversion points the face +Y in Godot, as the button expects.
"""

import bpy
import bmesh
import math
import os

# ---------------------------------------------------------------------------------------------
# Parameters, in Blender units. The Godot preview scales by 0.1971 onto the 0.685 m footprint the
# existing button uses, so KEEP THE WIDTH NEAR 3.5.
# ---------------------------------------------------------------------------------------------
WIDTH = 3.5            # capsule width (the reference is ~3.5:1)
HEIGHT = 1.0           # capsule height — for a stadium this is also the end-cap diameter
# THIN, because thickness is what the player actually sees as "the lateral wall". At 0.34 the plate
# was a third as tall as its face, and from the match camera (11 degrees off vertical) that wall
# projected as a visible dark band along the bottom edge of the button. 0.20 halves what shows.
# BEVEL must stay below THICK/2 or the round-over pokes through the underside, and POCKET_DEPTH
# below THICK/2 leaves the web under the stone: floor at 0.10 - 0.12 = -0.02, underside at -0.10.
THICK = 0.20           # plate thickness
BEVEL = 0.075          # rim round-over radius; the pocket's top edge is where it starts
POCKET_DEPTH = 0.12    # how deep the stone sits below the rim
STONE_GAP = 0.012      # clearance between the stone and the pocket wall
DOME_CLEARANCE = 0.02  # how far the dome's apex stays below the rim's top
OUTLINE_SEGMENTS = 96  # samples around the whole outline, shared by every ring
ARC_SEGMENTS = 6       # segments across the rim round-over
DOME_RINGS = 8         # rings from the stone's base to its apex
STONE_EMISSION = 0.35  # Blender-only: the real glow is shaders/gem_button.gdshader in Godot

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
GLB_PATH = os.path.join(OUT_DIR, "gem_button.glb")
BLEND_PATH = os.path.join(OUT_DIR, "gem_button.blend")


# ---------------------------------------------------------------------------------------------
# Outline: a stadium sampled by normalised perimeter parameter t in [0, 1).
# ---------------------------------------------------------------------------------------------
def stadium(half_w, half_h):
    """Returns t -> (x, y) for a stadium (pill) of the given half-extents.

    Insetting and offsetting a stadium both yield a stadium, which is why every ring here can be
    built by simply passing different half-extents — exact, and free of the folding that a
    per-point radial offset produces on the straight sections.
    """
    r = half_h
    straight = max(half_w - r, 0.0)
    s = 0.5 * straight / (straight + math.pi * r * 0.5) if (straight + r) > 0.0 else 0.0

    def point(t):
        t = t % 1.0
        if t < s:                                    # top straight, left -> right
            u = t / s if s > 0.0 else 0.0
            return (-straight + 2.0 * straight * u, r)
        if t < 0.5:                                  # right cap, 90 -> -90 degrees
            u = (t - s) / (0.5 - s) if (0.5 - s) > 0.0 else 0.0
            a = math.pi * 0.5 - math.pi * u
            return (straight + r * math.cos(a), r * math.sin(a))
        if t < 0.5 + s:                              # bottom straight, right -> left
            u = (t - 0.5) / s if s > 0.0 else 0.0
            return (straight - 2.0 * straight * u, -r)
        u = (t - 0.5 - s) / (0.5 - s) if (0.5 - s) > 0.0 else 0.0   # left cap
        a = -math.pi * 0.5 - math.pi * u
        return (-straight + r * math.cos(a), r * math.sin(a))

    return point


def ring(half_w, half_h, z, shrink=1.0):
    """One ring of OUTLINE_SEGMENTS points on the stadium (half_w, half_h) at height z.
    `shrink` scales the plan toward the centre — used for the dome, where it is a uniform scale
    of an already-correct stadium, so the shape stays a stadium all the way up."""
    shape = stadium(half_w * shrink, half_h * shrink)
    return [(*shape(i / OUTLINE_SEGMENTS), z) for i in range(OUTLINE_SEGMENTS)]


def build(name, rings):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    layers = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(layers[0])
    for a, b in zip(layers, layers[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(tuple(reversed(layers[0])))   # cap the first ring
    bm.faces.new(tuple(layers[-1]))            # cap the last
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.validate()
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for poly in me.polygons:
        poly.use_smooth = True
    return ob


def planar_uvs(ob, size_w, size_h):
    """Front projection: u across the face, v running BOTTOM -> TOP. That is exactly what
    shaders/gem_button.gdshader reads for its vertical gradient, so it must not be left to an
    automatic unwrap (a cylinder's UVs wrap around the barrel and the gradient runs sideways)."""
    me = ob.data
    layer = me.uv_layers.new(name="UVMap")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        layer.data[loop.index].uv = ((co.x / size_w) + 0.5, (co.y / size_h) + 0.5)


# ---------------------------------------------------------------------------------------------
# Scene reset + geometry
# ---------------------------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'

# ELONGATED AND SHORTER: 4.60 wide (was 4.20, and 3.50 two steps back) by 0.88 tall (was 1.00), so the
# pill reads longer and the label gets more air. The CAPSULE is what grows — END_BAND stays put — so
# the gem comes out longer with it (1.369 -> 1.527 m) while the metal band at each end holds at 0.133 m.
#
# WIDTH and HEIGHT are re-bound HERE rather than edited at the top of the file because planar_uvs() is
# called further down and normalises u by WIDTH: the shaders measure their horizontal falloff from
# UV.x, so a stale WIDTH would rescale that distance along with the geometry. At scale 0.392 the
# button becomes 1.803 x 0.345 m.
WIDTH = 4.6
HEIGHT = 0.88
hw, hh = WIDTH * 0.5, HEIGHT * 0.5
top_z = THICK * 0.5
bot_z = -THICK * 0.5
floor_z = top_z - POCKET_DEPTH
# The pocket is inset FURTHER along X than along Z, so the metal reads as a WIDER band at the ends of
# the capsule than along its top and bottom edges: 0.34 * 0.392 = 0.133 m at each end, against 0.081 m
# two steps back. How long the GEM is follows from this and from the capsule's width.
# The height inset is not set here; the rim block below takes it from RIM_RISE, which is what fixes the
# stone's z extent — and therefore the shader's `face_span`.
END_BAND = 0.34
in_hw, in_hh = hw - END_BAND, hh - BEVEL       # the pocket's half-extents

# --- the frame: a bezel with a pocket ----------------------------------------------------------
# Walked as one closed surface: pocket floor -> pocket wall -> rim round-over -> outer wall ->
# bottom. The first ring is capped (the pocket floor) and the last is capped (the bottom).
# THE RIM IS ONE CONTINUOUS CONVEX CURVE — a half-ellipse running from the pocket's top edge, out past
# the widest point, and back in to the underside. It used to be three pieces: a flat top band, a
# quarter-round, and a VERTICAL OUTER WALL. Those meet at hard edges, and a vertical wall seen from a
# camera near the vertical reads as a near-black outline that follows the capsule — so the frame
# looked like several separate PLANES with a dark ring around the outside, instead of the single
# smooth ring the reference shows. With the arc the surface turns smoothly from facing up, through
# facing outward, to facing down: one face, whose only shading comes from the lighting.
# END_BAND is the horizontal radius (how wide the metal reads) and RIM_RISE the vertical one.
RIM_RISE = THICK * 0.5           # the plate's half-thickness
RIM_SEGMENTS = 14                # enough segments that the shading across the curve is smooth
in_hh = hh - RIM_RISE            # NOTE: this widens the height inset from BEVEL, which changes the
                                 # stone's z extent — and therefore the shader's `face_span`, which
                                 # tests/button_probe.tscn asserts against this mesh.

frame_rings = [
    ring(in_hw, in_hh, floor_z),
    ring(in_hw, in_hh, top_z),                 # up the pocket wall to the rim's top edge
]
for i in range(1, RIM_SEGMENTS + 1):
    a = math.pi * i / RIM_SEGMENTS             # 0..180 degrees: crest -> outermost -> underside
    frame_rings.append(ring(in_hw + END_BAND * math.sin(a), in_hh + RIM_RISE * math.sin(a),
                            top_z - RIM_RISE * (1.0 - math.cos(a))))
frame = build("Frame", frame_rings)

# --- the stone: a dome set in the pocket -------------------------------------------------------
shw, shh = in_hw - STONE_GAP, in_hh - STONE_GAP
base_z = floor_z
rise = POCKET_DEPTH - DOME_CLEARANCE
apex_z = base_z + rise
stone_rings = []
for i in range(DOME_RINGS):
    t = (math.pi * 0.5) * i / DOME_RINGS
    stone_rings.append(ring(shw, shh, base_z + rise * math.sin(t), shrink=math.cos(t)))

me = bpy.data.meshes.new("Stone")
bm = bmesh.new()
layers = [[bm.verts.new(p) for p in r] for r in stone_rings]
n = len(layers[0])
for a, b in zip(layers, layers[1:]):
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
apex = bm.verts.new((0.0, 0.0, apex_z))        # a real apex vertex, fanned to the last ring
for i in range(n):
    j = (i + 1) % n
    bm.faces.new((layers[-1][i], layers[-1][j], apex))
bm.faces.new(tuple(reversed(layers[0])))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.normal_update()
bm.to_mesh(me)
bm.free()
me.validate()
me.update()
stone = bpy.data.objects.new("Stone", me)
bpy.context.collection.objects.link(stone)
for poly in me.polygons:
    poly.use_smooth = True

planar_uvs(frame, WIDTH, HEIGHT)
planar_uvs(stone, WIDTH, HEIGHT)

# ---------------------------------------------------------------------------------------------
# Materials. Metallic/Roughness ONLY: glTF cannot carry Blender's Specular, Coat or Sheen — they
# are dropped silently on export, which is very likely why the old asset never matched the
# viewport. glTF's default metallicFactor is 1.0, so the exporter omits it when it IS 1.0.
# ---------------------------------------------------------------------------------------------
def principled(name, base, metallic, roughness, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None and emission_strength > 0.0:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emission, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


frame.data.materials.append(principled("MetalFrame", (0.78, 0.80, 0.84), 1.0, 0.12))
stone.data.materials.append(principled("Stone", (0.02, 0.26, 0.28), 0.0, 0.15,
                                      emission=(0.10, 0.62, 0.58), emission_strength=STONE_EMISSION))

# ---------------------------------------------------------------------------------------------
# Studio, built for reflections rather than illumination.
# ---------------------------------------------------------------------------------------------
world = bpy.data.worlds.new("Studio")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
if bg is not None:
    # A DIM BLUE-GREY, not black. This is the lower hemisphere every down-facing surface mirrors,
    # and at near-black the whole lower half of the bezel rendered as a void — the metal read as
    # black plastic wearing a chrome outline. Chrome needs a GRADIENT to reflect, not darkness:
    # bright cards above for the highlight, this for the body. Same reasoning as the studio sky in
    # game.tscn, which pairs a bright top with a near-black ground; the difference here is that a
    # render has no floor for the light to bounce off, so the "ground" has to be lifted.
    bg.inputs[0].default_value = (0.070, 0.076, 0.090, 1.0)
    bg.inputs[1].default_value = 1.0

def add_card(name, energy, size, location, look_at_origin=True):
    """A large emissive plane. It exists to appear IN the metal: an emissive card is what a
    polished surface actually mirrors, and a light's energy/size ratio is what makes that
    reflection bright."""
    mesh = bpy.data.meshes.new(name)
    verts = [(-size, -size, 0.0), (size, -size, 0.0), (size, size, 0.0), (-size, size, 0.0)]
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    mesh.update()
    mat = bpy.data.materials.new(name + "Mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs[0].default_value = (1.0, 0.99, 0.97, 1.0)
    emit.inputs[1].default_value = energy
    nt.links.new(emit.outputs[0], out.inputs[0])
    mesh.materials.append(mat)
    ob = bpy.data.objects.new(name, mesh)
    ob.location = location
    bpy.context.collection.objects.link(ob)
    if look_at_origin:
        # Face the origin by hand: simpler and more predictable than a constraint per card.
        d = math.sqrt(location[0] ** 2 + location[1] ** 2 + location[2] ** 2)
        ob.rotation_euler = (math.acos(-location[2] / d) if d > 0 else 0.0, 0.0,
                             math.atan2(-location[0], location[1]))
    return ob

# BEHIND and ABOVE: a top face's reflection points up and away from the camera, so this is the
# card the chrome actually mirrors — the bright band along the top edge. Both cards are placed
# OUTSIDE the camera's frustum (at 3-5 units up/side they subtend more than the 16 x 9 degree
# half-fov), so the metal reflects them while the camera never sees them.
add_card("SoftboxBack", 9.0, 2.6, (0.0, 3.0, 5.0))
# No card in FRONT of the subject: an earlier version put a 10x10 emissive plane at y = -4.5, which
# sat between the camera and the button — the render was a photograph of the light card. Whatever
# the lower hemisphere needs must come from the world or from an off-axis card like this one, which
# also gives the metal an asymmetric reflection, as real chrome has.
add_card("SoftboxSide", 2.5, 1.6, (-4.0, 0.8, 2.6))

# ---------------------------------------------------------------------------------------------
# Camera. The distance is DERIVED from the button's width (a hand-picked one framed a slice of one
# edge the first time round). Two views: near-front for proportions, 3/4 for the dome and material.
# ---------------------------------------------------------------------------------------------
SENSOR = 36.0   # Blender's default sensor width, mm
FOCAL = 62.0    # mm
VIEWS = [("front", 8.0), ("three_quarter", 32.0)]

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = FOCAL
cam = bpy.data.objects.new("Camera", cam_data)
_half_fov = math.atan(SENSOR * 0.5 / FOCAL)
_distance = (WIDTH * 1.25 * 0.5) / math.tan(_half_fov)
print("[build_gem_button] camera %.2f units back for a %.2f-wide button" % (_distance, WIDTH))
bpy.context.collection.objects.link(cam)
target = bpy.data.objects.new("Target", None)
bpy.context.collection.objects.link(target)
con = cam.constraints.new(type='TRACK_TO')
con.target = target
con.track_axis = 'TRACK_NEGATIVE_Z'
con.up_axis = 'UP_Y'
scene.camera = cam

# ---------------------------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------------------------
# ONLY the button. The studio cards, lights and camera live in this same scene because they are what
# renders the previews — but an earlier version exported with use_selection=False and shipped all of
# them: the glb contained two 5.2-unit emissive planes, which the game would have drawn floating
# across the board, and which made the button measure 2.04 m across instead of 0.39. Selecting the
# two meshes explicitly is what keeps the asset to the asset.
BUTTON_OBJECTS = ("Frame", "Stone")

def export_glb(path):
    """The exporter's kwargs have moved between versions; try the full set and fall back to the
    minimal one rather than failing the build over an argument name."""
    for ob in bpy.context.scene.objects:
        ob.select_set(ob.name in BUTTON_OBJECTS)
    frame.select_set(True)
    bpy.context.view_layer.objects.active = frame
    full = dict(filepath=path, export_format='GLB', export_apply=True, export_normals=True,
                export_texcoords=True, export_yup=True, export_materials='EXPORT',
                use_selection=True)
    try:
        bpy.ops.export_scene.gltf(**full)
        return "full kwargs"
    except TypeError as exc:
        print("[build_gem_button] full export kwargs rejected (%s); retrying minimal" % exc)
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=True,
                                  use_selection=True)
        return "minimal kwargs"


print("[build_gem_button] exporting %s (%s)" % (GLB_PATH, export_glb(GLB_PATH)))
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

# ---------------------------------------------------------------------------------------------
# Render both views
# ---------------------------------------------------------------------------------------------
scene.render.engine = 'CYCLES'
scene.cycles.samples = 96
scene.cycles.use_denoising = False
scene.render.resolution_x = 760
scene.render.resolution_y = 420

for label, pitch_deg in VIEWS:
    p = math.radians(pitch_deg)
    cam.location = (0.0, -_distance * math.cos(p), _distance * math.sin(p))
    scene.render.filepath = os.path.join(OUT_DIR, "gem_button_%s.png" % label)
    bpy.ops.render.render(write_still=True)
    print("[build_gem_button] rendered %s view (pitch %.0f deg)" % (label, pitch_deg))

print("[build_gem_button] frame %d verts | stone %d verts" % (len(frame.data.vertices), len(stone.data.vertices)))
print("[build_gem_button] pocket floor z=%.3f | stone apex z=%.3f | rim top z=%.3f | dome rise %.3f"
      % (floor_z, apex_z, top_z, rise))
print("[build_gem_button] done")
