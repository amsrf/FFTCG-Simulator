"""Standalone composition study. Does not modify Godot scenes.
Godot (x,y,z) maps to Blender (x,-z,y). Camera matches camera_rig.gd.
Run with Blender 4.4 --background --python this_file.py.
"""
import bpy, math, random, os
from mathutils import Vector

random.seed(24)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'board_slabs')
os.makedirs(OUT, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100
scene.world.color = (.16, .16, .16)
scene.view_settings.view_transform = 'AgX'

def mat(name, color, rough=.75, emission=0):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color, 1); m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

wood = mat('Warm muted timber', (.28, .15, .065))
n = wood.node_tree.nodes; l = wood.node_tree.links; p = n.get('Principled BSDF')
tex = n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value = 3
coord = n.new('ShaderNodeTexCoord'); mapping = n.new('ShaderNodeVectorMath'); mapping.operation = 'MULTIPLY'
mapping.inputs[1].default_value = (1.4, 65, 12)
l.new(coord.outputs['Generated'], mapping.inputs[0]); l.new(mapping.outputs[0], tex.inputs['Vector'])
ramp = n.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].color = (.075, .037, .017, 1)
ramp.color_ramp.elements[1].color = (.25, .145, .065, 1)
l.new(tex.outputs['Fac'], ramp.inputs[0]); l.new(ramp.outputs[0], p.inputs['Base Color'])
bump=n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.16; bump.inputs['Distance'].default_value=.015
l.new(tex.outputs['Fac'],bump.inputs['Height']); l.new(bump.outputs['Normal'],p.inputs['Normal'])
rim = mat('Dark timber edge', (.085, .047, .025))
earth = mat('Forest soil', (.095, .12, .045))
moss = [mat('Moss '+str(i), c) for i,c in enumerate([(.19,.27,.065),(.27,.34,.09),(.12,.20,.055)])]
leaves = [mat('Canopy '+str(i), c) for i,c in enumerate([(.035,.12,.022),(.085,.22,.035),(.19,.32,.055)])]
stone = [mat('Basalt '+str(i), c) for i,c in enumerate([(.018,.019,.024),(.028,.026,.031),(.047,.038,.035)])]
bank = mat('Riverbank stone', (.23,.25,.18))
trunk = mat('Tree bark', (.12,.07,.035))
lava = mat('Red fissures', (.48,.008,.001), emission=1.5)
water = mat('Teal river', (.008,.105,.115), .26)
foam = mat('Water strokes', (.08,.29,.27), .4)
grain = mat('Carved wood grain',(.075,.035,.016))
iron = mat('Aged iron pins',(.055,.05,.043),.5)
grass = mat('Grass blades',(.14,.26,.045))
for material in stone+[bank]:
    nodes=material.node_tree.nodes; links=material.node_tree.links; shader=nodes.get('Principled BSDF')
    noise=nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=8
    bump=nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=.3; bump.inputs['Distance'].default_value=.045
    links.new(noise.outputs['Fac'],bump.inputs['Height']); links.new(bump.outputs['Normal'],shader.inputs['Normal'])
proxies = []

def box(name, pos, size, material, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=2
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o

def rock(name, pos, scale, material, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=pos)
    o=bpy.context.object; o.name=name; o.scale=scale
    o.rotation_euler=(random.random()*.3,random.random()*.3,random.random()*6.28)
    for v in o.data.vertices:
        v.co *= random.uniform(.88,1.12)
    o.data.materials.append(material); return o

def line(name, pts, material, width):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.bevel_depth=width; c.bevel_resolution=2
    s=c.splines.new('POLY'); s.points.add(len(pts)-1)
    for v,pt in zip(s.points,pts): v.co=(*pt,1)
    o=bpy.data.objects.new(name,c); scene.collection.objects.link(o); c.materials.append(material)

def branch(a,b,radius,material=trunk):
    delta=Vector(b)-Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=7,radius1=radius,radius2=radius*.55,depth=delta.length,location=(Vector(a)+Vector(b))/2)
    o=bpy.context.object; o.name='Tapered branch'; o.rotation_euler=delta.to_track_quat('Z','Y').to_euler(); o.data.materials.append(material)

def slab(name,x,y,sx,sy,height,material):
    # Uneven, broad flat-topped rock instead of isolated triangular pebbles.
    count=7; outline=[]
    for i in range(count):
        a=i*math.tau/count; r=random.uniform(.87,1.1)
        outline.append((x+math.cos(a)*sx*r,y+math.sin(a)*sy*r))
    verts=[(px,py,-.08) for px,py in outline]+[(px,py,height+random.uniform(-.018,.018)) for px,py in outline]
    faces=[tuple(range(count,2*count)),tuple(reversed(range(count)))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(name,mesh); scene.collection.objects.link(o); mesh.materials.append(material)
    bevel=o.modifiers.new('Worn edges','BEVEL'); bevel.width=.018; bevel.segments=2; o.modifiers.new('Rock normals','WEIGHTED_NORMAL')

def water_sheet():
    verts=[]
    for i in range(81):
        x=-5+i*.125
        width=.115+max(0,abs(x)-3.25)*.34
        bend=.018*math.sin(x*2.5)
        verts.extend([(x,river_y-width+bend,-.008),(x,river_y+width+bend,-.008)])
    mesh=bpy.data.meshes.new('River surface'); mesh.from_pydata(verts,[],[(i*2,i*2+1,i*2+3,i*2+2) for i in range(80)]); mesh.update()
    o=bpy.data.objects.new('Continuous river',mesh); scene.collection.objects.link(o); mesh.materials.append(water)

# Field occupies x +/-4.02; Blender y -2.31 .. 1.71.
# River aligns with midpoint of the existing forward anchors, world Godot z=.0785.
# Compensate for the .50-unit card elevation so water projects into the visible row gap.
river_y=-.29
box('Diorama foundation',(0,-.30,-.31),(10,6.4,.32),rim,.13)
water_sheet()
for lower,upper,label in [(-2.31,river_y-.075,'Forest half'),(river_y+.075,1.71,'Volcanic half')]:
    box(label+' structural edge',(0,(lower+upper)/2,-.13),(8.04,upper-lower,.24),rim)
    count=6
    for j in range(count):
        step=(upper-lower)/count
        plank_y=lower+(j+.5)*step
        box(label+' plank '+str(j),(random.uniform(-.025,.025),plank_y,.005),(8.02,step-.012,.12),wood,.009)
        # Scattered end joints leave the centre of each board quiet.
        x=(-1 if j%2 else 1)*(2.5+random.random())
        box('Plank end joint',(x,lower+(j+.5)*step,.067),(.012,step-.02,.002),rim,0)
        for end in [-1,1]:
            for k in range(3):
                start=end*random.uniform(2.2,3.65); length=random.uniform(.2,.65)
                gy=plank_y+random.uniform(-step*.35,step*.35)
                line('Timber weathering',[(start+end*length*t/8,gy+.009*math.sin(t*.7+k),.067) for t in range(9)],grain,.0025)
            for dy in [-step*.25,step*.25]:
                rock('Iron peg',(end*3.83,plank_y+dy,.068),(.015,.015,.004),iron,2)

# Replace the earlier timber construction after consuming its random sequence:
# terrain generation stays identical, making this a wood-only comparison.
for o in list(scene.objects):
    if any(s in o.name for s in [' plank ', 'structural edge', 'Plank end joint', 'Timber weathering', 'Iron peg']):
        bpy.data.objects.remove(o, do_unlink=True)

slab_rng = random.Random(81)
for lower,upper,label in [(-2.31,river_y-.075,'Forest'),(river_y+.075,1.71,'Volcanic')]:
    # Continuous flat top with a subtly irregular perimeter, no repeated seams.
    outline=[]
    for i in range(33):
        x=-4.01+i*8.02/32
        outline.append((x,lower+slab_rng.uniform(-.012,.012)))
    for i in range(1,9):
        outline.append((4.01+slab_rng.uniform(-.02,.02),lower+(upper-lower)*i/9))
    for i in range(33):
        x=4.01-i*8.02/32
        outline.append((x,upper+slab_rng.uniform(-.012,.012)))
    for i in range(1,9):
        outline.append((-4.01+slab_rng.uniform(-.02,.02),upper-(upper-lower)*i/9))
    count=len(outline)
    verts=[(x,y,-.23) for x,y in outline]+[(x,y,.065) for x,y in outline]
    faces=[tuple(range(count,2*count)),tuple(reversed(range(count)))]+[(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    mesh=bpy.data.meshes.new(label+' solid timber'); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(label+' single wood slab',mesh); scene.collection.objects.link(obj)
    mesh.materials.append(wood); mesh.materials.append(rim)
    for poly in mesh.polygons: poly.material_index=0 if poly.index==0 else 1
    bevel=obj.modifiers.new('Worn slab edge','BEVEL'); bevel.width=.018; bevel.segments=3
    obj.modifiers.new('Slab normals','WEIGHTED_NORMAL')
    for side in [-1,1]:
        for k in range(2):
            y=lower+(upper-lower)*(.24+k*.49)
            length=slab_rng.uniform(.40,.78)
            points=[(side*(4.005-length*t/10),y+.025*math.sin(t*.7+k),.067) for t in range(11)]
            line('Slab edge split',points,grain,.003)
            line('Split branch',[points[5],(points[5][0]-side*.15,points[5][1]+.05,.067),(points[5][0]-side*.23,points[5][1]+.065,.067)],grain,.0015)
        # A few long, faint grain accents stay near the outer portions of each slab.
        for k in range(3):
            y=lower+(upper-lower)*slab_rng.uniform(.12,.88)
            start=side*slab_rng.uniform(2.0,2.8)
            line('Slab grain accent',[(start+side*t*.055,y+.012*math.sin(t*.35+k),.066) for t in range(15)],grain,.001)

# Wider pools beside the playing surface.
for side in [-1,1]:
    for i in range(12):
        x=side*(3.98+i*.085); width=.115+(abs(x)-3.25)*.34
        for edge in [-1,1]:
            rock('Riverbank stone',(x,river_y+edge*(width+.04),.015),(.12,.095,random.uniform(.035,.085)),bank,2)
    for i in range(10):
        x=side*random.uniform(4.05,4.8); yy=river_y+random.uniform(-.15,.15)
        line('Pool ripple',[(x+t*.025,yy+.013*math.sin(t*.6),.001) for t in range(8)],foam,.002)
for i in range(15):
    x=random.uniform(-3.9,3.9); yy=river_y+random.uniform(-.055,.055)
    line('River current',[(x+t*.035,yy+.008*math.sin(t*.5),.001) for t in range(7)],foam,.002)

# Upper/nature border (negative Blender y).
box('Forest land',(0,-2.75,-.09),(9.6,.9,.28),earth,.15)
for i in range(60):
    x=random.uniform(-4.7,4.7); y=random.uniform(-3.12,-2.38)
    rock('Mossy terrain',(x,y,.03),(random.uniform(.18,.42),random.uniform(.15,.33),random.uniform(.06,.15)),random.choice(moss),2)
for x,y,h in [(-4.18,-2.12,.67),(-3.35,-2.73,.65),(4.2,-2.2,.72),(3.05,-2.8,.66),(-2.45,-2.92,.5),(4.4,-1.65,.5)]:
    branch((x,y,0),(x+.04,y,h*.8),.065)
    for j in range(7):
        a=j*math.tau/5
        endpoint=(x+.22*math.cos(a),y+.19*math.sin(a),h*.75+random.uniform(0,.13))
        branch((x,y,h*.35),endpoint,.026)
        rock('Tree crown',endpoint,(.21,.19,.16),leaves[j%3],2)
        for k in range(3):
            rock('Leaf cluster',(endpoint[0]+random.uniform(-.16,.16),endpoint[1]+random.uniform(-.14,.14),endpoint[2]+.08),(.10,.095,.07),leaves[(j+k)%3],1)
    for j in range(4):
        a=j*math.tau/4
        branch((x+.20*math.cos(a),y+.15*math.sin(a),.015),(x,y,.15),.025)
for i in range(95):
    x=random.uniform(-4.6,4.6); y=random.uniform(-2.85,-2.36)
    for j in range(3):
        branch((x,y,.09),(x+random.uniform(-.045,.045),y+random.uniform(-.04,.04),random.uniform(.14,.23)),.008,grass)

# Lower volcanic border; gaps between basalt blocks reveal red fissures.
box('Volcanic ground',(0,2.18,-.10),(9.6,1.12,.14),stone[0],.08)
for i in range(19):
    x=-4.7+i*.5
    pts=[(x+random.uniform(-.12,.12),1.72+j*.15,-.022) for j in range(7)]
    line('Narrow red fissure',pts,lava,random.uniform(.012,.022))
line('Branching fissure',[(-4.8+i*.2,2.05+.08*math.sin(i*1.7),-.021) for i in range(49)],lava,.016)
for row in range(3):
    for j in range(22):
        x=-4.65+j*.44+random.uniform(-.08,.08)
        y=1.85+row*.27+random.uniform(-.07,.07)
        slab('Basalt plate',x,y,.255,.18,random.uniform(.025,.09),random.choice(stone))
for side in [-1,1]:
    for j in range(9):
        y=.5+j*.17
        slab('Volcanic side rim',side*4.38,y,.25,.19,random.uniform(.04,.14),random.choice(stone))
    for j in range(9):
        y=-.8-j*.18
        rock('Forest side rim',(side*4.38,y,-.02),(.24,.2,.11),random.choice(moss),2)

# Layout witnesses: real card art on flat proxies, not gameplay/UI reproduction.
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def cardmat(code):
    m=mat('Card '+code,(.8,.8,.75)); p=m.node_tree.nodes.get('Principled BSDF')
    t=m.node_tree.nodes.new('ShaderNodeTexImage'); t.image=bpy.data.images.load(os.path.join(ROOT,'assets','cards',code+'.jpg'),check_existing=True)
    m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']); return m
arts=[cardmat(c) for c in ['1-007R','1-041L','1-043H','1-068C','1-064R'] if os.path.exists(os.path.join(ROOT,'assets','cards',c+'.jpg'))]
back=mat('Card backs',(.055,.065,.075))
def card(x,y,z,material,angle=0,width=.496,height=.718):
    o=box('Layout card',(x,y,z),(width,height,.012),back,.012); o.rotation_euler.z=angle; proxies.append(o)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(x,y,z+.008))
    o=bpy.context.object; o.name='Card face'; o.scale=(width,height,1); o.rotation_euler.z=math.pi+angle
    o.data.materials.append(material); proxies.append(o)
for row,(gz,count) in enumerate([(-.641989,3),(-1.49599,5),(.201241,3),(1.03035,5)]):
    for i in range(count):
        card((i-(count-1)/2)*.65*1.005,-(gz*1.005+.3),.5025,arts[(i+row)%len(arts)])
for x,gz in [(2.65,-1.3),(-2.9,1.45)]:
    for i in range(9):
        proxies.append(box('Deck proxy',(x,-gz,.46+i*.015),(.575,.833,.012),back,.009))
for x,gz in [(3.37,-1.3),(-3.62,1.45)]: card(x,-gz,.5,arts[0],width=.575,height=.833)
for i in range(8): card((i-3.5)*.46,2.4+abs(i-3.5)*.025,.95,arts[i%len(arts)],(i-3.5)*.035,.575,.833)
for i in range(5): card((i-2)*.5,-2.15,.95,back,0,.575,.833)

def area(name,pos,power,size,color):
    bpy.ops.object.light_add(type='AREA',location=pos); o=bpy.context.object; o.name=name
    o.data.energy=power; o.data.shape='DISK'; o.data.size=size; o.data.color=color
    o.rotation_euler=(Vector((0,0,0))-o.location).to_track_quat('-Z','Y').to_euler()
area('Broad warm key',(-3,1,7),1050,7,(1,.86,.68))
area('Forest fill',(2,-4,5),650,5,(.72,.86,1))
bpy.ops.object.camera_add()
cam=bpy.context.object; scene.camera=cam
target=Vector((0,.25,.35)); distance=8/(2*(1920/1080)*math.tan(math.radians(15)))
cam.location=target+Vector((0,distance*math.cos(math.radians(67)),distance*math.sin(math.radians(67))))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
# Blender horizontal sensor fit: derive horizontal FOV from Godot vertical FOV.
cam.data.type='PERSP'; cam.data.sensor_fit='HORIZONTAL'; cam.data.sensor_width=36
cam.data.lens=36/(2*(1920/1080)*math.tan(math.radians(15)))
cam.data.clip_end=100
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_slabs.blend'))
scene.render.filepath=os.path.join(OUT,'board_with_layout.png'); bpy.ops.render.render(write_still=True)
for o in proxies: o.hide_render=True
scene.render.filepath=os.path.join(OUT,'board_environment.png'); bpy.ops.render.render(write_still=True)
for o in proxies: o.hide_render=False
# Comparison only: 8.8 units visible versus the current 8; no Godot setting is edited.
cam.location=target+(cam.location-target)*1.10
scene.render.filepath=os.path.join(OUT,'board_wider_comparison.png'); bpy.ops.render.render(write_still=True)
print('RESULT: board blockout rendered; Godot scenes unchanged')
