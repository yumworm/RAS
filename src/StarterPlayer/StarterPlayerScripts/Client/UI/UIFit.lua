--!strict
-- UIFit: keeps a uniform UIScale on a fixed-layout panel so the panel always fits the
-- viewport. Uniform scaling shrinks the panel and every child together, so a complex
-- offset-based panel (the donation and leaderboard panels) stays fully on-screen on a
-- phone without reworking any child. The scale is capped at 1, so desktop rendering is
-- byte-for-byte unchanged -- it only ever shrinks, never enlarges.
--
-- Memory: it holds at most two connections per panel -- one to Workspace.CurrentCamera
-- and one to the active camera's ViewportSize -- and rebinds (never stacks) the
-- viewport connection when the camera is swapped, so it cannot grow over a session.
local Workspace = game:GetService("Workspace")

local UIFit = {}

-- Leave a small margin so the panel never kisses the screen edge on a phone.
local MARGIN = 0.94
-- Never shrink past this, so text stays legible even on tiny viewports.
local MIN_SCALE = 0.4

function UIFit.Fit(panel: GuiObject, designWidth: number, designHeight: number)
	if designWidth <= 0 or designHeight <= 0 then
		return
	end

	local existing = panel:FindFirstChild("FitScale")
	local scale: UIScale = if existing and existing:IsA("UIScale") then existing else Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = panel

	local viewportConn: RBXScriptConnection? = nil

	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		if viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local fit = math.min(1, (viewport.X * MARGIN) / designWidth, (viewport.Y * MARGIN) / designHeight)
		scale.Scale = math.max(fit, MIN_SCALE)
	end

	-- (Re)bind to the current camera's ViewportSize, dropping any prior binding first
	-- so a camera swap replaces the connection instead of accumulating connections.
	local function bindCamera()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
end

return UIFit
