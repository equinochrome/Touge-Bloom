import bpy,math,json,sys
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
from pathlib import Path
root=Path(r'C:\Users\super\OneDrive\Documents\Car Game\Assets\Blender\CedarCoupe')
bpy.ops.wm.open_mainfile(filepath=str(root/'Cedar_Coupe_Prototype.blend'))
body=bpy.data.objects['BodyShell'];body.data.calc_loop_triangles()
tree=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],[t.vertices[:] for t in body.data.loop_triangles],all_triangles=True)
fails=[];checks=0
for label in ['FL','FR','RL','RR']:
 tire=bpy.data.objects['Wheel_'+label+'_Tire'];tire.data.calc_loop_triangles();verts=[v.co.copy() for v in tire.data.vertices];tris=[t.vertices[:] for t in tire.data.loop_triangles]
 for length in [0,.3,.6,.9,1.2,1.6,2.2]:
  for angle in ([-32,-16,0,16,32] if label[0]=='F' else [0]):
   center=Vector((tire.location.x,tire.location.y,-.6-length));rotation=Matrix.Rotation(math.radians(angle),4,'Z')
   w=BVHTree.FromPolygons([center+rotation@v for v in verts],tris,all_triangles=True);overlap=tree.overlap(w);checks+=1
   if overlap:fails.append({'wheel':label,'spring_length':length,'steer_degrees':angle,'overlaps':len(overlap)})
(root/'wheel-clearance.json').write_text(json.dumps({'checks':checks,'body_surface_intersections':fails,'scope':'Tire triangle surface against body shell; excludes containment, other panels and road/chassis collision'},indent=2))
print(json.dumps({'checks':checks,'failures':fails}))
