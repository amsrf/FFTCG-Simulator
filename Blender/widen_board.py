"""Widen the wood, frame the board for the game's camera, and clear the corners the deck, pits and buttons moved into.

The first stage of the board pipeline since the 2026-11-21 camera change (BoardCameraRig: frame_width 9.6, fov 22,
elevation 67). Reads board_landmarks.blend (never modified) and writes board_widened/board_widened.blend, which
build_button_housing.py builds on.

* THE CAMERA. export_board_to_godot.py projects the scene camera's render onto the mesh as its texture, so that camera
  has to be the GAME's camera: with the old one (frame 8.0, fov 30) everything the zoomed-out view showed past its
  frame had no texture of its own and smeared. Godot (x, y, z) is Blender (x, -z, y).
* THE WOOD. Both single wood slabs grow by WIDEN at each end (x +-4.02 -> +-4.30), so the phase engravings around the
  coin, which moved to the bottom-right corner, still lie on wood. The slab end vertices move; the bevel modifiers
  re-run on the longer box. Every small piece of scenery beyond X_SCENERY moves out by the same amount, so the banks,
  rocks and edge splits keep their place against the new ends. Large sheets (ground, river) stay: the slab sits on them.
* THE CORNERS. Tall scenery is removed around the new button stations, pit stations and the (now hand-card-sized) deck,
  for both seats, so nothing stands in front of them on screen. The positions are game.tscn's (Godot x, -z).

    blender --background --python Blender/widen_board.py
"""
import bpy, os, math
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_widened'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_landmarks', 'board_landmarks.blend'))
scene = bpy.context.scene

# ---- The game camera (scripts/game/camera_rig.gd) ----
FRAME_WIDTH = 9.6
FOV_DEG = 22.0          # vertical (Godot keep_aspect = KEEP_HEIGHT)
ELEVATION_DEG = 67.0
TARGET = Vector((0.0, 0.35, -0.25))   # Godot
ASPECT = 16.0 / 9.0

# ---- The wood ----
WIDEN = 0.28            # metres added at each end of both slabs
SLAB_END = 3.97         # slab vertices beyond |x| this are the ends
X_SCENERY = 3.75        # small scenery whose centre is beyond |x| this moves out with the ends
SLABS = ('Forest single wood slab', 'Volcanic single wood slab')
KEEP = SLABS + ('Diorama', 'Continuous river', 'Layout card', 'Card face', 'Deck proxy')

# ---- The corners (Blender x, y = Godot x, -z), player side; the opponent's are TURNed ----
PIVOT = Vector((0, -0.30, 0))
TURN = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation(-PIVOT)
# (centre, radius): remove small scenery taller than CLEAR_TOP whose centre is within the radius.
CLEAR_DISCS = [
	(Vector((-3.59, 1.93, 0)), 0.85),   # pass coin + phase engravings
	(Vector((-3.03, 1.71, 0)), 0.40),   # cancel
	(Vector((2.92, 2.12, 0)), 0.45),    # Break Zone pit
	(Vector((2.54, 1.80, 0)), 0.40),    # Removed pit
]
# The deck (Card.DECK_WORLD_SCALE 1.8: 0.77 x 1.08 m) plus a margin: anything taller than DECK_TOP whose footprint
# touches it would poke through the cards.
DECK_C = Vector((3.64, 1.95, 0)); DECK_HALF = Vector((0.386 + 0.10, 0.54 + 0.10, 0))
CLEAR_TOP = 0.12
DECK_TOP = 0.06
# Only loose pieces go. The terrain (ground sheets, plates, shelves, moss, soil, rims) would leave holes, and a tree
# stripped branch by branch reads as broken; both stay, and the deck's height follows the ground it rests on.
NEVER_CLEAR = ('terrain', 'ground', 'soil', 'plate', 'shelf', 'rim', 'moss', 'footing', 'bank', 'branch', 'foliage',
	'trunk', 'leaf', 'leaves', 'canopy', 'root', 'grass', 'river', 'lava', 'fissure', 'mass')


def set_game_camera():
	cam = scene.camera
	h = math.radians(FOV_DEG) * 0.5
	d = FRAME_WIDTH / (2.0 * ASPECT * math.tan(h))
	e = math.radians(ELEVATION_DEG)
	g = TARGET + Vector((0.0, d * math.sin(e), -d * math.cos(e)))
	cam.location = (g.x, -g.z, g.y)
	cam.rotation_euler = (math.radians(90.0 - ELEVATION_DEG), 0.0, math.pi)
	cam.data.type = 'PERSP'
	cam.data.sensor_fit = 'HORIZONTAL'
	cam.data.sensor_width = 36.0
	hfov = 2.0 * math.atan(math.tan(h) * ASPECT)
	cam.data.lens = 18.0 / math.tan(hfov * 0.5)
	scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
	print('CAMERA at', tuple(round(v, 3) for v in cam.location), 'lens %.2f mm' % cam.data.lens, flush=True)


def bounds(o):
	bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
	lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
	hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
	return lo, hi, (lo + hi) * 0.5


def small(lo, hi):
	return (hi - lo).x <= 1.2 and (hi - lo).y <= 1.2


def widen_slabs():
	for name in SLABS:
		o = bpy.data.objects[name]
		inv = o.matrix_world.inverted()
		moved = 0
		for v in o.data.vertices:
			w = o.matrix_world @ v.co
			if abs(w.x) > SLAB_END:
				w.x += WIDEN if w.x > 0 else -WIDEN
				v.co = inv @ w
				moved += 1
		o.data.update()
		o.update_tag(); bpy.context.view_layer.update()
		lo, hi, _ = bounds(o)
		print('WIDENED %s: %d end vertices, x %.2f..%.2f' % (name, moved, lo.x, hi.x), flush=True)


def move_side_scenery():
	moved = 0
	for o in scene.objects:
		if o.type not in {'MESH', 'CURVE'} or o.name.startswith(KEEP) or o.parent is not None:
			continue
		lo, hi, ctr = bounds(o)
		if not small(lo, hi) or abs(ctr.x) < X_SCENERY:
			continue
		o.location.x += WIDEN if ctr.x > 0 else -WIDEN
		moved += 1
	print('MOVED %d side scenery objects out by %.2f m' % (moved, WIDEN), flush=True)


def clear_corners():
	discs = []
	for c, r in CLEAR_DISCS:
		discs += [(c, r), (TURN @ c, r)]
	decks = [DECK_C, TURN @ DECK_C]
	removed = 0
	for o in list(scene.objects):
		if o.type not in {'MESH', 'CURVE'} or o.name.startswith(KEEP) or o.parent is not None:
			continue
		lo, hi, ctr = bounds(o)
		if not small(lo, hi) or any(word in o.name.lower() for word in NEVER_CLEAR):
			continue
		hit = hi.z > CLEAR_TOP and any((Vector((ctr.x, ctr.y)) - Vector((c.x, c.y))).length < r for c, r in discs)
		for dc in decks:
			if hi.z > DECK_TOP and lo.x < dc.x + DECK_HALF.x and hi.x > dc.x - DECK_HALF.x \
					and lo.y < dc.y + DECK_HALF.y and hi.y > dc.y - DECK_HALF.y:
				hit = True
		if hit:
			# Deleted, not hidden: export_board_to_godot.py exports hidden objects too.
			print('CLEARED:', o.name, flush=True)
			bpy.data.objects.remove(o, do_unlink=True)
			removed += 1
	print('CLEARED %d objects around the stations and decks' % removed, flush=True)


TREE_WORDS = ('tree', 'branch', 'foliage', 'trunk')
TREE_REACH = 1.0        # a tree's parts lie within this of its trunk (xy)
TREE_GROUP = 1.6        # beyond this from every trunk, foliage is a bush of its own
STATION_CANOPY_CLEAR = (0.62, 0.40)   # no foliage above CLEAR_TOP within this of the coin / the Cancel button
BED_Z = 0.06            # the deck rests here: Deck node y 0.07 sits just above
BED_MARGIN = 0.03       # the flattened patch reaches only this far past the cards, so no cut edge shows


def remove_trees_over_decks():
	"""A tree standing by a deck, or hanging any part over a coin / Cancel station, would cover them on screen: the WHOLE
	tree goes (a tree stripped branch by branch reads as broken). Parts belong to their NEAREST trunk: a canopy reaches
	further than any fixed radius. Both seats are covered by clearing around both sides' positions here, because
	export --seat2 turns the scenery onto the other side's stations."""
	decks = [DECK_C, TURN @ DECK_C]
	stations = []
	for c, r in zip([CLEAR_DISCS[0][0], CLEAR_DISCS[1][0]], STATION_CANOPY_CLEAR):   # the coin and the Cancel button
		stations += [(Vector((c.x, c.y)), r), (Vector(((TURN @ c).x, (TURN @ c).y)), r)]
	trunks = []
	for o in scene.objects:
		if o.type == 'MESH' and 'trunk' in o.name.lower():
			lo, hi, ctr = bounds(o)
			trunks.append([Vector((ctr.x, ctr.y)), any(abs(ctr.x - dc.x) < DECK_HALF.x + 0.8
				and abs(ctr.y - dc.y) < DECK_HALF.y + 0.8 for dc in decks)])
	if not trunks:
		return
	parts = []
	for o in scene.objects:
		if o.type not in {'MESH', 'CURVE'} or not any(w in o.name.lower() for w in TREE_WORDS):
			continue
		lo, hi, ctr = bounds(o)
		p = Vector((ctr.x, ctr.y))
		tree = min(range(len(trunks)), key=lambda i: (trunks[i][0] - p).length)
		if (trunks[tree][0] - p).length > TREE_GROUP:
			tree = -1                       # a bush / free-standing foliage, not part of a trunked tree
		over = False
		if o.type == 'MESH' and hi.z > CLEAR_TOP:
			for v in o.data.vertices:
				w = o.matrix_world @ v.co
				if w.z > CLEAR_TOP and any((Vector((w.x, w.y)) - c).length < r for c, r in stations):
					over = True
					break
		if over and tree >= 0:
			trunks[tree][1] = True
		parts.append((o, tree, over))
	gone = 0
	for o, tree, over in parts:
		if (tree >= 0 and trunks[tree][1]) or (tree < 0 and over):
			bpy.data.objects.remove(o, do_unlink=True)
			gone += 1
	print('REMOVED %d tree parts over a deck or button (%d of %d trunks)' % (gone, sum(1 for t in trunks if t[1]), len(trunks)), flush=True)


def flatten_deck_beds():
	"""Trim whatever rises above BED_Z inside each deck's footprint, so the cards lie flat on the ground; then, in a band
	around it, whatever rises above EDGE_Z, so no lump stands in front of the cards (a deck's near side in one seat is
	its far side in the other: export --seat2 turns the scenery, not the decks)."""
	for dc, half, cap in [(dc, Vector((0.386 + BED_MARGIN, 0.54 + BED_MARGIN, 0)), BED_Z) for dc in [DECK_C, TURN @ DECK_C]] + \
			[(dc, Vector((0.386 + EDGE_BAND, 0.54 + EDGE_BAND, 0)), EDGE_Z) for dc in [DECK_C, TURN @ DECK_C]]:
		_trim(dc, half, cap)


EDGE_BAND = 0.22        # the band around a deck where lumps are capped at EDGE_Z
EDGE_Z = 0.10


def _trim(dc, half, cap):
	"""Cut everything inside the box (centre dc, half extents half) down to height cap."""
	trimmed = 0
	for o in list(scene.objects):
		if o.type not in {'MESH', 'CURVE'} or o.name.startswith(KEEP):
			continue
		lo, hi, _ = bounds(o)
		if hi.z <= cap or lo.x > dc.x + half.x or hi.x < dc.x - half.x or lo.y > dc.y + half.y or hi.y < dc.y - half.y:
			continue
		if o.type == 'CURVE':
			bpy.context.view_layer.objects.active = o; o.select_set(True)
			bpy.ops.object.convert(target='MESH'); o.select_set(False)
		inside = [o.matrix_world @ v.co for v in o.data.vertices]
		if not any(abs(w.x - dc.x) < half.x and abs(w.y - dc.y) < half.y and w.z > cap for w in inside):
			continue
		bpy.ops.mesh.primitive_cube_add(size=1, location=(dc.x, dc.y, cap + 1.0))
		box = bpy.context.object; box.dimensions = (half.x * 2, half.y * 2, 2.0)
		bpy.context.view_layer.objects.active = o
		m = o.modifiers.new('bed', 'BOOLEAN'); m.operation = 'DIFFERENCE'; m.solver = 'EXACT'; m.object = box
		m.use_hole_tolerant = True
		bpy.ops.object.modifier_apply(modifier=m.name)
		bpy.data.objects.remove(box, do_unlink=True)
		trimmed += 1
	print('DECK BED at (%.2f, %.2f): trimmed %d objects to z %.2f within +-(%.2f, %.2f)' % (
		dc.x, dc.y, trimmed, cap, half.x, half.y), flush=True)


set_game_camera()
widen_slabs()
move_side_scenery()
clear_corners()
remove_trees_over_decks()
flatten_deck_beds()
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_widened.blend'))
print('RESULT: widened board saved to', OUT, flush=True)
