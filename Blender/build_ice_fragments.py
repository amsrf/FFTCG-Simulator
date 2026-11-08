"""Cut the approved crystal into closed chunks; export Godot-ready triangle data."""
import bpy, bmesh, json, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Blender/ice_spike.blend'))
spike=bpy.data.objects['IceSpike']
def cut(mesh, point, normal, clear_outer):
 bm=bmesh.new();bm.from_mesh(mesh)
 result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,plane_co=point,plane_no=normal,clear_outer=clear_outer,clear_inner=not clear_outer)
 edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 if edges:
  filled=bmesh.ops.holes_fill(bm,edges=edges,sides=0)
  for face in filled["faces"]:face.material_index=1
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 out=bpy.data.meshes.new('IceChunk');bm.to_mesh(out);bm.free();return out
chunks=[spike.data.copy()]
# Eight height bands and eight radial sectors produce 64 smaller fitted shards.
planes=[((0,0,z),(.04*(-1)**i,.03,1)) for i,z in enumerate([.18,.38,.60,.82,1.04,1.26,1.46])]
planes += [((0,0,0),(math.cos(i*math.pi/4+.12),math.sin(i*math.pi/4+.12),0)) for i in range(4)]
for point,normal in planes:
 next_chunks=[]
 for mesh in chunks:
  distances=[(v.co-Vector(point)).dot(Vector(normal)) for v in mesh.vertices]
  if min(distances)<-.0001 and max(distances)>.0001:
   next_chunks.extend([cut(mesh,point,normal,side) for side in (True,False)])
  else:next_chunks.append(mesh)
 chunks=next_chunks

def godot(v):return [v.x,v.z,-v.y]
def triangles(mesh,center):
 mesh.calc_loop_triangles();out=[]
 for tri in mesh.loop_triangles:
  for i in reversed(tri.vertices):out.extend(godot(mesh.vertices[i].co-center))
 return out
# Face adjacency requires a shared area, not merely a touching corner/edge.
def shared_area(a,b):
 common=[]
 for v in a.vertices:
  if any((v.co-w.co).length < .00002 for w in b.vertices):common.append(v.co)
 if len(common)<3:return False
 return any((common[i]-common[0]).cross(common[j]-common[0]).length > .0000001 for i in range(1,len(common)) for j in range(i+1,len(common)))
neighbors=[[] for _ in chunks]
for i in range(len(chunks)):
 for j in range(i+1,len(chunks)):
  if shared_area(chunks[i],chunks[j]):neighbors[i].append(j);neighbors[j].append(i)
seen={0};pending=[0]
while pending:
 for neighbor in neighbors[pending.pop()]:
  if neighbor not in seen:seen.add(neighbor);pending.append(neighbor)
assert len(seen)==len(chunks), 'Fracture adjacency graph must be connected'
payload={'spike':triangles(spike.data,Vector()),'fragments':[]}

collection=bpy.data.collections.new('Ice Fragments');bpy.context.scene.collection.children.link(collection)
bpy.ops.object.select_all(action='DESELECT')
for i,mesh in enumerate(chunks):
 center=sum((v.co for v in mesh.vertices),Vector())/len(mesh.vertices)
 vertices=triangles(mesh,center)
 internal=[int(mesh.polygons[tri.polygon_index].material_index==1) for tri in mesh.loop_triangles]
 payload['fragments'].append({'center':godot(center),'vertices':vertices,'internal':internal,'neighbors':neighbors[i]})
 for v in mesh.vertices:v.co-=center
 obj=bpy.data.objects.new('IceFragment_%02d'%i,mesh);collection.objects.link(obj);obj.location=center
 if len(mesh.materials)==0:mesh.materials.append(spike.data.materials[0])
 obj.select_set(True)
(ROOT/'assets/effects/ice/ice_projectile_meshes.json').write_text(json.dumps(payload))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/effects/ice/ice_fragments.glb'),use_selection=True,export_format='GLB')
spike.hide_render=True;spike.hide_set(True)
# Exploded view makes the fitted fracture pieces inspectable.
for obj in collection.objects:
 obj.location.x*=1.9;obj.location.y*=1.9;obj.location.z=(obj.location.z-.82)*1.15+.82
bpy.context.scene.render.filepath=str(ROOT/'references/ice_fragments_preview.png')
bpy.context.scene.cycles.samples=24
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Blender/ice_fragments.blend'))
bpy.ops.render.render(write_still=True)
print('FRAGMENTS',len(chunks))
