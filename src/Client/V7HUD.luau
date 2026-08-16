--!strict
-- V7HUD.luau (Neumorphic Ethereal Redesign - Bugfix & Scale Fix)
-- Fixed clipping issues and layout distortions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local GearMeshBuilder = require(Shared:WaitForChild("GearMeshBuilder"))

local V7HUD = {}
V7HUD.__index = V7HUD

export type V7HUDController = {
	gui: ScreenGui,
	cashLabel: TextLabel,
	gemsLabel: TextLabel,
	diamondsLabel: TextLabel,
	multValue: TextLabel,
	-- The MULT chip's caption, which reads "LOCKED" while StreakStrength is 0.
	multCaption: TextLabel,
	streakValue: TextLabel,
	riskIcon: TextLabel,
	riskValue: TextLabel,
	payoutLabel: TextLabel,
	autoBtn: TextButton,
	-- The LAST SERVER-CONFIRMED auto-roll state. Not flipped optimistically:
	-- Auto-Roll is a gamepass entitlement the server can refuse.
	autoEnabled: boolean,
	rollBtn: TextButton,
	rollCooldownFill: Frame,
	menuCallbacks: { (menuId: string) -> () },
	setAutoState: (self: V7HUDController, enabled: boolean) -> (),
	updateBalances: (self: V7HUDController, cash: number, gems: number, diamonds: number) -> (),
	-- `voidRiskPct` is the CURRENT die's void probability, computed client-side
	-- from its own mass distribution -- never sent by the server, which would be
	-- an outcome-shaped value crossing the wire (NFR-5). nil means "unknown yet".
	-- `multUnlocked` is false when StreakStrength is 0, which pins the multiplier
	-- at 1 regardless of streak length. Optional so an un-updated caller keeps
	-- the previous behaviour instead of wrongly reporting the bonus as locked.
	updateStreak: (self: V7HUDController, multiplier: number, streak: number,
		voidRiskPct: number?, multUnlocked: boolean?) -> (),
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
			
		elseif iconType == "gems" then
			-- Vector Gem (Tall 6-sided Crystal Shard)
			local gemBase = Instance.new("Frame")
			gemBase.Size = UDim2.fromScale(0.65, 0.85)
			gemBase.Position = UDim2.fromScale(0.175, 0.075)
			gemBase.BackgroundColor3 = UITheme.Colors.Gems
			gemBase.BorderSizePixel = 0
			gemBase.ZIndex = 4
			gemBase.Parent = iconContainer
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.35, 0)
			corner.Parent = gemBase
			
			local innerFacet = Instance.new("Frame")
			innerFacet.Size = UDim2.fromScale(0.5, 0.7)
			innerFacet.Position = UDim2.fromScale(0.25, 0.15)
			innerFacet.BackgroundColor3 = Color3.fromRGB(186, 230, 253)
			innerFacet.BorderSizePixel = 0
			innerFacet.ZIndex = 5
			innerFacet.Parent = gemBase
			
			local fCorner = Instance.new("UICorner")
			fCorner.CornerRadius = UDim.new(0.25, 0)
			fCorner.Parent = innerFacet
			
		elseif iconType == "diamonds" then
			-- Vector Diamond (Original Rotated Square in Vibrant Pink)
			local pinkOuter = Color3.fromRGB(244, 114, 182)
			local pinkInner = Color3.fromRGB(251, 207, 232)
			
			local gemBase = Instance.new("Frame")
			gemBase.Size = UDim2.fromScale(0.7, 0.7)
			gemBase.Position = UDim2.fromScale(0.15, 0.15)
			gemBase.BackgroundColor3 = pinkOuter
			gemBase.BorderSizePixel = 0
			gemBase.Rotation = 45
			gemBase.ZIndex = 4
			gemBase.Parent = iconContainer
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.12, 0)
			corner.Parent = gemBase
			
			local inner = Instance.new("Frame")
			inner.Size = UDim2.fromScale(0.5, 0.5)
			inner.Position = UDim2.fromScale(0.25, 0.25)
			inner.BackgroundColor3 = pinkInner
			inner.BorderSizePixel = 0
			inner.ZIndex = 5
			inner.Parent = gemBase
			
			local innerCorner = Instance.new("UICorner")
			innerCorner.CornerRadius = UDim.new(0.08, 0)
			innerCorner.Parent = inner
		end

		local titleLbl = UITheme.label(labelText, UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.35, 0.1), UITheme.Colors.TextDim)
		titleLbl.Font = UITheme.Font
		titleLbl.Parent = pod

		local valLbl = UITheme.label("0", UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.35, 0.5), UITheme.Colors.TextPrimary)
		valLbl.Font = UITheme.FontHeading
		valLbl.Parent = pod
		
		return pod, valLbl
	end

	local cashPod, cashLabel = createCurrency("cash", "CASH", 0.3)
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
	-- THE GLYPH IS DRAWN, NOT TYPED.
	--
	-- It was the character U+2699 GEAR, which is a font-dependent symbol: it
	-- renders as a filled cog on one platform, an outlined one on another, and a
	-- tofu box wherever the font lacks it -- and Roblox's own fonts do not carry
	-- it consistently. Every other icon in this game is geometry for the same
	-- reason. Three concentric frames read as a gear at this size and render
	-- identically everywhere.
	--
	-- A SMALL DISC BEHIND IT, not the neumorphic pod.
	--
	-- The pod stacked three opaque 56x62 frames -- two shadow layers and a body
	-- -- which against this backdrop read as a dark rectangle with a gear
	-- floating inside it. Removing it entirely was worse the other way: a bare
	-- silhouette on the backdrop has nothing marking it as a control, and the
	-- operator's verdict on both was the same word, "weird".
	--
	-- One subtle circular plate is the middle: it says "this is a button" and
	-- follows the gear's own shape instead of fighting it with a rectangle.
	-- BIGGER, operator-directed. It was 0.045 x 0.08 of the screen, which lands
	-- at roughly 56x62 -- barely over the touch floor and visually slight next
	-- to the currency bar it sits beside.
	local gearWrapper = Instance.new("Frame")
	gearWrapper.Size = UDim2.fromScale(0.058, 0.105)
	gearWrapper.Position = UDim2.fromScale(0.812, 0.012)
	gearWrapper.BackgroundTransparency = 1
	gearWrapper.ZIndex = 5

	local gearPlate = Instance.new("Frame")
	gearPlate.Name = "Plate"
	gearPlate.AnchorPoint = Vector2.new(0.5, 0.5)
	gearPlate.Position = UDim2.fromScale(0.5, 0.5)
	-- Square, so `UICorner` at 1.0 makes a true circle rather than a lozenge.
	gearPlate.Size = UDim2.fromScale(1, 1)
	-- READ FROM THE BUILDER, not chosen here. The gear's hub hole and rim hollow
	-- are faked with discs painted to match whatever sits behind the model --
	-- a runtime CSG subtraction is not available -- so the plate and those discs
	-- must be the SAME colour or the fake holes show as wrong-coloured circles.
	-- One declaration, read by both sides, rather than two literals that agree
	-- today and drift the first time the plate is restyled (L-025).
	gearPlate.BackgroundColor3 = GearMeshBuilder.PlateColour
	-- OPAQUE, and that is a constraint rather than a preference. The gear's fake
	-- holes are opaque discs painted `PlateColour`; if the plate itself were
	-- semi-transparent it would blend toward the backdrop while the discs did
	-- not, and the "holes" would show as visibly lighter circles. The colour
	-- match only holds when both are solid.
	gearPlate.BackgroundTransparency = 0
	gearPlate.BorderSizePixel = 0
	gearPlate.ZIndex = 4
	gearPlate.Parent = gearWrapper

	local plateAspect = Instance.new("UIAspectRatioConstraint")
	plateAspect.AspectRatio = 1
	plateAspect.Parent = gearPlate

	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(1, 0)
	plateCorner.Parent = gearPlate

	local plateEdge = Instance.new("UIStroke")
	plateEdge.Color = UITheme.Colors.ShadowLight
	plateEdge.Thickness = 1
	plateEdge.Transparency = 0.45
	plateEdge.Parent = gearPlate

	-- The 44px touch floor came from `neumorphicButton`, which is no longer in
	-- play, so the control carries it directly. It is the accessibility minimum
	-- and does not scale per build tier.
	local gearFloor = Instance.new("UISizeConstraint")
	gearFloor.Name = "TouchFloor"
	gearFloor.MinSize = Vector2.new(UITheme.Scale.TouchTarget, UITheme.Scale.TouchTarget)
	gearFloor.Parent = gearWrapper

	local gearBtn = Instance.new("TextButton")
	gearBtn.Name = "GearButton"
	gearBtn.Size = UDim2.fromScale(1, 1)
	gearBtn.BackgroundTransparency = 1
	gearBtn.Text = ""
	gearBtn.AutoButtonColor = false
	gearBtn.ZIndex = 5
	gearBtn.Parent = gearWrapper

	-- Assigned by the icon block below, and nil if the gear failed to build.
	local gearSpinModel: Model? = nil
	-- The ViewportFrame itself, which sits ON TOP of the button and therefore
	-- receives the cursor first. Held so the hover handler can bind to it too.
	local gearIconFrame: ViewportFrame? = nil

	-- The 44px touch floor comes from `neumorphicButton` itself, so this control
	-- and the eight menu buttons and the AUTO toggle all clear it without each
	-- carrying its own constraint.

	-- A REAL 3D GEAR, not a texture.
	--
	-- It was an ImageLabel pointed at an uploaded decal. Geometry is better here
	-- for the same reason every other icon in this game is drawn: it renders
	-- identically on every platform, needs no upload, survives an asset being
	-- moderated or delisted, and is version-controlled as code rather than as an
	-- ID that means nothing when read. It also lets the thing MOVE, which a flat
	-- decal cannot do convincingly.
	do
		-- A ViewportFrame RENDERS AT ITS PIXEL SIZE AND CANNOT BE SUPERSAMPLED.
		--
		-- The graininess is real and its cause is resolution: the buffer matches
		-- `AbsoluteSize`, so 45 parts were resolving into 48 pixels across, with
		-- the gear's spokes landing at 3.49 px each and every edge falling on a
		-- hard pixel boundary with no anti-aliasing to soften it.
		--
		-- The obvious fix does not exist. Rendering large and scaling down was
		-- tried and MEASURED both ways -- `UIScale` on the frame, then `UIScale`
		-- on a parent wrapper -- and it shrinks `AbsoluteSize` in both cases, so
		-- the buffer follows it down and nothing is gained. Proven with a
		-- three-way probe: a plain 42px frame reports 42, a 126px frame under a
		-- 1/3 parent scale also reports 42, and only an unscaled 126px frame
		-- reports 126. There is no way to hold a big buffer at a small display
		-- size.
		--
		-- SO THE FIX IS FEWER, FATTER FEATURES, NOT MORE PIXELS. The frame is
		-- made as large as the control honestly allows, and the gear's own
		-- geometry does the rest -- see the tooth-count reduction below. This is
		-- the same lesson as the dice chamfers: when a feature cannot be given
		-- more pixels, give it fewer neighbours to compete with.
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "GearIcon"
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.5)
		-- Fills the control rather than insetting to 0.86. Every pixel of the
		-- 44px touch target is a pixel the gear can use.
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundTransparency = 1
		viewport.ZIndex = 6
		-- THE ICON MUST NOT EAT THE CURSOR. A ViewportFrame is an interactive
		-- GuiObject and it covers the button it decorates, so with the default
		-- `Active` behaviour it becomes the topmost object at the gear's centre
		-- and the TextButton beneath it never receives MouseEnter -- measured:
		-- 75 frames of a real cursor sitting on the gear produced zero hover
		-- events. Turning it off passes the cursor straight through to the
		-- control, which is what a decoration should always do.
		viewport.Active = false
		viewport.Parent = gearBtn
		gearIconFrame = viewport

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = viewport

		local okBuild, gear = pcall(function()
			return GearMeshBuilder.build(viewport)
		end)

		-- A FAILED ICON MUST NOT TAKE THE HUD WITH IT. This runs inside `new()`,
		-- and a constructor error here would destroy every surface built after
		-- it -- which is precisely how eight overlays once vanished because a
		-- switch tried to animate too early (L-036). The button still works
		-- without its glyph; it is a decoration, and it fails as one.
		if okBuild and typeof(gear) == "Instance" and gear:IsA("Model") then
			local model = gear :: Model

			-- PIVOT BEFORE THE CAMERA READS IT. A model renders on the frame it
			-- is parented, so posing it afterwards shows one frame at whatever
			-- orientation it was authored in (L-052).
			model:PivotTo(CFrame.new(0, 0, 0))

			local cam = Instance.new("Camera")
			-- FRAMED FROM THE BOUNDING SPHERE, not the axis-aligned extent. The
			-- gear is a flat disc -- 6.0 wide by 0.96 deep -- and framing a flat
			-- solid on its widest axis is exactly what made the D6 preview 44%
			-- too large next to its neighbours.
			local centre = model:GetPivot().Position
			local sphere = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "Pivot" then
					local r = (d.Position - centre).Magnitude + d.Size.Magnitude * 0.5
					if r > sphere then
						sphere = r
					end
				end
			end
			if sphere <= 0 then
				sphere = 3
			end
			-- HEAD-ON, deliberately. A gear is a disc and reads as one only face
			-- first; a three-quarter view of a flat solid presents its edge and
			-- turns a cog into a smear -- the same failure the D2 coin had.
			-- PULLED BACK SO THE TEETH FIT. At 2.35x the gear's outermost teeth
			-- ran off the frame edge and were sliced flat -- a ViewportFrame
			-- clips hard at its bounds, it does not letterbox. `sphere` is the
			-- furthest reach of any part, so framing must clear it with room to
			-- spare, and it must clear it AT EVERY ROTATION: the gear spins, and
			-- a corner that fits at 0 degrees can swing outside at 22.
			--
			-- 3.1x leaves roughly a quarter of the radius as margin, which holds
			-- through a full turn and still fills the plate.
			cam.CFrame = CFrame.new(Vector3.new(0, 0, sphere * 3.1),
				Vector3.new(0, 0, 0))
			cam.FieldOfView = 40
			cam.Parent = viewport
			viewport.CurrentCamera = cam

			gearSpinModel = model
		end
	end
	-- NAMED. Every other pod in this GUI is an anonymous "Frame", which makes
	-- them indistinguishable by path -- and a control that cannot be addressed by
	-- path cannot be driven by a test or an automated click.
	gearWrapper.Name = "SettingsGear"
	gearWrapper.Parent = gui

	-- ONE FULL TURN ON HOVER.
	--
	-- SINGLE-FLIGHT, and that is the whole difficulty. `MouseEnter` fires again
	-- every time the cursor crosses the boundary, and a player brushing past the
	-- corner produces several in a second -- so an unguarded handler starts a
	-- second spin over the first and the gear stutters or jumps backwards. The
	-- guard makes a re-entry during a turn a no-op: the current rotation simply
	-- finishes.
	--
	-- Driven by RenderStepped rather than TweenService because there is nothing
	-- tweenable here -- the rotation lives in a CFrame on a Model, not in a
	-- property. The connection exists only while a spin is in flight, so a
	-- stationary gear costs nothing per frame.
	do
		local SPIN_SECONDS = 0.55
		local spinning = false
		local spinConn: RBXScriptConnection? = nil

		local function stopSpin()
			if spinConn ~= nil then
				spinConn:Disconnect()
				spinConn = nil
			end
			spinning = false
		end

		local function spinOnce()
			local model = gearSpinModel
			if model == nil or spinning then
				return
			end
			spinning = true
			local elapsed = 0
			spinConn = RunService.RenderStepped:Connect(function(dt: number)
				-- The model can be destroyed mid-spin if the HUD is torn down;
				-- an orphaned connection writing to a dead Instance throws every
				-- frame thereafter.
				if model.Parent == nil then
					stopSpin()
					return
				end
				elapsed += dt
				local t = math.min(elapsed / SPIN_SECONDS, 1)
				-- Ease-in-out, so the turn starts and stops rather than
				-- snapping. A linear 360 reads as a spinning-loader animation;
				-- an eased one reads as a mechanism being turned.
				local eased = t * t * (3 - 2 * t)
				-- Spun about Z: the gear is a flat disc facing the camera, so Z
				-- is the axis it visibly turns on. Y would flip it edge-on and
				-- make it vanish at the halfway point.
				model:PivotTo(CFrame.Angles(0, 0, eased * math.pi * 2))
				if t >= 1 then
					-- Landed exactly where it started, so repeated hovers cannot
					-- accumulate drift.
					model:PivotTo(CFrame.new(0, 0, 0))
					stopSpin()
				end
			end)
		end

		-- HOVER IS DETECTED ON THE WRAPPER, NOT THE BUTTON.
		--
		-- The ViewportFrame carrying the gear covers the TextButton it decorates,
		-- and a ViewportFrame consumes the cursor even with `Active = false` --
		-- measured, twice: a real cursor parked on the gear for 300 frames
		-- produced ZERO MouseEnter events on the button, and
		-- `GetGuiObjectsAtPosition` confirmed the ViewportFrame was topmost both
		-- before and after clearing `Active`.
		--
		-- The wrapper is the ancestor of both, so it sees the cursor whichever
		-- child is on top. Binding here is also more honest about the intent:
		-- the thing being hovered is the CONTROL, not one particular layer of it.
		gearWrapper.MouseEnter:Connect(spinOnce)
		if gearIconFrame ~= nil then
			gearIconFrame.MouseEnter:Connect(spinOnce)
		end

		local lastGear = 0
		local function triggerGear()
			local now = os.clock()
			if now - lastGear < 0.15 then return end
			lastGear = now
			-- Pressing it turns it too. A control that responds to the cursor
			-- passing over but not to being pressed feels backwards.
			spinOnce()
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
	streakStrip.Size = UDim2.fromScale(0.28, 0.045)
	streakStrip.Position = UDim2.fromScale(0.36, 0.812)
	streakStrip.BackgroundTransparency = 1
	streakStrip.Parent = gui

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	chipLayout.Padding = UDim.new(0.08, 0)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = streakStrip

	-- A chip is a vertical floating callout (value on top, tag below) with subtle dark outline and no emojis.
	local function chip(order: number, name: string, tagText: string, valColor: Color3): (Frame, TextLabel, TextLabel)
		local holder = Instance.new("Frame")
		holder.Name = name
		holder.Size = UDim2.fromScale(0.26, 1)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = order
		holder.ZIndex = 15
		holder.Parent = streakStrip

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.Size = UDim2.fromScale(1, 0.65)
		value.Position = UDim2.fromScale(0, 0)
		value.BackgroundTransparency = 1
		value.Font = UITheme.FontHeading
		value.Text = ""
		value.TextColor3 = valColor
		value.TextScaled = true
		value.ZIndex = 16
		value.Parent = holder

		local stroke = Instance.new("UIStroke")
		stroke.Name = "Outline"
		stroke.Color = Color3.fromRGB(12, 10, 8)
		stroke.Transparency = 0.3
		stroke.Thickness = 1.2
		stroke.Parent = value

		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.Size = UDim2.fromScale(1, 0.3)
		tag.Position = UDim2.fromScale(0, 0.68)
		tag.BackgroundTransparency = 1
		tag.Font = UITheme.Font
		tag.Text = tagText
		tag.TextColor3 = UITheme.Colors.TextDim
		tag.TextScaled = true
		tag.ZIndex = 16
		tag.Parent = holder

		return holder, tag, value
	end

	-- The MULT chip's caption is captured because it CHANGES: it reads "LOCKED"
	-- until the StreakStrength node is bought, since a multiplier that cannot
	-- move should say so rather than sit at x1.00 looking broken.
	local _, multCaption, multValue = chip(1, "MultChip", "MULT", UITheme.Colors.Gems)
	local _, _, streakValue = chip(2, "StreakChip", "STREAK", UITheme.Colors.Cash)
	local _, riskIcon, riskValue = chip(3, "RiskChip", "RISK", UITheme.Colors.TextDim)

	-- THE PAYOUT FLASH, ATTACHED TO THE CASH READOUT.
	--
	-- WHERE THIS USED TO BE, TWICE, AND WHY BOTH WERE WRONG.
	--
	-- It began as floating text over the BOARD, anchored to the tray's centre and
	-- scaled up to a third of the screen on a big win. That put the number
	-- directly on top of the dice it was reporting -- and once thirty dice could
	-- roll at once, several payouts a second stacked into an unreadable pile over
	-- the whole board. It was then moved here, onto the streak strip, where it
	-- covered the MULT/STREAK/RISK chips instead; `flashPayout` was stubbed to a
	-- no-op rather than fixed (L-044), so the feature has been dead since.
	--
	-- The mistake both times was treating the payout as something that belongs
	-- near the DICE. It does not: it is a change to the player's cash, and the
	-- place a player looks to see their cash is the cash readout. Anchoring the
	-- flash there means the number rises from the figure it just changed, which
	-- explains itself with no text and no space of its own.
	--
	-- SIZED TO THE POD, so it cannot grow over anything. The old version scaled
	-- with the win, which is exactly how a jackpot ended up covering the arena.
	-- Magnitude is carried by COLOUR and by a brief lift instead -- neither of
	-- which can collide with another element.
	local payoutLabel = Instance.new("TextLabel")
	payoutLabel.Name = "PayoutFlash"
	payoutLabel.Size = UDim2.fromScale(0.75, 0.42)
	payoutLabel.Position = UDim2.fromScale(0.25, 1.05)
	payoutLabel.AnchorPoint = Vector2.new(0, 0.5)
	payoutLabel.BackgroundTransparency = 1
	payoutLabel.Font = UITheme.FontHeading
	payoutLabel.Text = ""
	payoutLabel.TextColor3 = UITheme.Colors.Cash
	payoutLabel.TextXAlignment = Enum.TextXAlignment.Left
	payoutLabel.TextScaled = true
	payoutLabel.Visible = false
	payoutLabel.ZIndex = 8
	payoutLabel.Parent = cashPod

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
	local rollStation, rollStationBody = UITheme.neumorphicPod(UDim2.fromScale(0.28, 0.11), UDim2.fromScale(0.36, 0.865))
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

	-- COOLDOWN SWEEP. A bar that fills left-to-right across the button over the
	-- manual-roll cooldown, so the limit is something the player can SEE rather
	-- than a press that appears to do nothing.
	--
	-- Sits above the button's tint (ZIndex 3) but below its caption (4), so ROLL
	-- stays readable while the sweep runs underneath it.
	local rollCooldownFill = Instance.new("Frame")
	rollCooldownFill.Name = "CooldownFill"
	rollCooldownFill.Size = UDim2.fromScale(0, 1)
	rollCooldownFill.Position = UDim2.fromScale(0, 0)
	rollCooldownFill.BackgroundColor3 = UITheme.Colors.TextGold
	rollCooldownFill.BackgroundTransparency = 0.78
	rollCooldownFill.BorderSizePixel = 0
	rollCooldownFill.Visible = false
	rollCooldownFill.ZIndex = 3
	rollCooldownFill.Parent = rollBtn

	local rollFillCorner = Instance.new("UICorner")
	rollFillCorner.CornerRadius = UDim.new(0.4, 0)
	rollFillCorner.Parent = rollCooldownFill

	-- The Auto Toggle
	-- Caption left empty here on purpose: `setAutoState` is called once at the end
	-- of construction and owns EVERY appearance of this button. Baking "AUTO" in
	-- at build time is how the button sat reading a third caption that neither
	-- state ever produces until the player pressed it.
	local autoWrapper, autoBtn = UITheme.neumorphicButton(
		"",
		UITheme.Colors.TextDim,
		UDim2.fromScale(0.25, 0.5),
		UDim2.fromScale(0.7, 0.25)
	)
	autoWrapper.Name = "AutoButton"
	autoWrapper.Parent = rollStationBody

	-- An outline that lights up when auto-roll is running. A second, redundant
	-- signal on purpose: colour alone is a poor state indicator, and this is a
	-- toggle a player leaves running and needs to confirm at a glance.
	local autoGlow = Instance.new("UIStroke")
	autoGlow.Name = "AutoGlow"
	autoGlow.Color = UITheme.Colors.Gems
	autoGlow.Thickness = 2
	autoGlow.Enabled = false
	autoGlow.Parent = autoBtn

	gui.Parent = playerGui

	local self: V7HUDController = setmetatable({
		gui = gui,
		cashLabel = cashLabel,
		gemsLabel = gemsLabel,
		diamondsLabel = diamondsLabel,
		multValue = multValue,
		multCaption = multCaption,
		streakValue = streakValue,
		riskIcon = riskIcon,
		riskValue = riskValue,
		payoutLabel = payoutLabel,
		-- The in-flight payout flash, so a new payout can cancel it rather than
		-- letting two tweens fight over the same label's Position.
		payoutTween = nil,
		autoBtn = autoBtn,
		autoEnabled = false,
		rollBtn = rollBtn,
		rollCooldownFill = rollCooldownFill,
		menuCallbacks = menuCallbacks,
	}, V7HUD) :: any

	-- PAINT THE INITIAL AUTO STATE through the same function every later change
	-- goes through. Without this the button renders with the empty caption it was
	-- built with -- and with a caption baked in at build time instead, it showed a
	-- third string ("AUTO") that neither real state ever produces.
	--
	-- Auto-roll is session-scoped server-side (it is deliberately not persisted,
	-- so a rejoin cannot leave the server rolling for an absent player), so OFF is
	-- the correct and honest starting state on every fresh session.
	self:setAutoState(false)

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
function V7HUD:updateStreak(multiplier: number, streak: number, voidRiskPct: number?,
	multUnlocked: boolean?)
	-- LOCKED AND "NOT YET BUILDING" ARE DIFFERENT THINGS, and both used to print
	-- a bare x1.00. StreakStrength is a Diamond node and defaults to zero, so for
	-- every new player the multiplier is mathematically pinned at 1 no matter how
	-- long the streak grows -- which reads as a broken readout, and was reported
	-- as exactly that ("we have a multi option, have never seen it work").
	--
	-- `multUnlocked` is optional so any caller that has not been updated keeps
	-- the old behaviour rather than silently claiming the bonus is locked.
	if multUnlocked == false then
		-- A DASH, not "x1.00". A number that cannot move should not be displayed
		-- as a number -- it invites the player to watch it and conclude the game
		-- is broken. The dash says "nothing here yet"; the dimmed colour and the
		-- caption below say why.
		self.multValue.Text = "--"
		self.multValue.TextColor3 = UITheme.Colors.TextDim
		if self.multCaption ~= nil then
			self.multCaption.Text = "LOCKED"
		end
	else
		self.multValue.Text = "x" .. string.format("%.2f", math.max(1, multiplier))
		self.multValue.TextColor3 = UITheme.Colors.Gems
		if self.multCaption ~= nil then
			self.multCaption.Text = "MULT"
		end
	end

	local streakN = math.max(0, math.floor(streak))
	self.streakValue.Text = tostring(streakN)
	self.streakValue.TextColor3 = if streakN > 0 then UITheme.Colors.Cash else UITheme.Colors.TextDim

	-- RISK percentage font is Red, while the RISK tag word matches MULT and STREAK (TextDim).
	self.riskIcon.TextColor3 = UITheme.Colors.TextDim
	if voidRiskPct == nil then
		self.riskValue.Text = "--"
		self.riskValue.TextColor3 = UITheme.Colors.TextDim
	else
		local pct = math.clamp(voidRiskPct, 0, 100)
		self.riskValue.Text = string.format("%.0f%%", pct)
		self.riskValue.TextColor3 = UITheme.Colors.Negative
	end
end

-- A one-shot payout flash where the mock "+$14.8M" used to sit permanently.
-- Rises and fades over the streak text, then hides -- so the strip's resting
-- state is always the live readout, never a stale payout from three rolls ago.
-- How long a payout flash lives, and how far it rises. Short: at the auto-roll
-- ceiling of 1.6 rolls/sec a longer flash would still be on screen when the next
-- one starts, and two overlapping numbers are less readable than one.
local PAYOUT_FLASH_SEC = 0.62

-- The flash DRIFTS DOWNWARD, away from the cash figure, and that is deliberate
-- rather than the conventional rise.
--
-- The currency pod's top edge sits at y = -44 in absolute screen coordinates --
-- the bar is anchored above the viewport edge -- so a flash rising 0.30 of the
-- pod's height travels to roughly y = -61 and finishes off-screen. Measured, not
-- assumed. Drifting down keeps the whole animation inside the window, and out of
-- a payout the eye is already on the number it came from, so the direction
-- carries no meaning worth preserving.
local PAYOUT_DRIFT = 0.34

-- A payout, shown rising out of the cash figure it just changed.
--
-- THIS WAS A NO-OP FOR THE WHOLE OF THE V7 BUILD. It floated over the BOARD
-- first, printing on top of the dice it was reporting; once thirty dice could
-- roll at once several payouts a second stacked into an unreadable pile. It was
-- then moved onto the streak strip, where it covered the MULT/STREAK/RISK chips
-- -- and at that point it was stubbed out rather than fixed (L-044), so the
-- feature has shown nothing since. See the label's construction for why the cash
-- readout is the right home for it.
--
-- SINGLE-FLIGHT, NOT POOLED. Only one flash can be in the air at a time, and a
-- new payout restarts it rather than queueing. At auto-roll speed a queue would
-- drift steadily behind the actual balance and start reporting stale numbers --
-- and a payout that arrives while the last is still rising is exactly the case
-- where the player wants the LATEST figure, not both.
--
-- TWEENED, NOT STEPPED. This is a fire-and-forget one-shot with no per-frame
-- state to advance, so it needs no RenderStepped connection and no teardown
-- beyond cancelling the tweens -- which `shutdown` already gets for free by
-- destroying the ScreenGui the label lives in.
function V7HUD:flashPayout(payout: number, voidHit: boolean)
	local label = self.payoutLabel
	if label == nil or label.Parent == nil then
		return
	end

	-- A non-finite payout is a contract violation upstream. `formatNumber`
	-- renders it honestly rather than inventing a plausible zero, but there is
	-- nothing to celebrate, so it is shown without the rise.
	local finite = type(payout) == "number" and payout == payout
		and payout ~= math.huge and payout ~= -math.huge

	local text: string
	local colour: Color3
	if not finite then
		text = Format.formatNumber(payout)
		colour = UITheme.Colors.Negative
	elseif payout > 0 then
		text = "+$" .. Format.formatNumber(payout)
		colour = UITheme.Colors.Cash
	elseif payout < 0 then
		-- `formatNumber` already carries the minus sign. A debit must read as
		-- one; telling a player "0" while their balance dropped is a false
		-- receipt.
		text = "$" .. Format.formatNumber(payout)
		colour = UITheme.Colors.Negative
	elseif voidHit then
		text = "VOID"
		colour = UITheme.Colors.VoidFace
	else
		-- A genuine zero with no void. Nothing happened worth animating.
		return
	end

	-- Cancel whatever is still in the air before restarting.
	local previous = self.payoutTween
	if previous ~= nil then
		previous:Cancel()
	end

	label.Text = text
	label.TextColor3 = colour
	label.TextTransparency = 0
	label.Position = UDim2.fromScale(0.25, 1.05)
	label.Visible = true

	local tween = TweenService:Create(
		label,
		TweenInfo.new(PAYOUT_FLASH_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromScale(0.25, 1.05 + PAYOUT_DRIFT),
			TextTransparency = 1,
		}
	)
	self.payoutTween = tween

	-- Hidden on completion as well as faded. A fully transparent label still
	-- occupies its slot for hit-testing and still renders; leaving it visible
	-- would also mean the next flash briefly shows the previous figure at full
	-- opacity before the new text is assigned.
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			label.Visible = false
		end
	end)

	tween:Play()
end

function V7HUD:onMenuClicked(callback: (menuId: string) -> ())
	table.insert(self.menuCallbacks, callback)
end

-- The manual roll cooldown, in seconds. Matches the server's 1/sec bucket
-- (5 rolls per 5 seconds, operator-set 2026-08-13) with a hair of slack, so a
-- press that clears this gate is one the server will honour -- a client stricter
-- than the server makes the game feel broken, and one looser produces silent
-- refusals the player cannot explain.
local ROLL_COOLDOWN = 1.02

function V7HUD:onRollClicked(callback: () -> ())
	local lastTrigger = 0
	local cooling = false

	-- THE COOLDOWN IS SHOWN, not just enforced.
	--
	-- OPERATOR-REPORTED: "the roll option is spammable which makes it like an
	-- exploit bug". The server bucket is the real defence and now caps manual
	-- rolling below the auto-roll ceiling -- but a rate limit the player cannot
	-- see reads as lag or a dropped click, and they respond by pressing harder.
	-- Sweeping the button back to full over the cooldown makes the limit legible
	-- as a game rule.
	local function sweep()
		if cooling then
			return
		end
		cooling = true
		local fill = self.rollCooldownFill
		if fill == nil then
			task.delay(ROLL_COOLDOWN, function()
				cooling = false
			end)
			return
		end
		fill.Size = UDim2.fromScale(0, 1)
		fill.Visible = true
		local tween = TweenService:Create(fill,
			TweenInfo.new(ROLL_COOLDOWN, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) })
		tween:Play()
		task.delay(ROLL_COOLDOWN, function()
			fill.Visible = false
			cooling = false
		end)
	end

	local function trigger()
		local now = os.clock()
		if now - lastTrigger < ROLL_COOLDOWN then
			return
		end
		lastTrigger = now
		sweep()
		pcall(callback)
	end

	UITheme.onPressed(self.rollBtn, trigger)
end

-- Paints the AUTO button to match a KNOWN state. Separate from the toggle so the
-- same rendering runs whether the change came from a press or from the server
-- correcting us.
function V7HUD:setAutoState(enabled: boolean)
	self.autoEnabled = enabled

	-- Through `setButtonText`, which knows the caption lives on a child named
	-- "Label". The old code did `wrapper:FindFirstChildOfClass("Frame")` and then
	-- looked for a TextLabel inside it -- but `neumorphicButton` parents its two
	-- SHADOW frames before the body, so that call returned `shadowDark`, which
	-- has no label. The colour assignment therefore never ran and AUTO looked
	-- identical on and off, which is exactly what the operator reported.
	-- "AUTO OFF" rather than a bare "AUTO" (operator-directed 2026-08-13). A
	-- caption that names only one of the two states leaves the other reading as
	-- a label rather than a state.
	UITheme.setButtonText(self.autoBtn, if enabled then "AUTO ON" else "AUTO OFF")

	local lbl = self.autoBtn:FindFirstChild("Label")
	if lbl ~= nil and lbl:IsA("TextLabel") then
		-- Gems (cyan) rather than Positive: `Positive` is the same orange as Cash
		-- in this palette, so an "on" state painted with it reads as just more
		-- amber against an amber UI.
		lbl.TextColor3 = if enabled then UITheme.Colors.Gems else UITheme.Colors.TextDim
	end

	-- A filled backing so the state is legible at a glance, not only by reading
	-- the caption colour.
	self.autoBtn.BackgroundColor3 = if enabled
		then UITheme.Colors.PanelMaroon else UITheme.Colors.BaseCream

	local glow = self.autoBtn:FindFirstChild("AutoGlow")
	if glow ~= nil and glow:IsA("UIStroke") then
		glow.Enabled = enabled
	end
end

-- THE TOGGLE IS SERVER-CONFIRMED, not optimistic.
--
-- This used to flip a local `active` and repaint immediately, then fire the
-- callback and ignore its result. Auto-Roll is a GAMEPASS entitlement (FR-7.1)
-- and `SetAutoRoll` refuses when the player does not own it -- so a player
-- without the pass saw the button turn on, stay on, and never roll. The button
-- claimed a state the server had explicitly declined to grant.
--
-- Now the request goes first and the paint happens only on success; a refusal
-- leaves the button showing the truth and says why.
function V7HUD:onAutoToggled(callback: (enabled: boolean) -> boolean?)
	local inFlight = false
	local function trigger()
		if inFlight then
			return
		end
		inFlight = true
		local desired = not self.autoEnabled

		task.spawn(function()
			local ok, accepted = pcall(callback, desired)
			-- `accepted` is nil for a caller that returns nothing, which is
			-- treated as success -- the callback contract only promises to report
			-- a REFUSAL, and an older caller that returns nothing must not have
			-- every toggle silently rejected.
			if ok and accepted ~= false then
				self:setAutoState(desired)
			else
				-- Repaint the state we still hold, so a failed toggle visibly
				-- snaps back rather than sitting ambiguous.
				self:setAutoState(self.autoEnabled == true)
			end
			inFlight = false
		end)
	end

	UITheme.onPressed(self.autoBtn, trigger)
end

return V7HUD
