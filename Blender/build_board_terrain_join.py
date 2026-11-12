"""Embed the wood perimeter in soil/moss above and rock shelves below."""
import bpy, math, random, os
from mathutils import Vector
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=os.path.join(HERE,'board_terrain_join'); os.makedirs(OUT,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE,'board_deck_trays','board_deck_trays.blend'))
scene=bpy.context.scene; scene.cycles.samples=40
rng=random.Random(605)
earth=bpy.data.materials['Forest soil']; bark=bpy.data.materials['Tree bark']
moss=[bpy.data.materials['Moss '+str(i)] for i in range(3)]
stone=[bpy.data.materials['Basalt '+str(i)] for i in range(3)]

def mesh_object(name,verts,faces,materials):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); scene.collection.objects.link(o)
    for m in materials: mesh.materials.append(m)
    return o

def ribbon(name,upper,materials):
    # Continuous terrain bed hides the old straight wooden sidewall.
    verts=[]; count=65
    for i in range(count):
        x=-4.12+i*8.24/(count-1)
        wave=.027*math.sin(x*6)+.017*math.sin(x*13)
        if upper:
            inside=-2.275+wave; outside=-2.55
            heights=(.068,.11)
        else:
            inside=1.73+wave; outside=1.86+.035*math.sin(x*9)
            # Keep the shallow deck pocket at x~2.8 clear.
            if 2.35<x<3.25: inside=max(inside,1.77)
            heights=(.045,.08)
        verts.extend([(x,inside,heights[0]),(x,outside,heights[1]),(x,inside,-.16),(x,outside,-.16)])
    faces=[]
    for i in range(count-1):
        a=i*4; b=a+4
        faces.extend([(a,b,b+1,a+1),(a+2,b+2,b,a),(a+1,b+1,b+3,a+3)])
    o=mesh_object(name,verts,faces,materials)
    for face in o.data.polygons: face.material_index=rng.randrange(len(materials))

def rock(name,x,y,rx,ry,height,material):
    count=7; outline=[]
    for j in range(count):
        a=j*math.tau/count; r=rng.uniform(.82,1.12)
        outline.append((x+rx*r*math.cos(a),y+ry*r*math.sin(a)))
    verts=[(px,py,-.025) for px,py in outline]+[(px,py,height+rng.uniform(-.012,.012)) for px,py in outline]
    faces=[tuple(range(count,2*count))]+[(j,(j+1)%count,(j+1)%count+count,j+count) for j in range(count)]
    o=mesh_object(name,verts,faces,[material]); mod=o.modifiers.new('Soft shelf edges','BEVEL'); mod.width=.012; mod.segments=2
    o.modifiers.new('Shelf normals','WEIGHTED_NORMAL')

# The forest bank and rear ground are one surface, built below. A separate
# raised ribbon here produced a straight exposed rear edge inside the grass.
ribbon('Continuous basalt bed',False,[stone[0]])
for i in range(29):
    x=-4.0+i*.285+rng.uniform(-.09,.09)
    # Low moss patches lap over the wood edge in uneven groups.
    y=-2.31+rng.uniform(-.045,.04)
    rock('Moss meeting wood',x,y,rng.uniform(.11,.24),rng.uniform(.055,.115),rng.uniform(.072,.11),moss[i%3])

for i in range(26):
    x=-4.02+i*.32+rng.uniform(-.07,.07)
    if 2.30<x<3.33: continue
    # Wide, shallow ledges cross the join rather than sitting in a separate row.
    y=1.80+rng.uniform(-.025,.07)
    rock('Basalt shelf meeting wood',x,y,rng.uniform(.17,.29),rng.uniform(.10,.17),rng.uniform(.08,.13),stone[i%3])
    if i%3==0:
        rock('Small edge fragment',x+.12,1.72,.07,.05,.075,stone[(i+1)%3])

# End caps connect perimeter treatments into the existing side scenery.
for side in [-1,1]:
    for j in range(5):
        rock('Forest corner soil',side*4.015,-2.26+j*.12,.10,.13,.09,moss[j%3])
        rock('Volcanic corner shelf',side*4.015,1.70-j*.12,.11,.14,.10,stone[j%3])

# Carry the forest beyond the camera frustum, preserving its board-facing edge.
land=bpy.data.objects['Forest land']
bpy.data.objects.remove(land,do_unlink=True)
ground_verts=[]; ground_faces=[]
nx=81; ny=41
for j in range(ny):
    t=j/(ny-1)
    for i in range(nx):
        x=-5.2+10.4*i/(nx-1)
        front=-2.275+.027*math.sin(x*6)+.017*math.sin(x*13)
        y=front*(1-t)-7.0*t
        z=.052+.016*math.exp(-t*12)+.007*math.sin(x*2.4)*math.sin(t*9)
        ground_verts.append((x,y,z))
for j in range(ny-1):
    for i in range(nx-1):
        a=j*nx+i
        ground_faces.append((a,a+nx,a+nx+1,a+1))
ground=mesh_object('Unified forest ground and bank',ground_verts,ground_faces,[earth])
for face in ground.data.polygons: face.use_smooth=True
extension_rng=random.Random(871)
for i in range(100):
    x=extension_rng.uniform(-4.7,4.7)
    y=extension_rng.uniform(-6.7,-3.03)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(x,y,.04))
    o=bpy.context.object; o.name='Continuing forest ground'
    o.scale=(extension_rng.uniform(.18,.45),extension_rng.uniform(.17,.38),extension_rng.uniform(.04,.13))
    o.data.materials.append(moss[i%3])

# A continuous lava pool fills the negative space between rock islands.
# This partly occluded plate exposed only two sharp tips in the central lava gap.
fragment=bpy.data.objects.get('Basalt plate.033')
if fragment: bpy.data.objects.remove(fragment,do_unlink=True)
for o in list(scene.objects):
    if o.name.startswith(('Narrow red fissure','Branching fissure','Connected hot fracture','Continuous basalt bed')):
        bpy.data.objects.remove(o,do_unlink=True)
lava=bpy.data.materials['Red fissures']
mesh_object('Continuous red lava under rocks',[(-5.2,1.70,.006),(5.2,1.70,.006),(5.2,4.0,.006),(-5.2,4.0,.006)],[(0,1,2,3)],[lava])

# Solid cooled terrain meets the wood; molten gaps begin farther down.
# The front edge tucks under the slab, and the lower boundary winds between rocks.
bank_verts=[]; bank_faces=[]
for i in range(101):
    x=-5.2+10.4*i/100
    lower=2.04+.055*math.sin(x*3.7)+.035*math.sin(x*9.3)
    bank_verts.extend([(x,1.67,.045),(x,1.82,.052),(x,lower,.028),(x,lower,-.025)])
for i in range(100):
    a=i*4; b=a+4
    bank_faces.extend([(a,b,b+1,a+1),(a+1,b+1,b+2,a+2),(a+2,b+2,b+3,a+3)])
cooled=mesh_object('Solid dark terrain connecting wood',bank_verts,bank_faces,[stone[0]])
for face in cooled.data.polygons: face.use_smooth=True

# Screen-right is negative world X. Remove the old overlapping branch generations
# and rebuild this tree as one explicit connected hierarchy.
for o in list(scene.objects):
    if o.location.x < -3.7 and o.location.y < -1.7:
        is_bark=any(m and m.name=='Tree bark' for m in o.data.materials) if o.type=='MESH' else False
        if is_bark or o.name.startswith(('Layered foliage','Tree crown','Leaf cluster')):
            bpy.data.objects.remove(o,do_unlink=True)
def limb(name,a,b,r1,r2):
    delta=Vector(b)-Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=9,radius1=r1,radius2=r2,depth=delta.length,location=(Vector(a)+Vector(b))/2)
    o=bpy.context.object; o.name=name
    o.rotation_euler=delta.to_track_quat('Z','Y').to_euler(); o.data.materials.append(bark)
base=Vector((-4.18,-2.14,.04)); fork=base+Vector((.025,-.015,.38)); tip=fork+Vector((-.035,-.02,.31))
limb('Connected tree trunk',base,fork,.075,.052)
limb('Connected upper trunk',fork,tip,.052,.024)
foliage_rng=random.Random(117)
for j,offset in enumerate([(.23,-.08,.17),(-.19,.04,.20),(.02,-.24,.23)]):
    end=fork+Vector(offset)
    limb('Branch attached at trunk fork',fork,end,.037,.012)
    for k in range(5):
        pos=end+Vector((foliage_rng.uniform(-.10,.10),foliage_rng.uniform(-.09,.09),foliage_rng.uniform(-.015,.09)))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=pos)
        o=bpy.context.object; o.name='Connected tree foliage'; o.scale=(.15,.13,.10)
        o.data.materials.append(bpy.data.materials['Canopy '+str((j+k)%3)])
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=tip)
o=bpy.context.object; o.name='Tree top foliage'; o.scale=(.18,.15,.12); o.data.materials.append(bpy.data.materials['Canopy 1'])

bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_terrain_join.blend'))
scene.render.filepath=os.path.join(OUT,'terrain_join_with_cards.png'); bpy.ops.render.render(write_still=True)
for o in scene.objects:
    if o.name.startswith(('Deck proxy','Layout card','Card face')): o.hide_render=True
scene.render.filepath=os.path.join(OUT,'terrain_join_environment.png'); bpy.ops.render.render(write_still=True)
print('RESULT: connected terrain perimeter rendered; Godot unchanged',flush=True)
