"""Export preview geometry with camera-projected baked appearance; no import-cache dependency."""
import bpy, os, struct, shutil, sys, math
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view
HERE=os.path.dirname(os.path.abspath(__file__))
ROOT=os.path.dirname(HERE); OUT=os.path.join(ROOT,'assets','board'); os.makedirs(OUT,exist_ok=True)
SOURCE=os.path.join(HERE,'board_landmarks')
bpy.ops.wm.open_mainfile(filepath=os.path.join(SOURCE,'board_landmarks.blend'))
scene=bpy.context.scene
seat_two='--seat2' in sys.argv
suffix='_seat2' if seat_two else ''
if seat_two:
    # The play surface/recesses use local zone coordinates. Swap only the
    # surrounding biomes about the centre of the playing surface.
    pivot=Vector((0,-.30,0))
    turn=Matrix.Translation(pivot) @ Matrix.Rotation(math.pi,4,'Z') @ Matrix.Translation(-pivot)
    fixed_prefixes=('Forest single wood slab','Volcanic single wood slab','Forest recessed wooden floor','Volcanic recessed wooden floor',
        'Slab edge split','Split branch','Slab grain accent','Wood knot','Grain around knot')
    for o in scene.objects:
        if o.name.startswith(('Deck proxy','Layout card','Card face')):
            o.hide_render=True
        elif o.type in {'MESH','CURVE'} and not o.name.startswith(fixed_prefixes):
            o.matrix_world=turn @ o.matrix_world
    if '--geometry-only' not in sys.argv:
        scene.render.filepath=os.path.join(OUT,'board_appearance_seat2.png')
        scene.cycles.samples=40
        bpy.ops.render.render(write_still=True)
for o in list(scene.objects):
    if o.type in {'CAMERA','LIGHT'} or o.name.startswith(('Deck proxy','Layout card','Card face')):
        if o!=scene.camera: bpy.data.objects.remove(o,do_unlink=True)
deps=bpy.context.evaluated_depsgraph_get()
def export_mesh(stem,river):
    vertices=[]; indices=[]
    for o in list(scene.objects):
        if o.type not in {'MESH','CURVE'}: continue
        if o.name.startswith(('River current','Pool ripple')): continue
        if o.name.startswith('Continuous river') != river: continue
        evaluated=o.evaluated_get(deps); mesh=evaluated.to_mesh(); mesh.calc_loop_triangles()
        offset=len(vertices)
        for v in mesh.vertices:
            p=o.matrix_world@v.co
            uv=world_to_camera_view(scene,scene.camera,p)
            vertices.append((p.x,p.z,-p.y,uv.x,1-uv.y))
        for tri in mesh.loop_triangles:
            indices.extend(offset+i for i in reversed(tri.vertices))
        evaluated.to_mesh_clear()
    with open(os.path.join(OUT,stem+suffix+'.bin'),'wb') as f:
        f.write(struct.pack('<4sII',b'BRD1',len(vertices),len(indices)))
        for v in vertices: f.write(struct.pack('<5f',*v))
        f.write(struct.pack('<%dI'%len(indices),*indices))
    print('RESULT:',stem,len(vertices),'vertices,',len(indices)//3,'triangles')
export_mesh('board_mesh',False)
export_mesh('river_mesh',True)
if not seat_two:
    shutil.copyfile(os.path.join(SOURCE,'board_environment.png'),os.path.join(OUT,'board_appearance.png'))
