-- Closed centripetal Catmull-Rom spline (no cusps or self-loops between control points)
-- and even arc-length resampling. Pure functions: no Instances, deterministic for the same input.
local Spline = {}

local EPSILON = 1e-4

-- Centripetal parameterization: knot spacing is sqrt(distance). math.sqrt is used instead of ^0.5
-- because sqrt is exactly specified by IEEE and gives identical results on every platform.
local function nextKnot(t: number, a: Vector3, b: Vector3): number
	return t + math.max(math.sqrt((b - a).Magnitude), EPSILON)
end

-- Point on the segment between p1 and p2, u in [0, 1] (Barry-Goldman formulation).
local function evaluate(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: number): Vector3
	local t0 = 0
	local t1 = nextKnot(t0, p0, p1)
	local t2 = nextKnot(t1, p1, p2)
	local t3 = nextKnot(t2, p2, p3)
	local t = t1 + (t2 - t1) * u

	local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
end

-- Dense polyline through a closed loop of control points. The last point does not repeat the first.
function Spline.sampleClosed(points: { Vector3 }, stepsPerSegment: number): { Vector3 }
	local count = #points
	local out = table.create(count * stepsPerSegment)
	for i = 1, count do
		local p0 = points[(i - 2) % count + 1]
		local p1 = points[i]
		local p2 = points[i % count + 1]
		local p3 = points[(i + 1) % count + 1]
		for step = 0, stepsPerSegment - 1 do
			table.insert(out, evaluate(p0, p1, p2, p3, step / stepsPerSegment))
		end
	end
	return out
end

-- Resamples a closed polyline to evenly spaced points. The spacing is adjusted slightly so the
-- loop closes exactly; returns the points and the actual spacing.
function Spline.resampleClosed(polyline: { Vector3 }, targetSpacing: number): ({ Vector3 }, number)
	local count = #polyline
	local cumulative = table.create(count + 1)
	cumulative[1] = 0
	for i = 1, count do
		cumulative[i + 1] = cumulative[i] + (polyline[i % count + 1] - polyline[i]).Magnitude
	end

	local total = cumulative[count + 1]
	local sampleCount = math.max(3, math.floor(total / targetSpacing + 0.5))
	local spacing = total / sampleCount
	local out = table.create(sampleCount)
	local segment = 1
	for k = 0, sampleCount - 1 do
		local target = k * spacing
		while segment < count and cumulative[segment + 1] < target do
			segment += 1
		end
		local segmentLength = cumulative[segment + 1] - cumulative[segment]
		local t = if segmentLength > 0 then (target - cumulative[segment]) / segmentLength else 0
		out[k + 1] = polyline[segment]:Lerp(polyline[segment % count + 1], t)
	end
	return out, spacing
end

return Spline
