-- Builds a placeholder car (box chassis + low ballast) for each player at the start line and
-- hands physics ownership to that player's client, which runs the suspension and tire forces.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarConfig = require(ReplicatedStorage.Shared.Config.CarConfig)
local RoadGeometry = require(ReplicatedStorage.Shared.Gen.RoadGeometry)

local CarSpawner = {}

local SPAWN_LANES = { 0, -9, 9 }

local function weldedPart(chassis: BasePart, name: string, size: Vector3, offset: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = chassis.CFrame * offset
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = part
	weld.Parent = part
	part.Parent = chassis.Parent
	return part
end

local function buildCar(player: Player, pose: CFrame): Model
	local layout = CarConfig.Layout
	local model = Instance.new("Model")
	model.Name = "Car_" .. player.UserId
	model:SetAttribute("OwnerUserId", player.UserId)
	for key, value in CarConfig.Tuning do
		model:SetAttribute(key, value)
	end

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = layout.ChassisSize
	chassis.CFrame = pose
	chassis.Color = Color3.fromRGB(220, 70, 40)
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CustomPhysicalProperties = PhysicalProperties.new(layout.ChassisDensity, 0.3, 0, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local chassisSize = layout.ChassisSize
	local ballast = weldedPart(chassis, "Ballast", layout.BallastSize, CFrame.new(layout.BallastOffset))
	ballast.Massless = false
	ballast.Transparency = 1
	ballast.CustomPhysicalProperties = PhysicalProperties.new(layout.BallastDensity, 0.3, 0, 1, 1)

	local cabin = weldedPart(chassis, "Cabin", Vector3.new(5.6, 1.8, 6), CFrame.new(0, chassisSize.Y / 2 + 0.9, 0.8))
	cabin.Color = Color3.fromRGB(30, 34, 40)
	cabin.Material = Enum.Material.Glass
	cabin.Transparency = 0.2

	-- White bar on the nose so the front is obvious while testing.
	local nose = weldedPart(chassis, "Nose", Vector3.new(chassisSize.X, 0.3, 1), CFrame.new(0, chassisSize.Y / 2 + 0.15, -chassisSize.Z / 2 + 0.5))
	nose.Color = Color3.fromRGB(245, 245, 245)

	return model
end

function CarSpawner.init(circuit)
	local carsFolder = Instance.new("Folder")
	carsFolder.Name = "Cars"
	carsFolder.Parent = Workspace

	local spawnCount = 0
	local function spawnFor(player: Player)
		local lane = SPAWN_LANES[spawnCount % #SPAWN_LANES + 1]
		spawnCount += 1
		local pose = RoadGeometry.spawnPose(circuit, 1, CarConfig.Layout.SpawnHeight, lane)
		local model = buildCar(player, pose)
		model.Parent = carsFolder
		model.PrimaryPart:SetNetworkOwner(player)
	end

	Players.PlayerAdded:Connect(spawnFor)
	for _, player in Players:GetPlayers() do
		spawnFor(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local model = carsFolder:FindFirstChild("Car_" .. player.UserId)
		if model then
			model:Destroy()
		end
	end)
end

return CarSpawner
