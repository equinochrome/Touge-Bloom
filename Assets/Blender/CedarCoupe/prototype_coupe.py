import bpy,bmesh,math,json,sys,argparse
from pathlib import Path
from mathutils import Vector
p=argparse.ArgumentParser();p.add_argument('--out',required=True);p.add_argument('--wheel-source',required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
s=bpy.context.scene;s.unit_settings.system='NONE'
assets=bpy.data.collections.new('EXPORT_CEDAR_COUPE');s.collection.children.link(assets)
review=bpy.data.collections.new('REVIEW_ONLY');s.collection.children.link(review)
def link(o):
 for c in list(o.users_collection):c.objects.unlink(o)
 assets.objects.link(o);return o
def mat(n,col,metal=0,rough=.45):
 m=bpy.data.materials.new(n);m.diffuse_color=(*col,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*col,1);bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
 return m
paint=mat('Cedar_Midnight_Teal',(.025,.19,.20),.65,.26);dark=mat('Rubber_Trim',(.015,.021,.026),0,.7)
glass=mat('Smoked_Glass',(.06,.12,.15),.3,.12);alloy=mat('Brushed_Metal',(.42,.47,.50),.8,.3)
seat=mat('Seat_Fabric',(.035,.045,.05),0,.88);red=mat('BrakeLens',(.65,.012,.017),.1,.2)
white=mat('HeadLens',(.65,.81,.85),.1,.18);amber=mat('IndicatorLens',(.9,.28,.02),.1,.22)
def mesh(n,v,f,m):
 me=bpy.data.meshes.new(n);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(n,me);assets.objects.link(o);me.materials.append(m)
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();return o
def finish(o,width=.04,segments=3):
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 if width:
  mod=o.modifiers.new('Manufactured_edge','BEVEL');mod.width=min(width,min(o.dimensions)*.35);mod.segments=segments;bpy.ops.object.modifier_apply(modifier=mod.name)
 for f in o.data.polygons:f.use_smooth=True
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);o.select_set(False);return o
def box(n,loc,size,m,bev=.04):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=link(bpy.context.object);o.name=n;o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m);return finish(o,bev)
def loft(n,sections,m):
 # Blender +Y is the nose; Roblox -Z is the nose. Eight-vertex beveled body section.
 v=[]
 for y,w,lo,hi in sections:
  c=min(.16,(hi-lo)*.2)
  v += [(-w+c,y,lo),(-w,y,lo+c),(-w,y,hi-c),(-w+c,y,hi),(w-c,y,hi),(w,y,hi-c),(w,y,lo+c),(w-c,y,lo)]
 f=[tuple(reversed(range(8)))]
 for j in range(len(sections)-1):
  for i in range(8):f.append((j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i))
 f.append(tuple((len(sections)-1)*8+i for i in range(8)))
 return mesh(n,v,f,m)
body=loft('BodyShell',[(-7.5,3.10,-1.0,.63),(-7.1,3.4,-1,.9),(-5.7,3.50,-1,1.05),(-3.2,3.45,-1,1.04),(0,3.35,-1,1.02),(3.2,3.45,-1,1.05),(5.8,3.5,-1,.95),(7.1,3.35,-.92,.66),(7.5,3.12,-.83,.48)],paint)
for y in [4.7,-4.5]:
 for x in [-3.2,3.2]:
  bpy.ops.mesh.primitive_cylinder_add(vertices=80,radius=2.05,depth=3.5,location=(x,y,-1.15),rotation=(0,math.pi/2,0))
  cutter=bpy.context.object;bpy.context.view_layer.objects.active=body
  mod=body.modifiers.new('Wheel_cavity','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
finish(body,.045,3)
# Closed solid roof, separate windshield/rear glass and side-window panels.
roof=loft('RoofPanel',[(-2.7,2.45,2.27,2.39),(-2.15,2.56,2.36,2.48),(0.1,2.59,2.42,2.54),(1.20,2.5,2.30,2.42)],paint);finish(roof,.04)
def slab(n,quad,m,thick=.045):
 v=[tuple(q) for q in quad]+[(q[0],q[1],q[2]-thick) for q in quad]
 return finish(mesh(n,v,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],m),.015,2)
slab('Windshield',[(-2.5,1.22,2.32),(2.5,1.22,2.32),(3.10,2.92,1.05),(-3.1,2.92,1.05)],glass)
slab('RearGlass',[(-2.45,-2.70,2.30),(-3.1,-4.05,1.05),(3.1,-4.05,1.05),(2.45,-2.70,2.30)],glass)
for side,label in [(-1,'L'),(1,'R')]:
 slab('SideGlass_'+label,[(side*2.55,1.07,2.25),(side*3.22,2.60,1.09),(side*3.23,-2.85,1.09),(side*2.5,-2.55,2.23)],glass)
 for n,y1,y2,x1,x2,z1,z2 in [('A',1.15,2.85,2.54,3.13,2.35,1.03),('C',-2.60,-3.97,2.48,3.14,2.34,1.04)]:
  slab(n+'Pillar_'+label,[(side*(x1-.08),y1,z1),(side*(x1+.08),y1,z1),(side*(x2+.08),y2,z2),(side*(x2-.08),y2,z2)],paint,.12)
 slab('B_Pillar_'+label,[(side*2.54,-1.26,2.24),(side*2.54,-1.13,2.24),(side*3.25,-1.13,1.07),(side*3.25,-1.26,1.07)],dark,.06)
 slab('RearQuarter_'+label,[(side*2.5,-2.55,2.23),(side*3.23,-2.85,1.09),(side*3.15,-4.05,1.05),(side*2.45,-2.70,2.30)],paint,.08)
 box('DoorHandle_'+label,(side*3.40,-.80,.61),(.07,.46,.10),alloy,.025)
 box('Mirror_'+label,(side*3.60,1.93,1.2),(.52,.65,.28),paint,.09)
 box('MirrorGlass_'+label,(side*3.61,1.63,1.21),(.38,.025,.19),glass,.025)
 box('Sill_'+label,(side*3.37,0,-.79),(.18,5.35,.22),dark,.055)
slab('HoodPanel',[(-3.13,3.10,1.07),(3.13,3.1,1.07),(3.10,6.72,.73),(-3.10,6.72,.73)],paint,.07)
slab('TrunkPanel',[(-3.1,-4.12,1.08),(3.1,-4.12,1.08),(3.12,-6.88,.96),(-3.12,-6.88,.96)],paint,.07)
box('FrontGrille',(0,7.48,-.12),(3.1,.07,.47),dark)
box('FrontSplitter',(0,7.48,-.79),(6.5,.40,.13),dark)
box('RearValance',(0,-7.45,-.65),(5.8,.14,.45),dark)
for side,label in [(-1,'L'),(1,'R')]:
 box('Headlight_'+label,(side*2.25,7.53,.27),(1.5,.22,.34),white,.08)
 box('FrontIndicator_'+label,(side*2.35,7.53,-.26),(.56,.12,.20),amber,.035)
 box('BrakeLight_'+label,(side*2.10,-7.56,.48),(1.72,.15,.37),red,.065)
 box('ReverseLight_'+label,(side*.91,-7.56,.48),(.49,.10,.30),white,.035)
box('RearPlateRecess',(0,-7.48,.02),(1.45,.05,.41),dark)
box('Dashboard',(0,2.0,.94),(5.4,1.0,.48),dark,.13)
box('CenterConsole',(0,.2,.33),(.72,2.85,.40),dark,.09)
box('InteriorFloor',(0,-.1,-.53),(4.7,5.8,.12),dark)
for x,label in [(-1.45,'Passenger'),(1.45,'Driver')]:
 box('SeatBase_'+label,(x,-.8,.12),(1.46,1.50,.45),seat,.17)
 o=box('SeatBack_'+label,(x,-1.50,.87),(1.45,.40,1.64),seat,.18);o.rotation_euler.x=math.radians(-10)
 box('Headrest_'+label,(x,-1.70,1.82),(.88,.30,.42),seat,.12)
def cyl(n,loc,r,depth,m,rot=(0,0,0)):
 bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=depth,location=loc,rotation=rot);o=link(bpy.context.object);o.name=n;o.data.materials.append(m);return finish(o,.02)
def pivot(o,point):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;s.cursor.location=point;bpy.ops.object.origin_set(type='ORIGIN_CURSOR');o.select_set(False)
bpy.ops.mesh.primitive_torus_add(major_radius=.49,minor_radius=.055,major_segments=48,minor_segments=10,location=(1.45,1.26,1.20),rotation=(math.pi/2,0,0));steering=link(bpy.context.object);steering.name='SteeringWheel';steering.data.materials.append(dark);finish(steering,0)
hub=cyl('SteeringHub',(1.45,1.26,1.2),.16,.15,dark,(math.pi/2,0,0))
for angle in [0,2.1,4.2]:
 o=box('SteeringSpoke',(1.45+math.sin(angle)*.25,1.26,1.20+math.cos(angle)*.25),(.10,.10,.48),alloy,.025);o.rotation_euler.y=angle
parts=[o for o in assets.objects if o.name.startswith('Steering')];bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=steering;bpy.ops.object.join();steering.name='SteeringWheel';finish(steering,0);pivot(steering,(1.45,1.26,1.2))
gear=cyl('GearLever',(0,.52,.70),.07,.59,alloy);knob=cyl('GearKnob',(0,.52,1.03),.13,.19,dark)
bpy.ops.object.select_all(action='DESELECT');gear.select_set(True);knob.select_set(True);bpy.context.view_layer.objects.active=gear;bpy.ops.object.join();pivot(gear,(0,.52,.4))
hand=box('HandbrakeLever',(.33,-.28,.65),(.13,.74,.13),dark,.04);pivot(hand,(.33,-.62,.55))
for n,x in [('Clutch',.94),('Brake',1.35),('Throttle',1.76)]:
 o=box('Pedal_'+n,(x,2.35,.03),(.26,.15,.37),alloy,.035);pivot(o,(x,2.35,.32))
for x in [-2.65,2.65]:cyl('ExhaustTip',(x,-7.60,-.61),.17,.44,alloy,(math.pi/2,0,0))
# Reuse Blender-authored wheel meshes; preserve individual axle pivots.
with bpy.data.libraries.load(a.wheel_source,link=False) as (src,dst):dst.objects=[n for n in src.objects if n in ['Cedar_Wheel_Tire','Cedar_Wheel_Rim','Cedar_Wheel_BrakeDisc']]
wheel_sources=[o for o in dst.objects if o]
mounts={'FL':(-2.9,4.7,-.6),'FR':(2.9,4.7,-.6),'RL':(-2.9,-4.5,-.6),'RR':(2.9,-4.5,-.6)}
wheels=[]
for label,loc in mounts.items():
 for source in wheel_sources:
  o=source.copy();o.data=source.data.copy();assets.objects.link(o);o.name='Wheel_'+label+'_'+source.name.split('_')[-1];o.location=(loc[0],loc[1],loc[2]-2.2);o.rotation_euler=(0,0,math.pi if loc[0]<0 else 0);finish(o,0);wheels.append(o)
for o in wheel_sources:bpy.data.objects.remove(o,do_unlink=True)
anchors={'ChassisRoot':(0,0,0),'DriverSeat':(1.45,-.8,.65),'CameraTarget':(0,0,1.3),'EngineAudio':(0,4.0,.4),'ExhaustAudio':(0,-7.3,-.5),'SteeringPivot':(1.45,1.26,1.2),'GearLeverPivot':(0,.52,.4),'HandbrakePivot':(.33,-.62,.55)}
for label,loc in mounts.items():anchors['Suspension_'+label]=loc
for n,loc in anchors.items():
 o=bpy.data.objects.new('ATT_'+n,None);assets.objects.link(o);o.location=loc;o.empty_display_size=.25;o.empty_display_type='ARROWS'
meshes=[o for o in assets.objects if o.type=='MESH'];report=[]
for o in meshes:
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
 bm=bmesh.new();bm.from_mesh(o.data);bad=sum(not e.is_manifold for e in bm.edges);zero=sum(f.calc_area()<1e-9 for f in bm.faces);bm.free();o.data.calc_loop_triangles()
 item={'name':o.name,'triangles':len(o.data.loop_triangles),'nonmanifold_edges':bad,'zero_area_faces':zero,'uv_layers':len(o.data.uv_layers),'pivot_blender':list(o.location),'dimensions_blender':list(o.dimensions)}
 assert bad==0 and zero==0 and item['triangles']<=20000,item;report.append(item)
def export(stem,objs):
 bpy.ops.object.select_all(action='DESELECT')
 for o in objs:o.select_set(True)
 bpy.ops.export_scene.fbx(filepath=str(out/(stem+'.fbx')),use_selection=True,global_scale=1,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',object_types={'MESH','EMPTY'},bake_anim=False,add_leaf_bones=False)
 bpy.ops.wm.obj_export(filepath=str(out/(stem+'.obj')),export_selected_objects=True,forward_axis='NEGATIVE_Z',up_axis='Y',global_scale=1,export_triangulated_mesh=True,export_materials=True)
export('Cedar_Coupe_Prototype',list(assets.objects));export('Cedar_Coupe_Body',[o for o in meshes if o not in wheels])
export('Cedar_Coupe_BodyShell_R2',[body])
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];bounds=[[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
# Verify actual OBJ roundtrip, not just export invocation.
bpy.ops.wm.obj_import(filepath=str(out/'Cedar_Coupe_Prototype.obj'),forward_axis='NEGATIVE_Z',up_axis='Y');imports=list(bpy.context.selected_objects)
pts=[o.matrix_world@v.co for o in imports for v in o.data.vertices];back=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]
assert max(abs(bounds[j][i]-back[j][i]) for j in range(2) for i in range(3))<1e-4,(bounds,back)
for o in imports:bpy.data.objects.remove(o,do_unlink=True)
manifest={'status':'Blender geometry verified; Studio import and gameplay pending','units':'1 Blender unit = 1 Roblox stud; import unit Stud','coordinate_mapping':'Roblox (x,y,z) = Blender (x,z,-y)','root':'ChassisRoot at origin; front Roblox -Z','chassis_size_studs':[6.4,1.6,14],'wheel_radius':1.4,'wheel_width':1.3,'wheel_mounts_roblox':{n:[v[0],v[2],-v[1]] for n,v in mounts.items()},'export_wheel_spring_length':2.2,'anchors_roblox':{n:[v[0],v[2],-v[1]] for n,v in anchors.items()},'mesh_audit':report,'total_triangles':sum(r['triangles'] for r in report),'obj_roundtrip_bounds_passed':True,'bounds_blender':bounds,'limits':['Visual prototype only; no driving or gearbox code in mesh','Blender empties require explicit Studio Attachment conversion','Suspension/steering body-clearance sweep still needs gameplay QA','Doors are cosmetic body panels; opening doors/hood is not implemented']}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2))
# Review pose is separate from canonical export; wheels shown at 0.6 stud spring length.
for o in wheels:o.location.z+=1.6
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.60));floor=bpy.context.object;floor.name='REVIEW_Ground';floor.data.materials.append(mat('ReviewFloor',(.12,.14,.15),0,.85))
for c in list(floor.users_collection):c.objects.unlink(floor)
review.objects.link(floor)
def area(n,loc,power,size):
 d=bpy.data.lights.new(n,'AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new(n,d);review.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,0))-o.location).to_track_quat('-Z','Y').to_euler()
area('Key',(3,7,13),2200,9);area('Fill',(-9,4,8),1800,8);area('Rim',(2,-9,9),3000,7)
d=bpy.data.cameras.new('REVIEW_Camera');camera=bpy.data.objects.new('REVIEW_Camera',d);review.objects.link(camera);s.camera=camera;d.type='ORTHO';d.ortho_scale=22
s.render.engine='CYCLES';s.cycles.samples=24;s.cycles.use_denoising=True;s.render.resolution_x=1400;s.render.resolution_y=900;s.render.resolution_percentage=100
s.world=bpy.data.worlds.new('World');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[0].default_value=(.3,.35,.4,1);s.world.node_tree.nodes['Background'].inputs[1].default_value=.45
for n,loc in [('front-three-quarter',(15,19,10)),('rear-three-quarter',(-15,-19,9)),('side',(22,0,5))]:
 camera.location=loc;camera.rotation_euler=(Vector((0,0,.1))-camera.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(out/(n+'.png'));bpy.ops.render.render(write_still=True)
for o in wheels:o.location.z-=1.6
bpy.ops.wm.save_as_mainfile(filepath=str(out/'Cedar_Coupe_Prototype.blend'))
print('CEDAR_COUPЕ_VALIDATED',manifest['total_triangles'],len(meshes),'meshes; OBJ roundtrip passed')
