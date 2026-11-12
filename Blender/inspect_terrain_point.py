import bpy
from mathutils import Vector
s=bpy.context.scene
for o in list(s.objects):
    if o.name.startswith(('Card face','Layout card','Deck proxy')): bpy.data.objects.remove(o,do_unlink=True)
c=s.camera
f=c.data.view_frame(scene=s)
for x,y in [(880,1020),(900,1025),(910,1015),(890,1030)]:
    v=Vector((min(v.x for v in f)+(max(v.x for v in f)-min(v.x for v in f))*x/1920,max(v.y for v in f)-(max(v.y for v in f)-min(v.y for v in f))*y/1080,f[0].z))
    r=s.ray_cast(bpy.context.evaluated_depsgraph_get(),c.location,c.matrix_world.to_3x3()@v)
    print('HIT',x,y,r[4].name if r[0] else 'none')

