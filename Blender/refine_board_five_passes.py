"""Five cumulative art passes; preserves the approved slab preview and Godot scenes."""
import os
HERE=os.path.dirname(os.path.abspath(__file__))
source=open(os.path.join(HERE,'build_board_slabs.py'),encoding='utf-8').read()
source=source.split('bpy.ops.file.pack_all()')[0]
exec(compile(source,os.path.join(HERE,'build_board_slabs.py'),'exec'))
OUT=os.path.join(HERE,'board_art_passes'); os.makedirs(OUT,exist_ok=True)
scene.cycles.samples=32
rng=random.Random(309)

def render_pass(number,name):
    scene.render.filepath=os.path.join(OUT,f'{number:02d}_{name}.png')
    bpy.ops.render.render(write_still=True)
    print(f'PASS {number}: {name}',flush=True)

# 1. Broad warped grain, with wear controlled by distance to the slab edges.
n=wood.node_tree.nodes; l=wood.node_tree.links; p=n.get('Principled BSDF')
mapping.inputs[1].default_value=(1.6,18,4)
warp=n.new('ShaderNodeTexNoise'); warp.inputs['Scale'].default_value=2.5; warp.inputs['Detail'].default_value=2
l.new(coord.outputs['Generated'],warp.inputs['Vector'])
scale=n.new('ShaderNodeVectorMath'); scale.operation='SCALE'; scale.inputs[3].default_value=.11
l.new(warp.outputs['Color'],scale.inputs[0])
add=n.new('ShaderNodeVectorMath'); add.operation='ADD'
l.new(coord.outputs['Generated'],add.inputs[0]); l.new(scale.outputs[0],add.inputs[1]); l.new(add.outputs[0],mapping.inputs[0])
ramp.color_ramp.elements[0].color=(.105,.052,.024,1); ramp.color_ramp.elements[1].color=(.24,.14,.065,1)
separate=n.new('ShaderNodeSeparateXYZ'); l.new(coord.outputs['Generated'],separate.inputs[0])
def mathnode(op,a,b=None):
    node=n.new('ShaderNodeMath'); node.operation=op
    if isinstance(a,(int,float)): node.inputs[0].default_value=a
    else: l.new(a,node.inputs[0])
    if b is not None:
        if isinstance(b,(int,float)): node.inputs[1].default_value=b
        else: l.new(b,node.inputs[1])
    return node.outputs[0]
dx=mathnode('MINIMUM',separate.outputs['X'],mathnode('SUBTRACT',1,separate.outputs['X']))
dy=mathnode('MINIMUM',separate.outputs['Y'],mathnode('SUBTRACT',1,separate.outputs['Y']))
edge=mathnode('MINIMUM',mathnode('MULTIPLY',dx,8),mathnode('MULTIPLY',dy,2))
fade=n.new('ShaderNodeMapRange'); fade.inputs['From Min'].default_value=0; fade.inputs['From Max'].default_value=.14
fade.inputs['To Min'].default_value=.40; fade.inputs['To Max'].default_value=1
l.new(edge,fade.inputs['Value'])
mix=n.new('ShaderNodeMixRGB'); mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=1
l.new(ramp.outputs[0],mix.inputs[1]); l.new(fade.outputs[0],mix.inputs[2]); l.new(mix.outputs[0],p.inputs['Base Color'])
knotmat=mat('Soft knot grain',(.11,.060,.028))
for x,y in [(-2.9,-1.65),(3.2,.78),(-2.6,1.37)]:
    for ring in range(4):
        rx=.055+ring*.035; ry=.018+ring*.012
        line('Wood knot',[(x+rx*math.cos(t*math.tau/48),y+ry*math.sin(t*math.tau/48)*(1+.12*math.cos(t*.4)),.067) for t in range(49)],knotmat,.0018)
    for side in [-1,1]:
        for k in range(2):
            line('Grain around knot',[(x+side*(.13+t*.04),y+(k*2-1)*(.02+.025*math.exp(-t*.18)),.067) for t in range(15)],knotmat,.001)
render_pass(1,'wood')

# 2. Irregular stone groups and damp moss transition into the water.
for o in list(scene.objects):
    if o.name.startswith('Riverbank stone'): bpy.data.objects.remove(o,do_unlink=True)
wet=mat('Wet bank stone',(.075,.12,.10),.4)
for side in [-1,1]:
    for edge_sign in [-1,1]:
        for cluster in range(4):
            cx=side*(4.04+cluster*.23)
            cy=river_y+edge_sign*(.115+(abs(cx)-3.25)*.34+.04)
            for k in range(rng.randint(2,4)):
                x=cx+rng.uniform(-.10,.10); y=cy+rng.uniform(-.06,.06)
                size=rng.uniform(.065,.15)
                rock('Grouped river stone',(x,y,.014),(size,size*.68,size*.40),wet if k%2 else bank,2)
            rock('Bank moss',(cx,cy+edge_sign*.075,.025),(.17,.10,.035),moss[2],2)
        for k in range(5):
            x=side*rng.uniform(4.1,4.65); y=river_y-.48-rng.uniform(0,.12)
            for blade in range(3):
                branch((x,y,.02),(x+rng.uniform(-.035,.035),y+.02,.12+rng.random()*.08),.006,grass)
render_pass(2,'riverbanks')

# 3. Uneven branching silhouettes and foliage clusters instead of round crowns.
for o in list(scene.objects):
    if o.name.startswith(('Tree crown','Leaf cluster')): bpy.data.objects.remove(o,do_unlink=True)
for index,(x,y,h) in enumerate([(-4.18,-2.12,.67),(-3.35,-2.73,.65),(4.2,-2.2,.72),(3.05,-2.8,.66),(-2.45,-2.92,.5),(4.4,-1.65,.5)]):
    for j in range(4):
        a=j*2.1+index; reach=rng.uniform(.16,.32)
        end=(x+math.cos(a)*reach,y+math.sin(a)*reach,h+rng.uniform(-.10,.12))
        branch((x,y,h*.45),end,.027)
        for k in range(rng.randint(4,7)):
            size=rng.uniform(.075,.14)
            rock('Layered foliage',(end[0]+rng.uniform(-.13,.13),end[1]+rng.uniform(-.12,.12),end[2]+rng.uniform(-.05,.06)),(size*1.4,size,size*.55),leaves[(j+k)%3],2)
    for j in range(3):
        a=j*2.1
        branch((x,y,.12),(x+.26*math.cos(a),y+.23*math.sin(a),.025),.025)
render_pass(3,'vegetation')

# 4. Break the regular basalt rows with broad fractured masses and small debris.
for o in list(scene.objects):
    if o.name.startswith('Basalt plate'):
        o.location.z+=rng.uniform(-.025,.025)
for side in [-1,1]:
    for k in range(4):
        x=side*(2.55+k*.5); y=2.08+rng.uniform(-.12,.20)
        slab('Fractured basalt mass',x,y,rng.uniform(.30,.45),rng.uniform(.18,.28),rng.uniform(.12,.22),stone[k%3])
        for j in range(3):
            rock('Basalt rubble',(x+rng.uniform(-.35,.35),y+rng.uniform(-.2,.2),.045),(.065,.055,.045),stone[j%3])
        line('Connected hot fracture',[(x-.25, y-.08,.03),(x-.08,y-.03,.035),(x+.05,y+.08,.035),(x+.23,y+.11,.03)],lava,.009)
render_pass(4,'volcanic_terrain')

# 5. Neutral playing-surface lighting with restrained cool and warm perimeter fills.
bpy.data.objects['Broad warm key'].data.color=(1,.94,.84)
bpy.data.objects['Broad warm key'].data.energy=920
bpy.data.objects['Forest fill'].data.color=(.68,.84,1)
bpy.data.objects['Forest fill'].data.energy=500
area('Warm volcanic rim',(0,3.1,1.8),85,4,(1,.22,.06))
area('Cool forest rim',(0,-3.5,2),110,4,(.65,.86,.90))
render_pass(5,'lighting_final')
for o in proxies: o.hide_render=True
scene.render.filepath=os.path.join(OUT,'environment_final.png'); bpy.ops.render.render(write_still=True)
for o in proxies: o.hide_render=False
bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'board_art_passes.blend'))
print('RESULT: five cumulative previews complete; Godot unchanged',flush=True)
