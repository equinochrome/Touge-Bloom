-- Chase camera that follows a blend of the car's heading and its travel direction,
-- so a drift angle stays visible. FOV widens with speed.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarConfig = require(ReplicatedStorage.Shared.Config.CarConfig)

local CameraController = {}

local BIND_NAME = "DriftChaseCamera"

function CameraController.start(chassis: BasePart)
	local settings = CarConfig.Camera
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	local look = chassis.CFrame.LookVector
	local direction = Vector3.new(look.X, 0, look.Z).Unit
	local position = chassis.Position - direction * settings.Distance + Vector3.yAxis * settings.Height

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not chassis:IsDescendantOf(Workspace) then
			return
		end
		local cf = chassis.CFrame
		local velocity = chassis.AssemblyLinearVelocity
		local heading = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		local travel = Vector3.new(velocity.X, 0, velocity.Z)

		local target = if heading.Magnitude > 1e-3 then heading.Unit else direction
		if travel.Magnitude > 10 then
			local blended = target:Lerp(travel.Unit, settings.VelocityBlend)
			if blended.Magnitude > 1e-3 then
				target = blended.Unit
			end
		end
		local turned = direction:Lerp(target, 1 - math.exp(-settings.YawFollow * dt))
		if turned.Magnitude > 1e-3 then
			direction = turned.Unit
		end

		local desired = cf.Position - direction * settings.Distance + Vector3.yAxis * settings.Height
		position = position:Lerp(desired, 1 - math.exp(-settings.PositionFollow * dt))
		camera.CFrame = CFrame.lookAt(position, cf.Position + Vector3.yAxis * settings.LookHeight)

		local maxSpeed = chassis.Parent and chassis.Parent:GetAttribute("MaxSpeed") or 150
		camera.FieldOfView = settings.BaseFov + settings.SpeedFov * math.clamp(velocity.Magnitude / maxSpeed, 0, 1)
	end)
end

function CameraController.stop()
	RunService:UnbindFromRenderStep(BIND_NAME)
end

return CameraController
