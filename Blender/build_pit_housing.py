"""Pit stations: the Break Zone and Removed pits set into the same stone housing as the button stations.

Each side gets ONE housing wrapping both pits (after Master Duel's graveyard/banish pits, ~/Desktop/Clips/pits): a
low-poly stone drum around the Break Zone pit, a smaller one around the Removed pit up and to its right, a stone web
joining them, and a metal ring round each well. Shape language and MATERIALS are the button stations' own
(build_button_housing.py): the stone and ring materials are taken from those housings in the board, so the two
stations cannot drift apart. The pits themselves are Godot (scripts/game/pit.gd); they sit in these wells.

Godot <-> Blender: Godot (x, y, z) = Blender (x, z, -y). The pit centres below are game.tscn's
Player/Graveyard (2.76, -1.62) and Player/Removed (2.4, -1.3), radii Graveyard.pit_radius (0.21 / 0.16). The
opponent's station is the player's turned pi about Z through (0, -0.30), exactly as the button stations are, which
lands on Opponent/Graveyard (-2.76, 2.22) and Opponent/Removed (-2.4, 1.9).

Input: board_filled_pockets/board_filled_pockets.blend (not modified).
Output: board_pit_stations/board_pit_stations.blend (the export source read by export_board_to_godot.py) and its
seat-one environment render board_environment.png, plus pit_stations_player.png / pit_stations_opponent.png crops.

    blender --background --python Blender/build_pit_housing.py
"""
import bpy, os, math
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_pit_stations'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_filled_pockets', 'board_filled_pockets.blend'))
scene = bpy.context.scene

# ---- Dimensions (Blender units). Pit centres/radii must match game.tscn (see the docstring). ----
BIG_C = Vector((2.76, 1.62, 0.0))       # Break Zone pit: straddles the volcanic slab's front edge (y = 1.72)
BIG_R = 0.21
SMALL_C = Vector((2.40, 1.30, 0.0))     # Removed pit: up and to the right of it on screen
SMALL_R = 0.16
RIM = 0.07                              # stone wall around each well (the buttons' 0.085 would touch the deck)
GAP = 0.016                             # well clearance around the Godot pit drum
BRIDGE_W = 0.24                         # the stone web joining the two drums
HOUSING_TOP = 0.115                     # the button stations' height: a little proud of the wood (top 0.06)
HOUSING_BOTTOM = -0.12
PIVOT = Vector((0, -0.30, 0))
TURN = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation(-PIVOT)
PITS = [(BIG_C, BIG_R, 'break zone'), (SMALL_C, SMALL_R, 'removed')]

STYLES = {
	'player': dict(slab='Volcanic single wood slab', housing='player button housing', ring='player ring big'),
	'opponent': dict(slab='Forest single wood slab', housing='opponent button housing', ring='opponent ring big'),
}
dark = bpy.data.materials.get('Well shadow')


def cylinder(name, centre, radius, z0, z1, verts=96):
	bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=z1 - z0,
		location=(centre.x, centre.y, (z0 + z1) / 2))
	o = bpy.context.object; o.name = name
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


def build_station(side):
	st = STYLES[side]
	stone = station_material(st['housing'])
	ring_mat = station_material(st['ring'])
	made = []
	housing = cylinder(f'{side} pit housing', BIG_C, BIG_R + GAP + RIM, HOUSING_BOTTOM, HOUSING_TOP, 12)
	housing.rotation_euler.z = 0.21
	drum = cylinder('small pit drum', SMALL_C, SMALL_R + GAP + RIM, HOUSING_BOTTOM, HOUSING_TOP, 10)
	drum.rotation_euler.z = 0.5
	apply_boolean(housing, drum, 'UNION'); bpy.data.objects.remove(drum, do_unlink=True)
	axis = SMALL_C - BIG_C
	bpy.ops.mesh.primitive_cube_add(size=1, location=((BIG_C + SMALL_C) / 2 + Vector((0, 0, (HOUSING_TOP + HOUSING_BOTTOM) / 2))))
	web = bpy.context.object
	web.dimensions = (axis.length, BRIDGE_W, HOUSING_TOP - HOUSING_BOTTOM)
	web.rotation_euler.z = math.atan2(axis.y, axis.x)
	apply_boolean(housing, web, 'UNION'); bpy.data.objects.remove(web, do_unlink=True)
	for c, r, _ in PITS:
		well = cylinder('well cutter', c, r + GAP, HOUSING_BOTTOM - 0.1, HOUSING_TOP + 0.1)
		apply_boolean(housing, well, 'DIFFERENCE'); bpy.data.objects.remove(well, do_unlink=True)
	b = housing.modifiers.new('Hewn edges', 'BEVEL'); b.width = 0.018; b.segments = 3
	housing.modifiers.new('Shading', 'WEIGHTED_NORMAL')
	housing.data.materials.clear(); housing.data.materials.append(stone)
	made.append(housing)
	for c, r, label in PITS:
		bpy.ops.mesh.primitive_torus_add(major_radius=r + GAP + 0.012, minor_radius=0.016,
			major_segments=128, minor_segments=12, location=(c.x, c.y, HOUSING_TOP))
		ring = bpy.context.object; ring.name = f'{side} pit ring {label}'; ring.data.materials.append(ring_mat)
		floor = cylinder(f'{side} pit well floor {label}', c, r + GAP + 0.002, HOUSING_BOTTOM, HOUSING_BOTTOM + 0.01)
		if dark is not None:
			floor.data.materials.append(dark)
		made += [ring, floor]
	turned = side == 'opponent'
	if turned:
		for o in made:
			o.matrix_world = TURN @ o.matrix_world
	# Scenery the housing sits ON goes (deleted, not hidden: the exporter exports hidden objects too); terrain sheets
	# that run through a well get the well cut out of them. Same rules as the button stations.
	centres = [(TURN @ c if turned else c, r + GAP + RIM * 0.7) for c, r, _ in PITS]
	wells = [(TURN @ c if turned else c, r + GAP) for c, r, _ in PITS]
	keep = ('Forest single', 'Volcanic single', 'Diorama', 'Continuous river', 'Layout card', 'Card face', 'Deck proxy')
	for o in list(scene.objects):
		if o.type not in {'MESH', 'CURVE'} or o in made or o.name.startswith(keep) \
				or 'button housing' in o.name or ' ring ' in o.name or 'well floor' in o.name or 'pit ' in o.name:
			continue
		bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
		ctr = sum(bb, Vector()) / 8
		lo = Vector((min(v.x for v in bb), min(v.y for v in bb))); hi = Vector((max(v.x for v in bb), max(v.y for v in bb)))

		def covers_well(c, r):
			near = Vector((min(max(c.x, lo.x), hi.x), min(max(c.y, lo.y), hi.y)))
			return (near - Vector((c.x, c.y))).length < r
		if (hi - lo).x > 1.2 or (hi - lo).y > 1.2:
			top = max(v.z for v in bb)
			if top > HOUSING_BOTTOM and any(covers_well(c, r) for c, r in wells):
				print('CUT pit wells out of:', o.name, flush=True)
				if o.type == 'CURVE':
					bpy.context.view_layer.objects.active = o; o.select_set(True)
					bpy.ops.object.convert(target='MESH'); o.select_set(False)
				for c, r in wells:
					plug = cylinder('ground plug', c, r + 0.004, HOUSING_BOTTOM + 0.011, 1.0)
					apply_boolean(o, plug, 'DIFFERENCE', open_sheet=True); bpy.data.objects.remove(plug, do_unlink=True)
			continue
		if any((Vector((ctr.x, ctr.y)) - Vector((c.x, c.y))).length < r for c, r in centres) or \
				any(covers_well(c, r) for c, r in wells):
			print('REMOVED under pit station:', o.name, flush=True)
			bpy.data.objects.remove(o, do_unlink=True)
	# Bite the slab with the full outer outline (wells included), down through its whole thickness.
	slab = bpy.data.objects[st['slab']]
	cutter = housing.copy(); cutter.data = housing.data.copy(); bpy.context.collection.objects.link(cutter)
	cutter.modifiers.clear()
	for c, r, _ in PITS:
		plug = cylinder('plug', TURN @ c if turned else c, r + GAP + 0.01, HOUSING_BOTTOM - 0.3, HOUSING_TOP)
		apply_boolean(cutter, plug, 'UNION'); bpy.data.objects.remove(plug, do_unlink=True)
	apply_boolean(slab, cutter, 'DIFFERENCE'); bpy.data.objects.remove(cutter, do_unlink=True)


build_station('player')
build_station('opponent')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_pit_stations.blend'))

R = scene.render
for o in scene.objects:
	if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
		o.hide_render = True
scene.cycles.samples = 40
R.use_border = False; R.use_crop_to_border = False
R.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: pit stations built, export source saved to', OUT, flush=True)
