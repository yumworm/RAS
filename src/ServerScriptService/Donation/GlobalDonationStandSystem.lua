--!strict
-- GlobalDonationStandSystem: owns the ONE shared Global Donation Stand in the world.
-- There is exactly one stand -- no owner, no claiming, no receiver, no per-player
-- booths. It finds a placed stand if the map ships one, otherwise it builds a
-- minimal anchored stand at runtime (with a single warning) so the feature always
-- works. It renders the Top 100 board (server-built SurfaceGui, so every client sees
-- identical data) and forwards the ProximityPrompt to open the client donation panel.
--
-- This system is deliberately thin: it never runs purchase math or touches profiles.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DonationConfig = require(ReplicatedStorage.Modules.Configuration.DonationConfig)
local LiveContentConfig = require(ReplicatedStorage.Modules.Configuration.LiveContentConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)

local Server = script.Parent.Parent
local Logger = require(Server.Utilities.Logger)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local GlobalDonationStandSystem = {}
local Services: any

local stand -- the GlobalDonationStand model
local boardRowsFrame -- ScrollingFrame the board rows live in
local boardUpdatedLabel -- "Last updated" label
local boardEmptyLabel -- shown when there are no donors yet
local boardRecentFrame -- "Recent supporters" strip (Phase 6, fed from DonationFeedSystem)

-- Highlight colors for the podium (color/weight only -- no emoji, per the text rule).
local RANK_COLORS = {
	[1] = Color3.fromRGB(255, 215, 0), -- gold
	[2] = Color3.fromRGB(192, 192, 200), -- silver
	[3] = Color3.fromRGB(205, 127, 50), -- bronze
}
local ROW_COLOR = Color3.fromRGB(28, 28, 34)

function GlobalDonationStandSystem.Init(services)
	Services = services
end

--------------------------------------------------------------------------------
-- Build (or adopt) the single stand
--------------------------------------------------------------------------------

local function buildBoardSurface(boardPart: BasePart)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Top100DonorsBoard"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(600, 800)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.Parent = boardPart

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	bg.BorderSizePixel = 0
	bg.Parent = surface

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(0, 12)
	header.Size = UDim2.new(1, 0, 0, 48)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 34
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.Text = DonationConfig.Text.BoardHeader
	header.Parent = bg

	-- Column captions.
	local columns = Instance.new("Frame")
	columns.Name = "Columns"
	columns.BackgroundTransparency = 1
	columns.Position = UDim2.fromOffset(20, 66)
	columns.Size = UDim2.new(1, -40, 0, 26)
	columns.Parent = bg

	local function caption(name: string, text: string, posScale: number, sizeScale: number, align: Enum.TextXAlignment)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(posScale, 0)
		label.Size = UDim2.fromScale(sizeScale, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(150, 150, 165)
		label.TextXAlignment = align
		label.Text = text
		label.Parent = columns
	end
	caption("RankCol", "Rank", 0, 0.18, Enum.TextXAlignment.Left)
	caption("NameCol", "Username", 0.18, 0.52, Enum.TextXAlignment.Left)
	caption("AmountCol", "Robux Donated", 0.7, 0.3, Enum.TextXAlignment.Right)

	boardRowsFrame = Instance.new("ScrollingFrame")
	boardRowsFrame.Name = "Rows"
	boardRowsFrame.Position = UDim2.fromOffset(20, 98)
	-- Leaves room at the bottom for the Phase 6 "Recent supporters" strip + the
	-- "Last updated" line (a taller reserved band than the Phase 3 -140).
	boardRowsFrame.Size = UDim2.new(1, -40, 1, -232)
	boardRowsFrame.BackgroundTransparency = 1
	boardRowsFrame.BorderSizePixel = 0
	boardRowsFrame.ScrollBarThickness = 8
	boardRowsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	boardRowsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	boardRowsFrame.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = boardRowsFrame

	boardEmptyLabel = Instance.new("TextLabel")
	boardEmptyLabel.Name = "Empty"
	boardEmptyLabel.BackgroundTransparency = 1
	boardEmptyLabel.Position = UDim2.fromOffset(20, 120)
	boardEmptyLabel.Size = UDim2.new(1, -40, 0, 40)
	boardEmptyLabel.Font = Enum.Font.Gotham
	boardEmptyLabel.TextSize = 20
	boardEmptyLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
	boardEmptyLabel.TextWrapped = true
	boardEmptyLabel.Text = DonationConfig.Text.EmptyBoardText
	boardEmptyLabel.Visible = false
	boardEmptyLabel.Parent = bg

	-- Phase 6: "Recent supporters" strip, fed from the same DonationFeedSystem cache the
	-- live feed uses (no separate ODS read). Sits just above the "Last updated" line.
	local recentTitle = Instance.new("TextLabel")
	recentTitle.Name = "RecentTitle"
	recentTitle.BackgroundTransparency = 1
	recentTitle.AnchorPoint = Vector2.new(0, 1)
	recentTitle.Position = UDim2.new(0, 20, 1, -104)
	recentTitle.Size = UDim2.new(1, -40, 0, 22)
	recentTitle.Font = Enum.Font.GothamBold
	recentTitle.TextSize = 18
	recentTitle.TextColor3 = Color3.fromRGB(150, 150, 165)
	recentTitle.TextXAlignment = Enum.TextXAlignment.Left
	recentTitle.Text = "RECENT SUPPORTERS"
	recentTitle.Parent = bg

	boardRecentFrame = Instance.new("Frame")
	boardRecentFrame.Name = "Recent"
	boardRecentFrame.BackgroundTransparency = 1
	boardRecentFrame.AnchorPoint = Vector2.new(0, 1)
	boardRecentFrame.Position = UDim2.new(0, 20, 1, -40)
	boardRecentFrame.Size = UDim2.new(1, -40, 0, 62)
	boardRecentFrame.Parent = bg
	local recentLayout = Instance.new("UIListLayout")
	recentLayout.Padding = UDim.new(0, 2)
	recentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	recentLayout.Parent = boardRecentFrame

	boardUpdatedLabel = Instance.new("TextLabel")
	boardUpdatedLabel.Name = "Updated"
	boardUpdatedLabel.BackgroundTransparency = 1
	boardUpdatedLabel.AnchorPoint = Vector2.new(0, 1)
	boardUpdatedLabel.Position = UDim2.new(0, 20, 1, -10)
	boardUpdatedLabel.Size = UDim2.new(1, -40, 0, 24)
	boardUpdatedLabel.Font = Enum.Font.Gotham
	boardUpdatedLabel.TextSize = 16
	boardUpdatedLabel.TextColor3 = Color3.fromRGB(120, 120, 135)
	boardUpdatedLabel.TextXAlignment = Enum.TextXAlignment.Left
	boardUpdatedLabel.Text = "Last updated: never"
	boardUpdatedLabel.Parent = bg
end

local function buildStand()
	local area = Instance.new("Folder")
	area.Name = "DonationArea"

	local model = Instance.new("Model")
	model.Name = "GlobalDonationStand"
	model.Parent = area

	-- Base + title post.
	local base = Instance.new("Part")
	base.Name = "InteractPart"
	base.Anchored = true
	base.Size = Vector3.new(8, 6, 3)
	base.Position = Vector3.new(0, 3, 24) -- near origin; move the placed model to relocate
	base.Color = Color3.fromRGB(40, 40, 52)
	base.Material = Enum.Material.SmoothPlastic
	base.Parent = model
	model.PrimaryPart = base

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DonatePrompt"
	prompt.ActionText = DonationConfig.Prompt.ActionText
	prompt.ObjectText = DonationConfig.Prompt.ObjectText
	prompt.HoldDuration = DonationConfig.Prompt.HoldDuration
	prompt.MaxActivationDistance = DonationConfig.Prompt.MaxActivationDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = base

	local titleGui = Instance.new("SurfaceGui")
	titleGui.Name = "TitleGui"
	titleGui.Face = Enum.NormalId.Front
	titleGui.CanvasSize = Vector2.new(400, 100)
	titleGui.Parent = base
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 1)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Text = DonationConfig.Text.StandTitle
	titleLabel.Parent = titleGui

	-- The Top 100 board panel behind the base.
	local boardPart = Instance.new("Part")
	boardPart.Name = "Board"
	boardPart.Anchored = true
	boardPart.Size = Vector3.new(12, 16, 1)
	boardPart.Position = Vector3.new(0, 9, 26)
	boardPart.Color = Color3.fromRGB(20, 20, 26)
	boardPart.Material = Enum.Material.SmoothPlastic
	boardPart.Parent = model
	buildBoardSurface(boardPart)

	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	local anchor = Instance.new("Attachment")
	anchor.Name = "EffectAnchor"
	anchor.WorldPosition = base.Position + Vector3.new(0, 4, 0)
	anchor.Parent = base
	effects.Parent = model

	area.Parent = Workspace
	Logger.Warn("Donation", "No placed GlobalDonationStand found -- built a minimal one at runtime")
	return model
end

-- Adopt a stand the map already placed: find its board surface + prompt so we can
-- drive them. Returns true if the placed stand had everything we need.
local function adoptPlacedStand(placed): boolean
	stand = placed
	local boardPart = placed:FindFirstChild("Board", true) or placed:FindFirstChild("BoardPart", true)
	local surface = boardPart and boardPart:FindFirstChildWhichIsA("SurfaceGui")
	if surface then
		boardRowsFrame = surface:FindFirstChild("Rows", true)
		boardUpdatedLabel = surface:FindFirstChild("Updated", true)
		boardEmptyLabel = surface:FindFirstChild("Empty", true)
		boardRecentFrame = surface:FindFirstChild("Recent", true)
	end
	-- If the placed board lacks our expected structure, (re)build one on its part.
	if boardPart and not boardRowsFrame then
		local existing = boardPart:FindFirstChildWhichIsA("SurfaceGui")
		if existing then
			existing:Destroy()
		end
		buildBoardSurface(boardPart)
	end
	return boardRowsFrame ~= nil
end

--------------------------------------------------------------------------------
-- Board rendering (server-built; replicates to every client identically)
--------------------------------------------------------------------------------

local function makeBoardRow(entry): Frame
	local row = Instance.new("Frame")
	row.Name = "Row_" .. entry.Rank
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = RANK_COLORS[entry.Rank] and RANK_COLORS[entry.Rank]:Lerp(ROW_COLOR, 0.55) or ROW_COLOR
	row.BorderSizePixel = 0
	row.LayoutOrder = entry.Rank

	local podium = RANK_COLORS[entry.Rank]

	local rankLabel = Instance.new("TextLabel")
	rankLabel.BackgroundTransparency = 1
	rankLabel.Position = UDim2.fromScale(0, 0)
	rankLabel.Size = UDim2.fromScale(0.18, 1)
	rankLabel.Font = podium and Enum.Font.GothamBold or Enum.Font.GothamMedium
	rankLabel.TextSize = 20
	rankLabel.TextColor3 = podium or Color3.fromRGB(220, 220, 230)
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Text = "#" .. entry.Rank
	rankLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0.18, 0)
	nameLabel.Size = UDim2.fromScale(0.52, 1)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 20
	nameLabel.TextColor3 = podium or Color3.fromRGB(235, 235, 240)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = entry.Username
	nameLabel.Parent = row

	local amountLabel = Instance.new("TextLabel")
	amountLabel.BackgroundTransparency = 1
	amountLabel.Position = UDim2.fromScale(0.7, 0)
	amountLabel.Size = UDim2.fromScale(0.3, 1)
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.TextSize = 20
	amountLabel.TextColor3 = podium or Color3.fromRGB(120, 255, 140)
	amountLabel.TextXAlignment = Enum.TextXAlignment.Right
	amountLabel.Text = NumberFormatter.FormatRobux(entry.RobuxDonated)
	amountLabel.Parent = row

	return row
end

local function renderBoard()
	if not boardRowsFrame then
		return
	end
	local snapshot = Services.DonationLeaderboard.GetSnapshot()

	-- Rebuild rows (cheap at the 30s cadence; at most 100 short frames).
	for _, child in ipairs(boardRowsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, entry in ipairs(snapshot.Entries) do
		makeBoardRow(entry).Parent = boardRowsFrame
	end

	if boardEmptyLabel then
		boardEmptyLabel.Visible = #snapshot.Entries == 0
	end
	if boardUpdatedLabel then
		local suffix = snapshot.Stale and (" " .. DonationConfig.Text.StaleSuffix) or ""
		if snapshot.GeneratedAt > 0 then
			boardUpdatedLabel.Text =
				string.format("Last updated: %s%s", os.date("!%H:%M:%S UTC", snapshot.GeneratedAt), suffix)
		else
			boardUpdatedLabel.Text = "Last updated: never" .. suffix
		end
	end
end

-- Render the "Recent supporters" strip from the DonationFeedSystem cache. Idempotent:
-- it rebuilds at most StandRecentCount short labels each call, so it never accumulates
-- instances. No-op when the strip or the feed system is absent.
local function renderRecentStrip()
	if not boardRecentFrame then
		return
	end
	if not (Services.DonationFeedSystem and Services.DonationFeedSystem.GetRecent) then
		return
	end
	local count = math.max(LiveContentConfig.DonationFeed.StandRecentCount, 0)
	local recent = Services.DonationFeedSystem.GetRecent(count)

	for _, child in ipairs(boardRecentFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	for i, event in ipairs(recent) do
		local label = Instance.new("TextLabel")
		label.Name = "Recent_" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 18)
		label.Font = Enum.Font.Gotham
		label.TextSize = 16
		label.TextColor3 = Color3.fromRGB(200, 220, 200)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = i
		label.Text = string.format("%s donated %s Robux", event.DonorName, NumberFormatter.FormatRobux(event.Amount))
		label.Parent = boardRecentFrame
	end
end

--------------------------------------------------------------------------------
-- Public hooks
--------------------------------------------------------------------------------

-- Phase 6: DonationFeedSystem calls this after each append so the stand strip tracks
-- the live feed. Cheap and idempotent.
function GlobalDonationStandSystem.OnDonationFeedUpdated()
	local ok, err = pcall(renderRecentStrip)
	if not ok then
		Logger.Warn("Donation", string.format("Recent strip render failed: %s", tostring(err)))
	end
end

-- Called by DonationLeaderboard after every refresh: re-render the world board and
-- push fresh per-player snapshots to online clients.
function GlobalDonationStandSystem.OnLeaderboardUpdated()
	local ok, err = pcall(renderBoard)
	if not ok then
		Logger.Warn("Donation", string.format("Board render failed: %s", tostring(err)))
	end
	if Services.RobuxDonationSystem then
		Services.RobuxDonationSystem.BroadcastLeaderboard()
	end
end

-- Fire a celebratory effect at the stand for a confirmed donation.
function GlobalDonationStandSystem.PlayDonationEffect(player: Player, amount: number)
	if not DonationConfig.Effects.SuccessParticleEnabled then
		return
	end
	Remotes.DonationStandEffect:FireAllClients({ UserId = player.UserId, Amount = amount })
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function GlobalDonationStandSystem.Start()
	-- Adopt a placed stand if the map ships exactly one; otherwise build the fallback.
	local placedArea = Workspace:FindFirstChild("DonationArea")
	local placed = placedArea and placedArea:FindFirstChild("GlobalDonationStand")
	if placed then
		if not adoptPlacedStand(placed) then
			Logger.Warn("Donation", "Placed GlobalDonationStand missing a usable board -- rebuilt its board surface")
		end
	else
		stand = buildStand()
	end

	-- Bind the prompt (server-side Triggered) to open the client donation panel.
	local prompt = stand and stand:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt.Triggered:Connect(function(player)
			Remotes.OpenDonationPanel:FireClient(player)
		end)
	else
		Logger.Warn("Donation", "GlobalDonationStand has no ProximityPrompt to bind")
	end

	renderBoard()
	renderRecentStrip()
end

return GlobalDonationStandSystem
