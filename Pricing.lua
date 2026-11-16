-- FlipFinder: price history, market reference price, and the flip calculation.
local _, ns = ...

local CALLER = "FlipFinder"

-- History key: commodities by item ID, gear and pets by the full item key.
function ns.KeyFor(itemKey, isCommodity)
	if (itemKey.battlePetSpeciesID or 0) > 0 then
		return "p" .. itemKey.battlePetSpeciesID
	end
	if isCommodity or (itemKey.itemLevel or 0) == 0 then
		return tostring(itemKey.itemID)
	end
	return string.format("%d:%d:%d", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix or 0)
end

function ns.PruneHistory()
	local cutoff = ns.Today() - 45
	for key, days in pairs(ns.db.history) do
		local any = false
		for day in pairs(days) do
			if day < cutoff then days[day] = nil else any = true end
		end
		if not any then ns.db.history[key] = nil end
	end
end

-- Remember the lowest unit price seen today for this item.
function ns.RecordPrice(key, unitPrice, day)
	if not unitPrice or unitPrice <= 0 then return end
	day = day or ns.Today()
	local h = ns.db.history[key]
	if not h then
		h = {}
		ns.db.history[key] = h
	end
	if not h[day] or unitPrice < h[day] then
		h[day] = unitPrice
	end
end

local function HasAuctionator()
	return Auctionator and Auctionator.API and Auctionator.API.v1
		and Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
end

local function AuctionatorLookup(itemID, link)
	if not HasAuctionator() then return nil end
	local api = Auctionator.API.v1
	local ok, price, age
	if link and api.GetAuctionPriceByItemLink then
		ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
		if ok and price then
			local ok2, a = pcall(api.GetAuctionAgeByItemLink, CALLER, link)
			age = ok2 and a or nil
			return price, age
		end
	end
	ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
	if not ok or not price then return nil end
	local ok2, a = pcall(api.GetAuctionAgeByItemID, CALLER, itemID)
	age = ok2 and a or nil
	return price, age
end

-- Auctionator overwrites today's price with whatever you just searched, so the
-- first value seen this session is kept as a snapshot. Older Auctionator prices
-- (age >= 1 day) are also copied into FlipFinder's own history.
local function AuctionatorSnapshot(key, itemID, link)
	local snap = ns.snapshots[key]
	if snap ~= nil then return snap or nil end
	local price, age = AuctionatorLookup(itemID, link)
	if price and price > 0 then
		snap = { price = price, age = age or 0, today = (age or 0) == 0 }
		if (age or 0) >= 1 then
			ns.RecordPrice(key, price, ns.Today() - age)
		end
	else
		snap = false
	end
	ns.snapshots[key] = snap
	return snap or nil
end

local function Median(t)
	table.sort(t)
	local n = #t
	if n == 0 then return nil end
	if n % 2 == 1 then return t[(n + 1) / 2] end
	return math.floor((t[n / 2] + t[n / 2 + 1]) / 2)
end

-- Returns refPrice, sampleCount, newestAgeDays, sourceText (or nil if no usable history).
-- Today's own observations are excluded: they include the very listings being judged.
function ns.GetReference(key, itemID, link)
	local s = ns.s
	local today = ns.Today()
	local snap = AuctionatorSnapshot(key, itemID, link)

	local samples, newest = {}, nil
	local h = ns.db.history[key]
	if h then
		for day, price in pairs(h) do
			if day < today and day >= today - s.historyDays then
				table.insert(samples, price)
				local age = today - day
				if not newest or age < newest then newest = age end
			end
		end
	end
	local source = #samples > 0 and "history" or nil

	-- A same-day Auctionator snapshot (e.g. from a full scan earlier today)
	-- counts as one sample, as long as it was taken before we judged listings.
	if snap and snap.today then
		table.insert(samples, snap.price)
		newest = 0
		source = source and "history+Auctionator" or "Auctionator"
	elseif snap and source then
		source = "history+Auctionator"
	elseif snap then
		source = "Auctionator"
	end

	if #samples == 0 then return nil end
	if #samples < s.minSamples then return nil, #samples, newest, "thin" end
	if newest and newest > s.maxAgeDays then return nil, #samples, newest, "stale" end
	return Median(samples), #samples, newest or 0, source
end

-- Deposit for relisting `qty` units. Commodities use the game's calculation;
-- other items use an estimate from the vendor price.
function ns.Deposit(itemID, isCommodity, qty)
	local d = ns.s.duration
	if isCommodity and C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit then
		local ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, d, qty)
		if ok and dep then return dep end
	end
	local vendor = select(11, ns.GetItemInfoCompat(itemID)) or 0
	local mult = ({ 1, 2, 4 })[d] or 2
	return math.floor(vendor * 0.15 * mult * qty)
end

local function Confidence(samples, isCheck)
	if isCheck then return "?" end
	if samples >= 4 then return "High" end
	if samples >= 2 then return "Med" end
	return "Low"
end

-- listings: array of { unit = copper per unit, qty = number }, sorted ascending.
-- Picks how many of the cheapest listings to buy so total profit is largest,
-- where the relist price is just under the next competitor, capped at the
-- market reference price.
function ns.Evaluate(info, listings)
	local s = ns.s
	if #listings == 0 then return nil end
	local ref, samples, newest, source = ns.GetReference(info.key, info.itemID, info.link)
	if not ref and not s.allowNoHistory then return nil, source end

	local best
	local cumQty, cumCost = 0, 0
	local limit = math.min(#listings, 60)
	for k = 1, limit do
		local l = listings[k]
		cumQty = cumQty + l.qty
		cumCost = cumCost + l.unit * l.qty
		if s.maxInvest > 0 and cumCost > s.maxInvest then break end

		local nextL = listings[k + 1]
		local sell
		if nextL then
			sell = nextL.unit - 1
			if ref then sell = math.min(sell, ref) end
		else
			sell = ref
		end
		if not sell then break end

		local deposit = ns.Deposit(info.itemID, info.isCommodity, cumQty)
		local profit = math.floor(sell * cumQty * (1 - s.cut) - deposit - cumCost)
		local pct = cumCost > 0 and (profit / cumCost * 100) or 0
		if profit >= s.minProfit and pct >= s.minPct and (not best or profit > best.profit) then
			best = {
				qty = cumQty, cost = cumCost, buyMax = l.unit, buyMin = listings[1].unit,
				buyAvg = math.floor(cumCost / cumQty), sell = sell, profit = profit, pct = pct,
				deposit = deposit,
			}
		end
	end
	if not best then return nil, source end

	best.ref = ref
	best.samples = samples or 0
	best.source = source or "price gap only"
	best.conf = ref and Confidence(samples or 0) or "Low"
	return best
end

-- Quick check from a browse result (only the cheapest price is known).
function ns.EvaluateBrowse(info, minPrice, totalQuantity)
	local s = ns.s
	local ref, samples, _, source = ns.GetReference(info.key, info.itemID, info.link)
	if not ref then return nil end
	local unitProfit = ref * (1 - s.cut) - ns.Deposit(info.itemID, info.isCommodity, 1) - minPrice
	local pct = unitProfit / minPrice * 100
	if pct < s.minPct then return nil end
	-- Upper bound on profit: we don't know how many units are at the cheap price.
	local bound = unitProfit * (info.isCommodity and math.max(totalQuantity or 1, 1) or 1)
	if bound < s.minProfit then return nil end
	return {
		qty = nil, cost = minPrice, buyMax = minPrice, buyMin = minPrice, buyAvg = minPrice,
		sell = ref, profit = math.floor(unitProfit), pct = pct, ref = ref,
		samples = samples or 0, source = source, conf = Confidence(0, true), isCheck = true,
	}
end

------------------------------------------------------------------------
-- Below vendor price: buy from the AH and sell to any merchant.
-- No AH cut, no deposit, no price history needed.
------------------------------------------------------------------------
function ns.VendorPrice(itemID, link)
	local p = link and select(11, ns.GetItemInfoCompat(link)) or nil
	if not p or p == 0 then
		p = select(11, ns.GetItemInfoCompat(itemID))
	end
	return p or 0
end

function ns.EvaluateVendor(info, listings)
	local vendor = ns.VendorPrice(info.itemID, info.link)
	if vendor <= 0 or #listings == 0 then return nil end
	local qty, cost, buyMax = 0, 0, nil
	for _, l in ipairs(listings) do
		if l.unit >= vendor then break end
		qty = qty + l.qty
		cost = cost + l.unit * l.qty
		buyMax = l.unit
	end
	if qty == 0 then return nil end
	local profit = vendor * qty - cost
	if profit < ns.s.vendorMinProfit then return nil end
	return {
		qty = qty, cost = cost, buyMax = buyMax, buyMin = listings[1].unit,
		buyAvg = math.floor(cost / qty), sell = vendor, profit = profit,
		pct = profit / cost * 100, conf = "Safe", isVendor = true, source = "vendor price",
	}
end

function ns.EvaluateVendorBrowse(info, minPrice, totalQuantity)
	local vendor = ns.VendorPrice(info.itemID, info.link)
	if vendor <= 0 or minPrice >= vendor then return nil end
	local unitProfit = vendor - minPrice
	local bound = unitProfit * (info.isCommodity and math.max(totalQuantity or 1, 1) or 1)
	if bound < ns.s.vendorMinProfit then return nil end
	return {
		qty = nil, cost = minPrice, buyMax = minPrice, buyMin = minPrice, buyAvg = minPrice,
		sell = vendor, profit = unitProfit, pct = unitProfit / minPrice * 100,
		conf = "?", isVendor = true, isCheck = true, source = "vendor price",
	}
end
