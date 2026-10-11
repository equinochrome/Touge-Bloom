-- Turns control points into a road centerline: evenly spaced samples with a local frame,
-- plus stats and a determinism hash. Used identically by the server and every client.
local Spline = require(script.Parent.Spline)

export type Sample = {
	position: Vector3,
	tangent: Vector3,
	right: Vector3,
	up: Vector3,
	distance: number,
}

export type Circuit = {
	samples: { Sample },
	count: number,
	spacing: number,
	length: number,
	width: number,
	hash: string,
	minRadius: number,
	maxGrade: number,
}

local RoadGeometry = {}

local DENSE_STEPS = 24
local HASH_MODULUS = 4294967296

-- djb2 over positions rounded to 0.01 studs. Must match between server and client.
local function hashSamples(samples: { Sample }): string
	local hash = 5381
	for _, sample in samples do
		local p = sample.position
		local text = string.format("%.2f,%.2f,%.2f;", p.X, p.Y, p.Z)
		for i = 1, #text do
			hash = (hash * 33 + string.byte(text, i)) % HASH_MODULUS
		end
	end
	return string.format("%08x", hash)
end

-- Smallest horizontal turn radius, from the circumcircle of every sample and its neighbors two steps away.
local function minimumRadius(points: { Vector3 }): number
	local count = #points
	local smallest = math.huge
	for i = 1, count do
		local a = points[(i - 3) % count + 1]
		local b = points[i]
		local c = points[(i + 1) % count + 1]
		local abx, abz = b.X - a.X, b.Z - a.Z
		local acx, acz = c.X - a.X, c.Z - a.Z
		local bcx, bcz = c.X - b.X, c.Z - b.Z
		local doubleArea = math.abs(abx * acz - abz * acx)
		if doubleArea > 1e-6 then
			local product = math.sqrt(abx * abx + abz * abz)
				* math.sqrt(acx * acx + acz * acz)
				* math.sqrt(bcx * bcx + bcz * bcz)
			smallest = math.min(smallest, product / (2 * doubleArea))
		end
	end
	return smallest
end

local function maximumGrade(points: { Vector3 }): number
	local count = #points
	local steepest = 0
	for i = 1, count do
		local delta = points[i % count + 1] - points[i]
		local horizontal = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
		if horizontal > 1e-6 then
			steepest = math.max(steepest, math.abs(delta.Y) / horizontal)
		end
	end
	return steepest
end

function RoadGeometry.build(controlPoints: { Vector3 }, roadConfig): Circuit
	local dense = Spline.sampleClosed(controlPoints, DENSE_STEPS)
	local points, spacing = Spline.resampleClosed(dense, roadConfig.SampleSpacing)
	local count = #points

	local samples = table.create(count)
	for i = 1, count do
		local previous = points[(i - 2) % count + 1]
		local following = points[i % count + 1]
		local tangent = (following - previous).Unit
		local right = tangent:Cross(Vector3.yAxis).Unit
		samples[i] = {
			position = points[i],
			tangent = tangent,
			right = right,
			up = right:Cross(tangent).Unit,
			distance = (i - 1) * spacing,
		}
	end

	return {
		samples = samples,
		count = count,
		spacing = spacing,
		length = count * spacing,
		width = roadConfig.Width,
		hash = hashSamples(samples),
		minRadius = minimumRadius(points),
		maxGrade = maximumGrade(points),
	}
end

-- Wrapping index access: sample(circuit, count + 1) is sample 1.
function RoadGeometry.sample(circuit: Circuit, index: number): Sample
	return circuit.samples[(index - 1) % circuit.count + 1]
end

function RoadGeometry.nearestIndex(circuit: Circuit, position: Vector3): number
	local bestIndex, bestDistance = 1, math.huge
	for i, sample in circuit.samples do
		local distance = (sample.position - position).Magnitude
		if distance < bestDistance then
			bestIndex, bestDistance = i, distance
		end
	end
	return bestIndex
end

-- Pose above the road at a sample, facing along the track, optionally shifted sideways.
function RoadGeometry.spawnPose(circuit: Circuit, index: number, height: number, lateral: number?): CFrame
	local sample = RoadGeometry.sample(circuit, index)
	local origin = sample.position + sample.up * height + sample.right * (lateral or 0)
	return CFrame.lookAt(origin, origin + sample.tangent)
end

return RoadGeometry
