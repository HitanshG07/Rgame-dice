--!strict
-- V7ForgePanel.luau
-- THE FORGE: the game's core mechanic surface (SRS FR-3).
--
-- WHAT THIS REPLACED, and why a rewrite rather than a patch. The previous panel
-- was a complete visual design with no connection to the game:
--
--   * it had NO WAY to receive dice state -- no method existed by which the
--     player's actual die could reach it, so it drew five hardcoded placeholder
--     cards regardless of what was owned;
--   * `onCommitClicked` sent `callback(1, { 10, 10, 10, 10, 10, 10 })` -- a
--     HARDCODED six-face distribution. On the starting D2 that is the wrong
--     length and the server rejects it outright, every time. The forge could not
--     work for anyone;
--   * ClientBootstrap never connected `onCommitClicked` at all, so even the
--     hardcoded payload was never sent.
--
-- THE RULE THIS PANEL EXISTS TO TEACH (FR-2.3): mass on a face makes that face
-- land LESS often, and payout rises superlinearly with mass. So the game is
-- about choosing which faces to starve. That is counter-intuitive, and a forge
-- that does not show the consequence live will simply be misread -- hence the
-- projected probability and Void readouts, which update as you move mass and
-- before you commit anything (FR-3.4: "players optimise openly; the maths is
-- public by design").
--
-- ZERO-SUM (FR-3.1). Moving mass never creates it. Every control here moves an
-- amount OFF one face and ONTO another, so the total is invariant by
-- construction rather than by validation. The server re-checks anyway.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local Format = require(Shared:WaitForChild("Format"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local NetClient = require(script.Parent:WaitForChild("NetClient"))

local V7ForgePanel = {}
V7ForgePanel.__index = V7ForgePanel

-- How much mass one press moves. Coarse enough to feel responsive on a 60-mass
-- die, fine enough to tune a distribution.
local STEP = 5

export type V7ForgeController = {
	overlay: Frame,
	show: (self: V7ForgeController) -> (),
	hide: (self: V7ForgeController) -> (),
	applyState: (self: V7ForgeController, state: any) -> (),
}

function V7ForgePanel.new(): V7ForgeController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7ForgePanel] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7ForgeGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = UITheme.Layer.Overlay

	local overlayFrame, bodyFrame = UITheme.overlay("Forge")
	overlayFrame.Parent = screenGui
	screenGui.Parent = playerGui

	----------------------------------------------------------------------------
	-- Working state
	--
	-- `draft` is the distribution being edited. It starts as a copy of the
	-- server's, so opening the forge and committing without touching anything is
	-- a no-op that costs nothing.
	----------------------------------------------------------------------------

	local shapeId: string = DiceCatalog.STARTING_SHAPE
	local budget = 0
	local cash = 0
	local committed: { number } = {}
	local draft: { number } = {}
	local faceRows: { any } = {}

	-- WHICH DIE IS BEING EDITED. The forge could only ever reach die 1, so a
	-- player who bought slots owned dice they could not build.
	local activeDie = 1
	local dieCount = 1
	local dieShapes: { string } = {}
	local faceElements: { string } = {}
	local unlockedElements: { [string]: boolean } = { None = true }
	local dieTabs: { any } = {}
	local emptySlots = 0

	-- TRUE only when the PLAYER has moved mass and not yet committed.
	--
	-- This used to be inferred by comparing draft to committed, which cannot tell
	-- a player's unsaved edit from a change the SERVER made -- so buying a mass
	-- upgrade, or switching shape, left the panel convinced the player was
	-- mid-edit and refusing to refresh. The die grew from 60 to 70 and the forge
	-- kept showing 60, with a phantom cost for the difference.
	local dirty = false

	-- The element order is fixed so the cycle is predictable: pressing the same
	-- face repeatedly walks the same list every time.
	local ELEMENT_ORDER = { "None", "Fire", "Freeze", "Gold", "Multiplier" }

	----------------------------------------------------------------------------
	-- THE PANEL'S BANDS, IN PIXELS.
	--
	-- Every section below used to be placed at a scale offset -- tab strip 0.062
	-- high, readout 0.125 down, face list 0.66 tall, action bar at 0.875. Those
	-- fractions were tuned against one window size, and the overlay body is now
	-- anchored to a fixed-pixel header, so on a short window they collapsed.
	-- Measured at a 276px viewport: the tab strip rendered ELEVEN pixels tall and
	-- the action bar hung 22px BELOW the panel, its FORGE button half outside the
	-- card.
	--
	-- Declared ONCE here and read by every section, so the bands cannot drift
	-- apart the way two copies of "34" immediately did (L-025). Chrome takes
	-- known pixels top and bottom; the face list takes whatever is left.
	----------------------------------------------------------------------------
	local TAB_H = 34
	local HEAD_H = 22
	local READ_H = 18
	local BAR_H = UITheme.Scale.TouchTarget
	local TOP_BAND = TAB_H + HEAD_H + READ_H + UITheme.Scale.SM

	-- DIE TABS (operator-directed). One row across the top; a tab per owned slot.
	-- THE TAB STRIP SCROLLS, AND ITS TABS ARE BUILT ON DEMAND.
	--
	-- TWO SEPARATE CEILINGS USED TO LIVE HERE, and both were real bugs the moment
	-- a player ascended past a few slots.
	--
	-- FIRST, the tabs were created ONCE at construction, `MAX_DIE_SLOTS` of them,
	-- and merely hidden or shown. That constant is 7 today and the operator
	-- intends it to reach 20+ with ascensions -- but `new()` runs at join, so a
	-- player who ascended DURING a session kept whatever count was baked in when
	-- they logged in, and any die past it was unreachable. The forge would show
	-- seven tabs for twenty dice with no way to select the rest.
	--
	-- SECOND, a fixed-width row cannot hold twenty tabs. At `0.12` scale each,
	-- seven already fill it; twenty would need `0.048` -- an unreadable sliver on
	-- a phone (NFR-3), and unhittable with a thumb.
	--
	-- So the row is a ScrollingFrame, tabs keep a readable fixed width, and the
	-- strip scrolls horizontally with the active tab brought into view. Tabs are
	-- created lazily by `ensureTabs` as the die count grows, and never destroyed
	-- -- a player's count only moves up within a session, and reusing them keeps
	-- the pool stable across snapshots (NFR-1).
	local tabRow = Instance.new("ScrollingFrame")
	tabRow.Name = "TabStrip"
	-- A FIXED PIXEL BAND. At 0.062 of the body it measured ELEVEN pixels tall on
	-- a short window -- a tab strip too thin to read or press.
	tabRow.Size = UDim2.new(0.96, 0, 0, TAB_H)
	tabRow.Position = UDim2.new(0.02, 0, 0, 0)
	tabRow.BackgroundTransparency = 1
	tabRow.BorderSizePixel = 0
	tabRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabRow.HorizontalScrollBarInset = Enum.ScrollBarInset.None
	tabRow.ScrollBarThickness = 3
	tabRow.ScrollBarImageColor3 = UITheme.Colors.BorderDim
	tabRow.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabRow.ClipsDescendants = true
	tabRow.Parent = bodyFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	-- Fixed PIXEL width, not a fraction of the strip. A fraction would shrink
	-- every tab as more dice arrive, which is the failure being fixed.
	local TAB_WIDTH_PX = 62

	-- The canvas has to grow with the content or the strip cannot scroll to it.
	tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		tabRow.CanvasSize = UDim2.new(0, tabLayout.AbsoluteContentSize.X, 0, 0)
	end)

	local selectDie: (number) -> ()

	-- Creates tabs up to `count`, reusing any that already exist. Called from the
	-- snapshot handler, so the strip tracks the live die count rather than
	-- whatever it was at join.
	local function ensureTabs(count: number): ()
		for i = #dieTabs + 1, count do
			local tc, tb = UITheme.neumorphicButton("D" .. tostring(i), UITheme.Colors.TextGold,
				UDim2.new(0, TAB_WIDTH_PX, 1, 0), UDim2.fromScale(0, 0))
			tc.Name = "DieTab" .. tostring(i)
			tc.LayoutOrder = i
			tc.Visible = false
			tc.Parent = tabRow
			local index = i
			UITheme.onPressed(tb, function()
				selectDie(index)
			end)
			table.insert(dieTabs, { container = tc, button = tb })
		end
	end

	-- Brings the active tab into view, so selecting a die the strip has scrolled
	-- past does not leave the highlight off screen.
	local function revealTab(index: number): ()
		local tab = dieTabs[index]
		if tab == nil or not tab.container.Visible then
			return
		end
		local left = (index - 1) * (TAB_WIDTH_PX + 6)
		local right = left + TAB_WIDTH_PX
		local window = tabRow.AbsoluteWindowSize.X
		if window <= 0 then
			return
		end
		local at = tabRow.CanvasPosition.X
		if left < at then
			tabRow.CanvasPosition = Vector2.new(left, 0)
		elseif right > at + window then
			tabRow.CanvasPosition = Vector2.new(right - window, 0)
		end
	end

	-- THE PANEL'S BANDS ARE PIXELS, NOT FRACTIONS.
	--
	-- Everything below used to be placed at scale offsets -- the tab strip at
	-- 0.062 high, the readout at 0.125 down, the face list 0.66 tall, the action
	-- bar at 0.875. Those fractions were tuned against one window size, and the
	-- overlay body is now anchored to a fixed header in pixels, so on a short
	-- window they collapsed: measured at a 276px viewport the tab strip rendered
	-- ELEVEN pixels tall and the action bar hung 22px BELOW the panel, with its
	-- FORGE button half outside the card.
	--
	-- A band layout fixes the class. Chrome takes a known number of pixels at the
	-- top and bottom; the face list takes everything left over, whatever that is.
	-- No fraction to retune, and nothing can fall outside the body.
	local slotNote = UITheme.label("", UDim2.new(0.34, 0, 0, HEAD_H),
		UDim2.new(0.64, 0, 0, TAB_H))
	slotNote.TextScaled = false
	slotNote.TextSize = UITheme.Scale.TextSmall
	slotNote.TextColor3 = UITheme.Colors.TextDim
	slotNote.TextXAlignment = Enum.TextXAlignment.Right
	slotNote.Visible = false
	slotNote.Parent = bodyFrame

	local header = UITheme.label("", UDim2.new(0.6, 0, 0, HEAD_H),
		UDim2.new(0.02, 0, 0, TAB_H))
	header.TextScaled = false
	header.TextSize = UITheme.Scale.TextBody
	header.Font = UITheme.FontHeading
	header.TextColor3 = UITheme.Colors.TextGold
	header.Parent = bodyFrame

	-- MOVE THIS DIE (operator-requested 2026-08-13: "in forge there has to be an
	-- option for you to select which dice sits on which slot").
	--
	-- Position in the profile's die array IS the board slot -- `BoardView`
	-- anchors by index -- so moving a die left or right in the array is exactly
	-- "which die sits where". The data model already supported this and nothing
	-- exposed it.
	--
	-- TWO ARROWS RATHER THAN DRAG-AND-DROP. Dragging inside a ScrollingFrame
	-- fights the scroll gesture, and on touch it is close to unusable. Arrows are
	-- unambiguous, work identically on every input device, and the tab strip
	-- above gives immediate feedback about where the die landed.
	-- The move controls sit in the header band, right-aligned in their own row so
	-- the two arrows and their caption cannot drift into the die title.
	local moveRow = Instance.new("Frame")
	moveRow.Name = "MoveRow"
	moveRow.Size = UDim2.new(0, 150, 0, HEAD_H + 6)
	moveRow.Position = UDim2.new(1, -150, 0, TAB_H - 3)
	moveRow.BackgroundTransparency = 1
	moveRow.Parent = bodyFrame

	local moveLayout = Instance.new("UIListLayout")
	moveLayout.FillDirection = Enum.FillDirection.Horizontal
	moveLayout.SortOrder = Enum.SortOrder.LayoutOrder
	moveLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	moveLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	moveLayout.Padding = UDim.new(0, UITheme.Scale.XS)
	moveLayout.Parent = moveRow

	local moveHint = UITheme.textLine("move", UITheme.Scale.TextSmall, UITheme.Colors.TextDim)
	moveHint.Size = UDim2.new(0, 34, 1, 0)
	moveHint.TextXAlignment = Enum.TextXAlignment.Right
	moveHint.LayoutOrder = 1
	moveHint.Parent = moveRow

	local moveLeftBtn = UITheme.actionButton("\u{2039}", "secondary", UITheme.Colors.Gems)
	moveLeftBtn.Name = "MoveLeft"
	moveLeftBtn.LayoutOrder = 2
	moveLeftBtn.Parent = moveRow

	local moveRightBtn = UITheme.actionButton("\u{203A}", "secondary", UITheme.Colors.Gems)
	moveRightBtn.Name = "MoveRight"
	moveRightBtn.LayoutOrder = 3
	moveRightBtn.Parent = moveRow

	local readout = UITheme.label("", UDim2.new(0.96, 0, 0, READ_H),
		UDim2.new(0.02, 0, 0, TAB_H + HEAD_H))
	readout.TextScaled = false
	readout.TextSize = UITheme.Scale.TextSmall
	readout.TextColor3 = UITheme.Colors.TextDim
	readout.Parent = bodyFrame

	-- The face list. Rows are created up to the largest shape and hidden when the
	-- current die has fewer, so switching shape never rebuilds Instances.
	-- IT SCROLLS, because twenty faces have never fitted.
	--
	-- This was a plain Frame at 66% of the panel height with no clipping and no
	-- scrolling, holding up to twenty rows. At 1080p that is roughly 570px of
	-- frame for up to 1150px of rows: a D20's later faces rendered straight
	-- THROUGH the cost label and the action bar below, and there was no way to
	-- reach them. Raising the row height to fit the 44px controls would have made
	-- a real defect slightly worse, which is what surfaced it.
	--
	-- A ScrollingFrame with an automatic canvas fixes the class rather than the
	-- symptom: any face count fits, and adding a row later cannot reintroduce it.
	local listHolder = Instance.new("ScrollingFrame")
	-- Named so the face rows beneath it are reachable by path. An anonymous rung
	-- anywhere in a chain makes the whole chain ambiguous (L-037) -- the rows and
	-- their buttons were named, but this frame between them and the body was not,
	-- so a driven click still could not find them.
	listHolder.Name = "FaceList"
	-- Takes the whole middle band: everything the chrome above and below leaves.
	listHolder.Size = UDim2.new(0.96, 0, 1, -(TOP_BAND + BAR_H + UITheme.Scale.SM * 2))
	listHolder.Position = UDim2.new(0.02, 0, 0, TOP_BAND)
	listHolder.BackgroundTransparency = 1
	listHolder.BorderSizePixel = 0
	listHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listHolder.CanvasSize = UDim2.fromScale(0, 0)
	listHolder.ScrollingDirection = Enum.ScrollingDirection.Y
	listHolder.ScrollBarThickness = 6
	listHolder.ScrollBarImageColor3 = UITheme.Colors.ShadowLight
	listHolder.ScrollBarImageTransparency = 0.4
	listHolder.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	listHolder.ClipsDescendants = true
	listHolder.Parent = bodyFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listHolder

	local MAX_FACES = 20
	local refresh: () -> ()
	local lastSnapshot: any = nil
	local applySnapshot: (any) -> ()

	-- Moves `amount` onto face `index`, taking it from the other faces.
	--
	-- ZERO-SUM BY CONSTRUCTION. Rather than add and hope validation catches it,
	-- this takes from donors first and only credits what it actually removed --
	-- so a face cannot gain mass that no other face lost, and the total is
	-- invariant even when the donors run out at the floor.
	local function adjust(index: number, amount: number)
		local floor = DiceCatalog.getMassFloor(shapeId)
		local count = #draft
		if count == 0 or draft[index] == nil then
			return
		end

		if amount > 0 then
			local need = amount
			local taken = 0
			-- Round-robin over the other faces so one neighbour is not stripped
			-- to the floor while the rest stay untouched.
			for _ = 1, count do
				if need <= 0 then
					break
				end
				for i = 1, count do
					if i ~= index and need > 0 then
						local spare = draft[i] - floor
						if spare > 0 then
							local grab = math.min(spare, need, 1)
							draft[i] -= grab
							taken += grab
							need -= grab
						end
					end
				end
			end
			draft[index] += taken
		else
			-- Giving mass away: never below the floor, and it is spread outward.
			local give = math.min(-amount, draft[index] - floor)
			if give <= 0 then
				return
			end
			draft[index] -= give
			local per = give / math.max(1, count - 1)
			for i = 1, count do
				if i ~= index then
					draft[i] += per
				end
			end
		end
		dirty = true
		refresh()
	end

	-- ONE COLUMN RULER FOR EVERY FACE ROW.
	--
	-- The four readouts were placed at x 0.02 / 0.13 / 0.31 / 0.40 with widths
	-- 0.10 / 0.16 / 0.16 / 0.14 -- so mass ended at 0.29 and probability began at
	-- 0.31, a two-point gutter that closes entirely once a value grows a digit.
	-- Declaring the columns once, in pixels, is what makes the grid a grid: every
	-- row aligns with every other row because they share these numbers rather
	-- than each carrying their own copy (L-025).
	local COL_FACE = 46
	local COL_MASS = 74
	local COL_PROB = 74
	local COL_PAY = 84

	for i = 1, MAX_FACES do
		local row, textCol, actions = UITheme.listRow(52)
		row.Name = "FaceRow" .. tostring(i)
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = listHolder

		-- The readouts live in the text column as a HORIZONTAL strip of their own,
		-- so they stay left while the controls stay right and neither can drift
		-- into the other.
		local readoutStrip = Instance.new("Frame")
		readoutStrip.Name = "Readouts"
		readoutStrip.Size = UDim2.fromScale(1, 1)
		readoutStrip.BackgroundTransparency = 1
		readoutStrip.Parent = textCol

		local stripLayout = Instance.new("UIListLayout")
		stripLayout.FillDirection = Enum.FillDirection.Horizontal
		stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
		stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		stripLayout.Padding = UDim.new(0, UITheme.Scale.XS)
		stripLayout.Parent = readoutStrip

		local function readout(width: number, colour: Color3, order: number): TextLabel
			local lbl = UITheme.textLine("", UITheme.Scale.TextBody, colour, UITheme.FontMono)
			lbl.Size = UDim2.new(0, width, 1, 0)
			lbl.LayoutOrder = order
			lbl.Parent = readoutStrip
			return lbl
		end

		local faceLbl = readout(COL_FACE, UITheme.Colors.TextGold, 1)
		faceLbl.Font = UITheme.FontHeading
		local massLbl = readout(COL_MASS, UITheme.Colors.TextPrimary, 2)
		-- Landing probability. THE COUNTER-INTUITIVE NUMBER, shown next to the
		-- mass it contradicts, because that adjacency is the whole lesson.
		local probLbl = readout(COL_PROB, UITheme.Colors.Gems, 3)
		local payLbl = readout(COL_PAY, UITheme.Colors.Cash, 4)

		-- ELEMENT CHIP (FR-4.1). Cycles through the elements the player has
		-- unlocked. A CYCLE rather than a dropdown because there are five options
		-- and a dropdown inside a scrolling list is a layering problem nobody
		-- needs; one tap advances, and the current element is always visible.
		local elemB = UITheme.actionButton("-", "secondary", UITheme.Colors.Multiplier)
		-- NAMED, like every other control (L-037). These were anonymous, so all
		-- three buttons on all twenty face rows shared one instance path and none
		-- of them could be addressed by a test or a click driver.
		elemB.Name = "Element"
		elemB.LayoutOrder = 1
		elemB.Parent = actions
		UITheme.onPressed(elemB, function()
			local current = faceElements[i] or "None"
			-- Advance to the next UNLOCKED element, wrapping. If nothing else is
			-- unlocked the press is a no-op rather than a request the server will
			-- refuse.
			local startIdx = 1
			for k, id in ipairs(ELEMENT_ORDER) do
				if id == current then startIdx = k break end
			end
			for step = 1, #ELEMENT_ORDER do
				local nextId = ELEMENT_ORDER[((startIdx - 1 + step) % #ELEMENT_ORDER) + 1]
				if unlockedElements[nextId] then
					NetClient.setElement(activeDie, i, nextId)
					return
				end
			end
		end)

		-- A MINUS SIGN, not a hyphen. U+2212 is the same width as the plus it sits
		-- beside; a hyphen is narrower and sits lower, so the pair looked
		-- misaligned in every row of the panel.
		local minusB = UITheme.actionButton("\u{2212}", "secondary", UITheme.Colors.Negative)
		minusB.Name = "Minus"
		minusB.LayoutOrder = 2
		minusB.Parent = actions

		local plusB = UITheme.actionButton("+", "secondary", UITheme.Colors.Positive)
		plusB.Name = "Plus"
		plusB.LayoutOrder = 3
		plusB.Parent = actions

		UITheme.onPressed(minusB, function()
			adjust(i, -STEP)
		end)
		UITheme.onPressed(plusB, function()
			adjust(i, STEP)
		end)

		table.insert(faceRows, {
			row = row, face = faceLbl, mass = massLbl,
			prob = probLbl, pay = payLbl, elem = elemB,
		})
	end

	-- THE ACTION BAR.
	--
	-- The four controls below were placed at x 0.02 / 0.29 / 0.46 / 0.63 with
	-- widths 0.24 / 0.15 / 0.15 / 0.21 -- four fractions and four widths, none of
	-- which relate to each other, and all of which have to be re-derived by hand
	-- whenever a caption changes length. A right-aligned bar sizes each button to
	-- its own caption and spaces them uniformly.
	-- ANCHORED TO THE BOTTOM EDGE, not to 87.5% of the height. At a short viewport
	-- that fraction put the bar 22px BELOW the panel with the FORGE button hanging
	-- outside the card -- measured, not theorised.
	local actionBar = Instance.new("Frame")
	actionBar.Name = "ActionBar"
	actionBar.Size = UDim2.new(0.96, 0, 0, BAR_H)
	actionBar.AnchorPoint = Vector2.new(0, 1)
	actionBar.Position = UDim2.new(0.02, 0, 1, -UITheme.Scale.XS)
	actionBar.BackgroundTransparency = 1
	actionBar.Parent = bodyFrame

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, UITheme.Scale.SM)
	barLayout.Parent = actionBar

	-- Sits directly above the action bar, anchored to the same bottom edge, so the
	-- cost and the button that charges it stay together at any panel height.
	local costLbl = UITheme.label("", UDim2.new(0.6, 0, 0, READ_H),
		UDim2.new(0.02, 0, 1, -(BAR_H + UITheme.Scale.XS + READ_H)))
	costLbl.AnchorPoint = Vector2.new(0, 1)
	costLbl.TextScaled = false
	costLbl.TextSize = UITheme.Scale.TextSmall
	costLbl.TextColor3 = UITheme.Colors.TextDim
	costLbl.Parent = bodyFrame

	-- BUY MASS (FR-3.6). The forge had no way to increase a die's TOTAL mass, so
	-- it was a one-time puzzle rather than something a player grows into. Moving
	-- mass around is the tactic; buying more of it is the progression.
	--
	-- Priced and validated entirely server-side through the existing
	-- `BuyUpgrade` path -- the client names the upgrade and shows the result, and
	-- never computes an entitlement.
	local buyMassBtn = UITheme.actionButton("Buy mass", "secondary", UITheme.Colors.Positive)
	buyMassBtn.Name = "BuyMass"
	buyMassBtn.LayoutOrder = 1
	buyMassBtn.Parent = actionBar
	UITheme.onPressed(buyMassBtn, function()
		UITheme.setActionEnabled(buyMassBtn, false)
		task.spawn(function()
			local ok, reason = NetClient.buyUpgrade("MassBudget")
			if not ok then
				buyMassBtn.Text = tostring(reason or "Refused")
				task.wait(1.2)
			end
			buyMassBtn.Text = "Buy mass"
			refresh()
		end)
	end)

	-- EVEN (operator-requested). Spreads the budget equally across every face.
	--
	-- DISTINCT FROM RESET, and the difference matters: RESET discards unsaved
	-- edits and returns to what the server currently holds, costing nothing.
	-- EVEN proposes a NEW distribution -- the flat one -- which still has to be
	-- forged and still costs Cash. It is the "start over from neutral" button,
	-- useful because rebuilding a flat spread by hand from a concentrated die is
	-- a lot of taps.
	local evenBtn = UITheme.actionButton("Even", "secondary", UITheme.Colors.Gems)
	evenBtn.Name = "Even"
	evenBtn.LayoutOrder = 2
	evenBtn.Parent = actionBar
	UITheme.onPressed(evenBtn, function()
		local count = #draft
		if count == 0 then
			return
		end
		local share = budget / count
		for i = 1, count do
			draft[i] = share
		end
		dirty = true
		refresh()
	end)

	local resetBtn = UITheme.actionButton("Reset", "quiet", UITheme.Colors.TextDim)
	resetBtn.Name = "Reset"
	resetBtn.LayoutOrder = 3
	resetBtn.Parent = actionBar

	-- THE ONE PRIMARY ACTION ON THIS SCREEN (ui_ux_design skill S1: exactly one
	-- dominant action per screen). Everything else here is secondary or quiet, so
	-- committing the die is unmistakably the thing the panel is for.
	local commitBtn = UITheme.actionButton("Forge", "primary", UITheme.Colors.Cash)
	commitBtn.Name = "Forge"
	commitBtn.LayoutOrder = 4
	commitBtn.Parent = actionBar

	----------------------------------------------------------------------------
	-- Rendering
	----------------------------------------------------------------------------

	-- Redraws every row from `draft`. All projections are computed from the DRAFT,
	-- never the committed state, so the player sees the consequence of a change
	-- before paying for it (FR-3.4).
	refresh = function()
		local count = #draft
		local floor = DiceCatalog.getMassFloor(shapeId)

		local total = 0
		for _, m in ipairs(draft) do
			total += m
		end

		-- P(face i) proportional to (M - m_i), normalised (FR-2.3).
		local denom = total * count - total
		local ev = 0
		local voidP = 0

		for i = 1, MAX_FACES do
			local ui = faceRows[i]
			if i > count then
				ui.row.Visible = false
			else
				ui.row.Visible = true
				local m = draft[i]
				local p = if denom > 0 then (total - m) / denom else 0
				local value = ForgeMath.faceValue(m)
				ev += p * value

				local isVoid = ForgeMath.isVoidFace(draft, i, floor)
				if isVoid then
					voidP += p
				end

				ui.face.Text = "F" .. tostring(i)
				-- The element chip shows what the face carries. "-" means Plain.
				local elemId = faceElements[i] or "None"
				-- "+ELEM" invites the press; the element's own name replaces it once
				-- set. It used to render "-" for None, directly beside the minus
				-- button, so every row appeared to have two minus controls.
				-- HONEST ABOUT BEING UNAVAILABLE. Elements are unlocked through the
				-- Diamond tree, and a new player has only "None". The chip used to
				-- render "+ELEM" regardless and simply do nothing when pressed --
				-- inert with no explanation, which reads as broken rather than as
				-- locked. Count what is actually unlocked and say so.
				local choices = 0
				for _, id in ipairs(ELEMENT_ORDER) do
					if unlockedElements[id] and id ~= "None" then
						choices += 1
					end
				end
				if elemId ~= "None" then
					ui.elem.Text = elemId
					UITheme.setActionEnabled(ui.elem, choices > 0)
				elseif choices > 0 then
					ui.elem.Text = "Element"
					UITheme.setActionEnabled(ui.elem, true)
				else
					ui.elem.Text = "Locked"
					UITheme.setActionEnabled(ui.elem, false)
				end
				ui.elem.Visible = true
				ui.mass.Text = string.format("%.0f", m)
				ui.prob.Text = string.format("%.1f%%", p * 100)
				ui.pay.Text = Format.formatNumber(value)
				-- A Void face pays nothing and breaks the streak; it reads dim so
				-- it is obvious at a glance which faces have been starved.
				local tint = if isVoid then UITheme.Colors.VoidFace else UITheme.Colors.TextPrimary
				ui.mass.TextColor3 = tint
				ui.pay.TextColor3 = if isVoid then UITheme.Colors.VoidFace else UITheme.Colors.Cash
			end
		end

		header.Text = string.format("DIE %d   %s  -  %d faces  -  %d mass",
			activeDie, shapeId, count, math.floor(total + 0.5))

		-- Tabs: one per die that EXISTS, the active one held down. Numbered, not
		-- shape-named -- labelling by shape made six slots read "D6 D6 D6 D6 D6
		-- D6", identical and unusable.
		for i, tab in ipairs(dieTabs) do
			tab.container.Visible = i <= dieCount
			if i <= dieCount then
				UITheme.setButtonText(tab.button, tostring(i))
				UITheme.setEnabled(tab.button, i ~= activeDie)
			end
		end
		-- Scroll the active tab into view. Without this, a player on die 15 of 20
		-- sees the strip's first few tabs and no highlight anywhere.
		revealTab(activeDie)

		-- The move arrows are only meaningful with somewhere to move TO. Hidden
		-- rather than greyed for a single die: with one die there is no ordering
		-- to speak of, and an always-visible dead control invites the press that
		-- does nothing.
		local canReorder = dieCount > 1
		-- The whole row hides together. It used to toggle three separate
		-- containers, two of which no longer exist after the arrows became
		-- `actionButton`s in a laid-out row -- which is what produced
		-- "attempt to index nil with 'Visible'" on every snapshot.
		moveRow.Visible = canReorder
		if canReorder then
			UITheme.setActionEnabled(moveLeftBtn, activeDie > 1)
			UITheme.setActionEnabled(moveRightBtn, activeDie < dieCount)
		end
		-- Owning a slot with no die in it is a real state and the player should
		-- be told, not left wondering why the tab count does not match what they
		-- bought.
		if emptySlots > 0 then
			slotNote.Text = string.format("%d empty slot%s -- add a die in SLOTS",
				emptySlots, if emptySlots == 1 then "" else "s")
			slotNote.Visible = true
		else
			slotNote.Visible = false
		end
		readout.Text = string.format(
			"Projected: %s per roll   |   Void risk %.1f%%   -   heavier faces land LESS often",
			Format.formatNumber(ev), voidP * 100)

		-- The cost of the pending change, quoted before committing (FR-3.3).
		if dirty then
			-- FR-3.4: the price is quoted BEFORE committing, using the SAME shared
			-- function the server charges with -- not a client reimplementation,
			-- which is how a quote and a charge drift apart (L-026).
			--
			-- HONEST CAVEAT: the server applies the VIP Forge discount on top, and
			-- pass ownership is server state this snapshot does not carry. So an
			-- owner is charged LESS than quoted, never more. Over-quoting is the
			-- only safe direction to be wrong about a price.
			local quoted = ForgeMath.forgeCost(committed, draft, budget)
			if ForgeMath.isFinite(quoted) then
				local afford = cash >= quoted
				costLbl.Text = "Cost: $" .. Format.formatNumber(quoted)
				costLbl.TextColor3 = if afford then UITheme.Colors.TextGold else UITheme.Colors.Negative
				UITheme.setActionEnabled(commitBtn, afford)
			else
				costLbl.Text = "Invalid distribution"
				costLbl.TextColor3 = UITheme.Colors.Negative
				UITheme.setActionEnabled(commitBtn, false)
			end
			UITheme.setActionEnabled(resetBtn, true)
		else
			costLbl.Text = "No changes pending"
			costLbl.TextColor3 = UITheme.Colors.TextDim
			UITheme.setActionEnabled(commitBtn, false)
			UITheme.setActionEnabled(resetBtn, false)
		end
	end

	-- Defined after `refresh` exists, and assigned to the forward local the tab
	-- buttons already captured.
	selectDie = function(index: number)
		if index < 1 or index > dieCount then
			return
		end
		activeDie = index
		-- A new die starts clean; the previous die's edit is not carried over.
		dirty = false
		-- Re-read from the last snapshot so switching tabs shows that die's real
		-- state rather than the previous die's draft.
		local st = lastSnapshot
		if st ~= nil then
			applySnapshot(st)
		end
	end

	-- MOVES THE ACTIVE DIE one slot along the board order.
	--
	-- REFUSES WHILE THERE ARE UNSAVED EDITS. A pending draft belongs to a die
	-- INDEX, and swapping the array under it would silently apply the player's
	-- half-finished mass layout to a different die -- which is the exact
	-- data-loss shape as the die-index bug fixed earlier (forging die 2 wrote
	-- onto die 1). Saying so is better than quietly discarding the edit.
	local function moveActiveDie(delta: number)
		local target = activeDie + delta
		if target < 1 or target > dieCount or dieCount < 2 then
			return
		end
		if dirty then
			costLbl.Text = "Save or reset your changes before moving this die"
			costLbl.TextColor3 = UITheme.Colors.Negative
			return
		end

		UITheme.setActionEnabled(moveLeftBtn, false)
		UITheme.setActionEnabled(moveRightBtn, false)
		task.spawn(function()
			local result = NetClient.swapDice(activeDie, target)
			if result.ok then
				-- Follow the die to its new slot, so the panel keeps showing the
				-- one the player was working on rather than whatever swapped in.
				activeDie = target
				costLbl.Text = string.format("Moved to slot %d", target)
				costLbl.TextColor3 = UITheme.Colors.Positive
			else
				costLbl.Text = "Could not move that die"
				costLbl.TextColor3 = UITheme.Colors.Negative
			end
			-- The snapshot that follows repaints everything; this only re-enables
			-- the arrows for the case where no snapshot arrives.
			refresh()
		end)
	end

	UITheme.onPressed(moveLeftBtn, function()
		moveActiveDie(-1)
	end)
	UITheme.onPressed(moveRightBtn, function()
		moveActiveDie(1)
	end)

	UITheme.onPressed(resetBtn, function()
		draft = table.clone(committed)
		dirty = false
		refresh()
	end)

	UITheme.onPressed(commitBtn, function()
		if #draft == 0 then
			return
		end
		-- Snapped to whole mass before sending. The +/- arithmetic can leave
		-- fractions when mass is spread across an awkward face count, and the
		-- server requires the total to equal the budget within epsilon -- so the
		-- REMAINDER goes back on the heaviest face rather than being dropped,
		-- which would silently destroy mass and fail zero-sum.
		local out: { number } = {}
		local sum = 0
		for i, m in ipairs(draft) do
			out[i] = math.floor(m + 0.5)
			sum += out[i]
		end
		local drift = math.floor(budget + 0.5) - sum
		if drift ~= 0 then
			local heaviest, heaviestIdx = -1, 1
			for i, m in ipairs(out) do
				if m > heaviest then
					heaviest, heaviestIdx = m, i
				end
			end
			out[heaviestIdx] += drift
		end
		-- FEEDBACK. A commit that silently succeeds or silently fails teaches the
		-- player nothing; the button state is the only signal they get, so it has
		-- to reflect the actual result.
		commitBtn.Text = "Forging..."
		UITheme.setActionEnabled(commitBtn, false)
		task.spawn(function()
			-- `activeDie`, NOT a literal 1.
			--
			-- THE BUG THIS FIXES DESTROYED DATA. The commit sent `forge(1, out)`
			-- regardless of which tab was open, so editing die 2 and pressing
			-- FORGE wrote die 2's distribution ONTO DIE 1 -- silently replacing a
			-- build the player had already paid to create, and reported as
			-- success. Every other control in this panel already used `activeDie`;
			-- this one line did not, which is exactly the kind of miss that
			-- survives a screenshot.
			local ok, reason = NetClient.forge(activeDie, out)
			if ok then
				dirty = false
				commitBtn.Text = "Forged"
			else
				-- The server's refusal code, shown as-is. It is an enumerated
				-- Notice, never an internal detail (T-7).
				commitBtn.Text = tostring(reason or "Refused")
				-- Snap the draft back to the truth so the panel cannot keep
				-- displaying a distribution the server rejected.
				draft = table.clone(committed)
				dirty = false
			end
			task.wait(1.2)
			commitBtn.Text = "Forge"
			refresh()
		end)
	end)

	----------------------------------------------------------------------------
	-- The data path
	----------------------------------------------------------------------------

	applySnapshot = function(state: any)
			lastSnapshot = state
			-- TABS FOLLOW THE DICE THAT EXIST, not the slots owned.
			--
			-- `dieSlots` is the ENTITLEMENT -- how many the player may have -- and
			-- `#state.dice` is how many they actually do. Drawing tabs from the
			-- entitlement produced tabs 5 and 6 for a player with four dice, and
			-- selecting one found no die, returned early, and left the previous
			-- die's numbers on screen under the new tab's header. The player was
			-- then editing what looked like an empty slot and was really editing
			-- nothing.
			-- NO HARDCODED CEILING. This clamped slots to a literal 7 -- a third
			-- copy of `MAX_DIE_SLOTS`, and one that would have quietly discarded
			-- every slot past the seventh the moment ascensions raised the cap.
			-- The floor of 1 is kept because a die count below one is nonsense;
			-- the upper bound is whatever the server actually reports, since the
			-- server is the authority on entitlement and the panel only draws it.
			local owned = if type(state.dice) == "table" then #state.dice else 1
			local slots = math.max(1, math.floor(tonumber(state.dieSlots) or 1))
			dieCount = math.max(1, math.min(owned, slots))
			emptySlots = math.max(0, slots - owned)
			if activeDie > dieCount then
				activeDie = 1
			end

			-- Grow the strip to match. Built here rather than at construction
			-- because a player can ascend mid-session and gain slots without
			-- rejoining -- tabs baked in at join would leave the new dice
			-- permanently unreachable.
			ensureTabs(dieCount)
			dieShapes = {}
			if type(state.dice) == "table" then
				for i, d in ipairs(state.dice) do
					dieShapes[i] = tostring(d.Shape)
				end
			end
			unlockedElements = {}
			local el = state.diamondTree and state.diamondTree.Elements
			if type(el) == "table" then
				for id, on in pairs(el) do
					unlockedElements[id] = on == true
				end
			end
			unlockedElements.None = true

			local die = state.dice and state.dice[activeDie]
			if type(die) ~= "table" or type(die.Faces) ~= "table" then
				return
			end
			shapeId = tostring(die.Shape)
			budget = tonumber(die.MassBudget) or 0
			cash = tonumber(state.cash) or 0

			committed = {}
			faceElements = {}
			for i, face in ipairs(die.Faces) do
				committed[i] = tonumber(face.Mass) or 0
				faceElements[i] = tostring(face.Element or "None")
			end
			-- The draft follows the server unless the PLAYER is mid-edit. `dirty`
			-- is set only by this panel's own controls, so a server-side change --
			-- a mass upgrade, a shape switch, an element write -- refreshes the
			-- view instead of being mistaken for the player's unsaved work.
			--
			-- A face-count change always wins: a draft sized for the old shape
			-- cannot be applied to the new one.
			if not dirty or #draft ~= #committed then
				draft = table.clone(committed)
				dirty = false
			end
			refresh()
	end

	local self: V7ForgeController = setmetatable({
		overlay = overlayFrame,
		_apply = applySnapshot,
	}, V7ForgePanel) :: any

	return self
end

function V7ForgePanel:show()
	self.overlay.Visible = true
end

function V7ForgePanel:hide()
	self.overlay.Visible = false
end

function V7ForgePanel:applyState(state: any)
	if type(state) ~= "table" then
		return
	end
	local ok, err = pcall(self._apply, state)
	if not ok then
		warn("[V7ForgePanel] applyState failed: " .. tostring(err))
	end
end

return V7ForgePanel
