--!strict
--[=[
    V7VaultOverlay.luau
    Offline Treasury Vault Overlay (Certified Casino Treasury Bond - Hybrid B1+B2).
    Implements the accepted high-roller certificate design with itemized calculations,
    retention gauge, gem sink capacity extension, and live authorization settle button.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))
local Format = require(Shared:WaitForChild("Format"))

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local NetClient = require(script.Parent:WaitForChild("NetClient"))

-- Theme tokens for Vault Bond
local VAULT_THEME = {
	ModalBg = Color3.fromRGB(24, 20, 18),
	CardBg = Color3.fromRGB(32, 26, 22),
	CardBgAlt = Color3.fromRGB(28, 23, 19),
	CardFeltDeep = Color3.fromRGB(18, 14, 12),
	InsetBg = Color3.fromRGB(18, 15, 13),
	InsetDark = Color3.fromRGB(14, 11, 10),
	ButtonDark = Color3.fromRGB(42, 34, 28),

	GoldPrimary = Color3.fromRGB(222, 178, 80),
	GoldBurnished = Color3.fromRGB(185, 148, 65),
	GreenSuccess = Color3.fromRGB(145, 185, 135),
	RedAlert = Color3.fromRGB(195, 85, 75),

	StrokeGold = Color3.fromRGB(160, 128, 55),
	StrokeSubtle = Color3.fromRGB(55, 45, 38),

	TextPrimary = Color3.fromRGB(235, 230, 222),
	TextMuted = Color3.fromRGB(175, 168, 160),
	TextSubtle = Color3.fromRGB(125, 118, 110),
	TextDark = Color3.fromRGB(28, 22, 18),
}

-- Pure Geometric Casino Brass Diamond Seal
local function drawVaultBrassSeal(parent: Instance, size: number): Frame
	local seal = Instance.new("Frame")
	seal.Name = "BrassSeal"
	seal.Size = UDim2.fromOffset(size, size)
	seal.BackgroundColor3 = VAULT_THEME.InsetBg
	seal.Parent = parent

	local sC = Instance.new("UICorner")
	sC.CornerRadius = UDim.new(1, 0)
	sC.Parent = seal

	local sS = Instance.new("UIStroke")
	sS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sS.Color = VAULT_THEME.GoldBurnished
	sS.Thickness = 2
	sS.Parent = seal

	local innerDiamond = Instance.new("Frame")
	innerDiamond.Name = "Diamond"
	innerDiamond.Size = UDim2.fromScale(0.48, 0.48)
	innerDiamond.AnchorPoint = Vector2.new(0.5, 0.5)
	innerDiamond.Position = UDim2.fromScale(0.5, 0.5)
	innerDiamond.BackgroundColor3 = VAULT_THEME.GoldPrimary
	innerDiamond.Rotation = 45
	innerDiamond.BorderSizePixel = 0
	innerDiamond.Parent = seal

	return seal
end

-- Pure Geometric Corner Brackets
local function addVaultCornerBrackets(parent: Frame, size: number, color: Color3)
	local positions = {
		UDim2.new(0, 8, 0, 8),
		UDim2.new(1, -8 - size, 0, 8),
		UDim2.new(0, 8, 1, -8 - size),
		UDim2.new(1, -8 - size, 1, -8 - size),
	}
	for idx, pos in ipairs(positions) do
		local b = Instance.new("Frame")
		b.Name = "CornerBracket_" .. idx
		b.Size = UDim2.fromOffset(size, size)
		b.Position = pos
		b.BackgroundTransparency = 1
		b.Parent = parent

		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = color
		s.Thickness = 1.5
		s.Parent = b

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 2)
		c.Parent = b
	end
end

local function formatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	if m > 0 then
		return string.format("%dm", m)
	end
	return string.format("%ds", s)
end

local function buildVaultOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any,
	formatModalShell: (overlay: Frame, title: string, getCtrl: () -> any) -> (Frame, Frame)
): (any) -> ()
	local vaultOverlay, legacyBody = UITheme.overlay("Offline Vault")
	vaultOverlay.Parent = screenGui
	overlays["vault"] = vaultOverlay
	if legacyBody then legacyBody.Visible = false end

	local _, vaultBody = formatModalShell(vaultOverlay, "~ Offline Treasury Vault ~", getController)

	-- Master Certificate Plaque Envelope
	local certPlaque = Instance.new("Frame")
	certPlaque.Name = "GrandCertificatePlaque"
	certPlaque.Size = UDim2.fromScale(1, 1)
	certPlaque.BackgroundColor3 = VAULT_THEME.ModalBg
	certPlaque.Parent = vaultBody

	local cpC = Instance.new("UICorner")
	cpC.CornerRadius = UDim.new(0, 8)
	cpC.Parent = certPlaque

	local cpS = Instance.new("UIStroke")
	cpS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cpS.Color = VAULT_THEME.GoldPrimary
	cpS.Thickness = 2
	cpS.Parent = certPlaque

	addVaultCornerBrackets(certPlaque, 14, VAULT_THEME.GoldBurnished)

	-- Inner Content Host with UIListLayout
	local innerContent = Instance.new("Frame")
	innerContent.Name = "InnerContent"
	innerContent.Size = UDim2.fromScale(1, 1)
	innerContent.BackgroundTransparency = 1
	innerContent.Parent = certPlaque

	local cpPad = Instance.new("UIPadding")
	cpPad.PaddingTop = UDim.new(0, 10)
	cpPad.PaddingBottom = UDim.new(0, 10)
	cpPad.PaddingLeft = UDim.new(0, 14)
	cpPad.PaddingRight = UDim.new(0, 14)
	cpPad.Parent = innerContent

	local cpList = Instance.new("UIListLayout")
	cpList.SortOrder = Enum.SortOrder.LayoutOrder
	cpList.Padding = UDim.new(0, 10)
	cpList.Parent = innerContent

	-- 1. Top Header Ribbon
	local certHeader = Instance.new("Frame")
	certHeader.Name = "CertHeader"
	certHeader.Size = UDim2.new(1, 0, 0, 18)
	certHeader.BackgroundTransparency = 1
	certHeader.LayoutOrder = 1
	certHeader.Parent = innerContent

	local chTitle = Instance.new("TextLabel")
	chTitle.Name = "Title"
	chTitle.Size = UDim2.new(1, 0, 1, 0)
	chTitle.BackgroundTransparency = 1
	chTitle.Font = Enum.Font.GothamBold
	chTitle.Text = "CASINO TREASURY VAULT"
	chTitle.TextColor3 = VAULT_THEME.TextMuted
	chTitle.TextSize = 12
	chTitle.TextXAlignment = Enum.TextXAlignment.Center
	chTitle.Parent = certHeader

	-- 2. Grand Certificate Hero Plaque
	local heroPlaque = Instance.new("Frame")
	heroPlaque.Name = "HeroPlaque"
	heroPlaque.Size = UDim2.new(1, 0, 0, 94)
	heroPlaque.BackgroundColor3 = VAULT_THEME.CardFeltDeep
	heroPlaque.LayoutOrder = 2
	heroPlaque.Parent = innerContent

	local hpC = Instance.new("UICorner")
	hpC.CornerRadius = UDim.new(0, 8)
	hpC.Parent = heroPlaque

	local hpS = Instance.new("UIStroke")
	hpS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hpS.Color = VAULT_THEME.StrokeGold
	hpS.Thickness = 1.5
	hpS.Parent = heroPlaque

	local hpPad = Instance.new("UIPadding")
	hpPad.PaddingTop = UDim.new(0, 9)
	hpPad.PaddingBottom = UDim.new(0, 9)
	hpPad.PaddingLeft = UDim.new(0, 14)
	hpPad.PaddingRight = UDim.new(0, 14)
	hpPad.Parent = heroPlaque

	local hpRow = Instance.new("Frame")
	hpRow.Name = "Row"
	hpRow.Size = UDim2.fromScale(1, 1)
	hpRow.BackgroundTransparency = 1
	hpRow.Parent = heroPlaque

	local hprList = Instance.new("UIListLayout")
	hprList.FillDirection = Enum.FillDirection.Horizontal
	hprList.VerticalAlignment = Enum.VerticalAlignment.Center
	hprList.SortOrder = Enum.SortOrder.LayoutOrder
	hprList.Padding = UDim.new(0, 14)
	hprList.Parent = hpRow

	local brassSeal = drawVaultBrassSeal(hpRow, 60)
	brassSeal.LayoutOrder = 1

	local hpAmountStack = Instance.new("Frame")
	hpAmountStack.Name = "AmountStack"
	hpAmountStack.Size = UDim2.new(1, -74, 1, 0)
	hpAmountStack.BackgroundTransparency = 1
	hpAmountStack.LayoutOrder = 2
	hpAmountStack.Parent = hpRow

	local hpasList = Instance.new("UIListLayout")
	hpasList.VerticalAlignment = Enum.VerticalAlignment.Center
	hpasList.SortOrder = Enum.SortOrder.LayoutOrder
	hpasList.Padding = UDim.new(0, 1)
	hpasList.Parent = hpAmountStack

	local hpSubTop = Instance.new("TextLabel")
	hpSubTop.Name = "SubTop"
	hpSubTop.Size = UDim2.new(1, 0, 0, 14)
	hpSubTop.BackgroundTransparency = 1
	hpSubTop.Font = Enum.Font.GothamMedium
	hpSubTop.Text = "UNCLAIMED OFFLINE EARNINGS"
	hpSubTop.TextColor3 = VAULT_THEME.TextSubtle
	hpSubTop.TextSize = 11
	hpSubTop.TextXAlignment = Enum.TextXAlignment.Left
	hpSubTop.LayoutOrder = 1
	hpSubTop.Parent = hpAmountStack

	local heroAmount = Instance.new("TextLabel")
	heroAmount.Name = "VaultAmount"
	heroAmount.Size = UDim2.new(1, 0, 0, 38)
	heroAmount.BackgroundTransparency = 1
	heroAmount.Font = Enum.Font.GothamBold
	heroAmount.Text = "$0"
	heroAmount.TextColor3 = VAULT_THEME.GoldPrimary
	heroAmount.TextSize = 38
	heroAmount.TextXAlignment = Enum.TextXAlignment.Left
	heroAmount.LayoutOrder = 2
	heroAmount.Parent = hpAmountStack

	local hpStatusSub = Instance.new("TextLabel")
	hpStatusSub.Name = "StatusSub"
	hpStatusSub.Size = UDim2.new(1, 0, 0, 15)
	hpStatusSub.BackgroundTransparency = 1
	hpStatusSub.Font = Enum.Font.GothamBold
	hpStatusSub.Text = "Earning Offline • Rate: +$0.00/sec"
	hpStatusSub.TextColor3 = VAULT_THEME.GreenSuccess
	hpStatusSub.TextSize = 12
	hpStatusSub.TextXAlignment = Enum.TextXAlignment.Left
	hpStatusSub.LayoutOrder = 3
	hpStatusSub.Parent = hpAmountStack

	-- 3. Middle Split Deck
	local splitDeck = Instance.new("Frame")
	splitDeck.Name = "SplitDeck"
	splitDeck.Size = UDim2.new(1, 0, 0, 242)
	splitDeck.BackgroundTransparency = 1
	splitDeck.LayoutOrder = 3
	splitDeck.Parent = innerContent

	local sdList = Instance.new("UIListLayout")
	sdList.FillDirection = Enum.FillDirection.Horizontal
	sdList.SortOrder = Enum.SortOrder.LayoutOrder
	sdList.Padding = UDim.new(0, 10)
	sdList.Parent = splitDeck

	-- LEFT COLUMN (52%): B2 ITEMIZED CALCULATION AUDIT SLIP
	local auditSlip = Instance.new("Frame")
	auditSlip.Name = "ItemizedAuditSlip"
	auditSlip.Size = UDim2.new(0.52, -5, 1, 0)
	auditSlip.BackgroundColor3 = VAULT_THEME.CardFeltDeep
	auditSlip.LayoutOrder = 1
	auditSlip.Parent = splitDeck

	local asC = Instance.new("UICorner")
	asC.CornerRadius = UDim.new(0, 6)
	asC.Parent = auditSlip

	local asS = Instance.new("UIStroke")
	asS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	asS.Color = VAULT_THEME.StrokeSubtle
	asS.Thickness = 1
	asS.Parent = auditSlip

	local asPad = Instance.new("UIPadding")
	asPad.PaddingTop = UDim.new(0, 10)
	asPad.PaddingBottom = UDim.new(0, 10)
	asPad.PaddingLeft = UDim.new(0, 14)
	asPad.PaddingRight = UDim.new(0, 14)
	asPad.Parent = auditSlip

	local aslList = Instance.new("UIListLayout")
	aslList.SortOrder = Enum.SortOrder.LayoutOrder
	aslList.Padding = UDim.new(0, 4)
	aslList.Parent = auditSlip

	local asHeader = Instance.new("TextLabel")
	asHeader.Name = "Header"
	asHeader.Size = UDim2.new(1, 0, 0, 18)
	asHeader.BackgroundTransparency = 1
	asHeader.Font = Enum.Font.GothamBold
	asHeader.Text = "EARNINGS BREAKDOWN"
	asHeader.TextColor3 = VAULT_THEME.GoldPrimary
	asHeader.TextSize = 12
	asHeader.TextXAlignment = Enum.TextXAlignment.Left
	asHeader.LayoutOrder = 1
	asHeader.Parent = auditSlip

	local function makeLineItem(name: string, val: string, order: number): (TextLabel, TextLabel)
		local row = Instance.new("Frame")
		row.Name = "Row_" .. order
		row.Size = UDim2.new(1, 0, 0, 21)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order + 1
		row.Parent = auditSlip

		local lLabel = Instance.new("TextLabel")
		lLabel.Size = UDim2.new(0.6, 0, 1, 0)
		lLabel.BackgroundTransparency = 1
		lLabel.Font = Enum.Font.GothamMedium
		lLabel.Text = name
		lLabel.TextColor3 = VAULT_THEME.TextMuted
		lLabel.TextSize = 12
		lLabel.TextXAlignment = Enum.TextXAlignment.Left
		lLabel.Parent = row

		local rLabel = Instance.new("TextLabel")
		rLabel.Size = UDim2.new(0.4, 0, 1, 0)
		rLabel.Position = UDim2.fromScale(0.6, 0)
		rLabel.BackgroundTransparency = 1
		rLabel.Font = Enum.Font.GothamBold
		rLabel.Text = val
		rLabel.TextColor3 = VAULT_THEME.TextPrimary
		rLabel.TextSize = 13
		rLabel.TextXAlignment = Enum.TextXAlignment.Right
		rLabel.Parent = row

		return lLabel, rLabel
	end

	local _, r1Val = makeLineItem("• Earning Rate", "+$0.00 / sec", 1)
	local _, r2Val = makeLineItem("• Vault Efficiency", "50% Standard", 2)
	local _, r3Val = makeLineItem("• Stored Time", "0s stored", 3)
	local _, r4Val = makeLineItem("• VIP Multiplier", "1.00x Normal", 4)
	local _, r5Val = makeLineItem("• Status", "Active (Earning)", 5)

	-- Net Grand Total Line
	local netTotalBox = Instance.new("Frame")
	netTotalBox.Name = "NetTotalBox"
	netTotalBox.Size = UDim2.new(1, 0, 0, 40)
	netTotalBox.BackgroundColor3 = VAULT_THEME.InsetBg
	netTotalBox.LayoutOrder = 7
	netTotalBox.Parent = auditSlip

	local ntbC = Instance.new("UICorner")
	ntbC.CornerRadius = UDim.new(0, 4)
	ntbC.Parent = netTotalBox

	local ntbS = Instance.new("UIStroke")
	ntbS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ntbS.Color = VAULT_THEME.StrokeGold
	ntbS.Thickness = 1
	ntbS.Parent = netTotalBox

	local ntbPad = Instance.new("UIPadding")
	ntbPad.PaddingLeft = UDim.new(0, 10)
	ntbPad.PaddingRight = UDim.new(0, 10)
	ntbPad.Parent = netTotalBox

	local ntbRow = Instance.new("Frame")
	ntbRow.Name = "Row"
	ntbRow.Size = UDim2.fromScale(1, 1)
	ntbRow.BackgroundTransparency = 1
	ntbRow.Parent = netTotalBox

	local ntbrList = Instance.new("UIListLayout")
	ntbrList.FillDirection = Enum.FillDirection.Horizontal
	ntbrList.VerticalAlignment = Enum.VerticalAlignment.Center
	ntbrList.SortOrder = Enum.SortOrder.LayoutOrder
	ntbrList.Padding = UDim.new(0, 6)
	ntbrList.Parent = ntbRow

	local ntbTitle = Instance.new("TextLabel")
	ntbTitle.Name = "Title"
	ntbTitle.Size = UDim2.new(0.45, 0, 1, 0)
	ntbTitle.BackgroundTransparency = 1
	ntbTitle.Font = Enum.Font.GothamBold
	ntbTitle.Text = "TOTAL UNCLAIMED:"
	ntbTitle.TextColor3 = VAULT_THEME.GoldPrimary
	ntbTitle.TextSize = 12
	ntbTitle.TextXAlignment = Enum.TextXAlignment.Left
	ntbTitle.LayoutOrder = 1
	ntbTitle.Parent = ntbRow

	local ntbAmount = Instance.new("TextLabel")
	ntbAmount.Name = "VaultAmount"
	ntbAmount.Size = UDim2.new(0.55, 0, 1, 0)
	ntbAmount.BackgroundTransparency = 1
	ntbAmount.Font = Enum.Font.GothamBold
	ntbAmount.Text = "$0"
	ntbAmount.TextColor3 = VAULT_THEME.GoldPrimary
	ntbAmount.TextSize = 18
	ntbAmount.TextXAlignment = Enum.TextXAlignment.Right
	ntbAmount.LayoutOrder = 2
	ntbAmount.Parent = ntbRow

	-- RIGHT COLUMN (48%): RETENTION CHRONOMETER + GEM CAPACITY PUNCH
	local instrumentsCol = Instance.new("Frame")
	instrumentsCol.Name = "InstrumentsCol"
	instrumentsCol.Size = UDim2.new(0.48, -5, 1, 0)
	instrumentsCol.BackgroundTransparency = 1
	instrumentsCol.LayoutOrder = 2
	instrumentsCol.Parent = splitDeck

	local icList = Instance.new("UIListLayout")
	icList.SortOrder = Enum.SortOrder.LayoutOrder
	icList.Padding = UDim.new(0, 10)
	icList.Parent = instrumentsCol

	-- Retention Gauge Card
	local gaugeCard = Instance.new("Frame")
	gaugeCard.Name = "RetentionGaugeCard"
	gaugeCard.Size = UDim2.new(1, 0, 0, 110)
	gaugeCard.BackgroundColor3 = VAULT_THEME.CardFeltDeep
	gaugeCard.LayoutOrder = 1
	gaugeCard.Parent = instrumentsCol

	local gcC = Instance.new("UICorner")
	gcC.CornerRadius = UDim.new(0, 6)
	gcC.Parent = gaugeCard

	local gcS = Instance.new("UIStroke")
	gcS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gcS.Color = VAULT_THEME.StrokeSubtle
	gcS.Thickness = 1
	gcS.Parent = gaugeCard

	local gcPad = Instance.new("UIPadding")
	gcPad.PaddingTop = UDim.new(0, 8)
	gcPad.PaddingBottom = UDim.new(0, 8)
	gcPad.PaddingLeft = UDim.new(0, 12)
	gcPad.PaddingRight = UDim.new(0, 12)
	gcPad.Parent = gaugeCard

	local gclList = Instance.new("UIListLayout")
	gclList.SortOrder = Enum.SortOrder.LayoutOrder
	gclList.Padding = UDim.new(0, 4)
	gclList.Parent = gaugeCard

	local gcHeaderRow = Instance.new("Frame")
	gcHeaderRow.Name = "HeaderRow"
	gcHeaderRow.Size = UDim2.new(1, 0, 0, 16)
	gcHeaderRow.BackgroundTransparency = 1
	gcHeaderRow.LayoutOrder = 1
	gcHeaderRow.Parent = gaugeCard

	local gcTitle = Instance.new("TextLabel")
	gcTitle.Name = "Title"
	gcTitle.Size = UDim2.new(0.5, 0, 1, 0)
	gcTitle.BackgroundTransparency = 1
	gcTitle.Font = Enum.Font.GothamBold
	gcTitle.Text = "STORAGE CAPACITY"
	gcTitle.TextColor3 = VAULT_THEME.TextPrimary
	gcTitle.TextSize = 12
	gcTitle.TextXAlignment = Enum.TextXAlignment.Left
	gcTitle.Parent = gcHeaderRow

	local gcDuration = Instance.new("TextLabel")
	gcDuration.Name = "Duration"
	gcDuration.Size = UDim2.new(0.5, 0, 1, 0)
	gcDuration.Position = UDim2.fromScale(0.5, 0)
	gcDuration.BackgroundTransparency = 1
	gcDuration.Font = Enum.Font.GothamBold
	gcDuration.Text = "0s / 4h 00m"
	gcDuration.TextColor3 = VAULT_THEME.GoldPrimary
	gcDuration.TextSize = 13
	gcDuration.TextXAlignment = Enum.TextXAlignment.Right
	gcDuration.Parent = gcHeaderRow

	local gcTrack = Instance.new("Frame")
	gcTrack.Name = "Track"
	gcTrack.Size = UDim2.new(1, 0, 0, 16)
	gcTrack.BackgroundColor3 = VAULT_THEME.InsetDark
	gcTrack.LayoutOrder = 2
	gcTrack.Parent = gaugeCard

	local gctC = Instance.new("UICorner")
	gctC.CornerRadius = UDim.new(0, 4)
	gctC.Parent = gcTrack

	local gcFill = Instance.new("Frame")
	gcFill.Name = "VaultBarFill"
	gcFill.Size = UDim2.fromScale(0, 1)
	gcFill.BackgroundColor3 = VAULT_THEME.GoldBurnished
	gcFill.BorderSizePixel = 0
	gcFill.Parent = gcTrack

	local gcfC = Instance.new("UICorner")
	gcfC.CornerRadius = UDim.new(0, 4)
	gcfC.Parent = gcFill

	local gcSub = Instance.new("TextLabel")
	gcSub.Name = "StatusText"
	gcSub.Size = UDim2.new(1, 0, 0, 16)
	gcSub.BackgroundTransparency = 1
	gcSub.Font = Enum.Font.GothamMedium
	gcSub.Text = "0% Full • Actively Earning"
	gcSub.TextColor3 = VAULT_THEME.TextMuted
	gcSub.TextSize = 12
	gcSub.TextXAlignment = Enum.TextXAlignment.Left
	gcSub.LayoutOrder = 3
	gcSub.Parent = gaugeCard

	local gcSub2 = Instance.new("TextLabel")
	gcSub2.Name = "StatusSub2"
	gcSub2.Size = UDim2.new(1, 0, 0, 15)
	gcSub2.BackgroundTransparency = 1
	gcSub2.Font = Enum.Font.Gotham
	gcSub2.Text = "4h left until vault is full"
	gcSub2.TextColor3 = VAULT_THEME.TextSubtle
	gcSub2.TextSize = 11
	gcSub2.TextXAlignment = Enum.TextXAlignment.Left
	gcSub2.LayoutOrder = 4
	gcSub2.Parent = gaugeCard

	-- Gem Capacity Extension Card
	local gemCard = Instance.new("Frame")
	gemCard.Name = "GemCapacityCard"
	gemCard.Size = UDim2.new(1, 0, 0, 122)
	gemCard.BackgroundColor3 = VAULT_THEME.CardFeltDeep
	gemCard.LayoutOrder = 2
	gemCard.Parent = instrumentsCol

	local gmcC = Instance.new("UICorner")
	gmcC.CornerRadius = UDim.new(0, 6)
	gmcC.Parent = gemCard

	local gmcS = Instance.new("UIStroke")
	gmcS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gmcS.Color = VAULT_THEME.StrokeSubtle
	gmcS.Thickness = 1
	gmcS.Parent = gemCard

	local gmcPad = Instance.new("UIPadding")
	gmcPad.PaddingTop = UDim.new(0, 8)
	gmcPad.PaddingBottom = UDim.new(0, 8)
	gmcPad.PaddingLeft = UDim.new(0, 12)
	gmcPad.PaddingRight = UDim.new(0, 12)
	gmcPad.Parent = gemCard

	local gmclList = Instance.new("UIListLayout")
	gmclList.SortOrder = Enum.SortOrder.LayoutOrder
	gmclList.Padding = UDim.new(0, 4)
	gmclList.Parent = gemCard

	local gmcTitle = Instance.new("TextLabel")
	gmcTitle.Name = "Title"
	gmcTitle.Size = UDim2.new(1, 0, 0, 16)
	gmcTitle.BackgroundTransparency = 1
	gmcTitle.Font = Enum.Font.GothamBold
	gmcTitle.Text = "UPGRADE VAULT STORAGE"
	gmcTitle.TextColor3 = VAULT_THEME.TextPrimary
	gmcTitle.TextSize = 12
	gmcTitle.TextXAlignment = Enum.TextXAlignment.Left
	gmcTitle.LayoutOrder = 1
	gmcTitle.Parent = gemCard

	local gmcSub = Instance.new("TextLabel")
	gmcSub.Name = "VaultInfo"
	gmcSub.Size = UDim2.new(1, 0, 0, 15)
	gmcSub.BackgroundTransparency = 1
	gmcSub.Font = Enum.Font.GothamMedium
	gmcSub.Text = "+0h bought / +8h Max upgrade"
	gmcSub.TextColor3 = VAULT_THEME.TextMuted
	gmcSub.TextSize = 12
	gmcSub.TextXAlignment = Enum.TextXAlignment.Left
	gmcSub.LayoutOrder = 2
	gmcSub.Parent = gemCard

	local gmcSub2 = Instance.new("TextLabel")
	gmcSub2.Name = "Sub2"
	gmcSub2.Size = UDim2.new(1, 0, 0, 14)
	gmcSub2.BackgroundTransparency = 1
	gmcSub2.Font = Enum.Font.Gotham
	gmcSub2.Text = "Permanently holds more offline earnings."
	gmcSub2.TextColor3 = VAULT_THEME.TextSubtle
	gmcSub2.TextSize = 11
	gmcSub2.TextXAlignment = Enum.TextXAlignment.Left
	gmcSub2.LayoutOrder = 3
	gmcSub2.Parent = gemCard

	local buyHoursBtn = Instance.new("TextButton")
	buyHoursBtn.Name = "BuyHoursButton"
	buyHoursBtn.Size = UDim2.new(1, 0, 0, 36)
	buyHoursBtn.BackgroundColor3 = VAULT_THEME.ButtonDark
	buyHoursBtn.BorderSizePixel = 0
	buyHoursBtn.Font = Enum.Font.GothamBold
	buyHoursBtn.Text = "+1 HOUR STORAGE (5 GEMS)"
	buyHoursBtn.TextColor3 = VAULT_THEME.TextPrimary
	buyHoursBtn.TextSize = 12
	buyHoursBtn.TextXAlignment = Enum.TextXAlignment.Center
	buyHoursBtn.TextYAlignment = Enum.TextYAlignment.Center
	buyHoursBtn.AutoButtonColor = true
	buyHoursBtn.LayoutOrder = 4
	buyHoursBtn.Parent = gemCard

	local bhC = Instance.new("UICorner")
	bhC.CornerRadius = UDim.new(0, 6)
	bhC.Parent = buyHoursBtn

	local bhS = Instance.new("UIStroke")
	bhS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bhS.Color = VAULT_THEME.StrokeGold
	bhS.Thickness = 1
	bhS.Parent = buyHoursBtn

	-- 4. Bottom Grand Authorization Settle Stamp Button
	local claimVaultBtn = Instance.new("TextButton")
	claimVaultBtn.Name = "ClaimVaultButton"
	claimVaultBtn.Size = UDim2.new(1, 0, 0, 52)
	claimVaultBtn.BackgroundColor3 = VAULT_THEME.GoldPrimary
	claimVaultBtn.BorderSizePixel = 0
	claimVaultBtn.Font = Enum.Font.GothamBold
	claimVaultBtn.Text = "CLAIM VAULT CASH"
	claimVaultBtn.TextColor3 = VAULT_THEME.TextDark
	claimVaultBtn.TextSize = 15
	claimVaultBtn.TextXAlignment = Enum.TextXAlignment.Center
	claimVaultBtn.TextYAlignment = Enum.TextYAlignment.Center
	claimVaultBtn.AutoButtonColor = true
	claimVaultBtn.LayoutOrder = 4
	claimVaultBtn.Parent = innerContent

	local cbC = Instance.new("UICorner")
	cbC.CornerRadius = UDim.new(0, 8)
	cbC.Parent = claimVaultBtn

	local cbS = Instance.new("UIStroke")
	cbS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cbS.Color = VAULT_THEME.GoldBurnished
	cbS.Thickness = 1.5
	cbS.Parent = claimVaultBtn

	local vaultBusy = false

	claimVaultBtn.MouseButton1Click:Connect(function()
		if vaultBusy or not claimVaultBtn.Active then
			return
		end
		vaultBusy = true
		task.spawn(function()
			local result = NetClient.claimVault(false)
			vaultBusy = false
			if not result.ok then
				hpStatusSub.Text = "Could not claim vault cash right now."
				hpStatusSub.TextColor3 = VAULT_THEME.RedAlert
			end
		end)
	end)

	buyHoursBtn.MouseButton1Click:Connect(function()
		if vaultBusy or not buyHoursBtn.Active then
			return
		end
		vaultBusy = true
		task.spawn(function()
			local result = NetClient.buyVaultHours(1)
			vaultBusy = false
			if not result.ok then
				gmcSub2.Text = "Could not upgrade storage right now."
				gmcSub2.TextColor3 = VAULT_THEME.RedAlert
			end
		end)
	end)

	local function refreshVault(state: any)
		local v = if type(state) == "table" then state.vault else nil
		if type(v) ~= "table" then
			heroAmount.Text = "--"
			ntbAmount.Text = "--"
			gcFill.Size = UDim2.fromScale(0, 1)
			claimVaultBtn.Active = false
			claimVaultBtn.AutoButtonColor = false
			claimVaultBtn.BackgroundColor3 = VAULT_THEME.ButtonDark
			claimVaultBtn.TextColor3 = VAULT_THEME.TextMuted
			claimVaultBtn.Text = "WAITING FOR FIGURES..."
			buyHoursBtn.Active = false
			buyHoursBtn.AutoButtonColor = false
			return
		end

		local ownedHours = tonumber(v.purchasedHours) or 0
		local maxHours = tonumber(v.maxPurchasedHours) or 8
		local gems = if type(state) == "table" then tonumber(state.gems) or 0 else 0
		local hourCost = VaultCatalog.gemCostForHours(1) or 5
		local buyable = tonumber(v.buyableHours) or 0
		local atPurchaseCap = maxHours > 0 and ownedHours >= maxHours

		local unclaimed = tonumber(v.unclaimed) or 0
		local claimable = tonumber(v.claimableSeconds) or 0
		local capacity = tonumber(v.capacitySeconds) or 14400
		local rate = tonumber(v.ratePerSec) or 0
		local eff = tonumber(v.efficiency) or 0.50
		local hasVip = v.hasVip == true
		local atCap = v.atCapacity == true

		heroAmount.Text = "$" .. Format.formatNumber(unclaimed)
		ntbAmount.Text = "$" .. Format.formatNumber(unclaimed)

		r1Val.Text = if rate > 0 then string.format("+$%.2f / sec", rate) else "$0.00 / sec"
		r2Val.Text = string.format("%d%% %s", math.floor(eff * 100), if hasVip then "VIP" else "Standard")
		r3Val.Text = string.format("%s stored", formatDuration(claimable))
		r4Val.Text = if hasVip then "1.50x VIP Active" else "1.00x Normal"
		r5Val.Text = if atCap then "Full (Stopped)" elseif rate <= 0 then "Need First Roll" else "Active (Earning)"

		gcDuration.Text = string.format("%s / %s", formatDuration(claimable), formatDuration(capacity))

		local frac = if capacity > 0 then math.clamp(claimable / capacity, 0, 1) else 0
		gcFill.Size = UDim2.fromScale(frac, 1)

		if atCap then
			gcFill.BackgroundColor3 = VAULT_THEME.RedAlert
			hpStatusSub.Text = "VAULT FULL • CLAIM REWARDS TO CONTINUE"
			hpStatusSub.TextColor3 = VAULT_THEME.RedAlert
			gcSub.Text = "100% Full • Storage Full"
			gcSub2.Text = "Maximum storage reached; no new income."
			claimVaultBtn.Active = true
			claimVaultBtn.AutoButtonColor = true
			claimVaultBtn.BackgroundColor3 = VAULT_THEME.GoldPrimary
			claimVaultBtn.TextColor3 = VAULT_THEME.TextDark
			claimVaultBtn.Text = "CLAIM FULL VAULT"
		elseif rate <= 0 then
			gcFill.BackgroundColor3 = VAULT_THEME.TextSubtle
			hpStatusSub.Text = "Roll dice to start generating offline cash"
			hpStatusSub.TextColor3 = VAULT_THEME.TextMuted
			gcSub.Text = "No active earning rate set"
			gcSub2.Text = string.format("Holds up to %s of earnings.", formatDuration(capacity))
			claimVaultBtn.Active = false
			claimVaultBtn.AutoButtonColor = false
			claimVaultBtn.BackgroundColor3 = VAULT_THEME.ButtonDark
			claimVaultBtn.TextColor3 = VAULT_THEME.TextMuted
			claimVaultBtn.Text = "ROLL DICE FIRST"
		else
			gcFill.BackgroundColor3 = VAULT_THEME.GoldBurnished
			hpStatusSub.Text = string.format("Earning Offline • Rate: +$%.2f/sec", rate)
			hpStatusSub.TextColor3 = VAULT_THEME.GreenSuccess
			gcSub.Text = string.format("%d%% Full • Actively Earning", math.floor(frac * 100))
			local remSec = math.max(0, capacity - claimable)
			gcSub2.Text = string.format("%s left until vault is full", formatDuration(remSec))

			local canClaim = unclaimed > 0
			claimVaultBtn.Active = canClaim
			claimVaultBtn.AutoButtonColor = canClaim
			claimVaultBtn.BackgroundColor3 = if canClaim then VAULT_THEME.GoldPrimary else VAULT_THEME.ButtonDark
			claimVaultBtn.TextColor3 = if canClaim then VAULT_THEME.TextDark else VAULT_THEME.TextMuted
			claimVaultBtn.Text = if canClaim then "CLAIM VAULT CASH" else "NO CASH TO CLAIM"
		end

		if atPurchaseCap then
			buyHoursBtn.Active = false
			buyHoursBtn.AutoButtonColor = false
			buyHoursBtn.Text = string.format("MAX UPGRADED (+%dh)", math.floor(maxHours))
			buyHoursBtn.BackgroundColor3 = VAULT_THEME.ButtonDark
			buyHoursBtn.TextColor3 = VAULT_THEME.TextMuted
			gmcSub.Text = string.format("Max storage upgrade (+%dh) unlocked.", math.floor(maxHours))
		elseif buyable <= 0 and hasVip then
			buyHoursBtn.Active = false
			buyHoursBtn.AutoButtonColor = false
			buyHoursBtn.Text = "INCLUDED WITH VIP"
			buyHoursBtn.BackgroundColor3 = VAULT_THEME.ButtonDark
			buyHoursBtn.TextColor3 = VAULT_THEME.TextMuted
			gmcSub.Text = "VIP covers maximum capacity."
		else
			local canBuy = gems >= hourCost
			buyHoursBtn.Active = canBuy
			buyHoursBtn.AutoButtonColor = canBuy
			buyHoursBtn.Text = string.format("+1 HOUR STORAGE (%d GEMS)", hourCost)
			buyHoursBtn.BackgroundColor3 = VAULT_THEME.ButtonDark
			buyHoursBtn.TextColor3 = if canBuy then VAULT_THEME.TextPrimary else VAULT_THEME.TextMuted
			gmcSub.Text = string.format("+%dh bought / +%dh Max upgrade", math.floor(ownedHours), math.floor(maxHours))
		end
	end

	return refreshVault
end

return buildVaultOverlay
