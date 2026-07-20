--!strict
-- InventoryController: the side-bar roster. It renders the server-sorted inventory
-- as-is (the UI never sorts) and shows collection progress in the header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = ReplicatedStorage.Modules.Configuration
local RarityConfig = require(Configuration.RarityConfig)
local NumberFormatter = require(ReplicatedStorage.Modules.Shared.NumberFormatter)

local InventoryController = {}

local titleLabel, subtitleLabel, listFrame
local rowCache = {} -- streamerId -> Frame (reused across renders)

local function build(parent: ScreenGui)
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.AnchorPoint = Vector2.new(1, 0.5)
	sidebar.Position = UDim2.new(1, -16, 0.5, 0)
	sidebar.Size = UDim2.fromOffset(280, 470)
	sidebar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	sidebar.BorderSizePixel = 0
	sidebar.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = sidebar

	titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -20, 0, 26)
	titleLabel.Position = UDim2.fromOffset(10, 6)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Text = "Your Streamers"
	titleLabel.Parent = sidebar

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Size = UDim2.new(1, -20, 0, 18)
	subtitleLabel.Position = UDim2.fromOffset(10, 30)
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextSize = 13
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
	subtitleLabel.Text = "Collection 0 / 0 (0%)"
	subtitleLabel.Parent = sidebar

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "InventoryList"
	listFrame.Position = UDim2.fromOffset(10, 54)
	listFrame.Size = UDim2.new(1, -20, 1, -64)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = sidebar

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame
end

local function makeRow(entry)
	local rarity = RarityConfig.Get(entry.rarity)

	local row = Instance.new("Frame")
	row.Name = "Row_" .. entry.id
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	row.BorderSizePixel = 0
	row.Parent = listFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Thickness = 2
	stroke.Parent = row

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(36, 36)
	icon.Position = UDim2.fromOffset(6, 6)
	icon.BackgroundColor3 = rarity.Color
	icon.BorderSizePixel = 0
	icon.Parent = row
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local initial = Instance.new("TextLabel")
	initial.Name = "Initial"
	initial.BackgroundTransparency = 1
	initial.Size = UDim2.fromScale(1, 1)
	initial.Font = Enum.Font.GothamBold
	initial.TextSize = 18
	initial.TextColor3 = Color3.fromRGB(255, 255, 255)
	initial.Text = string.sub(entry.name, 1, 1)
	initial.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(50, 4)
	nameLabel.Size = UDim2.new(1, -100, 0, 20)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = rarity.Color
	nameLabel.Text = entry.name
	nameLabel.Parent = row

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "IncomeLabel"
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Position = UDim2.fromOffset(50, 24)
	incomeLabel.Size = UDim2.new(1, -100, 0, 18)
	incomeLabel.Font = Enum.Font.Gotham
	incomeLabel.TextSize = 12
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	incomeLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.BackgroundTransparency = 1
	countLabel.AnchorPoint = Vector2.new(1, 0)
	countLabel.Position = UDim2.new(1, -6, 0, 0)
	countLabel.Size = UDim2.fromOffset(46, 48)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 14
	countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	countLabel.Parent = row

	return row
end

local function renderInventory(inventory)
	-- inventory is already sorted by the server; LayoutOrder mirrors the order.
	for order, entry in ipairs(inventory) do
		local row = rowCache[entry.id]
		if not row then
			row = makeRow(entry)
			rowCache[entry.id] = row
		end
		row.LayoutOrder = order
		row.IncomeLabel.Text = NumberFormatter.Format(entry.income) .. "/sec"
		row.CountLabel.Text = "x" .. entry.amount
	end
end

local function renderCollection(collection)
	if not collection then
		return
	end
	subtitleLabel.Text = string.format(
		"Collection %d / %d (%d%%)",
		collection.collected or 0,
		collection.total or 0,
		math.floor(collection.percentage or 0)
	)
end

local function onState(state, changed)
	if changed.inventory then
		renderInventory(state.inventory)
	end
	if changed.collection then
		renderCollection(state.collection)
	end
end

function InventoryController.Init(parent: ScreenGui, StateController)
	build(parent)
	StateController.Subscribe(onState)
end

return InventoryController
