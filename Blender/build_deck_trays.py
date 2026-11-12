"""Carve shallow deck pockets into the approved board art preview."""
import bpy, os, math
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(HERE,'board_deck_trays'); os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE,'board_art_passes','board_art_passes.blend'))
scene=bpy.context.scene
scene.cycles.samples=40

def rounded_box(name,location,dimensions,bevel):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location)
    o=bpy.context.object; o.name=name; o.dimensions=dimensions
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=o.modifiers.new('Rounded pocket corners','BEVEL'); mod.width=bevel; mod.segments=5
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

floor_mat=bpy.data.materials['Warm muted timber'].copy(); floor_mat.name='Recessed endgrain wood'
for node in floor_mat.node_tree.nodes:
    if node.type=='VALTORGB':
        for element in node.color_ramp.elements:
            element.color=tuple(v*.85 for v in element.color[:3])+(1,)

# Cards float above the table in the existing scene. Align the pocket to their
# projected footprint at the surface, retaining the actual deck/card transforms.
elevation=math.radians(67)
surface=.065
for label,x,y in [('Volcanic',2.65,1.3),('Forest',-2.9,-1.45)]:
    camera=scene.camera.location
    factor=(camera.z-surface)/(camera.z-.50)
    x=camera.x+(x-camera.x)*factor
    cy=camera.y+(y-camera.y)*factor
    slab=bpy.data.objects[label+' single wood slab']
    # Cutter bottom is below the top face but well above the bottom of the slab.
    cutter=rounded_box(label+' pocket cutter',(x,cy,.12),(.66,.95,.16),.012)
    bpy.context.view_layer.objects.active=slab
    cut=slab.modifiers.new('Carved deck recess','BOOLEAN'); cut.operation='DIFFERENCE'; cut.solver='EXACT'; cut.object=cutter
    # Apply after existing edge modifiers, creating a real watertight recess.
    bpy.ops.object.modifier_apply(modifier=cut.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    bpy.context.view_layer.objects.active=slab
    bevel=slab.modifiers.new('Soft pocket lip','BEVEL'); bevel.width=.004; bevel.segments=3
    slab.modifiers.new('Pocket shading','WEIGHTED_NORMAL')
    floor=rounded_box(label+' recessed wooden floor',(x,cy,.038),(.64,.93,.010),.003)
    floor.data.materials.append(floor_mat)

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_deck_trays.blend'))
scene.render.filepath=os.path.join(OUT,'deck_trays_with_cards.png'); bpy.ops.render.render(write_still=True)
for o in scene.objects:
    if o.name.startswith(('Deck proxy','Layout card','Card face')): o.hide_render=True
scene.render.filepath=os.path.join(OUT,'deck_trays_environment.png'); bpy.ops.render.render(write_still=True)
print('RESULT: two recessed deck trays rendered; Godot unchanged',flush=True)
