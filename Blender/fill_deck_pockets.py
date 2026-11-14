"""Plain wood under the piles: fill the old shallow deck pockets back in with the slab's own wood.

The deck and Break Zone lie flat on the wood (game.tscn), so the pockets build_deck_trays.py carved, which no longer
line up with any pile, are filled and their floors deleted. Nothing else changes.

Input: board_button_stations/board_button_stations.blend (not modified).
Output: board_filled_pockets/board_filled_pockets.blend (the export source read by export_board_to_godot.py) and its
seat-one environment render board_environment.png.

    blender --background --python Blender/fill_deck_pockets.py
"""
import bpy, os
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'board_filled_pockets'); os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'board_button_stations', 'board_button_stations.blend'))
scene = bpy.context.scene
scene.cycles.samples = 40


def fill_old_pocket(slab_name, floor_name):
	floor = bpy.data.objects.get(floor_name)
	slab = bpy.data.objects[slab_name]
	if floor is None:
		return
	bb = [floor.matrix_world @ Vector(v) for v in floor.bound_box]
	lo = Vector((min(v.x for v in bb), min(v.y for v in bb), 0)); hi = Vector((max(v.x for v in bb), max(v.y for v in bb), 0))
	top = max((slab.matrix_world @ v.co).z for v in slab.data.vertices)
	# The pocket was cut .66 x .95, its floor is .64 x .93: overfill by a hair so no wall survives.
	size = (hi - lo) + Vector((0.03, 0.03, 0))
	bpy.ops.mesh.primitive_cube_add(size=1, location=((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, top / 2))
	patch = bpy.context.object
	patch.dimensions = (size.x, size.y, top)
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	bpy.context.view_layer.objects.active = slab
	m = slab.modifiers.new('fill', 'BOOLEAN'); m.operation = 'UNION'; m.solver = 'EXACT'; m.object = patch
	bpy.ops.object.modifier_apply(modifier=m.name)
	bpy.data.objects.remove(patch, do_unlink=True)
	bpy.data.objects.remove(floor, do_unlink=True)
	print('FILLED old pocket in', slab_name, flush=True)


fill_old_pocket('Volcanic single wood slab', 'Volcanic recessed wooden floor')
fill_old_pocket('Forest single wood slab', 'Forest recessed wooden floor')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'board_filled_pockets.blend'))
for o in scene.objects:
	if o.name.startswith(('Deck proxy', 'Layout card', 'Card face')):
		o.hide_render = True
scene.render.use_border = False
scene.render.filepath = os.path.join(OUT, 'board_environment.png')
bpy.ops.render.render(write_still=True)
print('RESULT: export source saved to', OUT, flush=True)
