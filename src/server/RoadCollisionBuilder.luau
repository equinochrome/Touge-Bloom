-- Invisible box segments that the car's suspension raycasts hit. One box per centerline segment,
-- pitched to follow the road and lengthened enough to close the wedge gap on the outside of corners.
local RoadGeometry = require(game:GetService("ReplicatedStorage").Shared.Gen.RoadGeometry)

local RoadCollisionBuilder = {}

local DEBUG_COLORS = { Color3.fromRGB(255, 120, 60), Color3.fromRGB(60, 160, 255) }

-- Horizontal heading change at a sample, in radians.
local function turnAngle(circuit, index: number): number
	local before = RoadGeometry.sample(circuit, index).position - RoadGeometry.sample(circuit, index - 1).position
	local after = RoadGeometry.sample(circuit, index + 1).position - RoadGeometry.sample(circuit, index).position
	local a = Vector3.new(before.X, 0, before.Z).Unit
	local b = Vector3.new(after.X, 0, after.Z).Unit
	return math.acos(math.clamp(a:Dot(b), -1, 1))
end

function RoadCollisionBuilder.build(circuit, roadConfig, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "RoadCollision"

	local halfWidth = roadConfig.Width / 2
	local thickness = roadConfig.CollisionThickness
	for i = 1, circuit.count do
		local a = RoadGeometry.sample(circuit, i).position
		local b = RoadGeometry.sample(circuit, i + 1).position
		local segment = b - a
		local forward = segment.Unit
		local right = forward:Cross(Vector3.yAxis).Unit
		local up = right:Cross(forward)

		local extendStart = halfWidth * math.tan(turnAngle(circuit, i) / 2) + roadConfig.CollisionOverlap
		local extendEnd = halfWidth * math.tan(turnAngle(circuit, i + 1) / 2) + roadConfig.CollisionOverlap
		local center = (a + b) / 2 + forward * ((extendEnd - extendStart) / 2) - up * (thickness / 2)

		local part = Instance.new("Part")
		part.Name = "RoadSegment" .. i
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Material = Enum.Material.SmoothPlastic
		part.Color = DEBUG_COLORS[i % 2 + 1]
		part.Size = Vector3.new(roadConfig.Width, thickness, segment.Magnitude + extendStart + extendEnd)
		part.CFrame = CFrame.fromMatrix(center, right, up, -forward)
		part:AddTag("Road")
		part.Parent = folder
	end

	folder.Parent = parent
	return folder
end

return RoadCollisionBuilder
