-- Phase 0 server: builds the fixed test circuit's road collision and spawns one car per player.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RoadConfig = require(Shared.Config.RoadConfig)
local RoadGeometry = require(Shared.Gen.RoadGeometry)
local TestCircuits = require(Shared.Gen.TestCircuits)

local RoadCollisionBuilder = require(script.RoadCollisionBuilder)
local CarSpawner = require(script.CarSpawner)

local circuit = RoadGeometry.build(TestCircuits.Phase0Loop, RoadConfig)
RoadCollisionBuilder.build(circuit, RoadConfig, Workspace)

-- Clients rebuild the same circuit locally and compare against this hash.
Workspace:SetAttribute("CircuitHash", circuit.hash)

print(
	string.format(
		"[Phase0] Circuit built: %d samples, %.0f studs, spacing %.2f, min radius %.1f, max grade %.1f%%, hash %s",
		circuit.count,
		circuit.length,
		circuit.spacing,
		circuit.minRadius,
		circuit.maxGrade * 100,
		circuit.hash
	)
)

CarSpawner.init(circuit)
