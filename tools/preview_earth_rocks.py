import bpy
from mathutils import Vector, Matrix
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
mat=bpy.data.materials.new('ShapePreview');mat.diffuse_color=(0.35,0.23,0.13,1);mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(0.35,0.23,0.13,1)
for i in range(5):
 before=set(bpy.context.scene.objects)
 bpy.ops.import_scene.fbx(filepath=str(root/f'assets/effects/earth/Free_Rock_Model_{i}.fbx'))
 meshes=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
 for ob in meshes:
  world=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=world
  ob.data.transform(ob.matrix_world);ob.matrix_world=Matrix.Identity(4)
  pts=[v.co.copy() for v in ob.data.vertices]; lo=Vector([min(p[k] for p in pts) for k in range(3)]);hi=Vector([max(p[k] for p in pts) for k in range(3)])
  fac=1.4/max(hi-lo);center=(lo+hi)*.5
  ob.scale=Vector((fac,fac,fac));ob.location=Vector(((i-2)*1.9,0,(hi.z-lo.z)*fac*.5))-center*fac
  ob.data.materials.clear();ob.data.materials.append(mat)
  print('ROCK',i,'dimensions',list(hi-lo))
 bpy.ops.object.text_add(location=((i-2)*1.9,-.9,.02));text=bpy.context.object;text.data.body=str(i);text.data.align_x='CENTER';text.data.size=.35
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor_mat=bpy.data.materials.new('Floor');floor_mat.diffuse_color=(.08,.09,.11,1);floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(0,-10,7));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=10
bpy.ops.object.light_add(type='AREA',location=(-2,-4,7));bpy.context.object.data.energy=1700;bpy.context.object.data.size=7
scene=bpy.context.scene;scene.camera=cam;scene.world.color=(.2,.2,.2);scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=1200;scene.render.resolution_y=400;scene.render.resolution_percentage=100;scene.render.filepath=str(root/'references/earth_rock_shapes.png');bpy.ops.render.render(write_still=True)
