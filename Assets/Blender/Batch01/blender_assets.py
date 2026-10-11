"""Blender-native authoring and geometric validation for Scenic Drift."""
import bpy, bmesh, math, json, sys, argparse
from pathlib import Path
from mathutils import Vector

parser=argparse.ArgumentParser(); parser.add_argument('--out',required=True); parser.add_argument('--rail-source',required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]); OUT=Path(args.out); OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene; scene.unit_settings.system='NONE'; scene.unit_settings.scale_length=1
assets=bpy.data.collections.new('EXPORT_ASSETS'); scene.collection.children.link(assets)
review=bpy.data.collections.new('REVIEW_ONLY'); scene.collection.children.link(review)

def material(name,color,metal=0,rough=.5):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
    return m
rubber=material('Rubber',(0.026,.029,.032),0,.83)
alloy=material('Satin_Alloy',(.49,.54,.59),.82,.27)
disc=material('Brake_Steel',(.22,.25,.28),.72,.4)
caliper=material('Caliper',(.36,.085,.05),.45,.38)
paint=material('Rail_Offwhite',(.72,.75,.70),.05,.56)

def mesh_obj(name,verts,faces,mat):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    obj=bpy.data.objects.new(name,mesh); assets.objects.link(obj); obj.data.materials.append(mat)
    for p in mesh.polygons: p.use_smooth=True
    return obj

def lathe(name,profile,mat,segments=64):
    verts=[]; faces=[]
    for x,r in profile:
        for j in range(segments):
            a=j*math.tau/segments; verts.append((x,r*math.cos(a),r*math.sin(a)))
    for i in range(len(profile)):
        ni=(i+1)%len(profile)
        for j in range(segments):
            nj=(j+1)%segments; faces.append((i*segments+j,i*segments+nj,ni*segments+nj,ni*segments+j))
    return mesh_obj(name,verts,faces,mat)

def bevel(obj,width=.015,segments=2):
    mod=obj.modifiers.new('Edge_finish','BEVEL'); mod.width=width; mod.segments=segments
    bpy.context.view_layer.objects.active=obj; obj.select_set(True); bpy.ops.object.modifier_apply(modifier=mod.name); obj.select_set(False)

def cylinder_x(name,x,radius,depth,mat,y=0,z=0,segments=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=radius,depth=depth,location=(x,y,z),rotation=(0,math.pi/2,0))
    obj=bpy.context.object; obj.name=name
    for c in list(obj.users_collection): c.objects.unlink(obj)
    assets.objects.link(obj); obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    for p in obj.data.polygons: p.use_smooth=len(p.vertices)==4
    bevel(obj,.009,2); return obj

# Exact bounding profile: +/-0.65 width, outer radius 1.4.
profile=[(-.65,.985),(-.65,1.16),(-.61,1.27),(-.52,1.365),(-.42,1.4),(-.33,1.4),(-.315,1.366),(-.285,1.366),(-.27,1.4),(-.03,1.4),(-.015,1.366),(.015,1.366),(.03,1.4),(.27,1.4),(.285,1.366),(.315,1.366),(.33,1.4),(.42,1.4),(.52,1.365),(.61,1.27),(.65,1.16),(.65,.985),(.50,.975),(-.50,.975)]
tire=lathe('Cedar_Wheel_Tire',profile,rubber)
barrel=lathe('Cedar_Wheel_RimBarrel',[(-.48,.80),(-.52,.90),(-.50,.965),(-.45,.972),(.50,.972),(.57,.958),(.59,.92),(.55,.88),(.46,.86),(-.45,.86)],alloy)
wheel=[tire,barrel]

for j in range(5):
    a=j*math.tau/5; verts=[]
    for x in [.42,.56]:
        for r,da in [(.20,-.17),(.89,-.11),(.91,.04),(.22,.17)]:
            angle=a+da+.13*(r/.9); verts.append((x,r*math.cos(angle),r*math.sin(angle)))
    spoke=mesh_obj('Cedar_Wheel_Spoke_'+str(j+1),verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],alloy)
    bevel(spoke,.012,3); wheel.append(spoke)
    wheel.append(cylinder_x('Cedar_Wheel_Lug_'+str(j+1),.59,.043,.10,disc,.25*math.cos(a),.25*math.sin(a),12))
wheel.append(cylinder_x('Cedar_Wheel_CenterCap',.57,.15,.12,alloy))
rotor=lathe('Cedar_Wheel_BrakeDisc',[(.255,.20),(.255,.75),(.30,.75),(.30,.20)],disc); wheel.append(rotor)

# Wheel geometry centered at the axle origin. Join static rim details into one mesh; keep tire and brake disc separate.
def join(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]; bpy.ops.object.join(); o=bpy.context.object; o.name=name
    scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR'); bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return o
rim=join([o for o in wheel if o not in [tire,rotor]],'Cedar_Wheel_Rim'); wheel=[tire,rim,rotor]

# Import the original folded-profile geometry into Blender, weld coincident vertices, recalculate normals.
bpy.ops.wm.obj_import(filepath=args.rail_source,forward_axis='NEGATIVE_Z',up_axis='Y',use_split_objects=False,use_split_groups=False)
rail=bpy.context.object; rail.name='Mountain_Guardrail_12'
for c in list(rail.users_collection): c.objects.unlink(rail)
assets.objects.link(rail)
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
bm=bmesh.new(); bm.from_mesh(rail.data); bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(rail.data); bm.free()
rail.data.materials.clear(); rail.data.materials.append(paint)
for p in rail.data.polygons: p.use_smooth=True
scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

def unwrap(obj):
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.uv.smart_project(angle_limit=math.radians(55),island_margin=.02); bpy.ops.object.mode_set(mode='OBJECT')
for o in wheel+[rail]: unwrap(o)

def audit(obj):
    mesh=obj.data; mesh.calc_loop_triangles(); bm=bmesh.new(); bm.from_mesh(mesh)
    nonmanifold=sum(not e.is_manifold for e in bm.edges); zero_faces=sum(f.calc_area()<1e-9 for f in bm.faces)
    isolated=sum(not v.link_faces for v in bm.verts); bm.free()
    points=[obj.matrix_world@v.co for v in mesh.vertices]
    low=[min(p[i] for p in points) for i in range(3)]; high=[max(p[i] for p in points) for i in range(3)]
    item={'object':obj.name,'vertices':len(mesh.vertices),'triangles':len(mesh.loop_triangles),'dimensions_blender':[high[i]-low[i] for i in range(3)],'bounds_blender':[low,high],'nonmanifold_edges':nonmanifold,'zero_area_faces':zero_faces,'isolated_vertices':isolated,'uv_layers':len(mesh.uv_layers),'scale':list(obj.scale),'pivot':list(obj.location)}
    assert nonmanifold==0,item; assert zero_faces==0,item; assert isolated==0,item
    assert len(mesh.uv_layers)>0,item; assert all(abs(s-1)<1e-6 for s in obj.scale),item
    return item
report={'blender_version':bpy.app.version_string,'units':'one Blender unit = one Roblox stud; import Scale Unit Stud','model_status':'Blender verified; Studio import pending','objects':[audit(o) for o in wheel+[rail]]}
dimensions=list(tire.dimensions); assert max(abs(a-b) for a,b in zip(dimensions,[1.3,2.8,2.8]))<1e-5,dimensions
rd=list(rail.dimensions); assert abs(rd[0]-12)<1e-5,rd

def export(objects,stem):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.wm.obj_export(filepath=str(OUT/(stem+'.obj')),export_selected_objects=True,forward_axis='NEGATIVE_Z',up_axis='Y',global_scale=1,export_triangulated_mesh=True,export_materials=True)
    bpy.ops.export_scene.fbx(filepath=str(OUT/(stem+'.fbx')),use_selection=True,global_scale=1,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',object_types={'MESH'},use_mesh_modifiers=True,mesh_smooth_type='FACE',bake_anim=False,add_leaf_bones=False)
export(wheel,'Cedar_Wheel'); export([rail],'Mountain_Guardrail_12')

# Re-import OBJ exports into a temporary scene to verify round-trip dimension/pivot conservation.
original_names={o.name for o in bpy.data.objects}
roundtrip=[]
for stem,expected in [('Cedar_Wheel',[1.3,2.8,2.8]),('Mountain_Guardrail_12',rd)]:
    bpy.ops.object.select_all(action='DESELECT'); bpy.ops.wm.obj_import(filepath=str(OUT/(stem+'.obj')),forward_axis='NEGATIVE_Z',up_axis='Y')
    imported=list(bpy.context.selected_objects); points=[o.matrix_world@v.co for o in imported for v in o.data.vertices]
    actual=[max(p[i] for p in points)-min(p[i] for p in points) for i in range(3)]
    assert max(abs(a-b) for a,b in zip(actual,expected))<1e-4,(stem,expected,actual)
    roundtrip.append({'asset':stem,'format':'OBJ','expected':expected,'actual':actual,'passed':True})
    for o in imported: bpy.data.objects.remove(o,do_unlink=True)
report['roundtrip']=roundtrip
(OUT/'validation.json').write_text(json.dumps(report,indent=2))

# Stage originals for side-by-side review after exports; retain origins and stable export geometry.
for o in wheel: o.location=(3.7,0,1.4)
rail.location=(-1.5,1.7,0)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.02)); ground=bpy.context.object; ground.name='REVIEW_Ground'
for c in list(ground.users_collection): c.objects.unlink(ground)
review.objects.link(ground); ground.data.materials.append(material('Review_Ground',(.18,.21,.19),0,.85))
def area(name,location,energy,size):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size
    ob=bpy.data.objects.new(name,data); review.objects.link(ob); ob.location=location; ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
area('Key',(1,-5,10),1600,8); area('Fill',(-5,-2,6),1100,7); area('Rim',(3,6,8),2100,6)
camera_data=bpy.data.cameras.new('Review_Camera'); camera=bpy.data.objects.new('Review_Camera',camera_data); review.objects.link(camera)
camera.location=(13,-17,10); target=Vector((0,0,1.5)); camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler(); camera_data.type='ORTHO'; camera_data.ortho_scale=18
scene.camera=camera; scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.world=bpy.data.worlds.new('Review_World'); scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.28,.31,.35,1); scene.world.node_tree.nodes['Background'].inputs[1].default_value=.4
scene.render.resolution_x=1400; scene.render.resolution_y=800; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(OUT/'blender-review.png')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Scenic_Drift_Assets.blend'))
bpy.ops.render.render(write_still=True)
# A close wheel view makes spoke construction and tire grooves inspectable.
camera.location=(8.7,-5,4.3); camera.rotation_euler=(Vector((3.7,0,1.4))-camera.location).to_track_quat('-Z','Y').to_euler(); camera_data.ortho_scale=4.8
scene.render.resolution_x=900; scene.render.resolution_y=900; scene.render.filepath=str(OUT/'wheel-closeup.png')
rail.hide_render=True; bpy.ops.render.render(write_still=True); rail.hide_render=False
print('ASSET_VALIDATION_PASSED',json.dumps({'wheel':[1.3,2.8,2.8],'rail_span':12,'objects':len(report['objects']),'roundtrip':True}))
