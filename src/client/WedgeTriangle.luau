-- Fills an arbitrary 3D triangle with two right-angled WedgeParts (the standard Roblox technique).
-- Used only by the fallback road when EditableMesh is unavailable.
local WedgeTriangle = {}

function WedgeTriangle.draw(a: Vector3, b: Vector3, c: Vector3, template: WedgePart, parent: Instance)
	-- Reorder so bc is the longest edge; the height from a splits the triangle into two right triangles.
	local ab, ac, bc = b - a, c - a, c - b
	local abLength, acLength, bcLength = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abLength > acLength and abLength > bcLength then
		c, a = a, c
	elseif acLength > bcLength and acLength > abLength then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 1e-3 then
		return
	end

	local first = template:Clone()
	first.Size = Vector3.new(template.Size.X, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	first.Parent = parent

	local second = template:Clone()
	second.Size = Vector3.new(template.Size.X, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	second.Parent = parent
end

return WedgeTriangle
