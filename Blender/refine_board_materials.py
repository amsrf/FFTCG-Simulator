"""Grass edge, lava, river depth and wood grain; retains the approved geometry fixes."""
import bpy, os, math
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(HERE,'board_material_refinement'); os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE,'board_terrain_join','board_terrain_join.blend'))
scene=bpy.context.scene; scene.cycles.samples=48

def ramp(nodes,colors):
    r=nodes.new('ShaderNodeValToRGB')
    for e,c in zip(r.color_ramp.elements,colors): e.color=(*c,1)
    return r

# 1: continuous grassy soil, with only three groups of visible edge stones.
for o in list(scene.objects):
    if o.name.startswith('Moss meeting wood') and not any(abs(o.location.x-x)<.32 for x in [-3.6,-.8,2.4]):
        bpy.data.objects.remove(o,do_unlink=True)
ground=bpy.data.objects['Unified forest ground and bank']
for v in ground.data.vertices:
    if v.co.y> -2.5:
        strength=max(0,1-(-2.275-v.co.y)/.225)
        v.co.y+=strength*(.025+.028*math.sin(v.co.x*2.3))
grassmat=bpy.data.materials['Forest soil'].copy(); grassmat.name='Continuous grassy soil'
n=grassmat.node_tree.nodes; l=grassmat.node_tree.links; p=n.get('Principled BSDF')
noise=n.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=4; noise.inputs['Detail'].default_value=2
r=ramp(n,[(.065,.09,.025),(.15,.205,.045)])
l.new(noise.outputs['Fac'],r.inputs[0]); l.new(r.outputs[0],p.inputs['Base Color'])
ground.data.materials.clear(); ground.data.materials.append(grassmat)

# 2: a darker red pool with slow broad color variation, brighter near rock contacts.
lava=bpy.data.materials['Red fissures']; n=lava.node_tree.nodes; l=lava.node_tree.links; p=n.get('Principled BSDF')
noise=n.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=6; noise.inputs['Detail'].default_value=2; noise.inputs['Roughness'].default_value=.6
coord=n.new('ShaderNodeTexCoord'); l.new(coord.outputs['Object'],noise.inputs['Vector'])
r=ramp(n,[(.10,.001,.0003),(.60,.018,.001)])
r.color_ramp.elements[0].position=.25; r.color_ramp.elements[1].position=.78
l.new(noise.outputs['Fac'],r.inputs[0]); l.new(r.outputs[0],p.inputs['Base Color']); l.new(r.outputs[0],p.inputs['Emission Color'])
p.inputs['Emission Strength'].default_value=.9; p.inputs['Roughness'].default_value=.55
ao=n.new('ShaderNodeAmbientOcclusion'); ao.inputs['Distance'].default_value=.10
invert=n.new('ShaderNodeMath'); invert.operation='SUBTRACT'; invert.inputs[0].default_value=1; l.new(ao.outputs['AO'],invert.inputs[1])
boost=n.new('ShaderNodeMath'); boost.operation='MULTIPLY_ADD'; boost.inputs[1].default_value=.65; boost.inputs[2].default_value=.8
l.new(invert.outputs[0],boost.inputs[0]); l.new(boost.outputs[0],p.inputs['Emission Strength'])

# 3: deepen the water at the timber edges; lower and soften ripple geometry.
water=bpy.data.materials['Teal river']; n=water.node_tree.nodes; l=water.node_tree.links; p=n.get('Principled BSDF')
geometry=n.new('ShaderNodeNewGeometry'); split=n.new('ShaderNodeSeparateXYZ'); l.new(geometry.outputs['Position'],split.inputs[0])
offset=n.new('ShaderNodeMath'); offset.operation='ADD'; offset.inputs[1].default_value=.29; l.new(split.outputs['Y'],offset.inputs[0])
absolute=n.new('ShaderNodeMath'); absolute.operation='ABSOLUTE'; l.new(offset.outputs[0],absolute.inputs[0])
scale=n.new('ShaderNodeMath'); scale.operation='MULTIPLY'; scale.inputs[1].default_value=13; l.new(absolute.outputs[0],scale.inputs[0])
r=ramp(n,[(.008,.115,.12),(.002,.035,.033)])
l.new(scale.outputs[0],r.inputs[0]); l.new(r.outputs[0],p.inputs['Base Color'])
p.inputs['Roughness'].default_value=.32
for o in scene.objects:
    if o.type=='CURVE' and o.name.startswith(('River current','Pool ripple')): o.data.bevel_depth*=.65
foam=bpy.data.materials['Water strokes'].node_tree.nodes.get('Principled BSDF')
foam.inputs['Base Color'].default_value=(.035,.15,.14,1)

# 4: restrained flowing grain layered over the broad existing wood tones.
wood=bpy.data.materials['Warm muted timber']; n=wood.node_tree.nodes; l=wood.node_tree.links; p=n.get('Principled BSDF')
old=p.inputs['Base Color'].links[0].from_socket
coord=n.new('ShaderNodeTexCoord'); wave=n.new('ShaderNodeTexWave'); wave.wave_type='BANDS'; wave.bands_direction='Y'
wave.inputs['Scale'].default_value=5; wave.inputs['Distortion'].default_value=6
wave.inputs['Detail'].default_value=3; wave.inputs['Detail Scale'].default_value=1.2; wave.inputs['Detail Roughness'].default_value=.55
l.new(coord.outputs['Generated'],wave.inputs['Vector'])
r=ramp(n,[(.48,.40,.31),(.98,.94,.85)])
r.color_ramp.elements[0].position=.38; r.color_ramp.elements[1].position=.57
l.new(wave.outputs['Color'],r.inputs[0])
mix=n.new('ShaderNodeMixRGB'); mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=.22
l.new(old,mix.inputs[1]); l.new(r.outputs[0],mix.inputs[2]); l.new(mix.outputs[0],p.inputs['Base Color'])

bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_material_refinement.blend'))
scene.render.filepath=os.path.join(OUT,'board_with_cards.png'); bpy.ops.render.render(write_still=True)
for o in scene.objects:
    if o.name.startswith(('Deck proxy','Layout card','Card face')): o.hide_render=True
scene.render.filepath=os.path.join(OUT,'board_environment.png'); bpy.ops.render.render(write_still=True)
print('RESULT: four visual refinements rendered; Godot unchanged',flush=True)
