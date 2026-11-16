-- FlipFinder: panel docked to the right of the auction house window.
-- Built from Blizzard's own templates and auction house art where the client has them,
-- with plain fallbacks so it still works if a template or atlas is missing.
local _, ns = ...

local ROW_H, WIDTH, GAP = 22, 600, 4

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function HasTemplate(name)
	if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
		return C_XMLUtil.GetTemplateInfo(name) ~= nil
	end
	return false
end

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Font(preferred, fallback)
	return _G[preferred] and preferred or fallback
end

local MONEY_FONT = Font("Number14FontWhite", "GameFontHighlight")
local NAME_FONT = Font("GameFontHighlight", "GameFontHighlightSmall")

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

-- Money with coin icons, trimmed to stay readable in a narrow column.
local function CoinText(c)
	if not c then return "?" end
	c = math.floor(c + 0.5)
	local g = math.floor(c / 10000)
	local s = math.floor((c % 10000) / 100)
	local cp = c % 100
	if g >= 1000 then
		return (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. GOLD
	elseif g > 0 then
		return g .. GOLD .. " " .. s .. SILVER
	elseif s > 0 then
		return s .. SILVER .. " " .. cp .. COPPER
	end
	return cp .. COPPER
end

local CONF_COLOR = {
	High = "|cff33ff33", Med = "|cffffd100", Low = "|cffff8040", Safe = "|cff33ff33", ["?"] = "|cff9d9d9d",
}
local CONF_RANK = { Safe = 4, High = 3, Med = 2, Low = 1, ["?"] = 0 }

------------------------------------------------------------------------
-- Tabs and columns
------------------------------------------------------------------------
local TABS = {
	{
		list = "flips", title = "Flips", sortKey = "sortFlipsKey", sortDesc = "sortFlipsDesc",
		empty = "No flips yet. Search the auction house as usual; underpriced listings show up here.",
		cols = {
			{ title = "Item",   key = "name",   width = 150, justify = "LEFT" },
			{ title = "Buy",    key = "buy",    width = 80,  justify = "RIGHT" },
			{ title = "Sell",   key = "sell",   width = 80,  justify = "RIGHT" },
			{ title = "Qty",    key = "qty",    width = 36,  justify = "RIGHT" },
			{ title = "Profit", key = "profit", width = 84,  justify = "RIGHT" },
			{ title = "%",      key = "pct",    width = 40,  justify = "RIGHT" },
			{ title = "Conf",   key = "conf",   width = 40,  justify = "CENTER" },
		},
	},
	{
		list = "vendor", title = "Below vendor", sortKey = "sortVendorKey", sortDesc = "sortVendorDesc",
		empty = "Nothing below vendor price yet. Listings you can buy and sell to a merchant for a profit show up here.",
		cols = {
			{ title = "Item",   key = "name",   width = 170, justify = "LEFT" },
			{ title = "Buy",    key = "buy",    width = 84,  justify = "RIGHT" },
			{ title = "Vendor", key = "sell",   width = 84,  justify = "RIGHT" },
			{ title = "Qty",    key = "qty",    width = 40,  justify = "RIGHT" },
			{ title = "Profit", key = "profit", width = 88,  justify = "RIGHT" },
			{ title = "%",      key = "pct",    width = 44,  justify = "RIGHT" },
		},
	},
}

local function SortValue(f, key)
	if key == "name" then return (f.name or ""):lower() end
	if key == "buy" then return f.isCheck and f.buyMin or f.buyMax or 0 end
	if key == "qty" then return f.qty or 0 end
	if key == "conf" then return CONF_RANK[f.conf] or 0 end
	return f[key] or 0
end

local function CellText(f, key)
	if key == "name" then return f.name end
	if key == "buy" then return CoinText(f.isCheck and f.buyMin or f.buyMax) end
	if key == "sell" then return CoinText(f.sell) end
	if key == "qty" then return f.qty and tostring(f.qty) or "?" end
	if key == "profit" then return CoinText(f.profit) .. (f.isCheck and "|cff9d9d9d/ea|r" or "") end
	if key == "pct" then return string.format("%d%%", math.floor(f.pct or 0)) end
	if key == "conf" then return (CONF_COLOR[f.conf] or "") .. (f.conf or "") .. "|r" end
	return ""
end

local panel, rows, headers, offset, sorted = nil, {}, {}, 0, {}
local numRows = 16

local function CurrentTab() return TABS[ns.s.tab] or TABS[1] end

local function Sorted()
	wipe(sorted)
	local tab = CurrentTab()
	for _, f in pairs(ns.lists[tab.list]) do table.insert(sorted, f) end
	local key, desc = ns.s[tab.sortKey], ns.s[tab.sortDesc]
	table.sort(sorted, function(a, b)
		-- Fully checked entries first, "possible" ones (only cheapest price known) after.
		if (a.isCheck and true or false) ~= (b.isCheck and true or false) then return not a.isCheck end
		local va, vb = SortValue(a, key), SortValue(b, key)
		if va == vb then return (a.profit or 0) > (b.profit or 0) end
		if desc then return va > vb end
		return va < vb
	end)
	return sorted
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
local function ShowTooltip(row)
	local f = row.flip
	if not f then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if f.link then GameTooltip:SetHyperlink(f.link) else GameTooltip:SetItemByID(f.itemID) end
	GameTooltip:AddLine(" ")
	local W = { 1, 1, 1, 1, 1, 1 }
	if f.isCheck then
		GameTooltip:AddLine("Possible " .. (f.isVendor and "vendor buy" or "flip") .. ": only the cheapest price is known.", 1, 0.82, 0)
		GameTooltip:AddLine("Click to search it and get the full numbers.", 0.8, 0.8, 0.8)
	else
		GameTooltip:AddDoubleLine("Buy", string.format("%d unit(s), up to %s each", f.qty, ns.Money(f.buyMax)), unpack(W))
		GameTooltip:AddDoubleLine("Average buy price", ns.Money(f.buyAvg), unpack(W))
		GameTooltip:AddDoubleLine("Total cost", ns.Money(f.cost), unpack(W))
		if f.isVendor then
			GameTooltip:AddDoubleLine("Sell to a merchant for", ns.Money(f.sell) .. " each", 1, 1, 1, 0.2, 1, 0.6)
		else
			GameTooltip:AddDoubleLine("Relist each at", ns.Money(f.sell), 1, 1, 1, 0.2, 1, 0.6)
			GameTooltip:AddDoubleLine("Deposit (estimate)", ns.Money(f.deposit), unpack(W))
		end
	end
	GameTooltip:AddDoubleLine("Profit", string.format("%s (%d%%)", ns.Money(f.profit), math.floor(f.pct or 0)),
		1, 1, 1, 0.2, 1, 0.2)
	if not f.isVendor then
		if f.ref then GameTooltip:AddDoubleLine("Market price", ns.Money(f.ref), unpack(W)) end
		GameTooltip:AddDoubleLine("Based on", string.format("%s, %d day(s) of data", f.source or "?", f.samples or 0),
			0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Click: open it in the auction house. You buy by hand.", 0.5, 0.8, 1)
	GameTooltip:Show()
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local function LayoutColumns()
	local tab = CurrentTab()
	local ROW_X = 4                  -- rows sit 4px inside the list frame
	local x = 6 + ROW_H + GAP        -- first text column starts after the icon
	for i = 1, 7 do
		local col, h = tab.cols[i], headers[i]
		if col then
			h:ClearAllPoints()
			if i == 1 then
				-- The Item header also spans the icon.
				h:SetPoint("TOPLEFT", panel.listFrame, "TOPLEFT", ROW_X, -4)
				h:SetWidth(x + col.width)
			else
				h:SetPoint("TOPLEFT", panel.listFrame, "TOPLEFT", ROW_X + x, -4)
				h:SetWidth(col.width)
			end
			h:SetText(col.title)
			local fs = h:GetFontString()
			if fs then fs:SetJustifyH(col.justify) end
			h.key = col.key
			local sortKey = ns.s[tab.sortKey]
			if sortKey == col.key then
				h.arrow:Show()
				-- Arrow atlas points down; flip it for ascending.
				if ns.s[tab.sortDesc] then h.arrow:SetTexCoord(0, 1, 0, 1) else h.arrow:SetTexCoord(0, 1, 1, 0) end
			else
				h.arrow:Hide()
			end
			h:Show()
			for _, row in ipairs(rows) do
				local cell = row.cells[i]
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", row, "LEFT", x, 0)
				cell:SetWidth(col.width - 2)
				cell:SetJustifyH(col.justify)
				cell:Show()
			end
			x = x + col.width + GAP
		else
			h:Hide()
			for _, row in ipairs(rows) do row.cells[i]:Hide() end
		end
	end
end

local function UpdateTabs()
	if not panel.tabs then return end
	for i, tab in ipairs(TABS) do
		local n = 0
		for _ in pairs(ns.lists[tab.list]) do n = n + 1 end
		local btn = panel.tabs[i]
		btn:SetText(n > 0 and string.format("%s (%d)", tab.title, n) or tab.title)
		if PanelTemplates_TabResize and btn.usesBlizzardTab then pcall(PanelTemplates_TabResize, btn, 0) end
	end
	if panel.usesBlizzardTabs and PanelTemplates_SetTab then
		pcall(PanelTemplates_SetTab, panel, ns.s.tab)
	else
		for i, btn in ipairs(panel.tabs) do
			if i == ns.s.tab then btn:LockHighlight() else btn:UnlockHighlight() end
		end
	end
end

local function UpdateRows()
	if not panel or not panel:IsShown() then return end
	local tab = CurrentTab()
	local list = Sorted()
	local maxOffset = math.max(0, #list - numRows)
	if offset > maxOffset then offset = maxOffset end
	for i, row in ipairs(rows) do
		local f = list[i + offset]
		row.flip = f
		if f and i <= numRows then
			row.icon:SetTexture(f.icon or 134400)
			for c, col in ipairs(tab.cols) do
				row.cells[c]:SetText(CellText(f, col.key))
			end
			local color = f.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[f.quality]
			if color then row.cells[1]:SetTextColor(color.r, color.g, color.b) else row.cells[1]:SetTextColor(1, 1, 1) end
			row:SetAlpha(f.isCheck and 0.75 or 1)
			row:Show()
		else
			row:Hide()
		end
	end
	UpdateTabs()

	if #list == 0 then
		panel.empty:SetText(tab.empty)
		panel.empty:Show()
		panel.status:SetText("")
	else
		panel.empty:Hide()
		local checked = 0
		for _, f in ipairs(list) do if not f.isCheck then checked = checked + 1 end end
		local range = #list > numRows
			and string.format("   Showing %d-%d (scroll for more)", offset + 1, math.min(offset + numRows, #list)) or ""
		panel.status:SetText(string.format("%d confirmed, %d possible.%s", checked, #list - checked, range))
	end
	panel.snipe:SetText(ns.snipeQueue and string.format("Searching (%d)", #ns.snipeQueue) or "Search watchlist")
end

function ns.RefreshUI()
	UpdateRows()
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
local function SetTab(i)
	ns.s.tab = i
	offset = 0
	LayoutColumns()
	UpdateRows()
end

local function OnHeaderClick(h)
	local tab = CurrentTab()
	if ns.s[tab.sortKey] == h.key then
		ns.s[tab.sortDesc] = not ns.s[tab.sortDesc]
	else
		ns.s[tab.sortKey] = h.key
		ns.s[tab.sortDesc] = (h.key ~= "name") -- names A-Z, numbers biggest first
	end
	offset = 0
	LayoutColumns()
	UpdateRows()
end

local function CreateMainFrame(ah)
	local f
	if HasTemplate("ButtonFrameTemplate") then
		f = CreateFrame("Frame", "FlipFinderPanel", ah, "ButtonFrameTemplate")
		if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
		if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
		if f.SetTitle then f:SetTitle("FlipFinder")
		elseif f.TitleText then f.TitleText:SetText("FlipFinder") end
		f.listFrame = f.Inset
	else
		f = CreateFrame("Frame", "FlipFinderPanel", ah, "BackdropTemplate")
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", 0, -10)
		title:SetText("FlipFinder")
		f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		f.CloseButton:SetPoint("TOPRIGHT", -2, -2)
		f.listFrame = CreateFrame("Frame", nil, f, HasTemplate("InsetFrameTemplate") and "InsetFrameTemplate" or nil)
	end
	return f
end

local function CreatePanel()
	local ah = AuctionHouseFrame
	panel = CreateMainFrame(ah)
	local height = math.max(ah:GetHeight() or 538, 420)
	panel:SetSize(WIDTH, height)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 2, 0)
	panel:SetFrameStrata(ah:GetFrameStrata())
	panel:EnableMouse(true)
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		UpdateRows()
	end)
	if panel.CloseButton then
		panel.CloseButton:SetScript("OnClick", function()
			ns.s.shown = false
			panel:Hide()
			ns.Print("Panel hidden. Type /ff to show it again.")
		end)
	end

	-- List area (inset), leaving room on top for tabs and at the bottom for status.
	local lf = panel.listFrame
	lf:ClearAllPoints()
	lf:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -58)
	lf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 28)
	if HasAtlas("auctionhouse-background-index") then
		local bg = lf:CreateTexture(nil, "BACKGROUND", nil, 1)
		bg:SetAtlas("auctionhouse-background-index")
		bg:SetPoint("TOPLEFT", 3, -3)
		bg:SetPoint("BOTTOMRIGHT", -3, 3)
	end

	-- Tabs
	panel.tabs = {}
	local useTabs = HasTemplate("PanelTopTabButtonTemplate")
	panel.usesBlizzardTabs = useTabs
	for i, tab in ipairs(TABS) do
		local btn
		if useTabs then
			btn = CreateFrame("Button", "FlipFinderPanelTab" .. i, panel, "PanelTopTabButtonTemplate")
			btn.usesBlizzardTab = true
		else
			btn = CreateFrame("Button", "FlipFinderPanelTab" .. i, panel, "UIPanelButtonTemplate")
			btn:SetSize(130, 22)
		end
		btn:SetID(i)
		btn:SetText(tab.title)
		if i == 1 then
			btn:SetPoint("BOTTOMLEFT", lf, "TOPLEFT", 6, 0)
		else
			btn:SetPoint("LEFT", panel.tabs[i - 1], "RIGHT", useTabs and 0 or 4, 0)
		end
		btn:SetScript("OnClick", function(self)
			if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
			SetTab(self:GetID())
		end)
		panel.tabs[i] = btn
	end
	panel.Tabs = panel.tabs
	if useTabs and PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, panel, #TABS) end

	-- Buttons on the tab line, right side
	local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	clear:SetSize(64, 22)
	clear:SetPoint("BOTTOMRIGHT", lf, "TOPRIGHT", -2, 4)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function()
		wipe(ns.lists[CurrentTab().list])
		offset = 0
		UpdateRows()
	end)
	local snipe = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	snipe:SetSize(130, 22)
	snipe:SetPoint("RIGHT", clear, "LEFT", -4, 0)
	snipe:SetScript("OnClick", function() ns.StartSnipe() end)
	snipe:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Search watchlist")
		GameTooltip:AddLine("Searches each item on your watchlist once. Add items with /ff watch add [item].", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	snipe:SetScript("OnLeave", GameTooltip_Hide)
	panel.snipe = snipe

	-- Sortable column headers
	local headerTemplate = HasTemplate("ColumnDisplayButtonShortTemplate") and "ColumnDisplayButtonShortTemplate" or nil
	for i = 1, 7 do
		local h = CreateFrame("Button", nil, lf, headerTemplate)
		h:SetHeight(20)
		h:SetNormalFontObject("GameFontHighlightSmall")
		h:SetHighlightFontObject("GameFontHighlightSmall")
		h:SetText(" ")
		if not headerTemplate then
			local hl = h:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.08)
		end
		local fs = h:GetFontString()
		if fs then
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", 4, 0)
			fs:SetPoint("RIGHT", -12, 0)
		end
		h.arrow = h:CreateTexture(nil, "OVERLAY")
		if HasAtlas("auctionhouse-ui-sortarrow") then
			h.arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
		else
			h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
			h.arrow:SetSize(9, 8)
		end
		h.arrow:SetPoint("RIGHT", -3, 0)
		h:SetScript("OnClick", OnHeaderClick)
		h:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine("Click to sort, click again to reverse")
			GameTooltip:Show()
		end)
		h:SetScript("OnLeave", GameTooltip_Hide)
		headers[i] = h
	end

	-- Rows
	local listTop = 28
	local listHeight = height - 58 - 28 -- matches the inset anchors above
	numRows = math.max(8, math.floor((listHeight - listTop - 4) / ROW_H))
	local stripe = HasAtlas("auctionhouse-rowstripe-1")
	local highlight = HasAtlas("auctionhouse-ui-row-highlight")
	for i = 1, numRows do
		local row = CreateFrame("Button", nil, lf)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", lf, "TOPLEFT", 4, -listTop - (i - 1) * ROW_H)
		row:SetPoint("RIGHT", lf, "RIGHT", -4, 0)
		if i % 2 == 0 then
			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			if stripe then bg:SetAtlas("auctionhouse-rowstripe-1") else bg:SetColorTexture(1, 1, 1, 0.04) end
		end
		if highlight then
			row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")
		else
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		end
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ROW_H - 4, ROW_H - 4)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.cells = {}
		for c = 1, 7 do
			local fs = row:CreateFontString(nil, "OVERLAY", c == 1 and NAME_FONT or MONEY_FONT)
			fs:SetWordWrap(false)
			row.cells[c] = fs
		end
		row:SetScript("OnClick", function(self)
			if self.flip then ns.OpenFlip(self.flip) end
		end)
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
		rows[i] = row
	end

	local empty = lf:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOPLEFT", 30, -80)
	empty:SetPoint("TOPRIGHT", -30, -80)
	empty:SetJustifyH("CENTER")
	empty:SetSpacing(4)
	panel.empty = empty

	local status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("BOTTOMLEFT", 14, 10)
	status:SetPoint("BOTTOMRIGHT", -14, 10)
	status:SetJustifyH("LEFT")
	panel.status = status

	LayoutColumns()
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
