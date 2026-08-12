--!strict
-- V7HUD.luau (Neumorphic Ethereal Redesign - Bugfix & Scale Fix)
-- Fixed clipping issues and layout distortions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local V7HUD = {}
V7HUD.__index = V7HUD

export type V7HUDController = {
	gui: ScreenGui,
	cashLabel: TextLabel,
	gemsLabel: TextLabel,
	diamondsLabel: TextLabel,
	multValue: TextLabel,
	streakValue: TextLabel,
	riskIcon: TextLabel,
	riskValue: TextLabel,
	payoutLabel: TextLabel,
	autoBtn: TextButton,
	rollBtn: TextButton,
	menuCallbacks: { (menuId: string) -> () },
	updateBalances: (self: V7HUDController, cash: number, gems: number, diamonds: number) -> (),
	-- `voidRiskPct` is the CURRENT die's void probability, computed client-side
	-- from its own mass distribution -- never sent by the server, which would be
	-- an outcome-shaped value crossing the wire (NFR-5). nil means "unknown yet".
	updateStreak: (self: V7HUDController, multiplier: number, streak: number, voidRiskPct: number?) -> (),
	flashPayout: (self: V7HUDController, payout: number, voidHit: boolean) -> (),
	onMenuClicked: (self: V7HUDController, callback: (menuId: string) -> ()) -> (),
	onRollClicked: (self: V7HUDController, callback: () -> ()) -> (),
	onAutoToggled: (self: V7HUDController, callback: (enabled: boolean) -> ()) -> (),
}

function V7HUD.new(): V7HUDController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7HUD] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "V7HUDGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = UITheme.Layer.HUD
	
	-- Transparent HUD Background (BoardView owns the backdrop layer)
	local bgTint = Instance.new("Frame")
	bgTint.Size = UDim2.fromScale(1, 1)
	bgTint.Position = UDim2.fromScale(0, 0)
	bgTint.BackgroundColor3 = UITheme.Colors.BaseCream
	bgTint.BackgroundTransparency = 1
	bgTint.BorderSizePixel = 0
	bgTint.ZIndex = 0
	bgTint.Parent = gui

	local menuCallbacks: { (menuId: string) -> () } = {}

	-- ==========================================
	-- 1. TOP NEUMORPHIC BAR (Currencies)
	-- ==========================================
	local topBar, topBarBody = UITheme.neumorphicPod(UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.2, 0.02))
	topBar.Name = "CurrencyBar"
	topBar.Parent = gui

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.Padding = UDim.new(0.05, 0)
	topLayout.Parent = topBarBody

	local function createCurrency(iconType: string, labelText: string, widthScale: number)
		local pod = Instance.new("Frame")
		pod.Size = UDim2.fromScale(widthScale, 1)
		pod.BackgroundTransparency = 1
		pod.ZIndex = 3
		pod.Parent = topBarBody
		
		-- 2D Vector Icon Container
		local iconContainer = Instance.new("Frame")
		iconContainer.Size = UDim2.fromScale(0.35, 0.8)
		iconContainer.Position = UDim2.fromScale(0.02, 0.1)
		iconContainer.BackgroundTransparency = 1
		iconContainer.ZIndex = 4
		iconContainer.Parent = pod
		
		-- Keep aspect ratio square
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = iconContainer
		
		if iconType == "cash" then
			-- Vector Cash Stack
			local cashBase = Instance.new("Frame")
			cashBase.Size = UDim2.fromScale(0.9, 0.5)
			cashBase.Position = UDim2.fromScale(0.05, 0.25)
			cashBase.BackgroundColor3 = Color3.fromRGB(85, 170, 127)
			cashBase.ZIndex = 4
			cashBase.Parent = iconContainer
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.15, 0)
			corner.Parent = cashBase
			
			local band = Instance.new("Frame")
			band.Size = UDim2.fromScale(0.2, 1)
			band.Position = UDim2.fromScale(0.4, 0)
			band.BackgroundColor3 = Color3.fromRGB(240, 230, 140)
			band.BorderSizePixel = 0
			band.ZIndex = 5
			band.Parent = cashBase
			
			local inner = Instance.new("Frame")
			inner.Size = UDim2.fromScale(0.8, 0.6)
			inner.Position = UDim2.fromScale(0.1, 0.2)
			inner.BackgroundColor3 = Color3.fromRGB(130, 200, 150)
			inner.ZIndex = 4
			inner.Parent = cashBase
			
			local innerCorner = Instance.new("UICorner")
			innerCorner.CornerRadius = UDim.new(0.1, 0)
			innerCorner.Parent = inner
			
			-- Subtle rotation
			cashBase.Rotation = -10
			
		elseif iconType == "gems" or iconType == "diamonds" then
			-- Vector Gem/Diamond
			local color = iconType == "gems" and Color3.fromRGB(0, 120, 220) or Color3.fromRGB(220, 40, 130)
			
			local gemBase = Instance.new("Frame")
			gemBase.Size = UDim2.fromScale(0.7, 0.7)
			gemBase.Position = UDim2.fromScale(0.15, 0.15)
			gemBase.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			gemBase.Rotation = 45
			gemBase.ZIndex = 4
			gemBase.Parent = iconContainer
			
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color)
			grad.Rotation = 45
			grad.Parent = gemBase
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.1, 0)
			corner.Parent = gemBase
			
			local inner = Instance.new("Frame")
			inner.Size = UDim2.fromScale(0.5, 0.5)
			inner.Position = UDim2.fromScale(0.25, 0.25)
			inner.BackgroundColor3 = color
			inner.BorderSizePixel = 0
			inner.ZIndex = 5
			inner.Parent = gemBase
		end

		local titleLbl = UITheme.label(labelText, UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.35, 0.1), UITheme.Colors.TextDim)
		titleLbl.Font = UITheme.Font
		titleLbl.Parent = pod

		local valLbl = UITheme.label("0", UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.35, 0.5), UITheme.Colors.TextPrimary)
		valLbl.Font = UITheme.FontHeading
		valLbl.Parent = pod
		
		return pod, valLbl
	end

	local _, cashLabel = createCurrency("cash", "CASH", 0.3)
	local _, gemsLabel = createCurrency("gems", "GEMS", 0.25)
	local _, diamondsLabel = createCurrency("diamonds", "DIAMONDS", 0.25)

	-- ==========================================
	-- 1b. SETTINGS GEAR
	-- ==========================================
	--
	-- The settings overlay existed and NOTHING OPENED IT. Both side panels are
	-- full at four buttons each and both hold gameplay, so a fifth would have
	-- meant shrinking eight live controls to reach a menu a player touches twice
	-- a session.
	--
	-- Beside the currency bar instead: out of the way, always visible, and where
	-- a gear is conventionally found. Deliberately OUTSIDE `topBarBody`, whose
	-- UIListLayout would have folded it into the currency row and squeezed the
	-- three balances.
	local gearWrapper, gearBtn = UITheme.neumorphicButton("⚙", UITheme.Colors.TextDim,
		UDim2.fromScale(0.045, 0.08), UDim2.fromScale(0.815, 0.02))
	-- NAMED. Every other pod in this GUI is an anonymous "Frame", which makes
	-- them indistinguishable by path -- and a control that cannot be addressed by
	-- path cannot be driven by a test or an automated click.
	gearWrapper.Name = "SettingsGear"
	gearWrapper.Parent = gui

	do
		local lastGear = 0
		local function triggerGear()
			local now = os.clock()
			if now - lastGear < 0.15 then return end
			lastGear = now
			for _, cb in ipairs(menuCallbacks) do pcall(cb, "settings") end
		end
		gearBtn.MouseButton1Click:Connect(triggerGear)
		gearBtn.Activated:Connect(triggerGear)
	end

	-- ==========================================
	-- 2. STREAK STRIP
	-- ==========================================
	--
	-- WAS a 0.4 x 0.12 pod -- 40% of screen width, a real chunk of the middle of
	-- the screen -- showing hardcoded mock numbers (`x4.82`, `STREAK: 14`, `SAFE
	-- (0.0% VOID RISK)`) that NOTHING ever wrote. It never moved no matter what a
	-- player rolled, which is the worst kind of mock data: specific and plausible
	-- enough to read as real.
	--
	-- FOOTPRINT kept exactly where it was and just as small (operator-directed
	-- 2026-08-12: "just let it be where it is / make it smaller", confirmed
	-- "size is good enough" once shrunk). What changed after that is READABILITY
	-- within the same box: three separate chips instead of one long sentence, so
	-- the eye can find "is this risky" without parsing the whole string, and the
	-- risk chip can actually change colour with the number instead of always
	-- being the same dim grey as everything else.
	local streakStrip = Instance.new("Frame")
	streakStrip.Name = "StreakStrip"
	streakStrip.Size = UDim2.fromScale(0.28, 0.032)
	streakStrip.Position = UDim2.fromScale(0.36, 0.708)
	streakStrip.BackgroundTransparency = 1
	streakStrip.Parent = gui

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	chipLayout.Padding = UDim.new(0.03, 0)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = streakStrip

	-- A chip is an icon glyph plus a value, sized to its content rather than a
	-- fixed share of the strip -- "STREAK 128" and "STREAK 1" should not claim
	-- the same width and leave one of them padded with empty space.
	local function chip(order: number, name: string, glyph: string, glyphColor: Color3): (Frame, TextLabel, TextLabel)
		local holder = Instance.new("Frame")
		-- NAMED, not left as the anonymous "Frame" every sibling here would
		-- otherwise share (L-037) -- three identically-named chips would make
		-- `StreakStrip.Frame` ambiguous the same way the HUD's menu buttons once
		-- were.
		holder.Name = name
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.Size = UDim2.fromScale(0, 1)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = order
		holder.Parent = streakStrip

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 3)
		rowLayout.Parent = holder

		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.fromScale(0, 1)
		icon.AutomaticSize = Enum.AutomaticSize.X
		icon.BackgroundTransparency = 1
		icon.Font = UITheme.FontHeading
		icon.Text = glyph
		icon.TextColor3 = glyphColor
		icon.TextScaled = true
		icon.LayoutOrder = 1
		icon.Parent = holder

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.Size = UDim2.fromScale(0, 1)
		value.AutomaticSize = Enum.AutomaticSize.X
		value.BackgroundTransparency = 1
		value.Font = UITheme.FontHeading
		value.Text = ""
		value.TextColor3 = UITheme.Colors.TextPrimary
		value.TextScaled = true
		value.LayoutOrder = 2
		value.Parent = holder

		return holder, icon, value
	end

	local _, _, multValue = chip(1, "MultChip", "x", UITheme.Colors.Gems)
	local _, _, streakValue = chip(2, "StreakChip", "\u{1F525}", UITheme.Colors.Cash) -- fire glyph
	local _, riskIcon, riskValue = chip(3, "RiskChip", "\u{26A0}", UITheme.Colors.TextDim) -- warning glyph

	-- A one-shot "+$14.8M" that rises and fades on a payout, floating ABOVE the
	-- chip row rather than replacing it -- the chips are the resting readout and
	-- must never blank out mid-roll while a flash plays.
	local payoutLabel = Instance.new("TextLabel")
	payoutLabel.Name = "PayoutFlash"
	payoutLabel.Size = UDim2.fromScale(1, 1)
	payoutLabel.Position = UDim2.fromScale(0, 0)
	payoutLabel.BackgroundTransparency = 1
	payoutLabel.Font = UITheme.FontHeading
	payoutLabel.Text = ""
	payoutLabel.TextColor3 = UITheme.Colors.Cash
	payoutLabel.TextXAlignment = Enum.TextXAlignment.Center
	payoutLabel.TextScaled = true
	payoutLabel.Visible = false
	payoutLabel.ZIndex = 5
	payoutLabel.Parent = streakStrip

	-- ==========================================
	-- 3. LEFT & RIGHT NEUMORPHIC PANELS
	-- ==========================================
	local leftPanel, leftPanelBody = UITheme.neumorphicPod(UDim2.fromScale(0.12, 0.5), UDim2.fromScale(0.02, 0.25))
	leftPanel.Name = "LeftMenu"
	leftPanel.Parent = gui
	
	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Vertical
	leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leftLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	leftLayout.Padding = UDim.new(0.05, 0)
	leftLayout.Parent = leftPanelBody

	local rightPanel, rightPanelBody = UITheme.neumorphicPod(UDim2.fromScale(0.12, 0.5), UDim2.fromScale(0.86, 0.25))
	rightPanel.Name = "RightMenu"
	rightPanel.Parent = gui
	
	local rightLayout = Instance.new("UIListLayout")
	rightLayout.FillDirection = Enum.FillDirection.Vertical
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rightLayout.Padding = UDim.new(0.05, 0)
	rightLayout.Parent = rightPanelBody

	local function addMenuBtn(parentBody: Instance, id: string, text: string, color: Color3?)
		local btnWrapper, btn = UITheme.neumorphicButton(text, color, UDim2.fromScale(0.8, 0.18), UDim2.fromScale(0, 0))
		-- NAMED BY MENU ID. All eight of these were anonymous "Frame" wrappers
		-- nested inside anonymous pods, so every button in the HUD -- FORGE,
		-- SHAPE, SLOTS, ASCEND, SHOP, BOARDS, QUESTS, VAULT, ROLL and AUTO --
		-- resolved to the identical instance path. Nothing could address any of
		-- them, which means nothing could drive or inspect the primary controls of
		-- the game.
		btnWrapper.Name = "Menu_" .. id
		btnWrapper.Parent = parentBody
		
		local lastTrigger = 0
		local function trigger()
			local now = os.clock()
			if now - lastTrigger < 0.15 then return end
			lastTrigger = now
			for _, cb in ipairs(menuCallbacks) do pcall(cb, id) end
		end
		
		btn.MouseButton1Click:Connect(trigger)
		btn.Activated:Connect(trigger)
	end

	addMenuBtn(leftPanelBody, "forge", "FORGE", UITheme.Colors.TextGold)
	addMenuBtn(leftPanelBody, "shapes", "SHAPE", UITheme.Colors.PrimaryCyan)
	addMenuBtn(leftPanelBody, "slots", "SLOTS", UITheme.Colors.TextPrimary)
	addMenuBtn(leftPanelBody, "ascend", "ASCEND", UITheme.Colors.PurpleAscend)

	addMenuBtn(rightPanelBody, "shop", "SHOP", UITheme.Colors.Gems)
	addMenuBtn(rightPanelBody, "boards", "BOARDS", UITheme.Colors.TextPrimary)
	addMenuBtn(rightPanelBody, "quests", "QUESTS", UITheme.Colors.Cash)
	addMenuBtn(rightPanelBody, "vault", "VAULT", UITheme.Colors.TextGold)

	-- ==========================================
	-- 4. BOTTOM CENTER ROLL STATION
	-- ==========================================
	local rollStation, rollStationBody = UITheme.neumorphicPod(UDim2.fromScale(0.35, 0.16), UDim2.fromScale(0.325, 0.8))
	rollStation.Name = "RollStation"
	rollStation.Parent = gui
	
	-- The Main Roll Button (Extruded deeply)
	local rollWrapper, rollBtn = UITheme.neumorphicButton(
		"ROLL", 
		UITheme.Colors.TextGold, 
		UDim2.fromScale(0.6, 0.7), 
		UDim2.fromScale(0.05, 0.15)
	)
	rollWrapper.Name = "RollButton"
	rollWrapper.Parent = rollStationBody

	-- The Auto Toggle
	local autoWrapper, autoBtn = UITheme.neumorphicButton(
		"AUTO",
		UITheme.Colors.TextDim,
		UDim2.fromScale(0.25, 0.5),
		UDim2.fromScale(0.7, 0.25)
	)
	autoWrapper.Name = "AutoButton"
	autoWrapper.Parent = rollStationBody

	gui.Parent = playerGui

	local self: V7HUDController = setmetatable({
		gui = gui,
		cashLabel = cashLabel,
		gemsLabel = gemsLabel,
		diamondsLabel = diamondsLabel,
		multValue = multValue,
		streakValue = streakValue,
		riskIcon = riskIcon,
		riskValue = riskValue,
		payoutLabel = payoutLabel,
		autoBtn = autoBtn,
		rollBtn = rollBtn,
		menuCallbacks = menuCallbacks,
	}, V7HUD) :: any

	return self
end

function V7HUD:updateBalances(cash: number, gems: number, diamonds: number)
	-- NFR-4, THE SUFFIX LADDER. This was `string.format("$%.2e", cash)`, which
	-- showed players "$2.06e+04" instead of "$20.6K" -- scientific notation is a
	-- programmer's format, and an idle game whose central number is unreadable
	-- has broken its own core feedback loop.
	--
	-- `Format.formatNumber` is the shared implementation, already precision-safe
	-- to 1e300 and already handling NaN and infinity. It existed the whole time;
	-- this module simply never required it.
	self.cashLabel.Text = "$" .. Format.formatNumber(cash)
	self.gemsLabel.Text = Format.formatNumber(gems)
	self.diamondsLabel.Text = Format.formatNumber(diamonds)
end

-- Redraws the three streak chips from REAL data. Called on every StateSync and
-- every RollResult, so the strip is correct whether or not a roll just landed.
--
-- `voidRiskPct` is nil until the client has computed one from a die's own
-- distribution -- shown as "--" rather than a guessed 0%, because a die that has
-- not been examined yet has an unknown risk, not a safe one.
function V7HUD:updateStreak(multiplier: number, streak: number, voidRiskPct: number?)
	self.multValue.Text = string.format("%.2f", math.max(1, multiplier))

	local streakN = math.max(0, math.floor(streak))
	self.streakValue.Text = tostring(streakN)
	self.streakValue.TextColor3 = if streakN > 0 then UITheme.Colors.TextPrimary else UITheme.Colors.TextDim

	-- RISK IS COLOUR-CODED, which a flat grey number cannot be. Bands chosen to
	-- match how a player reads "safe / getting risky / about to void" rather
	-- than an even split of 0-100 -- most of a build's dice sit well under 30%,
	-- so the boundaries are where the feeling actually changes.
	if voidRiskPct == nil then
		self.riskValue.Text = "--"
		self.riskValue.TextColor3 = UITheme.Colors.TextDim
		self.riskIcon.TextColor3 = UITheme.Colors.TextDim
	else
		local pct = math.clamp(voidRiskPct, 0, 100)
		self.riskValue.Text = string.format("%.0f%%", pct)
		local riskColor = if pct < 15 then UITheme.Colors.Positive
			elseif pct < 40 then UITheme.Colors.TextGold
			else UITheme.Colors.Negative
		self.riskValue.TextColor3 = riskColor
		self.riskIcon.TextColor3 = riskColor
	end
end

-- A one-shot payout flash where the mock "+$14.8M" used to sit permanently.
-- Rises and fades over the streak text, then hides -- so the strip's resting
-- state is always the live readout, never a stale payout from three rolls ago.
function V7HUD:flashPayout(payout: number, voidHit: boolean)
	if not ForgeMath.isFinite(payout) or payout <= 0 or voidHit then
		return
	end
	local lbl = self.payoutLabel
	lbl.Text = "+$" .. Format.formatNumber(payout)
	lbl.Visible = true
	lbl.TextTransparency = 0
	lbl.Position = UDim2.fromScale(0, 0)

	local token = (lbl:GetAttribute("FlashToken") or 0) + 1
	lbl:SetAttribute("FlashToken", token)

	local rendered = if lbl:IsDescendantOf(game) then true else false
	if rendered then
		local riseTween = TweenService:Create(lbl,
			TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0, -0.6), TextTransparency = 1 })
		riseTween:Play()
	end

	task.delay(0.95, function()
		-- A NEWER flash may have started while this one was animating. The token
		-- is how this coroutine tells whether it is still the most recent one --
		-- without it, an early roll's delayed hide could blank a later roll's
		-- flash mid-animation.
		if lbl:GetAttribute("FlashToken") == token then
			lbl.Visible = false
		end
	end)
end

function V7HUD:onMenuClicked(callback: (menuId: string) -> ())
	table.insert(self.menuCallbacks, callback)
end

function V7HUD:onRollClicked(callback: () -> ())
	local lastTrigger = 0
	local function trigger()
		local now = os.clock()
		if now - lastTrigger < 0.1 then return end
		lastTrigger = now
		pcall(callback)
	end
	self.rollBtn.MouseButton1Click:Connect(trigger)
	self.rollBtn.Activated:Connect(trigger)
end

function V7HUD:onAutoToggled(callback: (enabled: boolean) -> ())
	local active = false
	local function trigger()
		active = not active
		
		local wrapper = self.autoBtn.Parent :: Frame
		local body = wrapper:FindFirstChildOfClass("Frame")
		if body then
			local lbl = body:FindFirstChildOfClass("TextLabel")
			if lbl then
				lbl.TextColor3 = if active then UITheme.Colors.Positive else UITheme.Colors.TextDim
			end
		end

		pcall(callback, active)
	end
	
	self.autoBtn.MouseButton1Click:Connect(trigger)
	self.autoBtn.Activated:Connect(trigger)
end

return V7HUD
