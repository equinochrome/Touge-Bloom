local imported=assert(workspace:FindFirstChild('Cedar_Coupe_Prototype'),'Missing prototype import')
local revision=assert(workspace:FindFirstChild('Cedar_Coupe_BodyShell_R2'),'Missing revised shell')
revision:PivotTo(CFrame.Angles(0,math.pi,0))
local shell=assert(revision:FindFirstChild('BodyShell',true))
assert((shell.Size-Vector3.new(7,2.05,15)).Magnitude<.001,'Revised shell scale mismatch')
local old=imported:FindFirstChild('BodyShell',true)
local archive=Instance.new('Folder');archive.Name='CedarImportArchive';archive.Parent=game.ServerStorage
old.Parent=archive;shell.Parent=imported;revision.Parent=archive
imported.PrimaryPart=nil;imported.WorldPivot=CFrame.identity
imported.Name='CedarCoupePrototype'
local assets=game.ReplicatedStorage:FindFirstChild('Assets')
if not assets then assets=Instance.new('Folder');assets.Name='Assets';assets.Parent=game.ReplicatedStorage end
local cars=assets:FindFirstChild('Cars')
if not cars then cars=Instance.new('Folder');cars.Name='Cars';cars.Parent=assets end
assert(not cars:FindFirstChild(imported.Name),'Template already exists')
local root=Instance.new('Part');root.Name='Chassis';root.Size=Vector3.new(6.4,1.6,14);root.CFrame=CFrame.identity;root.Transparency=1;root.Anchored=true;root.CanCollide=true;root.CustomPhysicalProperties=PhysicalProperties.new(.6,.3,0,1,1);root.Parent=imported
imported.PrimaryPart=root
local body=Instance.new('Model');body.Name='BodyVisuals';body.WorldPivot=CFrame.identity;body.Parent=imported
local controls=Instance.new('Folder');controls.Name='Controls';controls.Parent=imported
local wheelFolder=Instance.new('Folder');wheelFolder.Name='Wheels';wheelFolder.Parent=imported
local mounts={FL=Vector3.new(-2.9,-.6,-4.7),FR=Vector3.new(2.9,-.6,-4.7),RL=Vector3.new(-2.9,-.6,4.5),RR=Vector3.new(2.9,-.6,4.5)}
local wheels={}
for _,n in {'FL','FR','RL','RR'} do local m=Instance.new('Model');m.Name=n;m.WorldPivot=CFrame.new(mounts[n]-Vector3.new(0,2.2,0));m:SetAttribute('Front',n:sub(1,1)=='F');m:SetAttribute('Radius',1.4);m:SetAttribute('Width',1.3);m:SetAttribute('MountOffset',mounts[n]);m.Parent=wheelFolder;wheels[n]=m end
local anchors={DriverSeat=Vector3.new(1.45,.65,.8),CameraTarget=Vector3.new(0,1.3,0),EngineAudio=Vector3.new(0,.4,-4),ExhaustAudio=Vector3.new(0,-.5,7.3),SteeringPivot=Vector3.new(1.45,1.2,-1.26),GearLeverPivot=Vector3.new(0,.4,-.52),HandbrakePivot=Vector3.new(.33,.55,.62),Pedal_Clutch=Vector3.new(.94,.32,-2.35),Pedal_Brake=Vector3.new(1.35,.32,-2.35),Pedal_Throttle=Vector3.new(1.76,.32,-2.35)}
for n,v in mounts do anchors['Suspension_'..n]=v end
for n,v in anchors do local at=Instance.new('Attachment');at.Name=n;at.Position=v;at.Parent=root end
local moving={SteeringWheel='SteeringPivot',GearLever='GearLeverPivot',HandbrakeLever='HandbrakePivot',Pedal_Clutch='Pedal_Clutch',Pedal_Brake='Pedal_Brake',Pedal_Throttle='Pedal_Throttle'}
local meshCount=0
for _,p in imported:GetChildren() do
 if p:IsA('MeshPart') then
  meshCount+=1;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Massless=true;p.Material=Enum.Material.SmoothPlastic
  local n=p.Name
  if n:match('Tire') or n:match('Sill') or n:match('Grille') or n:match('Splitter') or n:match('Valance') or n:match('Plate') or n:match('Pillar_B') or n:match('B_Pillar') or n:match('SteeringWheel') or n:match('Handbrake') or n:match('Dashboard') or n:match('Console') or n:match('Floor') then p.Color=Color3.fromRGB(18,24,29)
  elseif n:match('Seat') or n:match('Headrest') then p.Color=Color3.fromRGB(28,34,37)
  elseif n:match('BrakeLight') then p.Color=Color3.fromRGB(120,8,12);p:SetAttribute('Signal','Brake');p.Material=Enum.Material.Glass
  elseif n:match('Indicator') then p.Color=Color3.fromRGB(230,120,15);p:SetAttribute('Signal','Indicator');p.Material=Enum.Material.Glass
  elseif n:match('Headlight') or n:match('ReverseLight') then p.Color=Color3.fromRGB(185,215,225);p:SetAttribute('Signal',if n:match('Headlight') then 'Headlight' else 'Reverse');p.Material=Enum.Material.Glass
  elseif n:match('Glass') or n=='Windshield' then p.Color=Color3.fromRGB(35,65,76);p.Material=Enum.Material.Glass;p.Transparency=.25
  elseif n:match('Rim') or n:match('BrakeDisc') or n:match('Handle') or n:match('Exhaust') or n:match('Pedal') or n=='GearLever' then p.Color=Color3.fromRGB(150,161,170);p.Material=Enum.Material.Metal
  else p.Color=Color3.fromRGB(30,111,118) end
  local wn=n:match('^Wheel_(%u%u)_')
  if wn then p.Parent=wheels[wn]
  elseif moving[n] then
   p.Parent=controls;local pivot=CFrame.new(anchors[moving[n]]);local motor=Instance.new('Motor6D');motor.Name=n..'Motor';motor.Part0=root;motor.Part1=p;motor.C0=root.CFrame:ToObjectSpace(pivot);motor.C1=p.CFrame:ToObjectSpace(pivot);motor.Parent=controls
  else
   p.Parent=body;local weld=Instance.new('WeldConstraint');weld.Name='VisualWeld';weld.Part0=root;weld.Part1=p;weld.Parent=p
  end
 end
end
assert(meshCount==65,'Unexpected mesh count '..meshCount)
for _,n in {'FL','FR','RL','RR'} do
 local w=wheels[n];local tire=assert(w:FindFirstChild('Wheel_'..n..'_Tire'));local expected=mounts[n]-Vector3.new(0,2.2,0)
 assert((tire.Position-expected).Magnitude<.001,'Wheel position mismatch '..n)
 assert((tire.Size-Vector3.new(1.3,2.8,2.8)).Magnitude<.001,'Wheel size mismatch '..n)
 w.PrimaryPart=nil;w.WorldPivot=CFrame.new(expected)
end
assert(imported:FindFirstChild('Headlight_R',true).Position.Z<0,'Front orientation mismatch')
imported:SetAttribute('AssetVersion','CedarCoupe_R2');imported:SetAttribute('Readiness','Model prepared; mechanics integration pending');imported:SetAttribute('DefaultSpringLength',2.2);imported:SetAttribute('TriangleBudget',43964)
imported.Parent=cars
local preview=imported:Clone();preview.Name='CedarCoupeReview';preview.Parent=workspace;preview:PivotTo(CFrame.new(50,2.6,0))
for _,n in {'FL','FR','RL','RR'} do local w=preview.Wheels[n];w:PivotTo(preview.Chassis.CFrame*CFrame.new(mounts[n]-Vector3.new(0,.6,0))) end
game:GetService('Selection'):Set({imported})
return {template=imported:GetFullName(),meshes=meshCount,size=tostring(imported:GetExtentsSize()),wheelMountsVerified=true,frontVerified=true,bodyShell=shell.MeshId}
