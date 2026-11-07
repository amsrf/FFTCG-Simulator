import bpy
from mathutils import Vector, Matrix
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=r'C:/Users/KABUM/Desktop/TCG Project/TCG-Simulator-on-Godot/assets/effects/earth/Free_Rock_Model_3.fbx')
for ob in bpy.context.scene.objects:
 if ob.type=='MESH':
  pts=[ob.matrix_world@Vector(c) for c in ob.bound_box]
  print('ROCK_INFO',ob.name,'dimensions',list(ob.dimensions),'bounds',[(min(p[i] for p in pts),max(p[i] for p in pts)) for i in range(3)],'materials',[m.name for m in ob.data.materials])

# Assembly preview only; Godot keeps the original FBX instances editable.
import math
from pathlib import Path
root = Path(__file__).resolve().parents[1]
rock = next(ob for ob in bpy.context.scene.objects if ob.type == 'MESH')
mat = bpy.data.materials.new('Arid Rock Preview'); mat.use_nodes = True
nodes = mat.node_tree.nodes; shader = nodes.get('Principled BSDF')
tex = nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images.load(str(root / 'assets/effects/earth/textures/Rocks_N_Boulders_Free_Arid.tga'))
mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color']); shader.inputs['Roughness'].default_value = 0.88
rock.data.materials.clear(); rock.data.materials.append(mat)
world_matrix = rock.matrix_world.copy(); rock.parent = None; rock.matrix_world = world_matrix
rock.scale *= 0.55; rock.location = (0.024,-0.09,0.49)
upper=rock.copy();upper.data=rock.data.copy();scene_collection = bpy.context.scene.collection
scene_collection.objects.link(upper)
upper.location=(-0.024,0.09,1.23);upper.rotation_euler.z += math.radians(175)
# Editable base stones match the Godot scene positions and sizes.
pieces=[(2,.47,.12,.23,.45,12),(0,.19,.08,.47,.30,63),(1,-.22,.10,.47,.36,122),(2,-.49,.10,.16,.43,174),(1,-.46,.10,-.23,.38,220),(0,-.14,.07,-.49,.29,267),(2,.23,.11,-.43,.40,312),(1,.51,.09,-.14,.34,348)]
for idx,(model,x,y,z,size,yaw) in enumerate(pieces):
 before=set(bpy.context.scene.objects)
 bpy.ops.import_scene.fbx(filepath=str(root/f'assets/effects/earth/Free_Rock_Model_{model}.fbx'))
 ob=next(o for o in bpy.context.scene.objects if o not in before and o.type=='MESH')
 matrix=ob.matrix_world.copy();ob.parent=None;ob.data.transform(matrix);ob.matrix_world=Matrix.Identity(4)
 pts=[v.co.copy() for v in ob.data.vertices];lo=Vector([min(p[k] for p in pts) for k in range(3)]);hi=Vector([max(p[k] for p in pts) for k in range(3)])
 center=(lo+hi)*.5;factor=1/max(hi-lo)
 for v in ob.data.vertices:v.co=(v.co-center)*factor
 ob.scale=(size,size*1.1,size*.85);ob.rotation_euler=(math.radians((idx%3-1)*12),-math.radians((idx%2*2-1)*9),math.radians(yaw));ob.location=(x,-z,y)
 ob.data.materials.clear();ob.data.materials.append(mat)
# Ground fracture geometry previews the procedural Godot mark.
def fracture_hash(v):return (math.sin(v*127.1+2*31.7)*43758.5453)%1
crack_mat=bpy.data.materials.new('BlackFractures');crack_mat.diffuse_color=(.008,.006,.004,1)
verts=[];faces=[]
def strip(a,b,width):
 delta=b-a;side=Vector((-delta.y,delta.x)).normalized()*width*.5
 start=len(verts)
 for point in [a-side,b-side,b+side,a+side]:verts.append((point.x*1.25,point.y*1.25,.008))
 faces.append((start,start+1,start+2,start+3))
def junction(sector,ring):
 index=sector%10;angle=index*math.tau/10+(fracture_hash(index+1)-.5)*.32+(fracture_hash(index+ring*19+5)-.5)*.18
 radius=.28+ring*.205+(fracture_hash(index+ring*31+21)-.5)*.11
 return Vector((math.cos(angle),math.sin(angle)))*radius
for i in range(10):
 a,b,c,d=[junction(i,r) for r in range(4)]
 for v,w,width in [(a,b,.016),(b,c,.012),(c,d,.006)]:strip(v,w,width)
 strip(b,junction(i+1,1),.012)
 if fracture_hash(i+150)>.24:strip(c,junction(i+1,2),.009)
mesh=bpy.data.meshes.new('GroundCracks');mesh.from_pydata(verts,[],faces);mesh.materials.append(crack_mat);obj=bpy.data.objects.new('GroundCracks',mesh);bpy.context.scene.collection.objects.link(obj)
bpy.ops.mesh.primitive_plane_add(size=200)
floor=bpy.context.object
floor_mat=bpy.data.materials.new('Ground');floor_mat.diffuse_color=(0.09,0.1,0.12,1);floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(3.2,-4.2,3.0));camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,0.8))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=3.2
scene=bpy.context.scene;scene.camera=camera
for obj in scene.objects:
 print('PREVIEW_OBJECT', obj.name, obj.type, list(obj.location), obj.hide_render)
bpy.ops.object.light_add(type='AREA',location=(1,-3,5));bpy.context.object.data.energy=600;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=4
scene.world.color=(0.18,0.18,0.18);scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.filepath=str(root/'references/earth_totem_assembly_preview.png');bpy.ops.render.render(write_still=True)
