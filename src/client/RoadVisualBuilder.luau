-- Builds the visible road on this client from the circuit centerline.
-- Preferred: EditableMesh ribbon chunks (surface + edge skirts) that share their boundary rows,
-- so there are no seams. Fallback: WedgePart triangles, if EditableMesh is disabled or fails.
-- Visuals never collide or block raycasts; the server's invisible boxes handle that.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoadGeometry = require(ReplicatedStorage.Shared.Gen.RoadGeometry)
local WedgeTriangle = require(script.Parent.WedgeTriangle)

local RoadVisualBuilder = {}

export type BuildResult = {
	mode: "EditableMesh" | "WedgeFallback",
	chunks: number,
	parts: number,
	fallbackReason: string?,
}

local function styleVisualPart(part: BasePart, roadConfig)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = roadConfig.SurfaceMaterial
	part.Color = roadConfig.SurfaceColor
end

-- One cross-section row: surface edges and skirt bottoms, in world space.
local function rowVertices(sample, halfWidth: number, roadConfig)
	local down = Vector3.yAxis * roadConfig.SkirtDepth
	local flare = sample.right * roadConfig.SkirtFlare
	local left = sample.position - sample.right * halfWidth
	local right = sample.position + sample.right * halfWidth
	return left, right, left - down - flare, right - down + flare
end

local function buildMeshChunk(circuit, roadConfig, first: number, last: number, vRepeat: number, parent: Instance)
	local halfWidth = circuit.width / 2

	-- Mesh-local coordinates are relative to the chunk's bounding-box center, which becomes the
	-- MeshPart's position. That holds whether or not CreateMeshPartAsync recenters the mesh.
	local rows = {}
	local minimum = Vector3.one * math.huge
	local maximum = -Vector3.one * math.huge
	for index = first, last do
		local sample = RoadGeometry.sample(circuit, index)
		local left, right, leftBottom, rightBottom = rowVertices(sample, halfWidth, roadConfig)
		for _, point in { left, right, leftBottom, rightBottom } do
			minimum = minimum:Min(point)
			maximum = maximum:Max(point)
		end
		-- Distance runs past the loop length on the final chunk so the texture stays continuous.
		local distance = (index - 1) * circuit.spacing
		table.insert(rows, { sample = sample, points = { left, right, leftBottom, rightBottom }, v = distance / vRepeat })
	end
	local center = (minimum + maximum) / 2

	local mesh = AssetService:CreateEditableMesh()
	if not mesh then
		error("CreateEditableMesh returned nil (client memory budget exceeded?)")
	end

	local ids = {}
	for r, row in rows do
		local sample = row.sample
		ids[r] = {
			left = mesh:AddVertex(row.points[1] - center),
			right = mesh:AddVertex(row.points[2] - center),
			leftBottom = mesh:AddVertex(row.points[3] - center),
			rightBottom = mesh:AddVertex(row.points[4] - center),
			up = mesh:AddNormal(sample.up),
			outLeft = mesh:AddNormal(-sample.right),
			outRight = mesh:AddNormal(sample.right),
			uvLeft = mesh:AddUV(Vector2.new(0, row.v)),
			uvRight = mesh:AddUV(Vector2.new(1, row.v)),
		}
	end

	-- Counterclockwise winding seen from the visible side (Roblox front-face convention).
	local function triangle(v0, v1, v2, normals, uvs)
		local face = mesh:AddTriangle(v0, v1, v2)
		mesh:SetFaceNormals(face, normals)
		mesh:SetFaceUVs(face, uvs)
	end
	for r = 1, #rows - 1 do
		local a, b = ids[r], ids[r + 1]
		-- Surface, facing up.
		triangle(a.left, a.right, b.left, { a.up, a.up, b.up }, { a.uvLeft, a.uvRight, b.uvLeft })
		triangle(a.right, b.right, b.left, { a.up, b.up, b.up }, { a.uvRight, b.uvRight, b.uvLeft })
		-- Left skirt, facing outward to the left.
		triangle(a.left, b.left, a.leftBottom, { a.outLeft, b.outLeft, a.outLeft }, { a.uvLeft, b.uvLeft, a.uvLeft })
		triangle(b.left, b.leftBottom, a.leftBottom, { b.outLeft, b.outLeft, a.outLeft }, { b.uvLeft, b.uvLeft, a.uvLeft })
		-- Right skirt, facing outward to the right.
		triangle(a.right, a.rightBottom, b.right, { a.outRight, a.outRight, b.outRight }, { a.uvRight, a.uvRight, b.uvRight })
		triangle(b.right, a.rightBottom, b.rightBottom, { b.outRight, a.outRight, b.outRight }, { b.uvRight, a.uvRight, b.uvRight })
	end

	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
		CollisionFidelity = Enum.CollisionFidelity.Box,
	})
	part.Name = string.format("RoadMesh_%03d", first)
	styleVisualPart(part, roadConfig)
	part.CFrame = CFrame.new(center)
	part.Parent = parent
	return mesh
end

local function buildEditableMesh(circuit, roadConfig, parent: Instance, keepAlive: { any }): number
	-- Round the texture repeat so the UVs land on a whole tile where the loop closes.
	local tiles = math.max(1, math.floor(circuit.length / roadConfig.TextureRepeatLength + 0.5))
	local vRepeat = circuit.length / tiles

	local chunks = 0
	local first = 1
	while first <= circuit.count do
		local last = math.min(first + roadConfig.ChunkSamples, circuit.count + 1)
		table.insert(keepAlive, buildMeshChunk(circuit, roadConfig, first, last, vRepeat, parent))
		chunks += 1
		first = last
	end
	return chunks
end

local function buildWedges(circuit, roadConfig, parent: Instance): number
	local template = Instance.new("WedgePart")
	template.Size = Vector3.new(roadConfig.WedgeThickness, 1, 1)
	template.CastShadow = false
	template.TopSurface = Enum.SurfaceType.Smooth
	template.BottomSurface = Enum.SurfaceType.Smooth
	styleVisualPart(template, roadConfig)

	local halfWidth = circuit.width / 2
	for index = 1, circuit.count do
		local a = RoadGeometry.sample(circuit, index)
		local b = RoadGeometry.sample(circuit, index + 1)
		-- Sink by half the wedge thickness so the top face sits on the road surface.
		local sinkA, sinkB = a.up * (roadConfig.WedgeThickness / 2), b.up * (roadConfig.WedgeThickness / 2)
		local aLeft, aRight = a.position - a.right * halfWidth - sinkA, a.position + a.right * halfWidth - sinkA
		local bLeft, bRight = b.position - b.right * halfWidth - sinkB, b.position + b.right * halfWidth - sinkB
		WedgeTriangle.draw(aLeft, aRight, bLeft, template, parent)
		WedgeTriangle.draw(aRight, bRight, bLeft, template, parent)
	end
	template:Destroy()
	return #parent:GetChildren()
end

local function buildStartLine(circuit, roadConfig, parent: Instance)
	local sample = RoadGeometry.sample(circuit, 1)
	local line = Instance.new("Part")
	line.Name = "StartLine"
	styleVisualPart(line, roadConfig)
	line.Material = Enum.Material.SmoothPlastic
	line.Color = Color3.fromRGB(240, 240, 240)
	line.Size = Vector3.new(circuit.width, 0.05, 2)
	line.CFrame = CFrame.lookAt(sample.position, sample.position + sample.tangent) + sample.up * 0.04
	line.Parent = parent
end

-- Returns how the road was built. keepAlive holds the EditableMesh objects for the session.
function RoadVisualBuilder.build(circuit, roadConfig, parent: Instance, keepAlive: { any }): BuildResult
	local meshFolder = Instance.new("Folder")
	meshFolder.Name = "Surface"
	meshFolder.Parent = parent

	local fallbackReason: string? = "RoadConfig.ForceWedgeFallback is true"
	if not roadConfig.ForceWedgeFallback then
		local ok, result = pcall(buildEditableMesh, circuit, roadConfig, meshFolder, keepAlive)
		if ok then
			buildStartLine(circuit, roadConfig, parent)
			return { mode = "EditableMesh", chunks = result, parts = #meshFolder:GetChildren() }
		end
		fallbackReason = tostring(result)
		warn("[Phase0] EditableMesh road failed, using wedge fallback: " .. fallbackReason)
		meshFolder:ClearAllChildren()
		table.clear(keepAlive)
	end

	local parts = buildWedges(circuit, roadConfig, meshFolder)
	buildStartLine(circuit, roadConfig, parent)
	return { mode = "WedgeFallback", chunks = 0, parts = parts, fallbackReason = fallbackReason }
end

return RoadVisualBuilder
