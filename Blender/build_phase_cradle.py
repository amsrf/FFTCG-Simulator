"""The phase crystal's cradle: a low stone lip round a rectangular slot the size of the triangular prism's top face,
over a dark recess in the wood, so the lying phase crystal (scripts/ui/phase_prism.gd) sits IN the board instead of on
it. Same stone as the button stations (build_button_housing.py), read off those objects so they cannot drift; it sits
just above the local Cancel/Pass station.

Godot <-> Blender: Godot (x, y, z) = Blender (x, z, -y). Fixed for both seats (the exporter's fixed_prefixes): the
crystal is always on the LOCAL player's right. For seat two the exporter swaps its stone to that seat's housing stone.
Its centre, depth and the crystal's shape are READ from scripts/ui/phase_prism.gd: change them there and re-run this.

Input: board_pit_stations/board_pit_stations.blend (not modified).
Output: board_phase_cradle/board_phase_cradle.blend (the export source read by export_board_to_godot.py) and its
seat-one environment render board_environment.png.

    blender --background --python /abs/path/Blender/build_phase_cradle.py
"""
import bpy, bmesh, os, re, math
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_phase_cradle'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_pit_stations', 'board_pit_stations.blend'))
scene = bpy.context.scene

# THE OPENING IS THE PRISM'S TOP FACE. The phase prism is a TRIANGULAR crystal lying with one face up, flush with
# the lip (scripts/ui/phase_prism.gd), so the slot is a plain rectangle: that face plus CLEARANCE all round. Its size,
# lip height and centre are READ FROM phase_prism.gd, so the two cannot drift. While it turns, its other edges pass
# under the lip's solid stone, which hides them.
ROOT = os.path.dirname(HERE)
GD = open(os.path.join(ROOT, 'scripts', 'ui', 'phase_prism.gd')).read()


def gd_const(name):
	m = re.search(r'^const %s\s*:?=\s*([-0-9.]+)' % name, GD, re.M)
	if m is None:
		raise RuntimeError('phase_prism.gd: const %s not found' % name)
	return float(m.group(1))


FACE, LENGTH, TOP = gd_const('FACE_WIDTH'), gd_const('LENGTH'), gd_const('CRADLE_TOP_Y')
# The top face stands RAISE above the lip; the two sloped faces (60 degrees from horizontal) close in by RAISE / tan 60
# each side on the way down, so the slot is the prism's width AT THE LIP, not its top face's width.
RAISE = gd_const('FACE_ABOVE_LIP')
SLOT = FACE - 2.0 * max(RAISE, 0.0) / math.tan(math.radians(60.0))   # flush or below: the face's own width
_c = re.search(r'^const CENTRE := Vector3\(([-0-9.]+),.*?,\s*([-0-9.]+)\)', GD, re.M)
GX, GZ = float(_c.group(1)), float(_c.group(2))
CENTRE = Vector((GX, -GZ, 0.0))
CLEARANCE = 0.002
LIP = 0.045              # stone round the slot
FLOOR_Z = -0.02          # the recess floor, under the prism's lowest edge (its apex points down)
BOTTOM = -0.12


def rect(half_x, half_y):
	"""Counter-clockwise rectangle in Blender XY around CENTRE, long axis along X."""
	return [Vector((CENTRE.x + x, CENTRE.y + y, 0)) for x, y in
		((-half_x, -half_y), (half_x, -half_y), (half_x, half_y), (-half_x, half_y))]


def prism(name, pts, z0, z1):
	me = bpy.data.meshes.new(name); bm = bmesh.new()
	low = [bm.verts.new((p.x, p.y, z0)) for p in pts]
	high = [bm.verts.new((p.x, p.y, z1)) for p in pts]
	bm.faces.new(list(reversed(low))); bm.faces.new(high)
	n = len(pts)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new([low[i], low[j], high[j], high[i]])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.normal_update(); bm.to_mesh(me); bm.free()
	o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o)
	return o


def apply_boolean(target, cutter, op, open_sheet=False):
	bpy.context.view_layer.objects.active = target
	m = target.modifiers.new('bool', 'BOOLEAN'); m.operation = op; m.solver = 'EXACT'; m.object = cutter
	m.use_hole_tolerant = open_sheet
	bpy.ops.object.modifier_apply(modifier=m.name)


def station_material(object_name):
	o = bpy.data.objects.get(object_name)
	if o is None or not o.material_slots or o.material_slots[0].material is None:
		raise RuntimeError('button station piece %r missing: build it first (build_button_housing.py)' % object_name)
	return o.material_slots[0].material


stone = station_material('player button housing')
dark = bpy.data.materials.get('Well shadow')
inner = rect(LENGTH / 2 + CLEARANCE, SLOT / 2 + CLEARANCE)
outer = rect(LENGTH / 2 + CLEARANCE + LIP, SLOT / 2 + CLEARANCE + LIP)
print('OPENING: %.3f x %.3f at (%.3f, %.3f), lip top %.3f, prism raised %.3f' % (LENGTH + 2 * CLEARANCE,
	SLOT + 2 * CLEARANCE, CENTRE.x, CENTRE.y, TOP, RAISE), flush=True)

lip = prism('Phase cradle lip', outer, BOTTOM, TOP)
hole = prism('cutter', inner, BOTTOM - 0.1, TOP + 0.1)
apply_boolean(lip, hole, 'DIFFERENCE'); bpy.data.objects.remove(hole, do_unlink=True)
b = lip.modifiers.new('Hewn edges', 'BEVEL'); b.width = 0.012; b.segments = 3
lip.modifiers.new('Shading', 'WEIGHTED_NORMAL')
# A boolean leaves an empty first slot (it rendered white): one slot, every face on it.
lip.data.materials.clear(); lip.data.materials.append(stone)
for poly in lip.data.polygons:
	poly.material_index = 0
floor = prism('Phase cradle floor', inner, FLOOR_Z - 0.01, FLOOR_Z)
if dark is not None:
	floor.data.materials.append(dark)
made = [lip, floor]

# Small scenery inside the footprint goes; the slab gets the recess cut out of it (down to the floor).
keep = ('Forest single', 'Volcanic single', 'Diorama', 'Continuous river', 'Layout card', 'Card face', 'Deck proxy')
xs = [p.x for p in outer]; ys = [p.y for p in outer]
for o in list(scene.objects):
	if o.type not in {'MESH', 'CURVE'} or o in made or o.name.startswith(keep) or o.name.startswith('Phase cradle'):
		continue
	bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
	if max(v.x for v in bb) - min(v.x for v in bb) > 1.6 or max(v.y for v in bb) - min(v.y for v in bb) > 1.6:
		continue
	ctr = sum(bb, Vector()) / 8
	if min(xs) <= ctr.x <= max(xs) and min(ys) <= ctr.y <= max(ys):
		print('REMOVED under phase cradle:', o.name, flush=True)
		bpy.data.objects.remove(o, do_unlink=True)
slab = bpy.data.objects['Volcanic single wood slab']
cut = prism('cutter', rect(LENGTH / 2 + CLEARANCE + 0.004, SLOT / 2 + CLEARANCE + 0.004), FLOOR_Z, 0.5)
apply_boolean(slab, cut, 'DIFFERENCE'); bpy.data.objects.remove(cut, do_unlink=True)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_phase_cradle.blend'))
for o in scene.objects:
	if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
		o.hide_render = True
scene.cycles.samples = 40
scene.render.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: phase cradle built, export source saved to', OUT, flush=True)
