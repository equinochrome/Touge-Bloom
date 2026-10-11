-- Seeded natural mountain heights around a road centerline, as pure data: no Instances and no
-- Terrain writes. Natural terrain is a basin floor ringed by ridges, built from independent noise
-- domains. Near the road it is held flat under the asphalt and shoulder, then blended smoothly
-- back to the natural surface.
--
--   local field = MountainHeightfield.new(seed, circuit, TerrainConfig) -- circuit may be nil
--   local y = MountainHeightfield.heightAt(field, x, z)
--   local info = MountainHeightfield.sample(field, x, z) -- height, slope, zone, material class
--
-- `circuit` is anything shaped like RoadGeometry.build's result: { samples = { { position } },
-- width }, optionally `closed = false` for an open road. Units follow TerrainConfig (studs).
--
-- Road shaping is continuous everywhere. The road height under a point is a weighted mix of every
-- segment whose closest point is less than a band (Road.BlendBand, growing with
-- Road.BlendBandGrowth past the shoulder) farther than the nearest one, so switching between two
-- road passes, or across the inside of a bend, never steps. Inside the asphalt and shoulder the
-- band is small and the terrain sits Road.Clearance below the road. new() rejects distinct road
-- passes whose corridors overlap at heights more than Road.Clearance apart, because no terrain
-- surface can sit below both.
--
-- Cost: new() is O(n * g) to register n segments in a uniform grid (g = cells per segment's bounds,
-- 1 to 4 for 4-stud samples; total capped by Limits.MaxGridEntries) plus the corridor-conflict check,
-- O(n * p) with p = segments in the cells within two corridor widths (total capped by
-- Limits.MaxPairChecks). heightAt() is O(octaves + r^2 + m): it searches grid rings outward until
-- no unvisited segment can matter, r <= ceil((influenceRadius + largest band) / GridCellSize)
-- (7 by default), m = segments in the visited cells. sample() costs five heightAt() calls (slope by
-- central differences). Nothing yields; builders should batch and yield themselves.
--
-- MountainHeightfield.selfTest() is opt-in and never runs on require.
local DefaultConfig = require(script.Parent.Parent.Config.TerrainConfig)

export type Zone = "Road" | "Shoulder" | "Transition" | "Natural"

export type RoadInput = {
	samples: { { position: Vector3 } },
	width: number,
	closed: boolean?, -- defaults to true: the last sample connects back to the first
}

export type TerrainSample = {
	height: number, -- final surface height
	naturalHeight: number, -- height before road shaping
	slope: number, -- gradient magnitude, rise over run
	zone: Zone,
	blend: number, -- 0 = road corridor height, 1 = natural height
	roadDistance: number?, -- horizontal distance to the centerline; nil beyond influenceRadius
	roadHeight: number?, -- road surface height the corridor follows (mixed where segments are equally close)
	roadSegment: number?, -- nearest segment, lowest on ties; i runs from sample i to i + 1 (the last wraps to 1 when closed)
	materialClass: string,
	material: Enum.Material,
}

type Domain = { offsetX: number, offsetY: number, offsetZ: number, cos: number, sin: number }

type RoadIndex = {
	segment: { number }, -- original segment number of each kept segment
	ax: { number },
	ay: { number },
	az: { number },
	dx: { number },
	dy: { number },
	dz: { number },
	length: { number }, -- horizontal length
	inverseLengthSq: { number },
	previous: { number }, -- kept segment sharing this one's start; 0 at an open end
	following: { number }, -- kept segment sharing this one's end; 0 at an open end
	cells: { [number]: { number } }, -- keyed lookup only; each list is in ascending segment order
	cellSize: number,
	maxRing: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	-- Per-query scratch, reused so queries do not allocate. A segment is visited once per query.
	stamp: { number },
	stampValue: number,
	candidate: { number },
	candidateDistance: { number },
	candidateParam: { number },
}

export type Field = {
	seed: number,
	version: number,
	config: any,
	centerX: number,
	centerZ: number,
	hasRoad: boolean,
	halfWidth: number,
	corridorEdge: number, -- half width + shoulder: flat out to here
	influenceRadius: number, -- corridorEdge + MaxTransitionWidth: natural beyond here
	_domains: { [string]: Domain },
	_road: RoadIndex?,
}

local MountainHeightfield = {}

-- Salts come from position in this list: append new domains, never reorder.
local DOMAIN_NAMES = { "WarpX", "WarpZ", "Ridges", "Hills", "Detail", "Material" }
local NOISE_SECTIONS = { "Warp", "Ridges", "Hills", "Detail", "Material" }
local MATERIAL_CLASSES = { "RoadBed", "Shoulder", "Embankment", "Rock", "Meadow", "Forest" }

local TWO_32 = 4294967296
local MAX_SEED = 2 ^ 53
local MAX_OCTAVES = 8
local OFFSET_RANGE = 1024 -- noise-space offset per domain; small enough to keep math.noise precise
local OCTAVE_SHIFT = 19.137 -- decorrelates octaves of one domain
local KEY_STRIDE = 2 ^ 24 -- grid key = cellX * stride + cellZ, valid while |cell| < 2^23
local MIN_SEGMENT_LENGTH_SQ = 1e-8
local BLEND_PEAK_SLOPE = 1.875 -- largest derivative of smootherstep over [0, 1]

local function fail(message: string): never
	error("MountainHeightfield: " .. message, 0)
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function requireFinite(value: any, name: string)
	if not isFinite(value) then
		fail(string.format("%s must be a finite number, got %s", name, tostring(value)))
	end
end

local function requirePositive(value: any, name: string)
	requireFinite(value, name)
	if value <= 0 then
		fail(string.format("%s must be positive, got %s", name, tostring(value)))
	end
end

local function requireRange(value: any, name: string, min: number, max: number)
	requireFinite(value, name)
	if value < min or value > max then
		fail(string.format("%s must be between %s and %s, got %s", name, tostring(min), tostring(max), tostring(value)))
	end
end

local function requireInteger(value: any, name: string, min: number, max: number)
	requireRange(value, name, min, max)
	if value % 1 ~= 0 then
		fail(string.format("%s must be an integer, got %s", name, tostring(value)))
	end
end

local function requireTable(value: any, name: string): any
	if type(value) ~= "table" then
		fail(name .. " must be a table")
	end
	return value
end

local function validateConfig(config: any)
	requireTable(config, "config")
	requireInteger(config.GeneratorVersion, "GeneratorVersion", 0, TWO_32 - 1)

	local basin = requireTable(config.Basin, "Basin")
	requireFinite(basin.FloorHeight, "Basin.FloorHeight")
	requirePositive(basin.FloorRadius, "Basin.FloorRadius")
	requireFinite(basin.RidgeRadius, "Basin.RidgeRadius")
	if basin.RidgeRadius <= basin.FloorRadius then
		fail("Basin.RidgeRadius must be greater than Basin.FloorRadius")
	end
	requireRange(basin.RidgeHeight, "Basin.RidgeHeight", 0, math.huge)
	if basin.CenterX ~= nil then
		requireFinite(basin.CenterX, "Basin.CenterX")
	end
	if basin.CenterZ ~= nil then
		requireFinite(basin.CenterZ, "Basin.CenterZ")
	end

	local noise = requireTable(config.Noise, "Noise")
	for i = 1, #NOISE_SECTIONS do
		local name = "Noise." .. NOISE_SECTIONS[i]
		local settings = requireTable(noise[NOISE_SECTIONS[i]], name)
		requirePositive(settings.Frequency, name .. ".Frequency")
		requireRange(settings.Amplitude, name .. ".Amplitude", 0, math.huge)
		requireInteger(settings.Octaves, name .. ".Octaves", 1, MAX_OCTAVES)
		requireRange(settings.Lacunarity, name .. ".Lacunarity", 1, 8)
		requireRange(settings.Gain, name .. ".Gain", 0.01, 1)
	end
	requireInteger(noise.Ridges.Sharpness, "Noise.Ridges.Sharpness", 1, 4)
	requireRange(noise.Ridges.BasinScale, "Noise.Ridges.BasinScale", 0, 1)

	local road = requireTable(config.Road, "Road")
	requirePositive(road.Clearance, "Road.Clearance")
	requirePositive(road.ShoulderWidth, "Road.ShoulderWidth")
	requirePositive(road.TransitionWidth, "Road.TransitionWidth")
	requireFinite(road.MaxTransitionWidth, "Road.MaxTransitionWidth")
	if road.MaxTransitionWidth < road.TransitionWidth then
		fail("Road.MaxTransitionWidth must be at least Road.TransitionWidth")
	end
	requirePositive(road.EmbankmentSlope, "Road.EmbankmentSlope")
	requirePositive(road.BlendBand, "Road.BlendBand")
	requireRange(road.BlendBandGrowth, "Road.BlendBandGrowth", 0, 4)

	local materials = requireTable(config.Materials, "Materials")
	requirePositive(materials.SlopeStep, "Materials.SlopeStep")
	requirePositive(materials.RockSlope, "Materials.RockSlope")
	if materials.RockSlope <= noise.Material.Amplitude then
		fail("Materials.RockSlope must exceed Noise.Material.Amplitude")
	end
	requireRange(materials.MeadowSlope, "Materials.MeadowSlope", 0, math.huge)
	requireFinite(materials.MeadowMaxAboveFloor, "Materials.MeadowMaxAboveFloor")
	local terrain = requireTable(materials.Terrain, "Materials.Terrain")
	for i = 1, #MATERIAL_CLASSES do
		if typeof(terrain[MATERIAL_CLASSES[i]]) ~= "EnumItem" then
			fail("Materials.Terrain." .. MATERIAL_CLASSES[i] .. " must be an Enum.Material")
		end
	end

	local limits = requireTable(config.Limits, "Limits")
	requireInteger(limits.MaxRoadSamples, "Limits.MaxRoadSamples", 2, 1e6)
	requirePositive(limits.MaxCoordinate, "Limits.MaxCoordinate")
	requireInteger(limits.MaxGridEntries, "Limits.MaxGridEntries", 1, 1e8)
	requirePositive(limits.GridCellSize, "Limits.GridCellSize")
	requireInteger(limits.MaxPairChecks, "Limits.MaxPairChecks", 1, 1e9)
end

-- Seed derivation: xorshift32 rounds over the seed's low and high 32 bits, the generator version
-- and a per-domain salt. Every step is invertible, so different seeds give different domain seeds.
local function mix(state: number, value: number): number
	local h = bit32.bxor(state, value)
	for _ = 1, 3 do
		h = bit32.bxor(h, bit32.lshift(h, 13))
		h = bit32.bxor(h, bit32.rshift(h, 17))
		h = bit32.bxor(h, bit32.lshift(h, 5))
	end
	return h
end

local function makeDomain(seed: number, version: number, salt: number): Domain
	local h = mix(2166136261, seed % TWO_32)
	h = mix(h, math.floor(seed / TWO_32) % TWO_32)
	h = mix(h, version)
	local rng = Random.new(mix(h, salt))
	local angle = rng:NextNumber(0, 2 * math.pi)
	return {
		offsetX = rng:NextNumber(-OFFSET_RANGE, OFFSET_RANGE),
		offsetY = rng:NextNumber(-OFFSET_RANGE, OFFSET_RANGE),
		offsetZ = rng:NextNumber(-OFFSET_RANGE, OFFSET_RANGE),
		cos = math.cos(angle),
		sin = math.sin(angle),
	}
end

local function smootherstep(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function ease(t: number): number
	return smootherstep(math.clamp(t, 0, 1))
end

-- Normalized fractal noise in [-1, 1], or [0, 1] when ridged (sharp crests where noise crosses zero).
local function fractal(domain: Domain, settings: any, x: number, z: number, ridged: boolean): number
	local u = (x * domain.cos - z * domain.sin) * settings.Frequency
	local v = (x * domain.sin + z * domain.cos) * settings.Frequency
	local total, norm, weight, scale = 0, 0, 1, 1
	for octave = 1, settings.Octaves do
		local n = math.noise(
			u * scale + domain.offsetX + octave * OCTAVE_SHIFT,
			v * scale + domain.offsetZ - octave * OCTAVE_SHIFT,
			domain.offsetY
		)
		n = math.clamp(n, -1, 1)
		if ridged then
			local crease = math.clamp(1 - 2 * math.abs(n), 0, 1)
			n = crease
			for _ = 2, settings.Sharpness do
				n *= crease
			end
		end
		total += n * weight
		norm += weight
		weight *= settings.Gain
		scale *= settings.Lacunarity
	end
	return total / norm
end

local function naturalHeight(field: Field, x: number, z: number): number
	local noise = field.config.Noise
	local basin = field.config.Basin
	local domains = field._domains
	local warp = noise.Warp
	local px = x + fractal(domains.WarpX, warp, x, z, false) * warp.Amplitude
	local pz = z + fractal(domains.WarpZ, warp, x, z, false) * warp.Amplitude

	local ox, oz = px - field.centerX, pz - field.centerZ
	local ringT = (math.sqrt(ox * ox + oz * oz) - basin.FloorRadius) / (basin.RidgeRadius - basin.FloorRadius)
	local ring = smootherstep(math.clamp(ringT, 0, 1))

	local ridges = noise.Ridges
	local ridgeAmplitude = ridges.Amplitude * (ridges.BasinScale + (1 - ridges.BasinScale) * ring)
	return basin.FloorHeight
		+ ring * basin.RidgeHeight
		+ fractal(domains.Ridges, ridges, px, pz, true) * ridgeAmplitude
		+ fractal(domains.Hills, noise.Hills, px, pz, false) * noise.Hills.Amplitude
		+ fractal(domains.Detail, noise.Detail, x, z, false) * noise.Detail.Amplitude
end

-- Unclamped parameter of (x, z) projected onto segment k: 0 at its start, 1 at its end.
local function projection(index: RoadIndex, k: number, x: number, z: number): number
	return ((x - index.ax[k]) * index.dx[k] + (z - index.az[k]) * index.dz[k]) * index.inverseLengthSq[k]
end

-- Horizontal squared distance from (x, z) to segment k and the road height at the closest point.
local function pointToSegment(index: RoadIndex, k: number, x: number, z: number): (number, number)
	local t = math.clamp(projection(index, k, x, z), 0, 1)
	local ex, ez = x - index.ax[k] - index.dx[k] * t, z - index.az[k] - index.dz[k] * t
	return ex * ex + ez * ez, index.ay[k] + index.dy[k] * t
end

-- Largest road height difference where segments i and j come within sqrt(thresholdSq) of each
-- other, or nil when they never do. Measured at the closest points of each endpoint and at a
-- crossing; between those, both heights are linear, which is exact enough for short samples.
local function closeHeightDifference(index: RoadIndex, i: number, j: number, thresholdSq: number): number?
	local worst: number? = nil
	for e = 0, 1 do
		local x, z, y = index.ax[i] + index.dx[i] * e, index.az[i] + index.dz[i] * e, index.ay[i] + index.dy[i] * e
		local distanceSq, other = pointToSegment(index, j, x, z)
		if distanceSq < thresholdSq then
			worst = math.max(worst or 0, math.abs(y - other))
		end
		x, z, y = index.ax[j] + index.dx[j] * e, index.az[j] + index.dz[j] * e, index.ay[j] + index.dy[j] * e
		distanceSq, other = pointToSegment(index, i, x, z)
		if distanceSq < thresholdSq then
			worst = math.max(worst or 0, math.abs(y - other))
		end
	end
	local denominator = index.dx[i] * index.dz[j] - index.dz[i] * index.dx[j]
	if denominator ~= 0 then
		local rx, rz = index.ax[j] - index.ax[i], index.az[j] - index.az[i]
		local s = (rx * index.dz[j] - rz * index.dx[j]) / denominator
		local t = (rx * index.dz[i] - rz * index.dx[i]) / denominator
		if s >= 0 and s <= 1 and t >= 0 and t <= 1 then
			worst = math.max(worst or 0, math.abs(index.ay[i] + index.dy[i] * s - index.ay[j] - index.dy[j] * t))
		end
	end
	return worst
end

-- Rejects distinct road passes whose corridors (plus BlendBand) overlap at heights more than
-- Clearance apart: no terrain surface could sit below both. Segments less than half a turn of
-- corridor radius apart along the road are the same pass and are not compared.
local function checkCorridorConflicts(index: RoadIndex, kept: number, closed: boolean, roadConfig: any, corridorEdge: number, maxChecks: number)
	local threshold = 2 * corridorEdge + roadConfig.BlendBand
	local thresholdSq = threshold * threshold
	local separation = math.pi * (corridorEdge + roadConfig.BlendBand)
	local cellSize = index.cellSize

	local arcStart = table.create(kept)
	local total = 0
	for k = 1, kept do
		arcStart[k] = total
		total += index.length[k]
	end

	local marks = table.create(kept, 0)
	local checks = 0
	for i = 1, kept do
		local ax, az = index.ax[i], index.az[i]
		local bx, bz = ax + index.dx[i], az + index.dz[i]
		local cx0, cx1 = math.floor((math.min(ax, bx) - threshold) / cellSize), math.floor((math.max(ax, bx) + threshold) / cellSize)
		local cz0, cz1 = math.floor((math.min(az, bz) - threshold) / cellSize), math.floor((math.max(az, bz) + threshold) / cellSize)
		for cx = cx0, cx1 do
			for cz = cz0, cz1 do
				local list = index.cells[cx * KEY_STRIDE + cz]
				if list ~= nil then
					for n = 1, #list do
						local j = list[n]
						if j > i and marks[j] ~= i then
							marks[j] = i
							checks += 1
							if checks > maxChecks then
								fail("corridor conflict check exceeds Limits.MaxPairChecks; the road is too dense")
							end
							local gap = arcStart[j] - (arcStart[i] + index.length[i])
							if closed then
								gap = math.min(gap, total - (arcStart[j] + index.length[j]) + arcStart[i])
							end
							if gap >= separation then
								local difference = closeHeightDifference(index, i, j, thresholdSq)
								if difference ~= nil and difference > roadConfig.Clearance then
									fail(string.format(
										"road segments %d and %d come within %.1f studs at heights %.2f studs apart; "
											.. "their corridors overlap, so terrain cannot sit below both. Separate the passes "
											.. "or keep the height difference within Road.Clearance (%s)",
										index.segment[i],
										index.segment[j],
										threshold,
										difference,
										tostring(roadConfig.Clearance)
									))
								end
							end
						end
					end
				end
			end
		end
	end
end

-- Validates the road and builds a uniform grid of horizontal segments. Each segment is listed in
-- every cell its bounds touch; queries search rings of cells outward from their own cell.
local function buildRoadIndex(road: any, config: any, corridorEdge: number, influence: number): (RoadIndex, number, number)
	local limits, roadConfig = config.Limits, config.Road
	local samples = road.samples
	if type(samples) ~= "table" then
		fail("road.samples must be an array of { position: Vector3 }")
	end
	local count = #samples
	if count < 2 then
		fail(string.format("road needs at least 2 samples, got %d", count))
	end
	if count > limits.MaxRoadSamples then
		fail(string.format("road has %d samples, more than Limits.MaxRoadSamples (%d)", count, limits.MaxRoadSamples))
	end
	local closed = road.closed
	if closed == nil then
		closed = true
	elseif type(closed) ~= "boolean" then
		fail("road.closed must be a boolean or nil")
	end

	local cellSize = limits.GridCellSize
	local reach = influence + roadConfig.BlendBand + roadConfig.BlendBandGrowth * roadConfig.MaxTransitionWidth
	local maxCoordinate = limits.MaxCoordinate
	if (maxCoordinate + reach) / cellSize + 2 >= KEY_STRIDE / 2 then
		fail("Limits.MaxCoordinate is too large for Limits.GridCellSize")
	end

	local points = table.create(count)
	local sumX, sumZ = 0, 0
	for i = 1, count do
		local sample = samples[i]
		local position = if type(sample) == "table" then sample.position else nil
		if typeof(position) ~= "Vector3" then
			fail(string.format("road.samples[%d].position must be a Vector3", i))
		end
		if not (isFinite(position.X) and isFinite(position.Y) and isFinite(position.Z)) then
			fail(string.format("road.samples[%d].position is not finite", i))
		end
		if math.abs(position.X) > maxCoordinate or math.abs(position.Z) > maxCoordinate then
			fail(string.format("road.samples[%d].position is beyond Limits.MaxCoordinate", i))
		end
		points[i] = position
		sumX += position.X
		sumZ += position.Z
	end

	local segmentCount = if closed then count else count - 1
	local index: RoadIndex = {
		segment = table.create(segmentCount),
		ax = table.create(segmentCount),
		ay = table.create(segmentCount),
		az = table.create(segmentCount),
		dx = table.create(segmentCount),
		dy = table.create(segmentCount),
		dz = table.create(segmentCount),
		length = table.create(segmentCount),
		inverseLengthSq = table.create(segmentCount),
		previous = table.create(segmentCount),
		following = table.create(segmentCount),
		cells = {},
		cellSize = cellSize,
		maxRing = math.ceil(reach / cellSize),
		minX = math.huge,
		maxX = -math.huge,
		minZ = math.huge,
		maxZ = -math.huge,
		stamp = {},
		stampValue = 0,
		candidate = {},
		candidateDistance = {},
		candidateParam = {},
	}

	local kept, entries = 0, 0
	for s = 1, segmentCount do
		local a = points[s]
		local b = points[s % count + 1]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local lengthSq = dx * dx + dz * dz
		-- Segments with no horizontal extent add nothing a neighbor does not already cover; their
		-- neighbors still meet at the same horizontal point.
		if lengthSq > MIN_SEGMENT_LENGTH_SQ then
			kept += 1
			index.segment[kept] = s
			index.ax[kept], index.ay[kept], index.az[kept] = a.X, a.Y, a.Z
			index.dx[kept], index.dy[kept], index.dz[kept] = dx, b.Y - a.Y, dz
			index.length[kept] = math.sqrt(lengthSq)
			index.inverseLengthSq[kept] = 1 / lengthSq

			local x0, x1 = math.min(a.X, b.X), math.max(a.X, b.X)
			local z0, z1 = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
			index.minX, index.maxX = math.min(index.minX, x0 - influence), math.max(index.maxX, x1 + influence)
			index.minZ, index.maxZ = math.min(index.minZ, z0 - influence), math.max(index.maxZ, z1 + influence)

			local cx0, cx1 = math.floor(x0 / cellSize), math.floor(x1 / cellSize)
			local cz0, cz1 = math.floor(z0 / cellSize), math.floor(z1 / cellSize)
			entries += (cx1 - cx0 + 1) * (cz1 - cz0 + 1)
			if entries > limits.MaxGridEntries then
				fail("road lookup grid exceeds Limits.MaxGridEntries; road samples are too sparse or too many")
			end
			for cx = cx0, cx1 do
				for cz = cz0, cz1 do
					local key = cx * KEY_STRIDE + cz
					local list = index.cells[key]
					if list == nil then
						list = {}
						index.cells[key] = list
					end
					table.insert(list, kept)
				end
			end
		end
	end
	if kept == 0 then
		fail("road is degenerate: every centerline segment has zero horizontal length")
	end

	for k = 1, kept do
		index.previous[k] = k - 1
		index.following[k] = if k < kept then k + 1 else 0
		index.stamp[k] = 0
	end
	if closed and kept > 1 then
		index.previous[1] = kept
		index.following[kept] = 1
	end

	checkCorridorConflicts(index, kept, closed, roadConfig, corridorEdge, limits.MaxPairChecks)
	return index, sumX / count, sumZ / count
end

-- Weight from 0 to 1 for a segment whose closest point is clamped to one of its ends, where it only
-- repeats the shared vertex. It stays while the neighbor across that vertex is clamped there too
-- (the vertex itself is nearest, outside a bend) and fades as the neighbor's interior takes over,
-- so a graded road's height is not skewed by its neighbors. Open road ends always stay. When the
-- vertex is nearest, the two segments' weights sum to at least 1. Continuous in (x, z).
local function endWeight(index: RoadIndex, k: number, u: number, x: number, z: number, band: number): number
	if u < 0 then
		local previous = index.previous[k]
		local past = ease(-u * index.length[k] / band)
		local neighborPast = if previous == 0 then 1 else ease((projection(index, previous, x, z) - 1) * index.length[previous] / band)
		return 1 - past * (1 - neighborPast)
	elseif u > 1 then
		local following = index.following[k]
		local past = ease((u - 1) * index.length[k] / band)
		local neighborPast = if following == 0 then 1 else ease(-projection(index, following, x, z) * index.length[following] / band)
		return 1 - past * (1 - neighborPast)
	end
	return 1
end

-- Mixing band for a nearest distance: BlendBand inside the corridor, growing beyond it.
local function bandAt(field: Field, distance: number): number
	local road = field.config.Road
	return road.BlendBand + road.BlendBandGrowth * math.max(0, distance - field.corridorEdge)
end

-- Distance to the nearest centerline point (horizontal), the road surface height the terrain
-- follows there, and the nearest segment number. Returns nil beyond the influence radius.
--
-- The nearest distance is continuous. Every segment less than bandAt(nearest) farther away gets a
-- weight that falls smoothly to 0 at that limit, so segments enter and leave the mix without
-- steps. Rings of cells are searched until no unvisited segment can be within that limit, which
-- makes the result independent of the query's grid cell.
local function nearestRoad(field: Field, index: RoadIndex, x: number, z: number): (number?, number?, number?)
	if x < index.minX or x > index.maxX or z < index.minZ or z > index.maxZ then
		return nil, nil, nil
	end
	local influence = field.influenceRadius
	local cellSize = index.cellSize
	local cx, cz = math.floor(x / cellSize), math.floor(z / cellSize)
	local stampValue = index.stampValue + 1
	index.stampValue = stampValue
	local stamp, candidate, candidateDistance, candidateParam =
		index.stamp, index.candidate, index.candidateDistance, index.candidateParam

	local count, best, bestK = 0, math.huge, 0
	local function scan(key: number)
		local list = index.cells[key]
		if list == nil then
			return
		end
		for n = 1, #list do
			local k = list[n]
			if stamp[k] ~= stampValue then
				stamp[k] = stampValue
				local u = projection(index, k, x, z)
				local t = math.clamp(u, 0, 1)
				local ex, ez = x - index.ax[k] - index.dx[k] * t, z - index.az[k] - index.dz[k] * t
				local distance = math.sqrt(ex * ex + ez * ez)
				count += 1
				candidate[count], candidateDistance[count], candidateParam[count] = k, distance, u
				if distance < best or (distance == best and k < bestK) then
					best, bestK = distance, k
				end
			end
		end
	end

	-- After ring r, every unvisited segment is at least r * cellSize away.
	for ring = 0, index.maxRing do
		if ring == 0 then
			scan(cx * KEY_STRIDE + cz)
		else
			for o = -ring, ring do
				scan((cx + o) * KEY_STRIDE + cz - ring)
				scan((cx + o) * KEY_STRIDE + cz + ring)
			end
			for o = 1 - ring, ring - 1 do
				scan((cx - ring) * KEY_STRIDE + cz + o)
				scan((cx + ring) * KEY_STRIDE + cz + o)
			end
		end
		local needed = if best < influence then best + bandAt(field, best) else influence
		if ring * cellSize >= needed then
			break
		end
	end
	if best >= influence then
		return nil, nil, nil
	end

	local band = bandAt(field, best)
	local vertexBand = field.config.Road.BlendBand
	local limit = best + band
	local sumWeight, sumHeight = 0, 0
	for n = 1, count do
		local distance = candidateDistance[n]
		if distance < limit then
			local k, u = candidate[n], candidateParam[n]
			local weight = (1 - ease((distance - best) / band)) * endWeight(index, k, u, x, z, vertexBand)
			if weight > 0 then
				sumWeight += weight
				sumHeight += weight * (index.ay[k] + index.dy[k] * math.clamp(u, 0, 1))
			end
		end
	end
	local roadY
	if sumWeight > 0 then
		roadY = sumHeight / sumWeight
	else
		-- Not expected: the nearest feature always carries weight of at least 1.
		local _, y = pointToSegment(index, bestK, x, z)
		roadY = y
	end
	return best, roadY, index.segment[bestK]
end

-- height, natural height, road distance, road height, road segment, blend.
local function evaluate(field: Field, x: number, z: number): (number, number, number?, number?, number?, number)
	local natural = naturalHeight(field, x, z)
	local index = field._road
	if index == nil then
		return natural, natural, nil, nil, nil, 1
	end
	local distance, roadY, segment = nearestRoad(field, index, x, z)
	if distance == nil or roadY == nil then
		return natural, natural, nil, nil, nil, 1
	end

	local road = field.config.Road
	local corridor = roadY - road.Clearance
	if distance <= field.corridorEdge then
		return corridor, natural, distance, roadY, segment, 0
	end
	-- Wider blends for bigger cuts and fills, so the peak slope stays near EmbankmentSlope.
	local width = math.clamp(
		BLEND_PEAK_SLOPE * math.abs(natural - corridor) / road.EmbankmentSlope,
		road.TransitionWidth,
		road.MaxTransitionWidth
	)
	local t = (distance - field.corridorEdge) / width
	if t >= 1 then
		return natural, natural, distance, roadY, segment, 1
	end
	local blend = smootherstep(t)
	return corridor + (natural - corridor) * blend, natural, distance, roadY, segment, blend
end

local function requireQuery(field: Field, x: any, z: any)
	requireFinite(x, "x")
	requireFinite(z, "z")
	local limit = field.config.Limits.MaxCoordinate
	if math.abs(x) > limit or math.abs(z) > limit then
		fail(string.format("query (%s, %s) is beyond Limits.MaxCoordinate", tostring(x), tostring(z)))
	end
end

local function requireFiniteResult(value: number, x: number, z: number): number
	if not isFinite(value) then
		fail(string.format("non-finite height at (%s, %s); check the configuration", tostring(x), tostring(z)))
	end
	return value
end

local function classify(field: Field, zone: Zone, x: number, z: number, height: number, slope: number): string
	if zone == "Road" then
		return "RoadBed"
	elseif zone == "Shoulder" then
		return "Shoulder"
	end
	local config = field.config
	local materials = config.Materials
	local jitter = fractal(field._domains.Material, config.Noise.Material, x, z, false) * config.Noise.Material.Amplitude
	if slope >= materials.RockSlope + jitter then
		return "Rock"
	elseif zone == "Transition" then
		return "Embankment"
	elseif slope <= materials.MeadowSlope and height <= config.Basin.FloorHeight + materials.MeadowMaxAboveFloor then
		return "Meadow"
	end
	return "Forest"
end

-- seed: integer with |seed| <= 2^53. road: RoadInput or nil for natural terrain only.
-- config: defaults to TerrainConfig. Errors with a clear message on any invalid input, including
-- road passes whose corridors overlap at conflicting heights.
function MountainHeightfield.new(seed: number, road: RoadInput?, config: any?): Field
	local resolved = if config == nil then DefaultConfig else config
	if not isFinite(seed) or seed % 1 ~= 0 or math.abs(seed) > MAX_SEED then
		fail(string.format("seed must be a finite integer with magnitude at most 2^53, got %s", tostring(seed)))
	end
	validateConfig(resolved)

	local domains = {}
	for salt = 1, #DOMAIN_NAMES do
		domains[DOMAIN_NAMES[salt]] = makeDomain(seed, resolved.GeneratorVersion, salt)
	end

	local field: Field = {
		seed = seed,
		version = resolved.GeneratorVersion,
		config = resolved,
		centerX = 0,
		centerZ = 0,
		hasRoad = false,
		halfWidth = 0,
		corridorEdge = 0,
		influenceRadius = 0,
		_domains = domains,
		_road = nil,
	}

	if road ~= nil then
		requireTable(road, "road")
		requirePositive(road.width, "road.width")
		field.halfWidth = road.width / 2
		field.corridorEdge = field.halfWidth + resolved.Road.ShoulderWidth
		field.influenceRadius = field.corridorEdge + resolved.Road.MaxTransitionWidth
		local index, centroidX, centroidZ = buildRoadIndex(road, resolved, field.corridorEdge, field.influenceRadius)
		field._road = index
		field.hasRoad = true
		field.centerX, field.centerZ = centroidX, centroidZ
	end
	local basin = resolved.Basin
	if basin.CenterX ~= nil then
		field.centerX = basin.CenterX
	end
	if basin.CenterZ ~= nil then
		field.centerZ = basin.CenterZ
	end
	return field
end

-- Final terrain surface height in studs at world (x, z).
function MountainHeightfield.heightAt(field: Field, x: number, z: number): number
	requireQuery(field, x, z)
	return requireFiniteResult((evaluate(field, x, z)), x, z)
end

-- Height before any road shaping.
function MountainHeightfield.naturalHeightAt(field: Field, x: number, z: number): number
	requireQuery(field, x, z)
	return requireFiniteResult(naturalHeight(field, x, z), x, z)
end

function MountainHeightfield.sample(field: Field, x: number, z: number): TerrainSample
	requireQuery(field, x, z)
	local height, natural, distance, roadY, segment, blend = evaluate(field, x, z)
	requireFiniteResult(height, x, z)

	local step = field.config.Materials.SlopeStep
	local gx = ((evaluate(field, x + step, z)) - (evaluate(field, x - step, z))) / (2 * step)
	local gz = ((evaluate(field, x, z + step)) - (evaluate(field, x, z - step))) / (2 * step)
	local slope = requireFiniteResult(math.sqrt(gx * gx + gz * gz), x, z)

	local zone: Zone = "Natural"
	if distance ~= nil then
		if distance <= field.halfWidth then
			zone = "Road"
		elseif distance <= field.corridorEdge then
			zone = "Shoulder"
		elseif blend < 1 then
			zone = "Transition"
		end
	end

	local materialClass = classify(field, zone, x, z, height, slope)
	return {
		height = height,
		naturalHeight = natural,
		slope = slope,
		zone = zone,
		blend = blend,
		roadDistance = distance,
		roadHeight = roadY,
		roadSegment = segment,
		materialClass = materialClass,
		material = field.config.Materials.Terrain[materialClass],
	}
end

-- Opt-in checks; call from the Studio command bar. Returns (passed, report lines). Never prints.
function MountainHeightfield.selfTest(): (boolean, { string })
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
	local function near(a: number?, b: number, tolerance: number?): boolean
		return a ~= nil and math.abs(a - b) <= (tolerance or 1e-4)
	end
	local function point(x: number, y: number, z: number)
		return { position = Vector3.new(x, y, z) }
	end
	local function withSetting(section: string, key: string, value: any): any
		local copy = table.clone(DefaultConfig)
		copy[section] = table.clone(DefaultConfig[section])
		copy[section][key] = value
		return copy
	end
	local function reversed(list: { any }): { any }
		local out = table.create(#list)
		for i = #list, 1, -1 do
			table.insert(out, list[i])
		end
		return out
	end

	local new, heightAt, sample = MountainHeightfield.new, MountainHeightfield.heightAt, MountainHeightfield.sample
	local clearance = DefaultConfig.Road.Clearance
	local blendBand = DefaultConfig.Road.BlendBand

	-- Largest height change per stud between consecutive points on a straight line, and whether
	-- every height was finite. A step of one stud or more over a short step reads as a huge slope.
	local MAX_SCAN_SLOPE = 20
	local function scan(field: Field, x0: number, z0: number, x1: number, z1: number, steps: number): (number, boolean)
		local length = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local previous = heightAt(field, x0, z0)
		local steepest, finite = 0, isFinite(previous)
		for i = 1, steps do
			local f = i / steps
			local h = heightAt(field, x0 + (x1 - x0) * f, z0 + (z1 - z0) * f)
			finite = finite and isFinite(h)
			steepest = math.max(steepest, math.abs(h - previous) / (length / steps))
			previous = h
		end
		return steepest, finite
	end

	local ran, err = pcall(function()
		-- Repeatability, seeds and negative coordinates.
		local probes = {
			{ 0, 0 },
			{ 137.25, -52.5 },
			{ -1234.5, -987.25 },
			{ -0.5, -0.5 },
			{ 2500, -3100 },
			{ -40000, 35000 },
			{ 611.1, 611.1 },
			{ -77, 903 },
		}
		local a, b = new(12345, nil), new(12345, nil)
		local other, negative = new(12346, nil), new(-12345, nil)
		local repeatable, finite, differs, differsNegative = true, true, 0, 0
		for i = 1, #probes do
			local x, z = probes[i][1], probes[i][2]
			local h = heightAt(a, x, z)
			if h ~= heightAt(b, x, z) or h ~= heightAt(a, x, z) then
				repeatable = false
			end
			finite = finite and isFinite(h)
			if math.abs(h - heightAt(other, x, z)) > 0.01 then
				differs += 1
			end
			if math.abs(h - heightAt(negative, x, z)) > 0.01 then
				differsNegative += 1
			end
		end
		check("same seed repeats exactly", repeatable)
		check("heights finite at negative and far coordinates", finite)
		check("adjacent seed changes heights", differs >= #probes - 1, string.format("%d/%d differ", differs, #probes))
		check("negated seed changes heights", differsNegative >= #probes - 1, string.format("%d/%d differ", differsNegative, #probes))
		check(
			"noise domains are independent",
			a._domains.WarpX.offsetX ~= a._domains.WarpZ.offsetX and a._domains.Hills.offsetX ~= other._domains.Hills.offsetX
		)
		check("negative coordinates are not mirrored", heightAt(a, -1234.5, -987.25) ~= heightAt(a, 1234.5, 987.25))

		-- Road clearance with elevation interpolated between samples, not taken from the nearest sample.
		local sloped = new(7, { width = 30, closed = false, samples = { point(0, 0, 0), point(100, 20, 0), point(200, 20, 0) } })
		local mid = sample(sloped, 50, 5)
		check(
			"interpolated road elevation under asphalt",
			mid.zone == "Road" and near(mid.roadHeight, 10) and near(mid.height, 10 - clearance) and mid.roadSegment == 1,
			string.format("zone %s, road %s, height %.4f", mid.zone, tostring(mid.roadHeight), mid.height)
		)

		-- Wraparound: the closing segment from the last sample back to the first.
		local loop = { point(0, 0, 0), point(400, 0, 0), point(400, 0, 400), point(0, 8, 400) }
		local closedLoop = new(7, { width = 30, samples = loop })
		local wrap = sample(closedLoop, -5, 200)
		check(
			"wraparound segment is used",
			wrap.zone == "Road" and wrap.roadSegment == 4 and near(wrap.roadHeight, 4) and near(wrap.height, 4 - clearance),
			string.format("zone %s, segment %s, height %.4f", wrap.zone, tostring(wrap.roadSegment), wrap.height)
		)
		local openLoop = new(7, { width = 30, closed = false, samples = loop })
		check("open road has no wraparound segment", sample(openLoop, -5, 200).zone == "Natural")

		-- Blend boundaries on a level straight road at Y 10, measured outward along Z from x = 0.
		local straight = new(7, { width = 30, closed = false, samples = { point(-400, 10, 0), point(0, 10, 0), point(400, 10, 0) } })
		local corridor = 10 - clearance
		local edge, radius = straight.corridorEdge, straight.influenceRadius
		check("edge of asphalt is Road", sample(straight, 0, 14.9).zone == "Road")
		check("just past asphalt is Shoulder", sample(straight, 0, 15.1).zone == "Shoulder")
		local atEdge = sample(straight, 0, edge)
		check("shoulder edge holds corridor height", atEdge.zone == "Shoulder" and near(atEdge.height, corridor))
		local justOut = sample(straight, 0, edge + 0.01)
		check("blend starts continuously", near(justOut.height, corridor, 0.01), string.format("height %.4f", justOut.height))
		local beyond = sample(straight, 0, radius + 1)
		check(
			"beyond influence radius is natural",
			beyond.zone == "Natural" and beyond.roadDistance == nil and beyond.height == beyond.naturalHeight
		)

		local bounded, continuous, belowRoad = true, true, true
		local previous = heightAt(straight, 0, 0)
		for step = 1, 520 do
			local z = step * 0.25
			local s = sample(straight, 0, z)
			local low, high = math.min(corridor, s.naturalHeight), math.max(corridor, s.naturalHeight)
			if s.height < low - 1e-6 or s.height > high + 1e-6 then
				bounded = false
			end
			if math.abs(s.height - previous) > 0.25 * 6 then
				continuous = false
			end
			if z <= edge and s.height >= 10 then
				belowRoad = false
			end
			previous = s.height
		end
		check("corridor stays below the road surface", belowRoad)
		check("blend stays between corridor and natural heights", bounded)
		check("blend has no jumps", continuous)

		-- Regression: two road passes 80 studs apart at heights 0 and 8 (Codex counterexample).
		-- Nearest-segment switching used to jump 4 studs at z = 40.
		local parallel = { point(-200, 0, 0), point(200, 0, 0), point(200, 8, 80), point(-200, 8, 80) }
		local layouts = {
			{ "open", new(7, { width = 30, closed = false, samples = parallel }) },
			{ "closed", new(7, { width = 30, samples = parallel }) },
		}
		local openReversed = new(7, { width = 30, closed = false, samples = reversed(parallel) })
		local closedReversed = new(7, { width = 30, samples = reversed(parallel) })
		for l = 1, #layouts do
			local name, field = layouts[l][1], layouts[l][2]
			local below, above = heightAt(field, 0, 39.999), heightAt(field, 0, 40.001)
			check(
				name .. " parallel passes: no jump across the midline",
				math.abs(above - below) <= MAX_SCAN_SLOPE * 0.002,
				string.format("z 39.999 -> %.6f, z 40.001 -> %.6f", below, above)
			)
			local worst, allFinite = 0, true
			for _, x in { -150, 0, 150 } do
				local steepest, finite = scan(field, x, 0, x, 80, 4000)
				worst, allFinite = math.max(worst, steepest), allFinite and finite
			end
			check(
				name .. " parallel passes: both sides of the transition scanned continuously",
				allFinite and worst <= MAX_SCAN_SLOPE,
				string.format("steepest %.3f per stud", worst)
			)
			local low, high = sample(field, 0, 10), sample(field, 0, 70)
			check(
				name .. " parallel passes: each corridor keeps exact clearance",
				near(low.height, -clearance) and near(high.height, 8 - clearance),
				string.format("%.6f and %.6f", low.height, high.height)
			)
			-- Inside the corner at (200, 0) the nearest segment switches on the bisector x = 200 - z.
			local steepest, finite = scan(field, 180, 10, 199, 10, 1900)
			check(
				name .. " parallel passes: no jump across the inside-corner bisector",
				finite and steepest <= MAX_SCAN_SLOPE,
				string.format("steepest %.3f per stud", steepest)
			)
		end

		local sameReversed = true
		for zi = 0, 80 do
			for _, x in { -150, 0, 150, 195 } do
				local z = zi + 0.37
				local h = heightAt(layouts[1][2], x, z)
				if math.abs(h - heightAt(openReversed, x, z)) > 1e-6 or math.abs(heightAt(layouts[2][2], x, z) - heightAt(closedReversed, x, z)) > 1e-6 then
					sameReversed = false
				end
			end
		end
		check("reversed segment order gives the same heights", sameReversed)

		-- Grid cell boundaries: no step across cell edges in X or Z, near both passes and between them.
		local field = layouts[1][2]
		local cellSize = (field._road :: RoadIndex).cellSize
		local acrossCells = true
		local worstCell = 0
		for _, z in { 5, 24.999, 30, 39.999, 40, 45, 75 } do
			for c = -3, 3 do
				local x = c * cellSize
				local jump = math.abs(heightAt(field, x - 0.001, z) - heightAt(field, x + 0.001, z))
				worstCell = math.max(worstCell, jump)
				acrossCells = acrossCells and jump <= MAX_SCAN_SLOPE * 0.002
			end
		end
		for _, x in { -100, 0, 100, 199 } do
			for c = 0, 3 do
				local z = c * cellSize
				local jump = math.abs(heightAt(field, x, z - 0.001) - heightAt(field, x, z + 0.001))
				worstCell = math.max(worstCell, jump)
				acrossCells = acrossCells and jump <= MAX_SCAN_SLOPE * 0.002
			end
		end
		check("no jumps across grid cell boundaries", acrossCells, string.format("largest %.6f", worstCell))

		-- Dense graded road like RoadGeometry output: 4-stud samples on a 5% grade.
		local graded = {}
		for i = 0, 100 do
			local x = -200 + i * 4
			table.insert(graded, point(x, 0.05 * x, 0))
		end
		local gradedField = new(7, { width = 30, closed = false, samples = graded })
		local exactMid, belowGraded = true, true
		for i = -20, 20 do
			local x = 2 + 4 * i
			for _, z in { -24, -10, 0, 10, 24 } do
				if not near(heightAt(gradedField, x, z), 0.05 * x - clearance, 1e-6) then
					exactMid = false
				end
			end
		end
		for i = 0, 2000 do
			local x = -100 + i * 0.1
			for _, z in { 0, 12, -20 } do
				if heightAt(gradedField, x, z) > 0.05 * x - clearance + 0.05 * blendBand + 1e-6 then
					belowGraded = false
				end
			end
		end
		check("graded 4-stud road: exact clearance between sample vertices", exactMid)
		check("graded 4-stud road: corridor never rises past clearance (grade x BlendBand)", belowGraded)

		-- Distinct passes whose corridors overlap: rejected at different heights, accepted level.
		local function hairpin(farHeight: number)
			return {
				point(-200, 0, 0),
				point(200, 0, 0),
				point(250, farHeight / 2, 20),
				point(200, farHeight, 40),
				point(-200, farHeight, 40),
			}
		end
		expectError("overlapping corridors at different heights", function()
			new(7, { width = 30, closed = false, samples = hairpin(8) })
		end)
		local levelOk, level = pcall(new, 7, { width = 30, closed = false, samples = hairpin(0) })
		check(
			"overlapping corridors at the same height are accepted",
			levelOk and near(heightAt(level, 0, 20), -clearance),
			if levelOk then nil else tostring(level)
		)

		-- Invalid input.
		expectError("NaN seed", function()
			new(0 / 0, nil)
		end)
		expectError("infinite seed", function()
			new(math.huge, nil)
		end)
		expectError("fractional seed", function()
			new(1.5, nil)
		end)
		expectError("string seed", function()
			new("1" :: any, nil)
		end)
		expectError("zero road width", function()
			new(1, { width = 0, samples = loop })
		end)
		expectError("negative road width", function()
			new(1, { width = -5, samples = loop })
		end)
		expectError("NaN road width", function()
			new(1, { width = 0 / 0, samples = loop })
		end)
		expectError("missing samples", function()
			new(1, { width = 30 } :: any)
		end)
		expectError("single sample", function()
			new(1, { width = 30, samples = { point(0, 0, 0) } })
		end)
		expectError("non-finite sample", function()
			new(1, { width = 30, samples = { point(0, 0, 0), point(0 / 0, 0, 10) } })
		end)
		expectError("degenerate road", function()
			new(1, { width = 30, samples = { point(5, 0, 5), point(5, 3, 5), point(5, 0, 5) } })
		end)
		expectError("zero shoulder width", function()
			new(1, nil, withSetting("Road", "ShoulderWidth", 0))
		end)
		expectError("negative transition width", function()
			new(1, nil, withSetting("Road", "TransitionWidth", -1))
		end)
		expectError("zero clearance", function()
			new(1, nil, withSetting("Road", "Clearance", 0))
		end)
		expectError("zero blend band", function()
			new(1, nil, withSetting("Road", "BlendBand", 0))
		end)
		expectError("zero grid cell size", function()
			new(1, nil, withSetting("Limits", "GridCellSize", 0))
		end)
		expectError("NaN query", function()
			heightAt(a, 0 / 0, 0)
		end)
		expectError("infinite query", function()
			sample(a, 0, math.huge)
		end)
		expectError("query beyond MaxCoordinate", function()
			heightAt(a, DefaultConfig.Limits.MaxCoordinate + 1, 0)
		end)

		-- Finite results and known classes across a wide grid around the closed loop.
		local allFinite, knownClasses = true, true
		for gx = -24, 24 do
			for gz = -24, 24 do
				local s = sample(closedLoop, gx * 125, gz * 125)
				if not (isFinite(s.height) and isFinite(s.naturalHeight) and isFinite(s.slope) and isFinite(s.blend)) then
					allFinite = false
				end
				if typeof(s.material) ~= "EnumItem" then
					knownClasses = false
				end
			end
		end
		for gx = -10, 10 do
			for gz = -10, 10 do
				local s = sample(layouts[2][2], gx * 4.3, 40 + gz * 4.3)
				allFinite = allFinite and isFinite(s.height) and isFinite(s.slope)
				knownClasses = knownClasses and typeof(s.material) == "EnumItem"
			end
		end
		local limit = DefaultConfig.Limits.MaxCoordinate
		for _, corner in { { limit, limit }, { -limit, -limit }, { -limit, limit } } do
			allFinite = allFinite and isFinite(heightAt(a, corner[1], corner[2]))
		end
		check("sample fields finite across the map, between passes and at limits", allFinite)
		check("every sample has a material class", knownClasses)
	end)
	if not ran then
		check("selfTest completed without an unexpected error", false, tostring(err))
	end

	-- The existing Phase 0 test circuit, read only, through the real road builder.
	local circuitRan, circuitErr = pcall(function()
		local RoadGeometry = require(script.Parent.RoadGeometry)
		local TestCircuits = require(script.Parent.TestCircuits)
		local RoadConfig = require(script.Parent.Parent.Config.RoadConfig)
		local circuit = RoadGeometry.build(TestCircuits.Phase0Loop, RoadConfig)
		local field = new(1, circuit)
		local underRoad = true
		local half = circuit.width / 2
		for i = 1, circuit.count do
			local s = circuit.samples[i]
			local p = s.position
			if heightAt(field, p.X, p.Z) > p.Y - clearance + 1e-6 then
				underRoad = false
			end
			for _, side in { -half, half } do
				local q = p + s.right * side
				if heightAt(field, q.X, q.Z) > p.Y - clearance / 2 then
					underRoad = false
				end
			end
		end
		check("Phase0Loop terrain stays below the road at centerline and edges", underRoad)
	end)
	if not circuitRan then
		check("Phase0Loop builds a field", false, tostring(circuitErr))
	end

	table.insert(lines, string.format("%s: %d failure(s)", if failures == 0 then "PASSED" else "FAILED", failures))
	return failures == 0, lines
end

return MountainHeightfield
