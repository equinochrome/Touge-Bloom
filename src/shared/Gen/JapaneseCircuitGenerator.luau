-- Seeded, deterministic closed circuits inspired by Japanese drift venues, as pure data: no
-- Instances, no Terrain writes. Profiles live in Config/JapaneseCircuitProfiles; they are fictional
-- inspirations, not replicas.
--
--   local result = JapaneseCircuitGenerator.generate("gunsai", seed)            -- options optional
--   if result.ok then
--       local circuit = result.circuit                -- exactly RoadGeometry.build's output
--       local field = JapaneseCircuitGenerator.createHeightfield(result) -- MountainHeightfield.new(...)
--       local pose = RoadGeometry.spawnPose(circuit, result.startIndex, 3)
--   else
--       warn(result.message)                          -- result.attempts holds every attempt's reasons
--   end
--   local ok, report = JapaneseCircuitGenerator.validate(circuit) -- independent final-sample check
--   local passed, lines = JapaneseCircuitGenerator.selfTest()      -- opt-in; never runs on require
--
-- Pipeline per attempt (attempt seeds derive from seed, profile salt and attempt number, so the
-- same seed always reaches the same final circuit):
--   1. Draw every template range. Correct arc angles so the loop turns exactly 360 degrees.
--   2. Integrate the path (straights, arcs with linear curvature ramps at both ends). Solve the
--      Closure straights' lengths (least-norm) so the end meets the start; reject if any falls below
--      the profile's MinStraight.
--   3. Emit control points UNIFORMLY spaced around the loop (Generation.ControlSpacing). Uneven
--      spacing makes the Catmull-Rom spline kink; uniform 12-stud spacing keeps the final radius
--      within about 2% of the template radius.
--   4. Add periodic elevation, build with RoadGeometry.build, validate the FINAL samples. If grade is
--      too steep, scale elevation down and rebuild (bounded). Any other failure rejects the attempt.
-- After Generation.MaxAttempts (or options.maxAttempts) failures, generate returns ok = false with
-- no circuit. There is no fallback circuit.
--
-- Validation (validate) works on the final samples only, including the closing segment from the
-- last sample back to the first: finite coordinates, width, segment spacing and closure, total
-- length, horizontal radius (circumcircle of samples i-2, i, i+2, as RoadGeometry measures it),
-- grade per segment, proper segment crossings, and nonlocal segment-to-segment separation.
--
-- "Nonlocal": two segments whose shortest along-road gap (arc distance between their nearest ends,
-- either way around the loop) is at least
--     localArc = 2 * MinRadius * asin(MinSeparation / (2 * MinRadius))   (80.2 studs by default).
-- A road whose radius never drops below MinRadius cannot bring two points closer than MinSeparation
-- within less road than that, so pairs closer along the road are the same stretch bending, not two
-- stretches meeting; every pair at or beyond it must be at least MinSeparation apart horizontally.
-- (If MinSeparation >= 2 * MinRadius, localArc is pi * MinRadius, half a minimum-radius turn.)
--
-- Cost: one attempt integrates about L / TraceStep steps twice, builds a RoadGeometry circuit
-- (24 dense points per control point) up to MaxGradePasses + 1 times and validates each build with
-- a uniform grid, O(n * k) for n samples and k segments per neighbourhood (capped by
-- Generation.MaxPairChecks). Typically a few tens of milliseconds; nothing yields.
local RoadGeometry = require(script.Parent.RoadGeometry)
local MountainHeightfield = require(script.Parent.MountainHeightfield)
local Profiles = require(script.Parent.Parent.Config.JapaneseCircuitProfiles)
local RoadConfig = require(script.Parent.Parent.Config.RoadConfig)
local TerrainConfig = require(script.Parent.Parent.Config.TerrainConfig)

export type Failure = { code: string, message: string }

export type ValidationReport = {
	ok: boolean,
	failures: { Failure },
	count: number,
	length: number, -- sum of all segment lengths including the closing one, studs
	closingSegmentLength: number,
	minSegmentLength: number,
	maxSegmentLength: number,
	minRadius: number, -- smallest horizontal circumradius over samples i-2, i, i+2
	minRadiusIndex: number,
	maxGrade: number,
	maxGradeSegment: number, -- segment i runs from sample i to i + 1 (the last wraps to 1)
	minSeparation: number?, -- smallest nonlocal horizontal distance found near MinSeparation; nil if none nearby
	minSeparationSegments: { number }?,
	crossings: number,
	firstCrossing: { number }?,
	localArc: number,
	pairChecks: number,
}

export type Feature = {
	kind: string, -- "Straight" | "Arc"
	name: string?,
	length: number, -- path length including transition ramps, studs
	radius: number, -- arcs only (0 for straights)
	angle: number, -- degrees, positive turns right; arcs only
	ramp: number, -- curvature ramp length at each end of an arc
	closure: boolean,
	heading: number, -- radians at the feature start; X/Z forward = (cos, sin)
	startDistance: number, -- along the integrated path
}

export type AttemptRecord = { attempt: number, stage: string, reasons: { string } }

export type Result = {
	ok: boolean,
	profileId: string,
	seed: number,
	version: number,
	message: string?,
	attempt: number?,
	attempts: { AttemptRecord }, -- failed attempts (all of them when ok is false)
	circuit: RoadGeometry.Circuit?,
	controlPoints: { Vector3 }?,
	features: { Feature }?,
	startIndex: number?,
	elevationScale: number?, -- fraction of the drawn relief kept to respect MaxGrade
	metrics: any?,
	validation: ValidationReport?,
	terrainConfig: any?, -- TerrainConfig with profile overrides and the basin centred on this circuit
	terrainSeed: number?,
	profile: any?,
}

local JapaneseCircuitGenerator = {}

local TWO_32 = 4294967296
local MAX_SEED = 2 ^ 53
local MAX_COORDINATE = 100000
local KEY_STRIDE = 2 ^ 24
local HAIRPIN_DEGREES = 140 -- nominal arc angle at or above which a template corner counts as a hairpin

local function fail(message: string): never
	error("JapaneseCircuitGenerator: " .. message, 0)
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Same xorshift32 mixing as MountainHeightfield; every step is invertible.
local function mix(state: number, value: number): number
	local h = bit32.bxor(state, value)
	for _ = 1, 3 do
		h = bit32.bxor(h, bit32.lshift(h, 13))
		h = bit32.bxor(h, bit32.rshift(h, 17))
		h = bit32.bxor(h, bit32.lshift(h, 5))
	end
	return h
end

local function deriveSeed(seed: number, salt: number, attempt: number, stream: number): number
	local h = mix(2166136261, seed % TWO_32)
	h = mix(h, math.floor(seed / TWO_32) % TWO_32)
	h = mix(h, Profiles.Version)
	h = mix(h, salt % TWO_32)
	h = mix(h, attempt)
	return mix(h, stream)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do -- order-independent: produces the same table either way
		out[key] = deepCopy(item)
	end
	return out
end

local function applyOverrides(target: any, overrides: any)
	for key, value in overrides do
		if type(value) == "table" then
			applyOverrides(target[key], value)
		else
			target[key] = value
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Input validation

local function requireRange(range: any, name: string, lowest: number)
	if type(range) ~= "table" or not isFinite(range[1]) or not isFinite(range[2]) then
		fail(name .. " must be { min, max } with finite numbers")
	end
	if range[1] > range[2] then
		fail(string.format("%s min %s exceeds max %s", name, tostring(range[1]), tostring(range[2])))
	end
	if range[1] < lowest then
		fail(string.format("%s min %s is below %s", name, tostring(range[1]), tostring(lowest)))
	end
end

local function checkConstraints(c: any)
	if type(c) ~= "table" then
		fail("constraints must be a table")
	end
	for _, key in { "Width", "MinRadius", "MinLength", "MaxLength", "MaxGrade", "MinSeparation" } do
		if not isFinite(c[key]) or c[key] <= 0 then
			fail("constraints." .. key .. " must be a positive finite number")
		end
	end
	if c.MaxLength < c.MinLength then
		fail("constraints.MaxLength must be at least MinLength")
	end
end

local function checkOverrideKeys(overrides: any, base: any, path: string)
	if type(overrides) ~= "table" then
		fail(path .. " must be a table")
	end
	for key, value in overrides do
		local existing = base[key]
		if existing == nil then
			fail(string.format("%s.%s is not a TerrainConfig setting", path, tostring(key)))
		end
		if type(value) == "table" then
			if type(existing) ~= "table" then
				fail(string.format("%s.%s must not be a table", path, tostring(key)))
			end
			checkOverrideKeys(value, existing, path .. "." .. tostring(key))
		elseif typeof(value) ~= typeof(existing) then
			fail(string.format("%s.%s must be a %s", path, tostring(key), typeof(existing)))
		end
	end
end

local validatedProfiles = setmetatable({}, { __mode = "k" })

local function validateProfile(profile: any, id: string)
	if validatedProfiles[profile] then
		return
	end
	local generation, constraints = Profiles.Generation, Profiles.Constraints
	local name = "profile " .. id
	if type(profile) ~= "table" then
		fail(name .. " must be a table")
	end
	if not isFinite(profile.Salt) or profile.Salt % 1 ~= 0 or profile.Salt < 0 then
		fail(name .. ".Salt must be a non-negative integer")
	end
	if not isFinite(profile.MinStraight) or profile.MinStraight <= 0 then
		fail(name .. ".MinStraight must be positive")
	end
	local layout = profile.Layout
	if type(layout) ~= "table" or #layout < 4 then
		fail(name .. ".Layout needs at least 4 features")
	end
	local closures, nominalTurn, absTurn = 0, 0, 0
	for i = 1, #layout do
		local spec = layout[i]
		local where = string.format("%s.Layout[%d]", name, i)
		if type(spec) ~= "table" then
			fail(where .. " must be a table")
		end
		if spec.Kind == "Straight" then
			requireRange(spec.Length, where .. ".Length", 1)
			if spec.Closure == true then
				closures += 1
			elseif spec.Closure ~= nil and spec.Closure ~= false then
				fail(where .. ".Closure must be a boolean")
			end
		elseif spec.Kind == "Arc" then
			if i == 1 then
				fail(where .. " must be a Straight: the first feature holds the start line")
			end
			requireRange(spec.Radius, where .. ".Radius", generation.DesignMinRadius)
			requireRange(spec.Angle, where .. ".Angle", -360)
			if spec.Angle[2] > 360 or spec.Angle[1] * spec.Angle[2] <= 0 then
				fail(where .. ".Angle must stay on one side of zero, within 360 degrees")
			end
			local mid = (spec.Angle[1] + spec.Angle[2]) / 2
			nominalTurn += mid
			absTurn += math.abs(mid)
		else
			fail(where .. ".Kind must be \"Straight\" or \"Arc\"")
		end
	end
	if layout[1].Kind ~= "Straight" then
		fail(name .. ".Layout[1] must be a Straight")
	end
	if closures < 2 then
		fail(name .. " needs at least two Closure straights")
	end
	if math.abs(math.abs(nominalTurn) - 360) > generation.MaxTurnCorrection or absTurn <= 0 then
		fail(string.format("%s nominal turning is %.1f degrees; it must be within %s of +/-360", name, nominalTurn, tostring(generation.MaxTurnCorrection)))
	end

	local elevation = profile.Elevation
	if type(elevation) ~= "table" then
		fail(name .. ".Elevation must be a table")
	end
	requireRange(elevation.Relief, name .. ".Elevation.Relief", 0)
	local harmonics = elevation.Harmonics
	if type(harmonics) ~= "table" or #harmonics < 1 or #harmonics > 6 then
		fail(name .. ".Elevation.Harmonics needs 1 to 6 weights")
	end
	for k = 1, #harmonics do
		if not isFinite(harmonics[k]) or harmonics[k] < 0 then
			fail(name .. ".Elevation.Harmonics weights must be non-negative")
		end
	end
	if elevation.Plateau ~= nil and (not isFinite(elevation.Plateau) or elevation.Plateau <= 0 or elevation.Plateau >= 1) then
		fail(name .. ".Elevation.Plateau must be between 0 and 1")
	end

	checkOverrideKeys(profile.TerrainOverrides or {}, TerrainConfig, name .. ".TerrainOverrides")
	local shaping = profile.TerrainShaping
	if type(shaping) ~= "table" then
		fail(name .. ".TerrainShaping must be a table")
	end
	for _, key in { "FloorDrop", "FloorMargin" } do
		if not isFinite(shaping[key]) or shaping[key] < 0 then
			fail(name .. ".TerrainShaping." .. key .. " must be a non-negative number")
		end
	end
	if not isFinite(shaping.RidgeWidth) or shaping.RidgeWidth <= 0 then
		fail(name .. ".TerrainShaping.RidgeWidth must be positive")
	end

	-- MountainHeightfield rejects distinct passes whose flat corridors overlap at different heights.
	-- Keep that overlap distance below the separation every generated circuit guarantees.
	local merged = deepCopy(TerrainConfig)
	applyOverrides(merged, profile.TerrainOverrides or {})
	local corridorReach = constraints.Width + 2 * merged.Road.ShoulderWidth + merged.Road.BlendBand
	if corridorReach >= constraints.MinSeparation then
		fail(string.format("%s terrain corridors (%.1f studs) would overlap at MinSeparation %s", name, corridorReach, tostring(constraints.MinSeparation)))
	end
	validatedProfiles[profile] = true
end

local function resolveProfile(profileOrId: any): (any, string)
	if type(profileOrId) == "string" then
		if profileOrId == "meihan_e" then
			fail("Meihan E has no verified references and is not a profile")
		end
		local profile = Profiles.Profiles[profileOrId]
		if profile == nil then
			fail(string.format("unknown profile %q; known: %s", profileOrId, table.concat(Profiles.Order, ", ")))
		end
		return profile, profileOrId
	elseif type(profileOrId) == "table" then
		local id = if type(profileOrId.Id) == "string" then profileOrId.Id else "custom"
		return profileOrId, id
	end
	fail("profile must be a profile id string or a profile table")
end

local function resolveOptions(options: any): (number, any)
	if options == nil then
		return Profiles.Generation.MaxAttempts, RoadConfig
	end
	if type(options) ~= "table" then
		fail("options must be a table or nil")
	end
	local maxAttempts = options.maxAttempts
	if maxAttempts == nil then
		maxAttempts = Profiles.Generation.MaxAttempts
	elseif not isFinite(maxAttempts) or maxAttempts % 1 ~= 0 or maxAttempts < 1 or maxAttempts > Profiles.Generation.MaxAttemptsLimit then
		fail(string.format("options.maxAttempts must be an integer from 1 to %d", Profiles.Generation.MaxAttemptsLimit))
	end
	local roadConfig = options.roadConfig
	if roadConfig == nil then
		roadConfig = RoadConfig
	elseif type(roadConfig) ~= "table" then
		fail("options.roadConfig must be a table")
	end
	if roadConfig.Width ~= Profiles.Constraints.Width then
		fail(string.format("roadConfig.Width must be %s", tostring(Profiles.Constraints.Width)))
	end
	if not isFinite(roadConfig.SampleSpacing) or roadConfig.SampleSpacing < 2 or roadConfig.SampleSpacing > 8 then
		fail("roadConfig.SampleSpacing must be between 2 and 8 studs")
	end
	return maxAttempts, roadConfig
end

--------------------------------------------------------------------------------------------------
-- Layout: draw, close, integrate

local function drawFeatures(profile: any, rng: Random): { Feature }
	local layout = profile.Layout
	local features = table.create(#layout)
	for i = 1, #layout do
		local spec = layout[i]
		if spec.Kind == "Straight" then
			features[i] = {
				kind = "Straight",
				name = spec.Name,
				length = rng:NextNumber(spec.Length[1], spec.Length[2]),
				radius = 0,
				angle = 0,
				ramp = 0,
				closure = spec.Closure == true,
				heading = 0,
				startDistance = 0,
			}
		else
			local radius = rng:NextNumber(spec.Radius[1], spec.Radius[2])
			local angle = rng:NextNumber(spec.Angle[1], spec.Angle[2])
			features[i] = {
				kind = "Arc",
				name = spec.Name,
				length = 0,
				radius = radius,
				angle = angle,
				ramp = 0,
				closure = false,
				heading = 0,
				startDistance = 0,
			}
		end
	end
	return features
end

local function sizeArc(feature: Feature)
	local generation = Profiles.Generation
	local body = feature.radius * math.abs(math.rad(feature.angle))
	feature.ramp = math.min(generation.TransitionMax, generation.TransitionFraction * body)
	feature.length = body + feature.ramp
end

-- Integrates the path. Each arc is three pieces with linear curvature (ramp in, constant, ramp out),
-- so heading is integrated exactly; position uses the midpoint heading of each step. When
-- `emitSpacing` is given, returns points (x, z, s) at s = 0, spacing, 2 * spacing, ... interpolated
-- along each step.
local function trace(features: { Feature }, step: number, emitSpacing: number?, emitCount: number?)
	local h, x, z, s = 0, 0, 0, 0
	local points = if emitSpacing then table.create(emitCount or 0) else nil
	local nextIndex = 0

	local function piece(k0: number, k1: number, length: number)
		if length <= 0 then
			return
		end
		local n = math.max(1, math.ceil(length / step))
		local d = length / n
		for i = 0, n - 1 do
			local ka = k0 + (k1 - k0) * (i / n)
			local kb = k0 + (k1 - k0) * ((i + 1) / n)
			local km = (ka + kb) / 2
			local hm = h + (ka + km) / 2 * (d / 2)
			local nx, nz = x + d * math.cos(hm), z + d * math.sin(hm)
			if points then
				while nextIndex < (emitCount :: number) and nextIndex * (emitSpacing :: number) <= s + d + 1e-9 do
					local t = (nextIndex * (emitSpacing :: number) - s) / d
					t = math.clamp(t, 0, 1)
					table.insert(points, { x = x + (nx - x) * t, z = z + (nz - z) * t, s = nextIndex * (emitSpacing :: number) })
					nextIndex += 1
				end
			end
			x, z = nx, nz
			h += (ka + kb) / 2 * d
			s += d
		end
	end

	for _, feature in features do
		feature.heading = h
		feature.startDistance = s
		if feature.kind == "Straight" then
			piece(0, 0, feature.length)
		else
			local body = feature.length - feature.ramp
			local k = math.rad(feature.angle) / body
			piece(0, k, feature.ramp)
			piece(k, k, body - feature.ramp)
			piece(k, 0, feature.ramp)
		end
	end
	return x, z, h, s, points
end

-- Returns features (closed) or nil and a reason.
local function buildLayout(profile: any, rng: Random): ({ Feature }?, string?)
	local generation = Profiles.Generation
	local features = drawFeatures(profile, rng)

	local total, absTotal = 0, 0
	for _, feature in features do
		if feature.kind == "Arc" then
			total += feature.angle
			absTotal += math.abs(feature.angle)
		end
	end
	local target = if total >= 0 then 360 else -360
	local correction = target - total
	if math.abs(correction) > generation.MaxTurnCorrection then
		return nil, string.format("turn: needs %.1f degrees of correction", correction)
	end
	for _, feature in features do
		if feature.kind == "Arc" then
			feature.angle += correction * math.abs(feature.angle) / absTotal
			sizeArc(feature)
		end
	end

	local ex, ez = trace(features, generation.TraceStep * 2)
	-- Least-norm lengths for the closure straights: minimize the sum of squared changes subject to
	-- sum(change_k * direction_k) = -endpoint. Straights do not turn, so this is exact.
	local a11, a12, a22 = 0, 0, 0
	for _, feature in features do
		if feature.closure then
			local ux, uz = math.cos(feature.heading), math.sin(feature.heading)
			a11 += ux * ux
			a12 += ux * uz
			a22 += uz * uz
		end
	end
	local det = a11 * a22 - a12 * a12
	if det < 1e-6 then
		return nil, "closure: closure straights are parallel"
	end
	local w0 = (a22 * -ex - a12 * -ez) / det
	local w1 = (-a12 * -ex + a11 * -ez) / det
	for _, feature in features do
		if feature.closure then
			feature.length += math.cos(feature.heading) * w0 + math.sin(feature.heading) * w1
			if feature.length < profile.MinStraight then
				return nil, string.format("closure: straight %s would be %.1f studs (minimum %s)", feature.name or "?", feature.length, tostring(profile.MinStraight))
			end
		end
	end
	if features[1].length < generation.MinStartStraight then
		return nil, string.format("closure: start straight %.1f studs is below %s", features[1].length, tostring(generation.MinStartStraight))
	end
	local rx, rz, rh = trace(features, generation.TraceStep * 2)
	if math.sqrt(rx * rx + rz * rz) > 0.25 or math.abs(math.abs(rh) - 2 * math.pi) > 1e-6 then
		return nil, string.format("closure: residual %.3f studs", math.sqrt(rx * rx + rz * rz))
	end
	return features, nil
end

-- Periodic elevation along the loop: harmonics k = 1..K with seeded weights and phases, scaled to a
-- seeded relief (peak-to-peak), optionally softened above Plateau * relief, shifted to 0 at the start.
local function makeElevation(profile: any, rng: Random, loopLength: number): ((number) -> number, number)
	local elevation = profile.Elevation
	local count = #elevation.Harmonics
	local amplitudes, phases = table.create(count), table.create(count)
	for k = 1, count do
		amplitudes[k] = elevation.Harmonics[k] * rng:NextNumber(0.6, 1)
		phases[k] = rng:NextNumber(0, 2 * math.pi)
	end
	local relief = rng:NextNumber(elevation.Relief[1], elevation.Relief[2])

	local function raw(s: number): number
		local y = 0
		for k = 1, count do
			y += amplitudes[k] * math.sin(2 * math.pi * k * s / loopLength + phases[k])
		end
		return y
	end
	local low, high = math.huge, -math.huge
	local probes = Profiles.Generation.ElevationProbeCount
	for i = 0, probes - 1 do
		local y = raw(loopLength * i / probes)
		low, high = math.min(low, y), math.max(high, y)
	end
	local scale = if high - low > 1e-9 then relief / (high - low) else 0
	local plateau = elevation.Plateau
	local cap = if plateau then relief * plateau else 0
	local width = math.max(relief * 0.08, 1)

	local function shaped(s: number): number
		local y = (raw(s) - low) * scale
		if plateau then
			local t = (y - cap) / width
			local softplus = if t > 30 then t else math.log(1 + math.exp(t))
			y -= 0.75 * width * softplus
		end
		return y
	end
	local base = shaped(0)
	return function(s: number): number
		return shaped(s) - base
	end, relief
end

--------------------------------------------------------------------------------------------------
-- Validation of final samples

local function orientation(ax: number, az: number, bx: number, bz: number, cx: number, cz: number): number
	return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
end

-- Proper crossing of two horizontal segments (shared endpoints and collinear touches excluded).
local function segmentsCross(ax, az, bx, bz, cx, cz, dx, dz): boolean
	local o1 = orientation(ax, az, bx, bz, cx, cz)
	local o2 = orientation(ax, az, bx, bz, dx, dz)
	local o3 = orientation(cx, cz, dx, dz, ax, az)
	local o4 = orientation(cx, cz, dx, dz, bx, bz)
	return o1 * o2 < 0 and o3 * o4 < 0
end

local function pointSegmentDistance(px, pz, ax, az, bx, bz): number
	local dx, dz = bx - ax, bz - az
	local lengthSq = dx * dx + dz * dz
	local t = if lengthSq > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / lengthSq, 0, 1) else 0
	local ex, ez = px - ax - dx * t, pz - az - dz * t
	return math.sqrt(ex * ex + ez * ez)
end

-- Crossing or touching: a proper crossing, or an endpoint lying on the other segment (two road
-- passes meeting exactly at a sample). Only used for non-adjacent segments.
local function segmentsMeet(ax, az, bx, bz, cx, cz, dx, dz): boolean
	return segmentsCross(ax, az, bx, bz, cx, cz, dx, dz)
		or pointSegmentDistance(ax, az, cx, cz, dx, dz) <= 1e-9
		or pointSegmentDistance(bx, bz, cx, cz, dx, dz) <= 1e-9
		or pointSegmentDistance(cx, cz, ax, az, bx, bz) <= 1e-9
		or pointSegmentDistance(dx, dz, ax, az, bx, bz) <= 1e-9
end

local function segmentDistance(ax, az, bx, bz, cx, cz, dx, dz): number
	if segmentsCross(ax, az, bx, bz, cx, cz, dx, dz) then
		return 0
	end
	return math.min(
		pointSegmentDistance(ax, az, cx, cz, dx, dz),
		pointSegmentDistance(bx, bz, cx, cz, dx, dz),
		pointSegmentDistance(cx, cz, ax, az, bx, bz),
		pointSegmentDistance(dx, dz, ax, az, bx, bz)
	)
end

-- Validates a closed circuit's final samples. Returns (ok, report); never raises for a bad
-- circuit (bad constraints do raise). `constraints` defaults to JapaneseCircuitProfiles.Constraints.
function JapaneseCircuitGenerator.validate(circuit: any, constraints: any?): (boolean, ValidationReport)
	local c = if constraints == nil then Profiles.Constraints else constraints
	checkConstraints(c)
	local localArc = if c.MinSeparation < 2 * c.MinRadius
		then 2 * c.MinRadius * math.asin(c.MinSeparation / (2 * c.MinRadius))
		else math.pi * c.MinRadius
	local report: ValidationReport = {
		ok = false,
		failures = {},
		count = 0,
		length = 0,
		closingSegmentLength = 0,
		minSegmentLength = 0,
		maxSegmentLength = 0,
		minRadius = math.huge,
		minRadiusIndex = 0,
		maxGrade = 0,
		maxGradeSegment = 0,
		minSeparation = nil,
		minSeparationSegments = nil,
		crossings = 0,
		firstCrossing = nil,
		localArc = localArc,
		pairChecks = 0,
	}
	local function add(code: string, message: string)
		table.insert(report.failures, { code = code, message = message })
	end
	local function finish(): (boolean, ValidationReport)
		report.ok = #report.failures == 0
		return report.ok, report
	end

	if type(circuit) ~= "table" or type(circuit.samples) ~= "table" then
		add("input", "circuit must be a table with a samples array")
		return finish()
	end
	local samples = circuit.samples
	local n = #samples
	report.count = n
	if n < 5 then
		add("count", string.format("circuit needs at least 5 samples, got %d", n))
		return finish()
	end
	if circuit.count ~= nil and circuit.count ~= n then
		add("count", string.format("circuit.count %s does not match %d samples", tostring(circuit.count), n))
	end
	if not isFinite(circuit.width) or math.abs(circuit.width - c.Width) > 1e-9 then
		add("width", string.format("road width %s must be %s", tostring(circuit.width), tostring(c.Width)))
	end

	local xs, ys, zs = table.create(n), table.create(n), table.create(n)
	for i = 1, n do
		local sample = samples[i]
		local position = if type(sample) == "table" then sample.position else nil
		if typeof(position) ~= "Vector3" then
			add("finite", string.format("samples[%d].position must be a Vector3", i))
			return finish()
		end
		if not (isFinite(position.X) and isFinite(position.Y) and isFinite(position.Z)) then
			add("finite", string.format("samples[%d].position is not finite", i))
			return finish()
		end
		if math.abs(position.X) > MAX_COORDINATE or math.abs(position.Z) > MAX_COORDINATE then
			add("finite", string.format("samples[%d].position is beyond %d studs", i, MAX_COORDINATE))
			return finish()
		end
		xs[i], ys[i], zs[i] = position.X, position.Y, position.Z
	end

	-- Segments, including the closing one (n -> 1).
	local segLength, segHorizontal, cumulative = table.create(n), table.create(n), table.create(n)
	local total = 0
	for i = 1, n do
		local j = i % n + 1
		local dx, dy, dz = xs[j] - xs[i], ys[j] - ys[i], zs[j] - zs[i]
		segHorizontal[i] = math.sqrt(dx * dx + dz * dz)
		segLength[i] = math.sqrt(dx * dx + dy * dy + dz * dz)
		cumulative[i] = total
		total += segLength[i]
	end
	report.length = total
	report.closingSegmentLength = segLength[n]
	local mean = total / n
	local shortest, longest = math.huge, 0
	local badSpacing, degenerate = 0, 0
	for i = 1, n do
		shortest, longest = math.min(shortest, segLength[i]), math.max(longest, segLength[i])
		if segHorizontal[i] < 1e-6 then
			degenerate += 1
		end
		if i < n and (segLength[i] < 0.5 * mean or segLength[i] > 1.5 * mean) then
			badSpacing += 1
		end
	end
	report.minSegmentLength, report.maxSegmentLength = shortest, longest
	if degenerate > 0 then
		add("degenerate", string.format("%d segments have no horizontal length", degenerate))
	end
	if badSpacing > 0 then
		add("spacing", string.format("%d segments are outside 0.5-1.5x the mean spacing %.2f", badSpacing, mean))
	end
	if segLength[n] < 0.5 * mean or segLength[n] > 1.5 * mean then
		add("closure", string.format("closing segment (sample %d -> 1) is %.2f studs; mean spacing %.2f", n, segLength[n], mean))
	end
	if total < c.MinLength or total > c.MaxLength then
		add("length", string.format("loop length %.1f studs is outside %s-%s", total, tostring(c.MinLength), tostring(c.MaxLength)))
	end

	-- Horizontal radius, matching RoadGeometry's estimator (samples two steps either side).
	for i = 1, n do
		local a, b = (i - 3) % n + 1, (i + 1) % n + 1
		local abx, abz = xs[i] - xs[a], zs[i] - zs[a]
		local acx, acz = xs[b] - xs[a], zs[b] - zs[a]
		local bcx, bcz = xs[b] - xs[i], zs[b] - zs[i]
		local doubleArea = math.abs(abx * acz - abz * acx)
		if doubleArea > 1e-6 then
			local radius = math.sqrt(abx * abx + abz * abz) * math.sqrt(acx * acx + acz * acz) * math.sqrt(bcx * bcx + bcz * bcz) / (2 * doubleArea)
			if radius < report.minRadius then
				report.minRadius, report.minRadiusIndex = radius, i
			end
		end
	end
	if report.minRadius < c.MinRadius then
		add("radius", string.format("horizontal radius %.2f studs at sample %d is below %s", report.minRadius, report.minRadiusIndex, tostring(c.MinRadius)))
	end

	for i = 1, n do
		if segHorizontal[i] > 1e-6 then
			local grade = math.abs(ys[i % n + 1] - ys[i]) / segHorizontal[i]
			if grade > report.maxGrade then
				report.maxGrade, report.maxGradeSegment = grade, i
			end
		end
	end
	if report.maxGrade > c.MaxGrade then
		add("grade", string.format("grade %.2f%% on segment %d exceeds %.2f%%", report.maxGrade * 100, report.maxGradeSegment, c.MaxGrade * 100))
	end

	-- Crossings and nonlocal separation with a uniform grid of segment bounds.
	local cellSize = c.MinSeparation
	local cells = {}
	for i = 1, n do
		local j = i % n + 1
		local cx0, cx1 = math.floor(math.min(xs[i], xs[j]) / cellSize), math.floor(math.max(xs[i], xs[j]) / cellSize)
		local cz0, cz1 = math.floor(math.min(zs[i], zs[j]) / cellSize), math.floor(math.max(zs[i], zs[j]) / cellSize)
		for cx = cx0, cx1 do
			for cz = cz0, cz1 do
				local key = cx * KEY_STRIDE + cz
				local list = cells[key]
				if list == nil then
					list = {}
					cells[key] = list
				end
				table.insert(list, i)
			end
		end
	end
	local marks = table.create(n, 0)
	local maxChecks = Profiles.Generation.MaxPairChecks
	local bestSeparation, bestI, bestJ = math.huge, 0, 0
	local crossI, crossJ = 0, 0
	local reach = c.MinSeparation
	for i = 1, n do
		local i2 = i % n + 1
		local ax, az, bx, bz = xs[i], zs[i], xs[i2], zs[i2]
		local cx0, cx1 = math.floor((math.min(ax, bx) - reach) / cellSize), math.floor((math.max(ax, bx) + reach) / cellSize)
		local cz0, cz1 = math.floor((math.min(az, bz) - reach) / cellSize), math.floor((math.max(az, bz) + reach) / cellSize)
		for cx = cx0, cx1 do
			for cz = cz0, cz1 do
				local list = cells[cx * KEY_STRIDE + cz]
				if list ~= nil then
					for _, j in list do
						if j > i and marks[j] ~= i and j ~= i + 1 and not (i == 1 and j == n) then
							marks[j] = i
							report.pairChecks += 1
							if report.pairChecks > maxChecks then
								add("density", "separation check exceeded Generation.MaxPairChecks")
								return finish()
							end
							local j2 = j % n + 1
							local qx, qz, rx, rz = xs[j], zs[j], xs[j2], zs[j2]
							if segmentsMeet(ax, az, bx, bz, qx, qz, rx, rz) then
								report.crossings += 1
								if crossI == 0 or i < crossI or (i == crossI and j < crossJ) then
									crossI, crossJ = i, j
								end
							end
							local forward = cumulative[j] - (cumulative[i] + segLength[i])
							local backward = total - (cumulative[j] + segLength[j]) + cumulative[i]
							if math.min(forward, backward) >= localArc then
								local distance = segmentDistance(ax, az, bx, bz, qx, qz, rx, rz)
								if distance < bestSeparation or (distance == bestSeparation and (i < bestI or (i == bestI and j < bestJ))) then
									bestSeparation, bestI, bestJ = distance, i, j
								end
							end
						end
					end
				end
			end
		end
	end
	if report.crossings > 0 then
		report.firstCrossing = { crossI, crossJ }
		add("crossing", string.format("%d segment crossings; first between segments %d and %d", report.crossings, crossI, crossJ))
	end
	if bestI > 0 then
		report.minSeparation = bestSeparation
		report.minSeparationSegments = { bestI, bestJ }
		if bestSeparation < c.MinSeparation then
			add("separation", string.format("segments %d and %d (nonlocal, along-road gap >= %.1f) are %.2f studs apart; minimum %s", bestI, bestJ, localArc, bestSeparation, tostring(c.MinSeparation)))
		end
	end
	return finish()
end

local function summarize(report: ValidationReport): { string }
	local reasons = table.create(#report.failures)
	for _, failure in report.failures do
		table.insert(reasons, failure.code .. ": " .. failure.message)
	end
	return reasons
end

--------------------------------------------------------------------------------------------------
-- Terrain configuration for MountainHeightfield

local function buildTerrainConfig(profile: any, circuit: any): any
	local config = deepCopy(TerrainConfig)
	applyOverrides(config, profile.TerrainOverrides or {})
	local samples = circuit.samples
	local minX, maxX, minZ, maxZ, sumY = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, sample in samples do
		local p = sample.position
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
		sumY += p.Y
	end
	local centerX, centerZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	local farthest = 0
	for _, sample in samples do
		local p = sample.position
		farthest = math.max(farthest, math.sqrt((p.X - centerX) ^ 2 + (p.Z - centerZ) ^ 2))
	end
	local shaping = profile.TerrainShaping
	local basin = config.Basin
	basin.CenterX, basin.CenterZ = centerX, centerZ
	basin.FloorHeight = sumY / #samples - shaping.FloorDrop
	basin.FloorRadius = farthest + shaping.FloorMargin
	basin.RidgeRadius = basin.FloorRadius + shaping.RidgeWidth
	return config
end

--------------------------------------------------------------------------------------------------
-- Public API

function JapaneseCircuitGenerator.listProfiles(): { string }
	return table.clone(Profiles.Order)
end

function JapaneseCircuitGenerator.getProfile(id: string): any
	local profile = resolveProfile(id)
	return profile
end

-- profileOrId: a JapaneseCircuitProfiles id (see listProfiles) or a profile table shaped like one.
-- seed: integer with |seed| <= 2^53. options: { maxAttempts: number?, roadConfig: RoadConfig? }.
-- Raises on invalid input. Returns a Result; ok = false (with every attempt's reasons and no
-- circuit) when the retry budget is exhausted.
function JapaneseCircuitGenerator.generate(profileOrId: any, seed: number, options: any?): Result
	local profile, id = resolveProfile(profileOrId)
	if not isFinite(seed) or seed % 1 ~= 0 or math.abs(seed) > MAX_SEED then
		fail(string.format("seed must be a finite integer with magnitude at most 2^53, got %s", tostring(seed)))
	end
	local maxAttempts, roadConfig = resolveOptions(options)
	validateProfile(profile, id)

	local generation, constraints = Profiles.Generation, Profiles.Constraints
	local attempts: { AttemptRecord } = {}
	for attempt = 1, maxAttempts do
		local features, reason = buildLayout(profile, Random.new(deriveSeed(seed, profile.Salt, attempt, 1)))
		if features == nil then
			table.insert(attempts, { attempt = attempt, stage = "layout", reasons = { reason :: string } })
			continue
		end

		local _, _, _, loopLength = trace(features, generation.TraceStep)
		local count = math.max(16, math.floor(loopLength / generation.ControlSpacing + 0.5))
		local _, _, _, _, emitted = trace(features, generation.TraceStep / 2, loopLength / count, count)
		local points = emitted :: { any }
		if #points ~= count then
			table.insert(attempts, { attempt = attempt, stage = "layout", reasons = { string.format("emit: %d of %d control points", #points, count) } })
			continue
		end
		local heightAt, relief = makeElevation(profile, Random.new(deriveSeed(seed, profile.Salt, attempt, 2)), loopLength)

		local scale = 1
		local circuit, report, controlPoints
		for pass = 1, generation.MaxGradePasses + 1 do
			controlPoints = table.create(count)
			for k = 1, count do
				local p = points[k]
				controlPoints[k] = Vector3.new(p.x, heightAt(p.s) * scale, p.z)
			end
			circuit = RoadGeometry.build(controlPoints, roadConfig)
			local _, validation = JapaneseCircuitGenerator.validate(circuit, constraints)
			report = validation
			if pass <= generation.MaxGradePasses and validation.maxGrade > constraints.MaxGrade * generation.GradeTrigger then
				scale *= constraints.MaxGrade * generation.GradeTarget / validation.maxGrade
			else
				break
			end
		end

		if report.ok then
			local lowY, highY = math.huge, -math.huge
			for _, sample in circuit.samples do
				lowY, highY = math.min(lowY, sample.position.Y), math.max(highY, sample.position.Y)
			end
			local longest, arcs, hairpins, turning = 0, 0, 0, 0
			for _, feature in features do
				if feature.kind == "Straight" then
					longest = math.max(longest, feature.length)
				else
					arcs += 1
					turning += feature.angle
				end
			end
			for _, spec in profile.Layout do
				if spec.Kind == "Arc" and math.abs((spec.Angle[1] + spec.Angle[2]) / 2) >= HAIRPIN_DEGREES then
					hairpins += 1
				end
			end
			local startDistance = features[1].length * generation.StartFraction
			return {
				ok = true,
				profileId = id,
				seed = seed,
				version = Profiles.Version,
				attempt = attempt,
				attempts = attempts,
				circuit = circuit,
				controlPoints = controlPoints,
				features = features,
				startIndex = math.floor(startDistance / circuit.spacing + 0.5) % circuit.count + 1,
				elevationScale = scale,
				metrics = {
					length = report.length,
					minRadius = report.minRadius,
					maxGrade = report.maxGrade,
					minSeparation = report.minSeparation,
					relief = highY - lowY,
					drawnRelief = relief,
					longestStraight = longest,
					longestStraightFraction = longest / report.length,
					arcCount = arcs,
					hairpinCount = hairpins,
					turnDirection = if turning > 0 then "Right" else "Left", -- net turning: +360 right-hand, -360 left-hand
				},
				validation = report,
				terrainConfig = buildTerrainConfig(profile, circuit),
				terrainSeed = deriveSeed(seed, profile.Salt, 0, 3),
				profile = profile,
			}
		end
		table.insert(attempts, { attempt = attempt, stage = "validation", reasons = summarize(report) })
	end

	return {
		ok = false,
		profileId = id,
		seed = seed,
		version = Profiles.Version,
		message = string.format("profile %s seed %s: no valid circuit in %d attempts (see attempts)", id, tostring(seed), maxAttempts),
		attempts = attempts,
	}
end

-- MountainHeightfield for a successful result, using the result's profile terrain configuration.
-- Raises if the result failed (MountainHeightfield.new also raises on corridor conflicts).
function JapaneseCircuitGenerator.createHeightfield(result: Result): any
	if type(result) ~= "table" or result.ok ~= true or result.circuit == nil then
		fail("createHeightfield needs a successful generate() result")
	end
	return MountainHeightfield.new(result.terrainSeed :: number, result.circuit, result.terrainConfig)
end

--------------------------------------------------------------------------------------------------
-- Opt-in checks; call from the Studio command bar. Returns (passed, report lines). Never prints.
-- Takes a few seconds: about 45 generations plus heightfield queries.
function JapaneseCircuitGenerator.selfTest(): (boolean, { string })
	local lines = {}
	local failures = 0
	local function check(name: string, ok: boolean, detail: string?)
		if not ok then
			failures += 1
		end
		table.insert(lines, (if ok then "PASS " else "FAIL ") .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
	local function expectError(name: string, fn: () -> ())
		local ok = pcall(fn)
		check("rejects " .. name, not ok, if ok then "no error raised" else nil)
	end
	local function hasCode(report: ValidationReport, code: string): boolean
		for _, failure in report.failures do
			if failure.code == code then
				return true
			end
		end
		return false
	end
	local function codes(report: ValidationReport): string
		local out = {}
		for _, failure in report.failures do
			table.insert(out, failure.code)
		end
		return if #out > 0 then table.concat(out, ",") else "none"
	end
	local function circuitFrom(points: { Vector3 }): any
		return RoadGeometry.build(points, RoadConfig)
	end

	local generate, validate = JapaneseCircuitGenerator.generate, JapaneseCircuitGenerator.validate
	local constraints = Profiles.Constraints
	local SEEDS = { 1, 2, 77, -12345, 2 ^ 40 + 3 }

	local ran, err = pcall(function()
		-- Every profile over several seeds: success, constraints, closure, repeatability, variation.
		local firstResults = {}
		for _, id in Profiles.Order do
			local generated, independent, closed, metricsOk, structure = 0, 0, 0, 0, 0
			local hashes, distinct = {}, 0
			local detail = ""
			for s, seed in SEEDS do
				local result = generate(id, seed)
				if result.ok then
					generated += 1
					local circuit = result.circuit :: any
					local ok, report = validate(circuit)
					if ok then
						independent += 1
					end
					local samples = circuit.samples
					local first, last = samples[1].position, samples[#samples].position
					if (first - last).Magnitude <= 1.5 * circuit.spacing and (first - result.controlPoints[1]).Magnitude < 1e-6 then
						closed += 1
					end
					local m = result.metrics
					if m.length >= constraints.MinLength and m.length <= constraints.MaxLength and m.minRadius >= constraints.MinRadius
						and m.maxGrade <= constraints.MaxGrade and (m.minSeparation == nil or m.minSeparation >= constraints.MinSeparation)
						and circuit.width == constraints.Width and circuit.minRadius >= constraints.MinRadius and circuit.maxGrade <= constraints.MaxGrade
						and circuit.count == #samples and result.startIndex >= 1 and result.startIndex <= circuit.count
					then
						metricsOk += 1
					end
					if not hashes[circuit.hash] then
						hashes[circuit.hash] = true
						distinct += 1
					end
					-- Seeds change values, never the template's sequence of features or turn directions.
					local layout = Profiles.Profiles[id].Layout
					local kept = #result.features == #layout
					for k = 1, math.min(#layout, #result.features) do
						local feature, spec = result.features[k], layout[k]
						kept = kept and feature.kind == spec.Kind
						if spec.Kind == "Arc" then
							kept = kept and math.sign(feature.angle) == math.sign(spec.Angle[1])
						end
					end
					if kept then
						structure += 1
					end
					if s == 1 then
						firstResults[id] = result
						detail = string.format("len %.0f, minR %.1f, grade %.2f%%, sep %s, relief %.1f, attempt %d",
							m.length, m.minRadius, m.maxGrade * 100, if m.minSeparation then string.format("%.1f", m.minSeparation) else "n/a", m.relief, result.attempt :: number)
					end
				else
					detail = result.message or "failed"
				end
			end
			local n = #SEEDS
			check(id .. ": generates every seed", generated == n, string.format("%d/%d; seed 1: %s", generated, n, detail))
			check(id .. ": independent validation passes", independent == generated and generated > 0)
			check(id .. ": constraints and RoadGeometry metrics hold", metricsOk == generated and generated > 0, string.format("%d/%d", metricsOk, generated))
			check(id .. ": closes through the wrap segment", closed == generated and generated > 0)
			check(id .. ": seeds vary the circuit", distinct >= n - 1, string.format("%d distinct of %d", distinct, n))
			check(id .. ": structure kept across seeds", structure == generated and generated > 0)

			local again, other = generate(id, SEEDS[1]), generate(id, SEEDS[1])
			local same = again.ok and other.ok and again.circuit.hash == other.circuit.hash and again.attempt == other.attempt
				and #again.controlPoints == #other.controlPoints
			if same then
				for k = 1, #again.controlPoints do
					if again.controlPoints[k] ~= other.controlPoints[k] then
						same = false
						break
					end
				end
			end
			check(id .. ": same seed repeats exactly", same)
		end

		-- Profiles differ structurally and keep their character.
		local function signature(id: string): { number }
			local profile = Profiles.Profiles[id]
			local arcs, straights, hairpins, radiusSum = 0, 0, 0, 0
			for _, spec in profile.Layout do
				if spec.Kind == "Arc" then
					arcs += 1
					radiusSum += (spec.Radius[1] + spec.Radius[2]) / 2
					if math.abs((spec.Angle[1] + spec.Angle[2]) / 2) >= HAIRPIN_DEGREES then
						hairpins += 1
					end
				else
					straights += 1
				end
			end
			return { arcs, straights, hairpins, radiusSum / arcs, (profile.Elevation.Relief[1] + profile.Elevation.Relief[2]) / 2 }
		end
		local order = Profiles.Order
		local alike = {}
		for a = 1, #order do
			for b = a + 1, #order do
				local x, y = signature(order[a]), signature(order[b])
				local differs = x[1] ~= y[1] or x[2] ~= y[2] or x[3] ~= y[3] or math.abs(x[4] - y[4]) >= 10 or math.abs(x[5] - y[5]) >= 5
				if not differs then
					table.insert(alike, order[a] .. "/" .. order[b])
				end
			end
		end
		check("profiles differ structurally", #alike == 0, if #alike > 0 then table.concat(alike, " ") else nil)

		local r = firstResults
		if r.meihan_c and r.minami_chiba and r.gunsai and r.ebisu_west and r.yz_east and r.nikko and r.ebisu_north then
			check("low-elevation venues stay low", r.meihan_c.metrics.relief <= 6 and r.minami_chiba.metrics.relief <= 6,
				string.format("meihan %.1f, chiba %.1f", r.meihan_c.metrics.relief, r.minami_chiba.metrics.relief))
			check("mountain venues keep relief", r.gunsai.metrics.relief >= 15 and r.ebisu_west.metrics.relief >= 15,
				string.format("gunsai %.1f, west %.1f", r.gunsai.metrics.relief, r.ebisu_west.metrics.relief))
			check("terrain overrides: flat venues get low ridges", r.meihan_c.terrainConfig.Basin.RidgeHeight < r.gunsai.terrainConfig.Basin.RidgeHeight
				and r.minami_chiba.terrainConfig.Noise.Ridges.Amplitude < r.ebisu_north.terrainConfig.Noise.Ridges.Amplitude)
			check("Minami Chiba keeps generous radii", r.minami_chiba.metrics.minRadius >= 58, string.format("%.1f", r.minami_chiba.metrics.minRadius))
			check("YZ East keeps a long main straight", r.yz_east.metrics.longestStraightFraction >= 0.27, string.format("%.2f", r.yz_east.metrics.longestStraightFraction))
			local wide = false
			for _, feature in r.nikko.features do
				if feature.kind == "Arc" and feature.radius >= 180 then
					wide = true
				end
			end
			check("Nikko has a fast wide sweeper", wide)
			check("Ebisu North runs left-handed, others right", r.ebisu_north.metrics.turnDirection == "Left" and r.gunsai.metrics.turnDirection == "Right")
		else
			check("first-seed results available for character checks", false)
		end

		-- Independent validator rejections on hand-made circuits.
		local valid = r.nikko
		if valid then
			local samples = valid.circuit.samples
			local truncated = table.move(samples, 1, #samples - 25, 1, {})
			local _, broken = validate({ samples = truncated, width = 30 })
			check("validator rejects a broken closing segment", hasCode(broken, "closure"), codes(broken))

			local nanSamples = table.clone(samples)
			nanSamples[7] = { position = Vector3.new(0 / 0, 0, 0) }
			local _, nanReport = validate({ samples = nanSamples, width = 30 })
			check("validator rejects non-finite coordinates", hasCode(nanReport, "finite"), codes(nanReport))

			local _, wide = validate({ samples = samples, width = 20, count = #samples })
			check("validator rejects the wrong width", hasCode(wide, "width"), codes(wide))
		end
		local _, missing = validate(nil)
		check("validator reports missing circuit", hasCode(missing, "input"))

		-- Two straights joined by semicircles; `bump` pushes both straights inward with a Gaussian
		-- (sigma 80 studs, peak curvature 2 * bump / 80^2) so they pinch without a tight radius.
		local function stadium(straight: number, radius: number, bump: number): { Vector3 }
			local points = {}
			local step = 10
			local arcSteps = math.max(6, math.floor(math.pi * radius / step + 0.5))
			local function pinch(x: number): number
				return bump * math.exp(-((x - straight / 2) / 80) ^ 2)
			end
			for x = 0, straight - step, step do
				table.insert(points, Vector3.new(x, 0, pinch(x)))
			end
			for k = 0, arcSteps - 1 do
				local a = -math.pi / 2 + math.pi * k / arcSteps
				table.insert(points, Vector3.new(straight + radius * math.cos(a), 0, radius + radius * math.sin(a)))
			end
			for x = straight, step, -step do
				table.insert(points, Vector3.new(x, 0, 2 * radius - pinch(x)))
			end
			for k = 0, arcSteps - 1 do
				local a = math.pi / 2 + math.pi * k / arcSteps
				table.insert(points, Vector3.new(radius * math.cos(a), 0, radius + radius * math.sin(a)))
			end
			return points
		end
		local _, tight = validate(circuitFrom(stadium(700, 30, 0)))
		check("validator rejects tight radius", hasCode(tight, "radius"), codes(tight))
		local _, pinched = validate(circuitFrom(stadium(600, 80, 50)))
		check("validator rejects nonlocal separation alone", hasCode(pinched, "separation") and not hasCode(pinched, "radius") and not hasCode(pinched, "crossing"), codes(pinched))

		local function circle(radius: number, rise: number): { Vector3 }
			local points = {}
			for k = 0, 95 do
				local a = 2 * math.pi * k / 96
				table.insert(points, Vector3.new(radius * math.cos(a), rise * math.sin(a), radius * math.sin(a)))
			end
			return points
		end
		local _, steep = validate(circuitFrom(circle(300, 40)))
		check("validator rejects steep grade alone", hasCode(steep, "grade") and not hasCode(steep, "radius") and not hasCode(steep, "length"), codes(steep))
		local _, short = validate(circuitFrom(circle(150, 0)))
		check("validator rejects short loops", hasCode(short, "length"), codes(short))

		local eight = {}
		for k = 0, 179 do
			local t = 2 * math.pi * k / 180
			table.insert(eight, Vector3.new(450 * math.sin(t), 0, 450 * math.sin(t) * math.cos(t)))
		end
		local _, crossed = validate(circuitFrom(eight))
		check("validator rejects self-crossing", hasCode(crossed, "crossing"), codes(crossed))

		-- Heightfield compatibility: road corridor sits Clearance below every probed sample.
		for _, id in Profiles.Order do
			local result = r[id]
			if result then
				local built, field = pcall(JapaneseCircuitGenerator.createHeightfield, result)
				local exact, finite = 0, true
				if built then
					local samples = result.circuit.samples
					local clearance = result.terrainConfig.Road.Clearance
					for k = 0, 23 do
						local sample = samples[math.floor(k * #samples / 24) + 1]
						local p = sample.position
						local info = MountainHeightfield.sample(field, p.X, p.Z)
						if info.zone == "Road" and info.roadHeight ~= nil and math.abs(info.roadHeight - p.Y) <= 1e-3 and math.abs(info.height - (p.Y - clearance)) <= 1e-3 then
							exact += 1
						end
						local away = p + sample.right * 160
						finite = finite and isFinite(MountainHeightfield.heightAt(field, away.X, away.Z))
					end
				end
				check(id .. ": MountainHeightfield accepts circuit and clears road", built and exact == 24 and finite,
					if built then string.format("%d/24 exact", exact) else tostring(field))
			end
		end

		-- Invalid inputs.
		expectError("unknown profile", function() generate("nope", 1) end)
		expectError("unverified Meihan E", function() generate("meihan_e", 1) end)
		expectError("nil profile", function() generate(nil :: any, 1) end)
		expectError("fractional seed", function() generate("gunsai", 1.5) end)
		expectError("NaN seed", function() generate("gunsai", 0 / 0) end)
		expectError("infinite seed", function() generate("gunsai", math.huge) end)
		expectError("seed beyond 2^53", function() generate("gunsai", 2 ^ 53 + 2) end)
		expectError("string seed", function() generate("gunsai", "1" :: any) end)
		expectError("non-table options", function() generate("gunsai", 1, 5 :: any) end)
		expectError("zero attempts", function() generate("gunsai", 1, { maxAttempts = 0 }) end)
		expectError("too many attempts", function() generate("gunsai", 1, { maxAttempts = 1000 }) end)
		expectError("wrong road width", function() generate("gunsai", 1, { roadConfig = { Width = 24, SampleSpacing = 4 } }) end)
		expectError("bad sample spacing", function() generate("gunsai", 1, { roadConfig = { Width = 30, SampleSpacing = 0 } }) end)
		expectError("bad validation constraints", function() validate({}, { Width = 30 }) end)

		local function variant(edit: (any) -> ()): any
			local profile = deepCopy(Profiles.Profiles.meihan_c)
			profile.Id = "variant"
			edit(profile)
			return profile
		end
		expectError("radius below design minimum", function()
			generate(variant(function(p) p.Layout[2].Radius = { 30, 40 } end), 1)
		end)
		expectError("one closure straight", function()
			generate(variant(function(p) p.Layout[10].Closure = nil end), 1)
		end)
		expectError("unknown terrain override", function()
			generate(variant(function(p) p.TerrainOverrides.Basin.Mountains = 5 end), 1)
		end)
		expectError("arc as first feature", function()
			generate(variant(function(p) p.Layout[1] = { Kind = "Arc", Radius = { 60, 60 }, Angle = { 10, 20 } } end), 1)
		end)
		expectError("angle range crossing zero", function()
			generate(variant(function(p) p.Layout[4].Angle = { -10, 10 } end), 1)
		end)
		expectError("terrain corridor wider than separation", function()
			generate(variant(function(p) p.TerrainOverrides.Road = { ShoulderWidth = 25 } end), 1)
		end)

		-- Exhausted retry budget fails explicitly, with no circuit.
		local impossible = generate(variant(function(p) p.Layout[6].Length = { 1400, 1500 } end), 1, { maxAttempts = 3 })
		local reasoned = #impossible.attempts == 3
		for _, record in impossible.attempts do
			reasoned = reasoned and #record.reasons > 0
		end
		check("exhausted budget returns ok = false without a circuit", impossible.ok == false and impossible.circuit == nil and reasoned and impossible.message ~= nil,
			impossible.attempts[1] and impossible.attempts[1].reasons[1] or nil)
	end)
	check("self-test ran without error", ran, if ran then nil else tostring(err))
	table.insert(lines, 1, string.format("JapaneseCircuitGenerator.selfTest: %d failure(s)", failures))
	return failures == 0, lines
end

return JapaneseCircuitGenerator
