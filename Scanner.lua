-- FlipFinder: listens to auction house search results, records prices, and finds flips.
-- Read-only: it never buys, bids, or posts. Watchlist searches only run after a button press.
local _, ns = ...

local function ItemKeyInfo(itemKey)
	if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo) then return nil end
	local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
	return ok and info or nil
end

local function BuildInfo(itemKey, isCommodity, link)
	local ki = ItemKeyInfo(itemKey)
	if isCommodity == nil then
		if not ki then return nil end
		isCommodity = ki.isCommodity
	end
	local name, icon, quality
	if ki then
		name, icon, quality = ki.itemName, ki.iconFileID, ki.quality
	end
	if not name then
		local n, l, q, _, _, _, _, _, _, tex = ns.GetItemInfoCompat(itemKey.itemID)
		name, icon, quality = n, tex, q
		link = link or l
	end
	return {
		itemKey = itemKey,
		itemID = itemKey.itemID,
		isCommodity = isCommodity and true or false,
		key = ns.KeyFor(itemKey, isCommodity),
		name = name or ("item:" .. itemKey.itemID),
		icon = icon,
		quality = quality,
		link = link,
	}
end

-- listName: "flips" or "vendor"
local function Store(listName, info, flip)
	local list = ns.lists[listName]
	if flip then
		for k, v in pairs(info) do flip[k] = v end
		flip.time = GetTime()
		-- A quick browse-only guess never replaces a fully checked entry.
		local old = list[info.key]
		if flip.isCheck and old and not old.isCheck then return end
		list[info.key] = flip
	end
	ns.RefreshUI()
end

local function Remove(listName, key, onlyChecks)
	local list = ns.lists[listName]
	local old = list[key]
	if old and (not onlyChecks or old.isCheck) then
		list[key] = nil
		ns.RefreshUI()
	end
end

-- Judge full listings for both lists, then record today's lowest price.
local function Judge(info, listings)
	local flip = ns.Evaluate(info, listings)
	if flip then Store("flips", info, flip) else Remove("flips", info.key) end
	local vend = ns.EvaluateVendor(info, listings)
	if vend then Store("vendor", info, vend) else Remove("vendor", info.key) end
	ns.RecordPrice(info.key, listings[1].unit)
end

------------------------------------------------------------------------
-- Commodities (stackable goods: herbs, ore, cloth...)
------------------------------------------------------------------------
local function OnCommodityResults(itemID)
	if not ns.db or not itemID then return end
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	if n == 0 then return end
	local listings = {}
	for i = 1, n do
		local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if r and r.unitPrice and r.unitPrice > 0 then
			local qty = (r.quantity or 0) - (r.numOwnerItems or 0)
			if qty > 0 then
				table.insert(listings, { unit = r.unitPrice, qty = qty })
			end
		end
	end
	if #listings == 0 then return end
	table.sort(listings, function(a, b) return a.unit < b.unit end)

	local itemKey = C_AuctionHouse.MakeItemKey(itemID)
	Judge(BuildInfo(itemKey, true), listings)
end

------------------------------------------------------------------------
-- Items (gear, pets, anything not stackable)
------------------------------------------------------------------------
local function OnItemResults(itemKey)
	if not ns.db or not itemKey then return end
	local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
	if n == 0 then return end
	local listings, link = {}, nil
	for i = 1, n do
		local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
			local qty = math.max(r.quantity or 1, 1)
			table.insert(listings, { unit = math.floor(r.buyoutAmount / qty), qty = qty })
			link = link or r.itemLink
		end
	end
	if #listings == 0 then return end
	table.sort(listings, function(a, b) return a.unit < b.unit end)

	Judge(BuildInfo(itemKey, false, link), listings)
end

------------------------------------------------------------------------
-- Browse results (the list you get from typing in the search bar)
------------------------------------------------------------------------
local pendingKeys = {} -- items whose name/commodity info was not cached yet

local function HandleBrowseResult(r)
	if not r or not r.itemKey or not r.minPrice or r.minPrice <= 0 then return end
	if r.containsOwnerItem and (r.totalQuantity or 0) <= 1 then return end
	local info = BuildInfo(r.itemKey)
	if not info then
		pendingKeys[r.itemKey.itemID] = r
		return
	end
	local flip = ns.EvaluateBrowse(info, r.minPrice, r.totalQuantity)
	if flip then Store("flips", info, flip) else Remove("flips", info.key, true) end
	local vend = ns.EvaluateVendorBrowse(info, r.minPrice, r.totalQuantity)
	if vend then Store("vendor", info, vend) else Remove("vendor", info.key, true) end
	ns.RecordPrice(info.key, r.minPrice)
end

local function OnBrowseUpdated()
	if not ns.db then return end
	local results = C_AuctionHouse.GetBrowseResults()
	if not results then return end
	for _, r in ipairs(results) do HandleBrowseResult(r) end
end

local function OnBrowseAdded(added)
	if not ns.db or not added then return end
	for _, r in ipairs(added) do HandleBrowseResult(r) end
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowseUpdated)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowseAdded)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
ns.On("COMMODITY_SEARCH_RESULTS_ADDED", OnCommodityResults)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey) OnItemResults(itemKey) end)
ns.On("ITEM_SEARCH_RESULTS_ADDED", OnItemResults)
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", function(itemID)
	local r = pendingKeys[itemID]
	if r then
		pendingKeys[itemID] = nil
		HandleBrowseResult(r)
	end
end)

ns.On("AUCTION_HOUSE_SHOW", function()
	ns.snapshots = {} -- take fresh Auctionator snapshots each visit
	-- Wait a frame so Blizzard's auction house window exists before docking to it.
	C_Timer.After(0, function() ns.ShowPanel() end)
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	ns.snipeQueue = nil
	ns.HidePanel()
end)

------------------------------------------------------------------------
-- Opening a flip in the auction house so you can buy it by hand
------------------------------------------------------------------------
function ns.OpenFlip(flip)
	local ah = AuctionHouseFrame
	if not (ah and ah:IsShown()) then
		ns.Print("Open the auction house first.")
		return
	end
	if not flip.isVendor then ns.TrackFlip(flip) end
	local ok = false
	if ah.SelectBrowseResult and ItemKeyInfo(flip.itemKey) then
		ok = pcall(ah.SelectBrowseResult, ah, { itemKey = flip.itemKey, minPrice = flip.buyMin or 0 })
	end
	if not ok and ah.SearchBar and ah.SearchBar.SetSearchText then
		ah.SearchBar:SetSearchText(flip.name)
		ah.SearchBar:StartSearch()
	end
end

------------------------------------------------------------------------
-- Watchlist "snipe": one button press re-searches the watchlist,
-- one query at a time, waiting for the server's throttle each time.
------------------------------------------------------------------------
local function PriceSorts()
	local order = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
	return { { sortOrder = order, reverseSort = false } }
end

local function SendNext()
	local q = ns.snipeQueue
	if not q then return end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		ns.snipeQueue = nil
		return
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end -- resumes on THROTTLED_SYSTEM_READY

	local entry = table.remove(q, 1)
	if not entry then
		ns.snipeQueue = nil
		ns.Print("Watchlist search done.")
		ns.RefreshUI()
		return
	end
	local _, _, _, _, _, _, _, stack = ns.GetItemInfoCompat(entry.id)
	if stack and stack > 1 then
		C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(entry.id), PriceSorts(), true)
	else
		C_AuctionHouse.SendBrowseQuery({
			searchString = entry.name or "",
			sorts = PriceSorts(),
			filters = {},
			itemClassFilters = {},
		})
	end
	ns.RefreshUI()
	-- Small gap between queries on top of the server throttle.
	C_Timer.After(1.5, SendNext)
end

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
	if ns.snipeQueue then C_Timer.After(0.2, SendNext) end
end)

function ns.StartSnipe()
	if ns.snipeQueue then
		ns.Print("Watchlist search already running.")
		return
	end
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
		ns.Print("Open the auction house first.")
		return
	end
	local list = ns.db.watchlist
	if #list == 0 then
		ns.Print("Your watchlist is empty. Add items with /ff watch add [item link]")
		return
	end
	ns.snipeQueue = {}
	for i = 1, math.min(#list, 25) do
		table.insert(ns.snipeQueue, list[i])
	end
	ns.Print(string.format("Searching %d watchlist item(s)...", #ns.snipeQueue))
	SendNext()
end
