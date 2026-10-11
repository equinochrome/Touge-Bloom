-- Phase 0 client: builds the road visuals locally, drives this player's car and shows a debug readout.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadConfig = require(Shared.Config.RoadConfig)
local RoadGeometry = require(Shared.Gen.RoadGeometry)
local TestCircuits = require(Shared.Gen.TestCircuits)

local RoadVisualBuilder = require(script.RoadVisualBuilder)
local CarController = require(script.CarController)
local CameraController = require(script.CameraController)
local DebugOverlay = require(script.DebugOverlay)

local player = Players.LocalPlayer
local overlay = DebugOverlay.new()

local circuit = RoadGeometry.build(TestCircuits.Phase0Loop, RoadConfig)

local roadVisuals = Instance.new("Folder")
roadVisuals.Name = "RoadVisual"
roadVisuals.Parent = Workspace
local keepAlive = {}
local buildStart = os.clock()
local road = RoadVisualBuilder.build(circuit, RoadConfig, roadVisuals, keepAlive)
local buildMs = (os.clock() - buildStart) * 1000
print(string.format("[Phase0] Road visuals: %s, %d chunks, %d parts, %.0f ms", road.mode, road.chunks, road.parts, buildMs))

local car = Workspace:WaitForChild("Cars"):WaitForChild("Car_" .. player.UserId)
local controller = CarController.new(car, circuit, { roadVisuals })
CameraController.start(controller.chassis)

local showCollision = false
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
		controller:reset()
	elseif input.KeyCode == Enum.KeyCode.C then
		-- Local-only change: shows the server's collision boxes in alternating colors.
		showCollision = not showCollision
		local collision = Workspace:FindFirstChild("RoadCollision")
		if collision then
			for _, part in collision:GetChildren() do
				part.Transparency = if showCollision then 0.5 else 1
			end
		end
	end
end)

RunService.PreSimulation:Connect(function(dt)
	controller:step(dt)
end)

local fps = 60
local sinceOverlay = 0
RunService.RenderStepped:Connect(function(dt)
	controller:updateVisuals(dt)

	fps += (1 / math.max(dt, 1e-3) - fps) * math.min(dt * 4, 1)
	sinceOverlay += dt
	if sinceOverlay < 0.1 then
		return
	end
	sinceOverlay = 0

	local serverHash = Workspace:GetAttribute("CircuitHash")
	local hashStatus = if serverHash == nil then "waiting" elseif serverHash == circuit.hash then "MATCH" else "MISMATCH"
	local t = controller.telemetry
	local wheelText = {}
	for _, wheel in controller.wheels do
		table.insert(
			wheelText,
			string.format("%s %.2f%s", wheel.mount.name, wheel.compression, if wheel.grounded then (if wheel.onRoad then "R" else "G") else "-")
		)
	end
	local roadLine = string.format("Road: %s  chunks %d  parts %d  built %.0f ms", road.mode, road.chunks, road.parts, buildMs)
	local lines = {
		roadLine,
		string.format(
			"Circuit: %.0f studs  %d samples  min radius %.1f  max grade %.1f%%",
			circuit.length,
			circuit.count,
			circuit.minRadius,
			circuit.maxGrade * 100
		),
		string.format("Hash: client %s  server %s  %s", circuit.hash, tostring(serverHash), hashStatus),
		string.format(
			"FPS %.0f  speed %.0f studs/s (~%.0f km/h)  drift %.0f deg  steer %.2f",
			fps,
			t.speed,
			t.speed * 1.008,
			t.driftAngle,
			controller.steer
		),
		"Wheels (compression, R=road G=other -=air): " .. table.concat(wheelText, "  "),
		"W/S throttle, brake/reverse  A/D steer  Space handbrake  R reset  C show collision  (Studio: Shift+P free camera)",
	}
	if road.fallbackReason then
		table.insert(lines, 2, "Fallback reason: " .. road.fallbackReason)
	end
	overlay:setLines(lines)
end)
