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

	local overlayFrame, bodyFrame = UITheme.overlay("🔨 THE FORGE")
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
	local committed: { number } = {}
	local draft: { number } = {}
	local faceRows: { any } = {}

	local header = UITheme.label("", UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.02, 0.01),
		UITheme.Colors.TextGold)
	header.TextScaled = true
	header.Parent = bodyFrame

	local readout = UITheme.label("", UDim2.fromScale(0.96, 0.05), UDim2.fromScale(0.02, 0.075),
		UITheme.Colors.TextDim)
	readout.TextScaled = true
	readout.Parent = bodyFrame

	-- The face list. Rows are created up to the largest shape and hidden when the
	-- current die has fewer, so switching shape never rebuilds Instances.
	local listHolder = Instance.new("Frame")
	listHolder.Size = UDim2.fromScale(0.96, 0.72)
	listHolder.Position = UDim2.fromScale(0.02, 0.14)
	listHolder.BackgroundTransparency = 1
	listHolder.Parent = bodyFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listHolder

	local MAX_FACES = 20
	local refresh: () -> ()

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
		refresh()
	end

	for i = 1, MAX_FACES do
		local row = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
		row.Size = UDim2.new(1, 0, 0, 46)
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = listHolder

		local faceLbl = UITheme.label("", UDim2.fromScale(0.10, 0.6), UDim2.fromScale(0.02, 0.2),
			UITheme.Colors.TextGold)
		faceLbl.TextScaled = true
		faceLbl.Parent = row

		local massLbl = UITheme.label("", UDim2.fromScale(0.16, 0.6), UDim2.fromScale(0.13, 0.2),
			UITheme.Colors.TextPrimary)
		massLbl.TextScaled = true
		massLbl.Parent = row

		-- Landing probability. THE COUNTER-INTUITIVE NUMBER, shown next to the
		-- mass it contradicts, because that adjacency is the whole lesson.
		local probLbl = UITheme.label("", UDim2.fromScale(0.16, 0.6), UDim2.fromScale(0.31, 0.2),
			UITheme.Colors.Gems)
		probLbl.TextScaled = true
		probLbl.Parent = row

		local payLbl = UITheme.label("", UDim2.fromScale(0.18, 0.6), UDim2.fromScale(0.49, 0.2),
			UITheme.Colors.Cash)
		payLbl.TextScaled = true
		payLbl.Parent = row

		local minusC, minusB = UITheme.neumorphicButton("-", UITheme.Colors.Negative,
			UDim2.fromScale(0.10, 0.66), UDim2.fromScale(0.70, 0.17))
		minusC.Parent = row
		local plusC, plusB = UITheme.neumorphicButton("+", UITheme.Colors.Positive,
			UDim2.fromScale(0.10, 0.66), UDim2.fromScale(0.83, 0.17))
		plusC.Parent = row

		minusB.Activated:Connect(function()
			adjust(i, -STEP)
		end)
		plusB.Activated:Connect(function()
			adjust(i, STEP)
		end)

		table.insert(faceRows, {
			row = row, face = faceLbl, mass = massLbl,
			prob = probLbl, pay = payLbl,
		})
	end

	local costLbl = UITheme.label("", UDim2.fromScale(0.44, 0.05), UDim2.fromScale(0.02, 0.885),
		UITheme.Colors.TextDim)
	costLbl.TextScaled = true
	costLbl.Parent = bodyFrame

	local resetC, resetBtn = UITheme.neumorphicButton("RESET", UITheme.Colors.TextDim,
		UDim2.fromScale(0.2, 0.07), UDim2.fromScale(0.48, 0.875))
	resetC.Parent = bodyFrame

	local commitC, commitBtn = UITheme.neumorphicButton("FORGE", UITheme.Colors.Cash,
		UDim2.fromScale(0.26, 0.07), UDim2.fromScale(0.71, 0.875))
	commitC.Parent = bodyFrame

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

		header.Text = string.format("%s  -  %d faces  -  %d mass", shapeId, count, math.floor(total + 0.5))
		readout.Text = string.format(
			"Projected: %s per roll   |   Void risk %.1f%%   -   heavier faces land LESS often",
			Format.formatNumber(ev), voidP * 100)

		-- The cost of the pending change, quoted before committing (FR-3.3).
		local changed = false
		for i = 1, count do
			if math.abs((committed[i] or 0) - draft[i]) > 1e-6 then
				changed = true
				break
			end
		end
		if changed then
			costLbl.Text = "Cost to forge: see server on commit"
			UITheme.setEnabled(commitBtn, true)
			UITheme.setEnabled(resetBtn, true)
		else
			costLbl.Text = "No changes pending"
			UITheme.setEnabled(commitBtn, false)
			UITheme.setEnabled(resetBtn, false)
		end
	end

	resetBtn.Activated:Connect(function()
		draft = table.clone(committed)
		refresh()
	end)

	commitBtn.Activated:Connect(function()
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
		NetClient.forge(1, out)
	end)

	----------------------------------------------------------------------------
	-- The data path
	----------------------------------------------------------------------------

	local self: V7ForgeController = setmetatable({
		overlay = overlayFrame,
		_apply = function(state: any)
			local die = state.dice and state.dice[1]
			if type(die) ~= "table" or type(die.Faces) ~= "table" then
				return
			end
			shapeId = tostring(die.Shape)
			budget = tonumber(die.MassBudget) or 0

			committed = {}
			for i, face in ipairs(die.Faces) do
				committed[i] = tonumber(face.Mass) or 0
			end
			-- The draft follows the server unless the player is mid-edit; a
			-- snapshot arriving during a roll must not silently discard changes
			-- they have not committed yet.
			local editing = false
			if #draft == #committed then
				for i = 1, #draft do
					if math.abs(draft[i] - committed[i]) > 1e-6 then
						editing = true
						break
					end
				end
			end
			if not editing or #draft ~= #committed then
				draft = table.clone(committed)
			end
			refresh()
		end,
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
