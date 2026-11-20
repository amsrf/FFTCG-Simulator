"""Carve a chamfered socket in the wood for the phase crystal (scripts/ui/phase_prism.gd).
The socket has sloped stone walls, a lip just above the board, and a dark floor below the crystal's roll.

Godot <-> Blender: Godot (x, y, z) = Blender (x, z, -y). Fixed for both seats (the exporter's fixed_prefixes): the
crystal is always on the LOCAL player's right. For seat two the exporter swaps its stone to that seat's housing stone.
The centre, mouth size and depth come from scripts/ui/phase_prism.gd.

Input: board_pit_stations/board_pit_stations.blend (not modified).
Output: board_phase_cradle/board_phase_cradle.blend (the export source read by export_board_to_godot.py) and its
seat-one environment render board_environment.png.

    blender --background --python /abs/path/Blender/build_phase_cradle.py
"""
import bpy, bmesh, os, re
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_phase_cradle'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_pit_stations', 'board_pit_stations.blend'))
scene = bpy.context.scene

ROOT = os.path.dirname(HERE)
GD = open(os.path.join(ROOT, 'scripts', 'ui', 'phase_prism.gd')).read()


def gd_const(name):
	m = re.search(r'^const %s\s*:?=\s*([-0-9.]+)' % name, GD, re.M)
	if m is None:
		raise RuntimeError('phase_prism.gd: const %s not found' % name)
	return float(m.group(1))


LENGTH, WIDTH = gd_const('CAVITY_LENGTH'), gd_const('CAVITY_WIDTH')
TOP, FLOOR = gd_const('CRADLE_TOP_Y'), gd_const('CAVITY_FLOOR_Y')
_c = re.search(r'^const CENTRE := Vector3\(([-0-9.]+),.*?,\s*([-0-9.]+)\)', GD, re.M)
GX, GZ = float(_c.group(1)), float(_c.group(2))
CENTRE = Vector((GX, -GZ, 0.0))
LIP = 0.011
WALL_SLOPE = 0.006


def outline(offset):
	"""Chamfered outline in Blender XY, with the long axis along X."""
	x, y = LENGTH / 2 + offset, WIDTH / 2 + offset
	dx, dy = 0.105, 0.055
	return [(CENTRE.x + a, CENTRE.y + b) for a, b in (
		(-x + dx, -y), (x - dx, -y), (x, -y + dy), (x, y - dy),
		(x - dx, y), (-x + dx, y), (-x, y - dy), (-x, -y + dy))]


def bands(name, levels, closed=False):
	"""Join matching outlines and either wrap them into a ring or cap the two ends."""
	me = bpy.data.meshes.new(name)
	bm = bmesh.new()
	rings = [[bm.verts.new((x, y, z)) for x, y in points] for points, z in levels]
	for a, b in zip(rings, rings[1:] + (rings[:1] if closed else [])):
		for i in range(len(a)):
			j = (i + 1) % len(a)
			bm.faces.new([a[i], a[j], b[j], b[i]])
	if not closed:
		bm.faces.new(list(reversed(rings[0])))
		bm.faces.new(rings[-1])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(me)
	bm.free()
	o = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(o)
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
mouth = outline(0.0)
throat = outline(-WALL_SLOPE)
outer = outline(LIP)
print('OPENING: %.3f x %.3f at (%.3f, %.3f), depth %.3f' % (LENGTH, WIDTH, CENTRE.x, CENTRE.y,
	TOP - FLOOR), flush=True)

lip = bands('Phase cradle lip', [(outer, FLOOR - 0.012), (outer, TOP), (mouth, TOP), (throat, FLOOR - 0.004)],
	closed=True)
b = lip.modifiers.new('Hewn edges', 'BEVEL'); b.width = 0.003; b.segments = 3
lip.modifiers.new('Shading', 'WEIGHTED_NORMAL')
lip.data.materials.append(stone)
floor_edge = outline(-WALL_SLOPE + 0.012)
floor = bands('Phase cradle floor', [(floor_edge, FLOOR - 0.010), (floor_edge, FLOOR)])
if dark is not None:
	floor.data.materials.append(dark)
made = [lip, floor]

# Small scenery inside the footprint goes; the slab gets the recess cut out of it (down to the floor).
keep = ('Forest single', 'Volcanic single', 'Diorama', 'Continuous river', 'Layout card', 'Card face', 'Deck proxy')
xs, ys = zip(*outer)
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
cut = bands('cutter', [(outline(-WALL_SLOPE + 0.008), FLOOR - 0.010), (outline(0.008), TOP),
	(outline(0.008), 0.5)])
apply_boolean(slab, cut, 'DIFFERENCE'); bpy.data.objects.remove(cut, do_unlink=True)

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_phase_cradle.blend'))
for o in scene.objects:
	if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
		o.hide_render = True
scene.cycles.samples = 40
scene.render.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: phase cradle built, export source saved to', OUT, flush=True)
