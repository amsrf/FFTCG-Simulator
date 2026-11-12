"""Composed corner landmarks, varied volcanic masses and framed river entrances."""
import bpy, os, math, random
from mathutils import Vector
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(HERE,'board_landmarks'); os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE,'board_material_refinement','board_material_refinement.blend'))
scene=bpy.context.scene; scene.cycles.samples=48
rng=random.Random(818)
stone=[bpy.data.materials['Basalt '+str(i)] for i in range(3)]
moss=[bpy.data.materials['Moss '+str(i)] for i in range(3)]
bank=bpy.data.materials['Riverbank stone']

def block(name,pos,size,material,angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
    o=bpy.context.object; o.name=name; o.dimensions=size; o.rotation_euler.z=angle
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(material)
    bevel=o.modifiers.new('Weathered edges','BEVEL'); bevel.width=.035; bevel.segments=2
    o.modifiers.new('Stone normals','WEIGHTED_NORMAL')
    return o

def boulder(name,pos,size,material):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=pos)
    o=bpy.context.object; o.name=name
    for v in o.data.vertices:
        v.co*=rng.uniform(.88,1.08)
    o.scale=size; o.rotation_euler.z=rng.random()*math.tau; o.data.materials.append(material)
    return o

def basalt_column(name,pos,radius,height,lean):
    count=6; verts=[]
    for z in [0,height]:
        for i in range(count):
            a=math.tau*i/count
            verts.append((pos[0]+radius*math.cos(a)+lean*z,pos[1]+radius*math.sin(a),pos[2]+z+(rng.uniform(-.06,.06) if z else 0)))
    faces=[tuple(range(count,2*count))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); scene.collection.objects.link(o)
    for m in stone: mesh.materials.append(m)
    for f in mesh.polygons: f.material_index=f.index%3
    bevel=o.modifiers.new('Chipped column edges','BEVEL'); bevel.width=.018; bevel.segments=2
    o.modifiers.new('Column normals','WEIGHTED_NORMAL')

# Lower right in the seat-one view, well outside the deck and damage footprints.
# A broken basalt outcrop rather than a new gameplay-looking ornament.
for x,y,r,h,lean in [(-3.53,1.92,.23,.30,-.12),(-3.88,2.03,.25,.40,.09),(-4.17,1.85,.19,.24,-.14)]:
    basalt_column('Broken volcanic outcrop',(x,y,.025),r,h,lean)
for i in range(8):
    boulder('Outcrop fallen stone',(-3.80+rng.uniform(-.40,.40),2.14+rng.uniform(-.12,.12),.06),(.12,.09,.07),stone[i%3])

# Opposite corner: the remains of an old stone gateway, bedded into moss.
ruinmat=bank.copy(); ruinmat.name='Old forest masonry'
ruinmat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.18,.21,.135,1)
for x,y in [(3.15,-2.35),(3.74,-2.42)]:
    block('Ruin buried footing',(x,y,.08),(.37,.39,.16),ruinmat,.10)
    height=.24 if x<3.5 else .30
    block('Broken gateway pier',(x,y,.16+height/2),(.22,.24,height),ruinmat,.10)
    boulder('Moss across ruin footing',(x-.06,y+.08,.18),(.23,.18,.06),moss[2])
# A fallen lintel connects visibly to the footing, with moss over the joint.
block('Fallen gateway lintel',(3.48,-2.28,.115),(.72,.18,.16),ruinmat,-.18)
for i in range(6):
    boulder('Ruin moss',(3.0+i*.14,-2.28+rng.uniform(-.11,.06),.20),(.12,.10,.045),moss[i%3])

# Break the repeated small-stone pattern with a few broad masses and sparse debris.
for x,y,sx,sy,h in [(-2.4,2.29,.48,.30,.17),(.85,2.23,.57,.28,.15),(3.9,2.28,.42,.31,.20)]:
    boulder('Large cooled lava mass',(x,y,.035),(sx,sy,h),stone[1])
    for j in range(3):
        boulder('Mass edge debris',(x+sx*rng.uniform(-1.2,1.2),y+rng.uniform(-.23,.23),.035),(.085,.065,.05),stone[j%3])

# Side-only banks frame the open river; central water and damage cards remain clear.
for side in [-1,1]:
    for edge in [-1,1]:
        for j in range(3):
            x=side*(4.14+j*.23)
            y=-.29+edge*(.30+j*.08)
            material=bank if edge<0 else stone[1]
            boulder('River entrance bank',(x,y,.025),(.21,.16,.10+j*.012),material)
    # One low stone at the pool edge provides an identifiable foam/wake origin.
    boulder('River entrance water stone',(side*4.36,-.29+.18,.012),(.14,.10,.065),bank)

bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_landmarks.blend'))
scene.render.filepath=os.path.join(OUT,'board_with_cards.png'); bpy.ops.render.render(write_still=True)
for o in scene.objects:
    if o.name.startswith(('Deck proxy','Layout card','Card face')): o.hide_render=True
scene.render.filepath=os.path.join(OUT,'board_environment.png'); bpy.ops.render.render(write_still=True)
print('RESULT: landmarks and river entrance composition rendered',flush=True)
