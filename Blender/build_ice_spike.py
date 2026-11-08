"""Build one editable, downward-facing ice projectile and a studio preview.
Blender Z is up; the impact tip is at the origin, pointing down (-Z).
Only IceSpike is exported to GLB (Godot: tip at origin, pointing -Y).
"""
import math
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
HEIGHT = 1.65
RADIUS = 0.23
SIDES = 7
PREVIEW = ROOT / 'references/ice_spike_preview.png'

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
# Uneven cross sections keep the silhouette crystalline rather than machined.
profile = [1.0, .88, 1.04, .92, 1.08, .86, .97]
rings = [(.22, .27, .018, -.012), (.66, .76, -.012, .008),
         (1.30, 1.0, 0, 0), (1.54, .71, .012, -.014)]
verts = [(0, 0, 0)]
for z, radius, dx, dy in rings:
    for i in range(SIDES):
        angle = math.tau * i / SIDES
        # A sloping crown with short bevel faces.
        crown = .045 * math.cos(angle + .4) if z > 1.5 else 0
        verts.append((math.cos(angle)*RADIUS*radius*profile[i]+dx,
                      math.sin(angle)*RADIUS*radius*profile[i]+dy, z+crown))
verts.append((.018, -.018, HEIGHT))
faces = []
for i in range(SIDES):
    j = (i+1) % SIDES
    faces.append((0, 1+j, 1+i))
for ring in range(len(rings)-1):
    for i in range(SIDES):
        j=(i+1)%SIDES
        a,b=1+ring*SIDES+i,1+ring*SIDES+j
        c,d=b+SIDES,a+SIDES
        # Alternate broad walls and a few diagonal fracture facets.
        if ring == 1 and i in (1,4):
            faces.extend([(a,b,d),(b,c,d)])
        else:
            faces.append((a,b,c,d))
for i in range(SIDES):
    faces.append((1+3*SIDES+i,1+3*SIDES+(i+1)%SIDES,len(verts)-1))
mesh=bpy.data.meshes.new('IceSpike_FacetedMesh')
mesh.from_pydata(verts,[],faces);mesh.update()
spike=bpy.data.objects.new('IceSpike',mesh)
bpy.context.collection.objects.link(spike)
# Consistent outward normals, flat facets, and a closed volume for later fragments.
bpy.context.view_layer.objects.active=spike;spike.select_set(True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
# Tutorial settings verified from the user's downloaded clip.
def linear_hex(value):
    channels=[int(value[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in channels)+(1,)
mat=bpy.data.materials.new('Tutorial Frosted Ice');mat.use_nodes=True
nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
output=nodes.new('ShaderNodeOutputMaterial');output.location=(850,100)
frost=nodes.new('ShaderNodeBsdfPrincipled');frost.label='Pale frost #D4EDFF';frost.location=(150,0)
clear=nodes.new('ShaderNodeBsdfPrincipled');clear.label='Clear blue #51ACFF';clear.location=(150,-380)
for shader,color,roughness in [(frost,'D4EDFF',1.0),(clear,'51ACFF',.2)]:
    shader.inputs['Base Color'].default_value=linear_hex(color)
    shader.inputs['Roughness'].default_value=roughness
    shader.inputs['Transmission Weight'].default_value=1.0
    shader.inputs['IOR'].default_value=1.5
mat.diffuse_color=linear_hex('D4EDFF')
tex=nodes.new('ShaderNodeTexCoord');tex.location=(-850,300)
noise=nodes.new('ShaderNodeTexNoise');noise.location=(-650,300)
noise.inputs['Scale'].default_value=15
noise.inputs['Detail'].default_value=10
noise.inputs['Roughness'].default_value=.8
noise.inputs['Lacunarity'].default_value=2
links.new(tex.outputs['Object'],noise.inputs['Vector'])
ramp=nodes.new('ShaderNodeValToRGB');ramp.location=(-400,300)
ramp.color_ramp.interpolation='LINEAR';ramp.color_ramp.elements[0].position=0;ramp.color_ramp.elements[1].position=.751
links.new(noise.outputs['Fac'],ramp.inputs['Fac'])
curve=nodes.new('ShaderNodeRGBCurve');curve.location=(-100,400)
curve.mapping.initialize();combined=curve.mapping.curves[3]
combined.points[0].location=(0,0);combined.points[-1].location=(1,0)
combined.points.new(.5025,.6821);curve.mapping.update()
links.new(ramp.outputs['Color'],curve.inputs['Color'])
mix=nodes.new('ShaderNodeMixShader');mix.location=(600,100)
links.new(curve.outputs['Color'],mix.inputs[0]);links.new(frost.outputs['BSDF'],mix.inputs[1]);links.new(clear.outputs['BSDF'],mix.inputs[2]);links.new(mix.outputs[0],output.inputs['Surface'])
spike.data.materials.append(mat)
spike['purpose']='Single falling Ice damage projectile; tip is local origin'
spike['impact_direction']='Blender -Z / Godot -Y'
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/effects/ice/ice_spike.glb'),use_selection=True,export_format='GLB')
# Separate preview collection keeps staging easy to hide while editing the mesh.
studio=bpy.data.collections.new('Preview Studio');bpy.context.scene.collection.children.link(studio)
def to_studio(obj):
    for collection in list(obj.users_collection):collection.objects.unlink(obj)
    studio.objects.link(obj)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.12))
floor=bpy.context.object;floor.name='StudioFloor';to_studio(floor)
fm=bpy.data.materials.new('StudioSlate');fm.diffuse_color=(.025,.04,.06,1);floor.data.materials.append(fm)
for name,location,power,size,color in [
    ('Key', (2,-3,3),650,2.5,(.80,.93,1)),
    ('Rim', (-2,1,2.3),900,2,(.36,.72,1)),
    ('Fill', (1,2,1),400,1.8,(1,1,1))]:
    bpy.ops.object.light_add(type='AREA',location=location)
    light=bpy.context.object;light.name=name;to_studio(light)
    light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.data.color=color
    light.rotation_euler=(Vector((0,0,.85))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2.5,-4,2.0))
camera=bpy.context.object;to_studio(camera)
camera.rotation_euler=(Vector((0,0,.82))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=2.15
scene=bpy.context.scene;scene.camera=camera
scene.world.color=(.12,.12,.12)
scene.render.engine='CYCLES';scene.cycles.samples=48
scene.render.resolution_x=700;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.render.filepath=str(PREVIEW)
bpy.ops.object.select_all(action='DESELECT');spike.select_set(True);bpy.context.view_layer.objects.active=spike
# Open Blender with the actual asset selected and framed.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=Vector((0,0,.82))
            area.spaces.active.region_3d.view_distance=2.8
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Blender/ice_spike.blend'))
bpy.ops.render.render(write_still=True)
print('ICE_SPIKE: vertices=%d faces=%d; tip=(0,0,0); height=%.2f' % (len(verts),len(faces),HEIGHT))
