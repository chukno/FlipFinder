-- FlipFinder: panel docked to the right of the auction house window.
local _, ns = ...

local ROWS, ROW_H, WIDTH = 16, 20, 470
local COLS = {
	{ title = "Item",   width = 150, justify = "LEFT" },
	{ title = "Buy",    width = 70,  justify = "RIGHT" },
	{ title = "Sell",   width = 70,  justify = "RIGHT" },
	{ title = "Qty",    width = 36,  justify = "RIGHT" },
	{ title = "Profit", width = 76,  justify = "RIGHT" },
	{ title = "Conf",   width = 40,  justify = "CENTER" },
}

local panel, rows, offset, sorted = nil, {}, 0, {}

local function Sorted()
	wipe(sorted)
	for _, f in pairs(ns.flips) do table.insert(sorted, f) end
	table.sort(sorted, function(a, b)
		if (a.isCheck and true or false) ~= (b.isCheck and true or false) then return not a.isCheck end
		return a.profit > b.profit
	end)
	return sorted
end

local function ShortMoney(c)
	if not c then return "?" end
	if c >= 10000 then
		local g = c / 10000
		return string.format(g >= 100 and "%dg" or "%.1fg", g)
	elseif c >= 100 then
		return string.format("%ds", math.floor(c / 100))
	end
	return string.format("%dc", c)
end

local function ShowTooltip(row)
	local f = row.flip
	if not f then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if f.link then
		GameTooltip:SetHyperlink(f.link)
	else
		GameTooltip:SetItemByID(f.itemID)
	end
	GameTooltip:AddLine(" ")
	if f.isCheck then
		GameTooltip:AddLine("Possible flip (only the cheapest price is known).", 1, 0.82, 0)
		GameTooltip:AddLine("Click to search it and get the full numbers.", 0.8, 0.8, 0.8)
	else
		GameTooltip:AddDoubleLine("Buy", string.format("%d unit(s), up to %s each", f.qty, ns.Money(f.buyMax)), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Average buy price", ns.Money(f.buyAvg), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Total cost", ns.Money(f.cost), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Relist each at", ns.Money(f.sell), 1, 1, 1, 0.2, 1, 0.6)
		GameTooltip:AddDoubleLine("Deposit (estimate)", ns.Money(f.deposit), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Profit", string.format("%s (%d%%)", ns.Money(f.profit), f.pct), 1, 1, 1, 0.2, 1, 0.2)
	if f.ref then
		GameTooltip:AddDoubleLine("Market price", ns.Money(f.ref), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Based on", string.format("%s, %d day(s) of data", f.source or "?", f.samples or 0),
		0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Click: open it in the auction house. You buy by hand.", 0.5, 0.8, 1)
	GameTooltip:Show()
end

local function UpdateRows()
	if not panel or not panel:IsShown() then return end
	local list = Sorted()
	local maxOffset = math.max(0, #list - ROWS)
	if offset > maxOffset then offset = maxOffset end
	for i = 1, ROWS do
		local row = rows[i]
		local f = list[i + offset]
		row.flip = f
		if f then
			row.icon:SetTexture(f.icon or 134400)
			local color = f.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[f.quality]
			row.cells[1]:SetText(f.name)
			if color then row.cells[1]:SetTextColor(color.r, color.g, color.b) else row.cells[1]:SetTextColor(1, 1, 1) end
			row.cells[2]:SetText(ShortMoney(f.isCheck and f.buyMin or f.buyMax))
			row.cells[3]:SetText(ShortMoney(f.sell))
			row.cells[4]:SetText(f.qty and tostring(f.qty) or "?")
			row.cells[5]:SetText(ShortMoney(f.profit) .. (f.isCheck and "/u" or ""))
			row.cells[6]:SetText(f.conf)
			row:Show()
		else
			row:Hide()
		end
	end
	local checked = 0
	for _, f in ipairs(list) do if not f.isCheck then checked = checked + 1 end end
	if #list == 0 then
		panel.status:SetText("No flips yet. Search the auction house as usual; underpriced listings show up here.")
	else
		panel.status:SetText(string.format("%d flip(s), %d possible. Scroll for more.", checked, #list - checked))
	end
	panel.snipe:SetText(ns.snipeQueue and string.format("Searching (%d)", #ns.snipeQueue) or "Search watchlist")
end

function ns.RefreshUI()
	UpdateRows()
end

local function CreatePanel()
	local ah = AuctionHouseFrame
	panel = CreateFrame("Frame", "FlipFinderPanel", ah, "BackdropTemplate")
	panel:SetSize(WIDTH, ROWS * ROW_H + 92)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, 0)
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	panel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		UpdateRows()
	end)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("FlipFinder")

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function()
		ns.s.shown = false
		panel:Hide()
		ns.Print("Panel hidden. Type /ff to show it again.")
	end)

	local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	clear:SetSize(60, 20)
	clear:SetPoint("TOPRIGHT", -30, -8)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function()
		wipe(ns.flips)
		offset = 0
		UpdateRows()
	end)

	local snipe = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	snipe:SetSize(130, 20)
	snipe:SetPoint("RIGHT", clear, "LEFT", -4, 0)
	snipe:SetScript("OnClick", function() ns.StartSnipe() end)
	panel.snipe = snipe

	-- Column headers
	local x = 30
	for i, col in ipairs(COLS) do
		local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		h:SetPoint("TOPLEFT", x, -38)
		h:SetWidth(col.width)
		h:SetJustifyH(col.justify)
		h:SetText(col.title)
		h:SetTextColor(1, 0.82, 0)
		x = x + col.width + 6
	end

	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, panel)
		row:SetSize(WIDTH - 20, ROW_H)
		row:SetPoint("TOPLEFT", 10, -52 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ROW_H - 4, ROW_H - 4)
		row.icon:SetPoint("LEFT", 2, 0)
		row.cells = {}
		local cx = 20
		for c, col in ipairs(COLS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(col.width)
			fs:SetJustifyH(col.justify)
			fs:SetWordWrap(false)
			row.cells[c] = fs
			cx = cx + col.width + 6
		end
		row:SetScript("OnClick", function(self)
			if self.flip then ns.OpenFlip(self.flip) end
		end)
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		rows[i] = row
	end

	local status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	status:SetPoint("BOTTOMLEFT", 12, 12)
	status:SetPoint("BOTTOMRIGHT", -12, 12)
	status:SetJustifyH("LEFT")
	panel.status = status
end

function ns.ShowPanel(force)
	if not AuctionHouseFrame then return end
	if force then ns.s.shown = true end
	if not ns.s.shown then return end
	if not panel then CreatePanel() end
	panel:Show()
	UpdateRows()
end

function ns.HidePanel()
	if panel then panel:Hide() end
end

function ns.TogglePanel()
	if panel and panel:IsShown() then
		ns.s.shown = false
		panel:Hide()
	elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		ns.ShowPanel(true)
	else
		ns.s.shown = true
		ns.Print("The panel will show next to the auction house when you open it.")
	end
end
