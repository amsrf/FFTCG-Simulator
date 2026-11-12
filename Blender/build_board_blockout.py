"""Standalone composition study. Does not modify Godot scenes.
Godot (x,y,z) maps to Blender (x,-z,y). Camera matches camera_rig.gd.
Run with Blender 4.4 --background --python this_file.py.
"""
import bpy, math, random, os
from mathutils import Vector

random.seed(24)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'board_blockout')
os.makedirs(OUT, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
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
ramp.color_ramp.elements[0].color = (.12, .065, .029, 1)
ramp.color_ramp.elements[1].color = (.36, .23, .115, 1)
l.new(tex.outputs['Fac'], ramp.inputs[0]); l.new(ramp.outputs[0], p.inputs['Base Color'])
rim = mat('Dark timber edge', (.085, .047, .025))
earth = mat('Forest soil', (.095, .12, .045))
moss = [mat('Moss '+str(i), c) for i,c in enumerate([(.19,.27,.065),(.27,.34,.09),(.12,.20,.055)])]
leaves = [mat('Canopy '+str(i), c) for i,c in enumerate([(.13,.29,.07),(.25,.39,.08),(.37,.46,.10)])]
stone = [mat('Basalt '+str(i), c) for i,c in enumerate([(.047,.04,.043),(.085,.065,.06),(.12,.09,.075)])]
bank = mat('Riverbank stone', (.23,.25,.18))
trunk = mat('Tree bark', (.12,.07,.035))
lava = mat('Red fissures', (.65,.025,.003), emission=2)
water = mat('Teal river', (.015,.19,.20), .22)
foam = mat('Water strokes', (.15,.43,.39), .4)
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
    o.data.materials.append(material); return o

def line(name, pts, material, width):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.bevel_depth=width; c.bevel_resolution=2
    s=c.splines.new('POLY'); s.points.add(len(pts)-1)
    for v,pt in zip(s.points,pts): v.co=(*pt,1)
    o=bpy.data.objects.new(name,c); scene.collection.objects.link(o); c.materials.append(material)

# Field occupies x +/-4.02; Blender y -2.31 .. 1.71.
# River aligns with midpoint of the existing forward anchors, world Godot z=.0785.
# Compensate for the .50-unit card elevation so water projects into the visible row gap.
river_y=-.29
box('Diorama foundation',(0,-.30,-.31),(10,6.4,.32),rim,.13)
box('Water channel',(0,river_y,-.025),(9.8,.30,.04),water)
for lower,upper,label in [(-2.31,river_y-.075,'Forest half'),(river_y+.075,1.71,'Volcanic half')]:
    box(label+' structural edge',(0,(lower+upper)/2,-.13),(8.04,upper-lower,.24),rim)
    count=6
    for j in range(count):
        step=(upper-lower)/count
        box(label+' plank '+str(j),(0,lower+(j+.5)*step,.005),(8.02,step-.014,.12),wood,.014)
        # Scattered end joints leave the centre of each board quiet.
        x=(-1 if j%2 else 1)*(2.5+random.random())
        box('Plank end joint',(x,lower+(j+.5)*step,.067),(.012,step-.02,.002),rim,0)

# Wider pools beside the playing surface.
for x in [-4.45,4.45]:
    rock('River side pool',(x,river_y,-.03),(.8,.58,.045),water,2)
    for i in range(9):
        a=i*math.tau/9
        rock('Bank stone',(x+.65*math.cos(a),river_y+.49*math.sin(a),.01),(.16,.12,.09),bank)
for i in range(22):
    x=-4.6+i*.43
    line('River current',[(x,river_y+.025*math.sin(x*3),.002),(x+.17,river_y+.025*math.sin(x*3)+.01,.002)],foam,.005)

# Upper/nature border (negative Blender y).
box('Forest land',(0,-2.75,-.09),(9.6,.9,.28),earth,.15)
for i in range(60):
    x=random.uniform(-4.7,4.7); y=random.uniform(-3.12,-2.38)
    rock('Mossy terrain',(x,y,.03),(random.uniform(.18,.42),random.uniform(.15,.33),random.uniform(.06,.15)),random.choice(moss),2)
for x,y,h in [(-4.05,-2.62,.85),(-3.35,-2.82,.65),(3.8,-2.7,.9),(3.05,-2.9,.66),(-2.45,-2.92,.5),(4.4,-2.1,.6)]:
    box('Tree trunk',(x,y,h*.38),(.085,.09,h*.75),trunk)
    for j in range(5):
        a=j*math.tau/5
        rock('Tree crown',(x+.17*math.cos(a),y+.14*math.sin(a),h*.75+random.uniform(0,.16)),(.3,.28,.3),leaves[j%3],2)

# Lower volcanic border; gaps between basalt blocks reveal red fissures.
box('Volcanic fissure bed',(0,2.18,-.11),(9.6,.86,.14),lava,.08)
for row in range(3):
    for j in range(22):
        x=-4.65+j*.44+random.uniform(-.08,.08)
        y=1.85+row*.27+random.uniform(-.07,.07)
        rock('Basalt border',(x,y,-.015),(.28,.19,random.uniform(.10,.24)),random.choice(stone))
for side in [-1,1]:
    for j in range(9):
        y=.5+j*.17
        rock('Volcanic side rim',(side*4.38,y,-.04),(.23,.22,.14),random.choice(stone))
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
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_blockout.blend'))
scene.render.filepath=os.path.join(OUT,'board_with_layout.png'); bpy.ops.render.render(write_still=True)
for o in proxies: o.hide_render=True
scene.render.filepath=os.path.join(OUT,'board_environment.png'); bpy.ops.render.render(write_still=True)
for o in proxies: o.hide_render=False
# Comparison only: 8.8 units visible versus the current 8; no Godot setting is edited.
cam.location=target+(cam.location-target)*1.10
scene.render.filepath=os.path.join(OUT,'board_wider_comparison.png'); bpy.ops.render.render(write_still=True)
print('RESULT: board blockout rendered; Godot scenes unchanged')
