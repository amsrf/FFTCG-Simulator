"""Mock-up: a button station set into each player's slab corner.

Each station is a stone housing holding one large disc (go forward: Pass / Next
Phase / Confirm / Declare) and one small disc (Cancel / No Block). Each disc is a
coin on a horizontal axle in its own well: the +Z face is a lit gem, the -Z face
is carved stone, flush with the housing.

* Player (volcanic slab, bottom-right): basalt + iron, lava glow, teal/red gems.
* Opponent (forest slab, top-left, the player's station turned 180 degrees about
  the board pivot exactly as export_board_to_godot.py --seat2 turns the biomes):
  grey stone + bronze, emerald glow, a violet forward gem. Its Cancel disc is
  always on its stone face; the forward disc lights only while the opponent has
  priority.

Built on top of board_widened.blend (widen_board.py: the wider wood, the game camera, the cleared corners); the
source file is never modified.

    blender --background --python Blender/build_button_housing.py
"""
import bpy, os, math
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'button_housing'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_widened', 'board_widened.blend'))
scene = bpy.context.scene
scene.cycles.samples = 48

# ---- Dimensions (Blender units; camera looks back along -y, so -x is screen RIGHT, +y screen DOWN) ----
# 2026-11-21: down into the bottom-right corner for the zoomed-out camera, mostly off the wood (front edge y = 1.72);
# game.tscn's LocalForward / LocalCancel are these mapped (x, z, -y).
BIG_C = Vector((-3.59, 1.93, 0.0))
BIG_R = 0.30                            # disc radius
SMALL_C = Vector((-3.03, 1.71, 0.0))    # up and toward the board from the big one (same offset as before)
SMALL_R = 0.17
RIM = 0.085                             # stone wall around each well
BRIDGE_W = 0.36                         # width of the stone web joining the two drums
HOUSING_TOP = 0.115                     # a little proud of the wood (top 0.06)
HOUSING_BOTTOM = -0.12
DISC_THICK = 0.055
DISC_Z = 0.085
GAP = 0.016                             # glowing gap between disc and well wall
# The seat-2 turn used by export_board_to_godot.py: pi about Z through (0, -0.30).
PIVOT = Vector((0, -0.30, 0))
TURN = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation(-PIVOT)


def cylinder(name, centre, radius, z0, z1, verts=96):
	bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=z1 - z0,
		location=(centre.x, centre.y, (z0 + z1) / 2))
	o = bpy.context.object; o.name = name
	return o


def apply_boolean(target, cutter, op, open_sheet=False):
	bpy.context.view_layer.objects.active = target
	m = target.modifiers.new('bool', 'BOOLEAN'); m.operation = op; m.solver = 'EXACT'; m.object = cutter
	# Terrain sheets are not closed solids; without this EXACT turns a cut into a filled column.
	m.use_hole_tolerant = open_sheet
	bpy.ops.object.modifier_apply(modifier=m.name)


def material(name, base, rough=0.5, metal=0.0, emit=None, strength=0.0, coat=0.0):
	m = bpy.data.materials.new(name); m.use_nodes = True
	b = m.node_tree.nodes['Principled BSDF']
	b.inputs['Base Color'].default_value = (*base, 1)
	b.inputs['Roughness'].default_value = rough
	b.inputs['Metallic'].default_value = metal
	if coat:
		b.inputs['Coat Weight'].default_value = coat
	if emit:
		b.inputs['Emission Color'].default_value = (*emit, 1)
		b.inputs['Emission Strength'].default_value = strength
	return m


glyph = material('Glyph', (1, 1, 1), 0.3, 0.0, (1.0, 0.97, 0.9), 4.0)
dark = material('Well shadow', (0.01, 0.01, 0.01), 0.9)
STYLES = {
	'player': dict(
		slab='Volcanic single wood slab',
		stone=bpy.data.materials.get('Basalt 1') or material('Housing basalt', (0.05, 0.05, 0.055), 0.8),
		ring=material('Housing iron', (0.16, 0.15, 0.14), 0.32, 1.0),
		glow=material('Lava gap', (0.9, 0.25, 0.02), 0.5, 0.0, (1.0, 0.32, 0.04), 2.5),
		face=material('Carved basalt', (0.035, 0.034, 0.036), 0.85),
		groove=material('Basalt groove', (0.11, 0.10, 0.09), 0.6, 0.6),
		forward=material('Player forward gem', (0.0, 0.26, 0.25), 0.12, 0.0, (0.02, 0.55, 0.50), 0.55, coat=0.4),
		cancel=material('Player cancel gem', (0.36, 0.03, 0.02), 0.12, 0.0, (0.7, 0.08, 0.03), 0.5, coat=0.4),
	),
	'opponent': dict(
		slab='Forest single wood slab',
		stone=material('Forest housing stone', (0.2, 0.2, 0.19), 0.85),
		ring=material('Housing bronze', (0.42, 0.27, 0.12), 0.38, 1.0),
		glow=material('Spirit gap', (0.2, 0.9, 0.4), 0.5, 0.0, (0.25, 1.0, 0.45), 2.0),
		face=material('Carved grey stone', (0.12, 0.12, 0.115), 0.85),
		groove=material('Bronze groove', (0.42, 0.27, 0.12), 0.4, 1.0),
		forward=material('Opponent forward gem', (0.17, 0.04, 0.30), 0.12, 0.0, (0.45, 0.14, 0.80), 0.6, coat=0.4),
		cancel=material('Opponent cancel gem', (0.17, 0.04, 0.30), 0.12, 0.0, (0.45, 0.14, 0.80), 0.4, coat=0.4),
	),
}


def play_glyph(centre, size, z):
	"""Forward: a filled triangle pointing screen-right (-x), optically centred."""
	h = size * 0.42
	verts = [(centre.x - h * 0.62, centre.y, z), (centre.x + h * 0.38, centre.y - h * 0.58, z),
		(centre.x + h * 0.38, centre.y + h * 0.58, z)]
	me = bpy.data.meshes.new('play glyph'); me.from_pydata(verts, [], [(0, 1, 2)])
	o = bpy.data.objects.new('play glyph', me); bpy.context.collection.objects.link(o)
	o.modifiers.new('thick', 'SOLIDIFY').thickness = 0.006
	return [o]


def cross_glyph(centre, size, z):
	parts = []
	for ang in (45, -45):
		bpy.ops.mesh.primitive_cube_add(size=1, location=(centre.x, centre.y, z))
		bar = bpy.context.object
		bar.dimensions = (size * 0.85, size * 0.17, 0.006)
		bar.rotation_euler.z = math.radians(ang)
		parts.append(bar)
	return parts


def build_disc(label, c, r, st, active_mat, glyph_fn):
	disc = cylinder(f'Disc {label}', c, r, DISC_Z - DISC_THICK / 2, DISC_Z + DISC_THICK / 2, 128)
	b = disc.modifiers.new('Soft edge', 'BEVEL'); b.width = 0.008; b.segments = 3
	disc.data.materials.append(st['face'])     # slot 0: rim + inactive face
	disc.data.materials.append(active_mat)     # slot 1: active face
	for p in disc.data.polygons:
		if p.normal.z > 0.9:
			p.material_index = 1
	top = DISC_Z + DISC_THICK / 2 - 1e-4
	bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=24, radius=1, location=(c.x, c.y, top))
	lens = bpy.context.object; lens.name = f'Lens {label}'
	lens.scale = (r * 0.86, r * 0.86, 0.035); lens.data.materials.append(active_mat)
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	cut = cylinder('lens cut', c, r, top - 1.0, top)
	apply_boolean(lens, cut, 'DIFFERENCE'); bpy.data.objects.remove(cut, do_unlink=True)
	parts = [lens]
	for g in glyph_fn(c, r * 1.1, top + 0.04):
		g.data.materials.append(glyph); parts.append(g)
	bpy.ops.mesh.primitive_torus_add(major_radius=r * 0.62, minor_radius=0.008, major_segments=96,
		minor_segments=8, location=(c.x, c.y, DISC_Z - DISC_THICK / 2 - 0.002))
	eng = bpy.context.object; eng.data.materials.append(st['groove']); parts.append(eng)
	for p in parts:
		p.parent = disc
		p.matrix_parent_inverse = disc.matrix_world.inverted()
	return disc


def build_station(side):
	st = STYLES[side]
	made = []
	# Housing: two low-poly drums + a web between them, merged, wells cut.
	housing = cylinder(f'{side} button housing', BIG_C, BIG_R + GAP + RIM, HOUSING_BOTTOM, HOUSING_TOP, 12)
	housing.rotation_euler.z = 0.21
	drum = cylinder('small drum', SMALL_C, SMALL_R + GAP + RIM, HOUSING_BOTTOM, HOUSING_TOP, 10)
	drum.rotation_euler.z = 0.5
	apply_boolean(housing, drum, 'UNION'); bpy.data.objects.remove(drum, do_unlink=True)
	axis = SMALL_C - BIG_C
	bpy.ops.mesh.primitive_cube_add(size=1, location=((BIG_C + SMALL_C) / 2 + Vector((0, 0, (HOUSING_TOP + HOUSING_BOTTOM) / 2))))
	web = bpy.context.object
	web.dimensions = (axis.length, BRIDGE_W, HOUSING_TOP - HOUSING_BOTTOM)
	web.rotation_euler.z = math.atan2(axis.y, axis.x)
	apply_boolean(housing, web, 'UNION'); bpy.data.objects.remove(web, do_unlink=True)
	for c, r in [(BIG_C, BIG_R), (SMALL_C, SMALL_R)]:
		well = cylinder('well cutter', c, r + GAP, HOUSING_BOTTOM - 0.1, HOUSING_TOP + 0.1)
		apply_boolean(housing, well, 'DIFFERENCE'); bpy.data.objects.remove(well, do_unlink=True)
	b = housing.modifiers.new('Hewn edges', 'BEVEL'); b.width = 0.018; b.segments = 3
	housing.modifiers.new('Shading', 'WEIGHTED_NORMAL')
	housing.data.materials.clear(); housing.data.materials.append(st['stone'])
	made.append(housing)
	for c, r, label in [(BIG_C, BIG_R, 'big'), (SMALL_C, SMALL_R, 'small')]:
		bpy.ops.mesh.primitive_torus_add(major_radius=r + GAP + 0.012, minor_radius=0.016,
			major_segments=128, minor_segments=12, location=(c.x, c.y, HOUSING_TOP))
		ring = bpy.context.object; ring.name = f'{side} ring {label}'; ring.data.materials.append(st['ring'])
		floor = cylinder(f'{side} well floor {label}', c, r + GAP + 0.002, HOUSING_BOTTOM, HOUSING_BOTTOM + 0.01)
		floor.data.materials.append(dark)
		# The well is dark underneath: the Godot button (a lens) fills the well, so only a turning button shows it.
		# The glow lives on the ring instead, live in Godot (disc_ring_glow.gdshader).
		made += [ring, floor]
	big = build_disc(f'{side} big', BIG_C, BIG_R, st, st['forward'], play_glyph)
	small = build_disc(f'{side} small', SMALL_C, SMALL_R, st, st['cancel'], cross_glyph)
	made += [big, small]
	yaw = 0.0
	if side == 'opponent':
		yaw = math.pi
		for o in made:
			o.matrix_world = TURN @ o.matrix_world
	for d in (big, small):
		d['yaw'] = yaw
	# Hide scenery the housing sits ON (centre inside it); pieces that merely touch it stay, so
	# the housing reads as set among the rocks/foliage rather than in a cleared patch.
	hb = [housing.matrix_world @ Vector(v) for v in housing.bound_box]
	hlo = Vector((min(v.x for v in hb), min(v.y for v in hb))); hhi = Vector((max(v.x for v in hb), max(v.y for v in hb)))
	centres = [(TURN @ c if yaw else c, r + GAP + RIM * 0.7) for c, r in [(BIG_C, BIG_R), (SMALL_C, SMALL_R)]]
	# Anything overlapping a well would sit over a disc: those go too.
	wells = [(TURN @ c if yaw else c, r + GAP) for c, r in [(BIG_C, BIG_R), (SMALL_C, SMALL_R)]]
	for o in list(scene.objects):
		if o.type not in {'MESH', 'CURVE'} or o in made or o.name.startswith(('Forest single', 'Volcanic single', 'Diorama',
				'Continuous river', 'Layout card', 'Card face', 'Deck proxy')) or o.parent in (big, small):
			continue
		bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
		ctr = sum(bb, Vector()) / 8
		lo = Vector((min(v.x for v in bb), min(v.y for v in bb))); hi = Vector((max(v.x for v in bb), max(v.y for v in bb)))
		def covers_well(c, r):
			near = Vector((min(max(c.x, lo.x), hi.x), min(max(c.y, lo.y), hi.y)))
			return (near - Vector((c.x, c.y))).length < r
		# Ground planes, lava beds and terrain sheets span far more than a station: never delete them,
		# but if one runs through a well (the forest ground does) cut the wells out of it.
		if (hi - lo).x > 1.2 or (hi - lo).y > 1.2:
			top = max(v.z for v in bb)
			if top > HOUSING_BOTTOM and any(covers_well(c, r) for c, r in wells):
				print('CUT wells out of:', o.name, flush=True)
				if o.type == 'CURVE':
					bpy.context.view_layer.objects.active = o; o.select_set(True)
					bpy.ops.object.convert(target='MESH'); o.select_set(False)
				for c, r in wells:
					plug = cylinder('ground plug', c, r + 0.004, HOUSING_BOTTOM + 0.011, 1.0)
					apply_boolean(o, plug, 'DIFFERENCE', open_sheet=True); bpy.data.objects.remove(plug, do_unlink=True)
			continue
		if any((Vector((ctr.x, ctr.y)) - Vector((c.x, c.y))).length < r for c, r in centres) or \
				any(covers_well(c, r) for c, r in wells):
			# Deleted, not hidden: export_board_to_godot.py exports hidden objects too.
			print('REMOVED under station:', o.name, flush=True)
			bpy.data.objects.remove(o, do_unlink=True)
	# Bite the slab with the full outer outline (wells included), down through its whole thickness.
	slab = bpy.data.objects[st['slab']]
	cutter = housing.copy(); cutter.data = housing.data.copy(); bpy.context.collection.objects.link(cutter)
	cutter.modifiers.clear()
	for c, r in [(BIG_C, BIG_R), (SMALL_C, SMALL_R)]:
		plug = cylinder('plug', TURN @ c if yaw else c, r + GAP + 0.01, HOUSING_BOTTOM - 0.3, HOUSING_TOP)
		apply_boolean(cutter, plug, 'UNION'); bpy.data.objects.remove(plug, do_unlink=True)
	apply_boolean(slab, cutter, 'DIFFERENCE'); bpy.data.objects.remove(cutter, do_unlink=True)
	return big, small


def set_flip(disc, t):
	"""t = 0 active face up, 1 stone face up; the axle is the station's local X."""
	disc.rotation_euler = (math.pi * t, 0, disc['yaw'])


p_big, p_small = build_station('player')
o_big, o_small = build_station('opponent')

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'button_housing.blend'))

R = scene.render
PLAYER_CROP = (0.62, 1.0, 0.0, 0.48)
OPPONENT_CROP = (0.0, 0.40, 0.55, 1.0)


def shoot(path, crop=None):
	R.use_border = crop is not None; R.use_crop_to_border = crop is not None
	if crop:
		R.border_min_x, R.border_max_x, R.border_min_y, R.border_max_y = crop
	R.filepath = os.path.join(OUT, path)
	bpy.ops.render.render(write_still=True)


for f in ['crop_a_both_active.png', 'crop_b_forward_only.png', 'crop_c_both_off.png', 'crop_d_mid_flip.png']:
	p = os.path.join(OUT, f)
	if os.path.exists(p):
		os.remove(p)

# Opponent's Cancel never lights.
set_flip(o_small, 1)
set_flip(p_big, 0); set_flip(p_small, 0); set_flip(o_big, 1)
shoot('full_player_prompt.png')                       # my target prompt: both of mine lit, theirs dark
shoot('player_a_both_active.png', PLAYER_CROP)
set_flip(p_small, 1)
shoot('player_b_forward_only.png', PLAYER_CROP)
set_flip(p_big, 1)
shoot('player_c_both_off.png', PLAYER_CROP)
set_flip(p_big, 0.5)
shoot('player_d_mid_flip.png', PLAYER_CROP)
set_flip(p_big, 1)
shoot('opponent_off.png', OPPONENT_CROP)
set_flip(o_big, 0)
shoot('opponent_priority.png', OPPONENT_CROP)
shoot('full_opponent_priority.png')                   # their priority: mine dark, their forward lit
print('RESULT: button stations rendered to', OUT, flush=True)

# ---- Export source: the board WITH the stations but WITHOUT the discs (Godot builds and animates those). ----
# export_board_to_godot.py reads this blend and its environment-only render (the seat-one baked appearance).
SOURCE = os.path.join(HERE, 'board_button_stations'); os.makedirs(SOURCE, exist_ok=True)
for d in (p_big, p_small, o_big, o_small):
	for o in [d] + list(d.children_recursive):
		bpy.data.objects.remove(o, do_unlink=True)
R.use_border = False; R.use_crop_to_border = False
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE, 'board_button_stations.blend'))
for o in scene.objects:
	if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
		o.hide_render = True
scene.cycles.samples = 40
R.filepath = os.path.join(SOURCE, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: export source saved to', SOURCE, flush=True)
