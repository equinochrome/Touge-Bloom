-- Raycast-suspension car, simulated on the owning client.
-- Each physics frame: four suspension raycasts, a spring/damper per wheel, then simple tire forces
-- (grip that eases off to a sliding plateau, friction circle, rear-wheel drive, handbrake),
-- all applied as impulses on the chassis. Wheels are client-side visuals only.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarConfig = require(ReplicatedStorage.Shared.Config.CarConfig)
local RoadGeometry = require(ReplicatedStorage.Shared.Gen.RoadGeometry)

local CarController = {}
CarController.__index = CarController

local MIN_DT, MAX_DT = 1 / 240, 1 / 20
local STICK_DEADZONE = 0.12
local HOLD_SPEED = 1.5 -- below this with no throttle, the tires hold the car still
local FALL_RESET_HEIGHT = -60
local GAMEPAD = Enum.UserInputType.Gamepad1

local function moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

-- Attribute values override CarConfig.Tuning, so tuning can be changed while playing.
local function readTuning(model: Model)
	local tuning = {}
	for key, default in CarConfig.Tuning do
		local value = model:GetAttribute(key)
		tuning[key] = if typeof(value) == typeof(default) then value else default
	end
	return tuning
end

-- 1 up to the peak slip angle, then easing down to the sliding plateau.
local function gripCurve(slipDegrees: number, tuning): number
	if slipDegrees <= tuning.PeakSlipAngle then
		return 1
	end
	local range = math.max(tuning.SlideFalloffAngle - tuning.PeakSlipAngle, 1e-3)
	local t = math.clamp((slipDegrees - tuning.PeakSlipAngle) / range, 0, 1)
	return 1 + (tuning.SlidingGrip - 1) * t
end

function CarController.new(model: Model, circuit, ignore: { Instance })
	local self = setmetatable({}, CarController)
	self.model = model
	self.chassis = model:WaitForChild("Chassis") :: BasePart
	self.circuit = circuit
	self.tuning = readTuning(model)
	self.steer = 0
	self.steerAngle = 0
	self.input = { throttle = 0, steer = 0, handbrake = false }
	self.telemetry = { speed = 0, forwardSpeed = 0, driftAngle = 0, grounded = 0, onRoad = 0 }

	self.visuals = Instance.new("Folder")
	self.visuals.Name = "CarVisuals"
	self.visuals.Parent = Workspace

	self.wheels = {}
	for _, mount in CarConfig.Layout.WheelMounts do
		local part = Instance.new("Part")
		part.Name = "Wheel" .. mount.name
		part.Shape = Enum.PartType.Cylinder -- axis along X, which is the car's axle direction
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Color = Color3.fromRGB(28, 28, 30)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = self.visuals
		table.insert(self.wheels, {
			mount = mount,
			part = part,
			springLength = self.tuning.SuspensionRestLength,
			compression = 0,
			grounded = false,
			onRoad = false,
			rollSpeed = 0,
			spin = 0,
		})
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { model, self.visuals }
	for _, instance in ignore do
		table.insert(filter, instance)
	end
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	self.rayParams = params

	return self
end

function CarController:readInput()
	local throttle, steer, handbrake = 0, 0, false
	if not UserInputService:GetFocusedTextBox() then
		local function down(...)
			for _, keyCode in { ... } do
				if UserInputService:IsKeyDown(keyCode) then
					return true
				end
			end
			return false
		end
		if down(Enum.KeyCode.W, Enum.KeyCode.Up) then
			throttle += 1
		end
		if down(Enum.KeyCode.S, Enum.KeyCode.Down) then
			throttle -= 1
		end
		if down(Enum.KeyCode.D, Enum.KeyCode.Right) then
			steer += 1
		end
		if down(Enum.KeyCode.A, Enum.KeyCode.Left) then
			steer -= 1
		end
		handbrake = down(Enum.KeyCode.Space)
	end

	if UserInputService:GetGamepadConnected(GAMEPAD) then
		for _, input in UserInputService:GetGamepadState(GAMEPAD) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(input.Position.X) > STICK_DEADZONE then
				steer = input.Position.X
			elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
				throttle += input.Position.Z
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				throttle -= input.Position.Z
			end
		end
		handbrake = handbrake or UserInputService:IsGamepadButtonDown(GAMEPAD, Enum.KeyCode.ButtonA)
	end

	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1), handbrake
end

function CarController:step(rawDt: number)
	local chassis = self.chassis
	if not chassis:IsDescendantOf(Workspace) then
		return
	end
	if chassis.Position.Y < FALL_RESET_HEIGHT then
		self:reset()
		return
	end

	local dt = math.clamp(rawDt, MIN_DT, MAX_DT)
	local tuning = readTuning(self.model)
	self.tuning = tuning

	local throttle, steerTarget, handbrake = self:readInput()
	self.input.throttle, self.input.steer, self.input.handbrake = throttle, steerTarget, handbrake
	local turningIn = math.abs(steerTarget) > math.abs(self.steer) and steerTarget * self.steer >= 0
	local steerRate = if turningIn then tuning.SteerRate else tuning.SteerReturnRate
	self.steer = moveTowards(self.steer, steerTarget, steerRate * dt)

	local cf = chassis.CFrame
	local up, forward, right = cf.UpVector, cf.LookVector, cf.RightVector
	local velocity = chassis.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	local forwardSpeed = velocity:Dot(forward)

	local speedFactor = math.clamp(speed / tuning.SteerSpeedRef, 0, 1)
	local maxSteer = tuning.MaxSteerAngle + (tuning.MinSteerAngle - tuning.MaxSteerAngle) * speedFactor
	self.steerAngle = math.rad(self.steer * maxSteer)

	local mass = chassis.AssemblyMass
	local massPerWheel = mass / 4
	local gravity = Workspace.Gravity
	local omega = 2 * math.pi * tuning.SuspensionFrequency
	local springRate = massPerWheel * omega * omega
	local damperRate = 2 * tuning.SuspensionDamping * massPerWheel * omega
	local rest = tuning.SuspensionRestLength
	local radius = tuning.WheelRadius

	-- Pass 1: suspension raycasts.
	local grounded, onRoad = 0, 0
	for _, wheel in self.wheels do
		local mountPosition = cf:PointToWorldSpace(wheel.mount.offset)
		wheel.mountPosition = mountPosition
		local hit = Workspace:Raycast(mountPosition, -up * (rest + radius), self.rayParams)
		if hit then
			wheel.springLength = math.clamp(hit.Distance - radius, 0, rest)
			wheel.compression = rest - wheel.springLength
			wheel.grounded = true
			wheel.contact = hit.Position
			wheel.normal = hit.Normal
			wheel.onRoad = hit.Instance:HasTag("Road")
			grounded += 1
			if wheel.onRoad then
				onRoad += 1
			end
		else
			wheel.springLength = rest
			wheel.compression = 0
			wheel.grounded = false
			wheel.onRoad = false
		end
	end

	-- Anti-roll: shift spring force toward the more compressed wheel of each axle (FL/FR, RL/RR).
	local antiRoll = { 0, 0, 0, 0 }
	for axle = 0, 1 do
		local left, rightWheel = self.wheels[axle * 2 + 1], self.wheels[axle * 2 + 2]
		if left.grounded and rightWheel.grounded then
			local transfer = (left.compression - rightWheel.compression) * springRate * tuning.AntiRoll
			antiRoll[axle * 2 + 1] = transfer
			antiRoll[axle * 2 + 2] = -transfer
		end
	end

	-- Pass 2: suspension and tire forces.
	for index, wheel in self.wheels do
		if not wheel.grounded then
			wheel.rollSpeed *= 0.98
			continue
		end

		local mountVelocity = chassis:GetVelocityAtPosition(wheel.mountPosition)
		local compressionSpeed = -mountVelocity:Dot(up)
		local load = math.max(0, springRate * wheel.compression + damperRate * compressionSpeed + antiRoll[index])
		chassis:ApplyImpulseAtPosition(up * (load * dt), wheel.mountPosition)

		local normal = wheel.normal
		local isFront = wheel.mount.front
		local heading = if isFront
			then forward * math.cos(self.steerAngle) + right * math.sin(self.steerAngle)
			else forward
		local wheelForward = (heading - normal * heading:Dot(normal)).Unit
		local wheelRight = wheelForward:Cross(normal).Unit

		local contactVelocity = chassis:GetVelocityAtPosition(wheel.contact)
		local longSpeed = contactVelocity:Dot(wheelForward)
		local latSpeed = contactVelocity:Dot(wheelRight)
		wheel.rollSpeed = longSpeed

		local slip = math.deg(math.atan2(math.abs(latSpeed), math.max(math.abs(longSpeed), 0.5)))
		local handbraking = handbrake and not isFront
		local grip = tuning.Grip * gripCurve(slip, tuning) * (if handbraking then tuning.HandbrakeRearGrip else 1)
		local maxForce = grip * load

		-- Lateral: remove part of the sideways slide each frame, limited by grip.
		local latForce = math.clamp(-latSpeed * massPerWheel * tuning.LateralResponse / dt, -maxForce, maxForce)

		-- Longitudinal: the force that would stop this corner's rolling motion this frame.
		local stopForce = math.abs(longSpeed) * massPerWheel / dt
		local longForce = 0
		if handbraking then
			longForce = -math.sign(longSpeed) * math.min(tuning.BrakeAccel * massPerWheel, stopForce)
		elseif throttle < 0 and forwardSpeed > 2 then
			longForce = -math.sign(longSpeed) * math.min(tuning.BrakeAccel * massPerWheel, stopForce)
		elseif throttle > 0 and not isFront then
			local taper = 1 - math.clamp(forwardSpeed / tuning.MaxSpeed, 0, 1) ^ 2
			longForce = throttle * tuning.EngineAccel * (mass / 2) * taper
		elseif throttle < 0 and not isFront then
			local taper = 1 - math.clamp(-forwardSpeed / tuning.MaxReverseSpeed, 0, 1) ^ 2
			longForce = throttle * tuning.ReverseAccel * (mass / 2) * taper
		elseif throttle == 0 then
			if math.abs(longSpeed) < HOLD_SPEED then
				-- Hold still, including against the slope.
				longForce = -longSpeed * massPerWheel / dt + gravity * wheelForward.Y * massPerWheel
			else
				longForce = -math.sign(longSpeed) * math.min(tuning.RollingResistance * massPerWheel, stopForce)
			end
		end

		-- Friction circle: drive or braking force uses up grip available for cornering.
		local total = math.sqrt(latForce * latForce + longForce * longForce)
		if total > maxForce and total > 0 then
			local scale = maxForce / total
			latForce *= scale
			longForce *= scale
		end

		local applyAt = wheel.contact + up * tuning.TireForceHeight
		chassis:ApplyImpulseAtPosition((wheelRight * latForce + wheelForward * longForce) * dt, applyAt)
	end

	if speed > 0.1 then
		chassis:ApplyImpulse(-velocity * (speed * tuning.AirDrag * mass * dt))
	end

	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local driftAngle = 0
	if flatVelocity.Magnitude > 5 and flatForward.Magnitude > 1e-3 then
		driftAngle = math.deg(math.acos(math.clamp(flatForward.Unit:Dot(flatVelocity.Unit), -1, 1)))
	end
	local telemetry = self.telemetry
	telemetry.speed, telemetry.forwardSpeed, telemetry.driftAngle = speed, forwardSpeed, driftAngle
	telemetry.grounded, telemetry.onRoad = grounded, onRoad
end

function CarController:updateVisuals(dt: number)
	local cf = self.chassis.CFrame
	local radius = self.tuning.WheelRadius
	local size = Vector3.new(CarConfig.Layout.WheelWidth, radius * 2, radius * 2)
	for _, wheel in self.wheels do
		if wheel.part.Size ~= size then
			wheel.part.Size = size
		end
		wheel.spin = (wheel.spin - wheel.rollSpeed / radius * dt) % (2 * math.pi)
		local center = cf:PointToWorldSpace(wheel.mount.offset) - cf.UpVector * wheel.springLength
		local steer = if wheel.mount.front then -self.steerAngle else 0
		wheel.part.CFrame = CFrame.new(center) * cf.Rotation * CFrame.Angles(0, steer, 0) * CFrame.Angles(wheel.spin, 0, 0)
	end
end

function CarController:reset()
	local index = RoadGeometry.nearestIndex(self.circuit, self.chassis.Position)
	self.model:PivotTo(RoadGeometry.spawnPose(self.circuit, index, CarConfig.Layout.SpawnHeight))
	self.chassis.AssemblyLinearVelocity = Vector3.zero
	self.chassis.AssemblyAngularVelocity = Vector3.zero
	self.steer = 0
end

return CarController
