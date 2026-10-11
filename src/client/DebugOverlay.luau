-- Plain text readout in the top-left corner for Phase 0 verification.
local Players = game:GetService("Players")

local DebugOverlay = {}
DebugOverlay.__index = DebugOverlay

function DebugOverlay.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Phase0Debug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.Position = UDim2.fromOffset(12, 12)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = "Phase 0 starting..."
	local padding = Instance.new("UIPadding")
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	padding.Parent = label
	label.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return setmetatable({ label = label }, DebugOverlay)
end

function DebugOverlay:setLines(lines: { string })
	self.label.Text = table.concat(lines, "\n")
end

return DebugOverlay
