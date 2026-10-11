"""Original modular roadside mesh authoring; OBJ units are Roblox studs."""
from pathlib import Path
import argparse, math, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

class Mesh:
    def __init__(self): self.faces=[]
    def tri(self,a,b,c,uv,mat):
        p=np.array([a,b,c],dtype=float); n=np.cross(p[1]-p[0],p[2]-p[0]); length=np.linalg.norm(n)
        if length<1e-9: raise ValueError('Degenerate triangle')
        self.faces.append((p,n/length,np.array(uv),mat))
    def quad(self,a,b,c,d,mat='paint'):
        self.tri(a,b,c,[(0,0),(1,0),(1,1)],mat)
        self.tri(a,c,d,[(0,0),(1,1),(0,1)],mat)
    def cylinder(self,center,radius,length,axis,mat='steel',sides=16):
        center=np.array(center,float); ax=np.eye(3)[axis]; other=[i for i in range(3) if i!=axis]
        if axis==1: other=[2,0]
        rings=[]
        for end in [-.5,.5]:
            ring=[]
            for i in range(sides):
                theta=2*math.pi*i/sides; p=center+ax*length*end
                p[other[0]]+=radius*math.cos(theta); p[other[1]]+=radius*math.sin(theta); ring.append(p)
            rings.append(ring)
        for i in range(sides):
            j=(i+1)%sides; self.quad(rings[0][i],rings[0][j],rings[1][j],rings[1][i],mat)
            self.tri(center-ax*length/2,rings[0][j],rings[0][i],[(.5,.5),(0,0),(1,0)],mat)
            self.tri(center+ax*length/2,rings[1][i],rings[1][j],[(.5,.5),(0,0),(1,0)],mat)

def build():
    m=Mesh(); count=40; thickness=.055
    profile=[]
    for i in range(count+1):
        t=i/count; profile.append((2.65+.55-1.1*t,.20+.115*math.cos(4*math.pi*t)))
    perimeter=profile+[(y,z-thickness) for y,z in reversed(profile)]
    for i in range(len(perimeter)):
        j=(i+1)%len(perimeter); y,z=perimeter[i]; yy,zz=perimeter[j]
        m.quad((-6,y,z),(6,y,z),(6,yy,zz),(-6,yy,zz))
    # Each end is capped by thin quads along the folded profile, avoiding an invalid concave fan.
    for x in [-6,6]:
        for i in range(count):
            y,z=profile[i]; yy,zz=profile[i+1]
            points=[(x,y,z),(x,yy,zz),(x,yy,zz-thickness),(x,y,z-thickness)]
            if x<0: points.reverse()
            m.quad(*points)
    for x in [-4.5,4.5]:
        m.cylinder((x,1.42,-.24),.17,2.84,1,'paint',24)
        m.cylinder((x,2.83,-.24),.19,.07,1,'steel',24)
        for y in [2.42,2.88]:
            m.cylinder((x,y,.25),.08,.16,2,'steel',6)
        # Narrow dark connector behind the beam, modeled as mesh rather than Studio primitives.
        m.cylinder((x,2.65,-.08),.11,.30,2,'steel',16)
    return m

def export(m,out):
    out.mkdir(parents=True,exist_ok=True)
    text=['# Original Codex guardrail mesh; Y up, X length; units studs','mtllib Mountain_Guardrail.mtl','o Mountain_Guardrail_12','s off']
    prev=None
    for i,(p,n,uv,mat) in enumerate(m.faces):
        for a in p: text.append('v '+' '.join(f'{v:.6f}' for v in a))
        for a in uv: text.append('vt '+' '.join(f'{v:.6f}' for v in a))
        for _ in range(3): text.append('vn '+' '.join(f'{v:.6f}' for v in n))
        if mat!=prev: text.append('usemtl '+mat); prev=mat
        indices=[3*i+j+1 for j in range(3)]; text.append('f '+' '.join(f'{j}/{j}/{j}' for j in indices))
    (out/'Mountain_Guardrail_12.obj').write_text('\n'.join(text)+'\n')
    (out/'Mountain_Guardrail.mtl').write_text('newmtl paint\nKd 0.78 0.79 0.75\nKs 0.25 0.25 0.25\nNs 35\nmap_Kd rail_paint_color.png\n\nnewmtl steel\nKd 0.31 0.34 0.36\nKs 0.7 0.7 0.7\nNs 80\n')
    rng=np.random.default_rng(471); noise=rng.normal(0,1.3,(512,512,1)); base=np.array([199,202,192]).reshape(1,1,3)
    Image.fromarray(np.clip(base+noise,0,255).astype('uint8')).save(out/'rail_paint_color.png')
    Image.new('RGB',(512,512),(145,145,145)).save(out/'rail_paint_roughness.png')
    Image.new('RGB',(512,512),(0,0,0)).save(out/'rail_paint_metalness.png')
    Image.new('RGB',(512,512),(128,128,255)).save(out/'rail_paint_normal.png')
    vertices=np.concatenate([p for p,_,_,_ in m.faces]); bbox=[vertices.min(0).tolist(),vertices.max(0).tolist()]
    (out/'mesh-info.json').write_text(json.dumps({'name':'Mountain_Guardrail_12','triangles':len(m.faces),'bounds':bbox,'axis':'Y up, X module length','pivot':[0,0,0],'status':'candidate; Studio import pending','source':'original procedural mesh authoring','reference':'Design/References/Modeling Detail Board.md R09'},indent=2))

def preview(m,out):
    scale=2; W,H=1100*scale,620*scale; im=Image.new('RGB',(W,H),(232,235,231)); draw=ImageDraw.Draw(im)
    eye=np.array([14.,8.,15.]); forward=-eye/np.linalg.norm(eye); right=np.cross(forward,[0,1,0]); right/=np.linalg.norm(right); up=np.cross(right,forward)
    factor=64*scale
    def project(p):
        p=p-np.array([0,1.5,0]); return (W/2+np.dot(p,right)*factor,H*.53-np.dot(p,up)*factor)
    # Neutral ground plane in the same coordinate system.
    ground=[project(np.array(p)) for p in [(-9,-.03,-2),(9,-.03,-2),(9,-.03,2),(-9,-.03,2)]]
    draw.polygon(ground,fill=(207,213,205))
    light=np.array([-.3,1,.7]); light/=np.linalg.norm(light)
    colors={'paint':np.array([199,202,192]),'steel':np.array([90,99,107])}
    faces=sorted(m.faces,key=lambda f:np.dot(f[0].mean(0),forward),reverse=True)
    for p,n,uv,mat in faces:
        shade=.48+.52*max(0,float(np.dot(n,light))); color=tuple(np.clip(colors[mat]*shade,0,255).astype(int))
        draw.polygon([project(a) for a in p],fill=color)
    fontpath='C:/Windows/Fonts/segoeui.ttf'; boldpath='C:/Windows/Fonts/segoeuib.ttf'
    title=ImageFont.truetype(boldpath,28*scale); small=ImageFont.truetype(fontpath,17*scale)
    draw.text((40*scale,30*scale),'MOUNTAIN ROADS / ASSET STUDY 01',font=title,fill=(32,51,43))
    draw.text((40*scale,77*scale),'Original folded steel rail with posts, caps and mounting bolts',font=small,fill=(70,83,75))
    draw.text((40*scale,H-84*scale),f'12-stud modular span  |  {len(m.faces):,} triangles  |  OBJ + material maps',font=small,fill=(45,67,54))
    draw.text((40*scale,H-51*scale),'Candidate geometry preview. Studio import and lighting review still required.',font=small,fill=(83,94,85))
    im.resize((1100,620),Image.Resampling.LANCZOS).save(out/'guardrail-preview.png')

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--out',required=True); args=parser.parse_args(); out=Path(args.out); mesh=build(); export(mesh,out); preview(mesh,out); print(json.dumps({'triangles':len(mesh.faces),'output':str(out)}))
