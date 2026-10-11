-- Car layout and tuning. Every value in Tuning is mirrored as an Attribute on the car model,
-- so it can be edited live during a Studio play test (select the car model on the client view).
-- Accelerations are in studs/s^2 and are multiplied by the car's mass, so they do not depend on part density.
local CarConfig = {}

CarConfig.Layout = {
	ChassisSize = Vector3.new(6.4, 1.6, 14),
	ChassisDensity = 0.6,
	-- Dense invisible part welded low to pull the center of mass down. +Z is the rear of the car.
	BallastSize = Vector3.new(4, 0.4, 7),
	BallastOffset = Vector3.new(0, -0.8, 0.4),
	BallastDensity = 20,
	-- Suspension mount points relative to the chassis center. -Z is the front of the car.
	WheelMounts = {
		{ name = "FL", offset = Vector3.new(-2.9, -0.6, -4.7), front = true },
		{ name = "FR", offset = Vector3.new(2.9, -0.6, -4.7), front = true },
		{ name = "RL", offset = Vector3.new(-2.9, -0.6, 4.5), front = false },
		{ name = "RR", offset = Vector3.new(2.9, -0.6, 4.5), front = false },
	},
	WheelWidth = 1.3,
	SpawnHeight = 4,
}

CarConfig.Tuning = {
	WheelRadius = 1.4,

	SuspensionRestLength = 2.2,
	SuspensionFrequency = 2.2, -- Hz, sets spring rate from the mass on each wheel
	SuspensionDamping = 0.45, -- damping ratio
	AntiRoll = 0.5, -- fraction of spring rate resisting left/right compression difference

	Grip = 1.1, -- friction coefficient against wheel load
	PeakSlipAngle = 8, -- degrees, full grip up to here
	SlideFalloffAngle = 20, -- degrees, grip has dropped to SlidingGrip by here
	SlidingGrip = 0.75, -- grip multiplier while sliding (the drift plateau)
	LateralResponse = 0.5, -- fraction of sideways corner velocity removed per frame before the grip limit
	TireForceHeight = 1.0, -- studs above the contact point where tire forces act; higher means less body roll

	EngineAccel = 90,
	MaxSpeed = 150,
	ReverseAccel = 40,
	MaxReverseSpeed = 35,
	BrakeAccel = 170,
	HandbrakeRearGrip = 0.4,
	RollingResistance = 4,
	AirDrag = 0.0012, -- per (stud/s)^2

	MaxSteerAngle = 32, -- degrees at standstill
	MinSteerAngle = 10, -- degrees at SteerSpeedRef and above
	SteerSpeedRef = 130,
	SteerRate = 3.5, -- input units per second when turning in
	SteerReturnRate = 6, -- input units per second when releasing or reversing direction
}

CarConfig.Camera = {
	Distance = 22,
	Height = 7,
	LookHeight = 2.5,
	VelocityBlend = 0.35, -- how much the camera follows travel direction instead of heading
	YawFollow = 6,
	PositionFollow = 10,
	BaseFov = 70,
	SpeedFov = 15, -- extra FOV at MaxSpeed
}

return CarConfig
