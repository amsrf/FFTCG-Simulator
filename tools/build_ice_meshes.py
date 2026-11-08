import bpy, json, math
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
out=root/'assets/effects/ice'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
mat=bpy.data.materials.new('Ice'); mat.diffuse_color=(.38,.78,.94,1); mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(.38,.78,.94,1); bs.inputs['Metallic'].default_value=.25; bs.inputs['Roughness'].default_value=.22
sources=[]
for filename,key in [(None,'crystal'),('SM_GroundIce01','ground')]:
 if key == 'crystal':
  # Broad irregular hexagonal prism: long planar walls and a short,
  # oblique termination rather than a cone tapering all the way to a tip.
  section=[(-.15,-.07),(-.065,-.13),(.11,-.11),(.155,.025),(.045,.125),(-.12,.10)]
  verts=[(x,y,0) for x,y in section]
  verts += [(x*.96+.018,y*.96-.012,.80 + x*.20) for x,y in section]
  verts += [(x*.56+.035,y*.56-.018,.94+x*.40-y*.18) for x,y in section]
  faces=[tuple(reversed(range(6)))]
  for layer in range(2):
   for i in range(6):
    j=(i+1)%6;faces.append((layer*6+i,layer*6+j,(layer+1)*6+j,(layer+1)*6+i))
  faces.append(tuple(range(12,18)))
  mesh=bpy.data.meshes.new('BroadFacetedCrystal');mesh.from_pydata(verts,[],faces);mesh.update()
  ob=bpy.data.objects.new('Crystal',mesh);bpy.context.collection.objects.link(ob)
 else:
  before=set(bpy.context.scene.objects)
  bpy.ops.import_scene.fbx(filepath=str(root/'assets/effects/earth/ice'/f'{filename}.fbx'))
  ob=next(o for o in bpy.context.scene.objects if o not in before and o.type=='MESH')
  ob.data.transform(ob.matrix_world); ob.matrix_world.identity()
  pts=[v.co.copy() for v in ob.data.vertices]; low=Vector([min(p[k] for p in pts) for k in range(3)]); high=Vector([max(p[k] for p in pts) for k in range(3)])
  size=high-low; factor=1/max(size.x,size.y); center=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
  for v in ob.data.vertices:v.co=(v.co-center)*factor
 ob.data.calc_loop_triangles()
 vertices=[]
 for tri in ob.data.loop_triangles:
  for idx in reversed(tri.vertices):  # Godot uses clockwise front faces.
   p=ob.data.vertices[idx].co; vertices.extend([p.x,p.z,-p.y])
 (out/f'{key}_mesh.json').write_text(json.dumps(vertices))
 ob.data.materials.clear();ob.data.materials.append(mat);ob.hide_render=True;sources.append(ob)
# Same arrangement as the Godot first pass, around a field-size card.
placements=[(-.19,-.22,.67),(.18,-.20,.82),(-.21,.03,.92),(.20,.07,.72),(-.14,.24,.76),(.15,.25,.96)]
for i,(x,z,h) in enumerate(placements):
 ob=sources[0].copy();ob.data=sources[0].data.copy();bpy.context.collection.objects.link(ob);ob.hide_render=False;ob.location=(x,-z,0);ob.scale=(1.25,1.25,h);ob.rotation_euler.z=i*1.1
base=sources[1];base.hide_render=False;base.scale=(.95,.95,.5)
bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,.018));card=bpy.context.object;card.scale=(.411,.595,.012)
cardmat=bpy.data.materials.new('Card placeholder');cardmat.diffuse_color=(.12,.07,.035,1);card.data.materials.append(cardmat)
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.location.z=-.005
fm=bpy.data.materials.new('Floor');fm.diffuse_color=(.055,.065,.085,1);floor.data.materials.append(fm)
bpy.ops.object.camera_add(location=(1.5,-2,2.5));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,.3))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.8
scene=bpy.context.scene;scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=(1,-2,4));bpy.context.object.data.energy=450;bpy.context.object.data.size=3
scene.world.color=(.22,.22,.22);scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
bpy.ops.wm.save_as_mainfile(filepath=str(root/'Blender/ice_crystals.blend'))
scene.render.filepath=str(root/'references/ice_cluster_preview.png');bpy.ops.render.render(write_still=True)
