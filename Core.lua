-- FlipFinder: core setup, saved variables, shared helpers.
local ADDON, ns = ...

ns.defaults = {
	minProfit      = 50 * 10000, -- copper (50g)
	minPct         = 20,         -- minimum profit as % of money spent
	maxAgeDays     = 3,          -- newest price sample must be at most this old
	historyDays    = 14,         -- how far back price history is used
	minSamples     = 1,          -- days of price data needed before an item is considered
	duration       = 2,          -- relist duration: 1 = 12h, 2 = 24h, 3 = 48h
	cut            = 0.05,       -- auction house cut on sales
	maxInvest      = 0,          -- copper; 0 = no cap on the cost of one flip
	allowNoHistory = false,      -- also flag price gaps for items with no history
	shown          = true,       -- show the panel next to the auction house
}

ns.flips = {}      -- key -> flip entry (this session)
ns.snapshots = {}  -- key -> Auctionator price snapshot (this session)

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then dst[k] = v end
	end
end

function ns.Print(...)
	print("|cff33ff99FlipFinder|r:", ...)
end

function ns.Today()
	return math.floor(GetServerTime() / 86400)
end

-- Compact money string: 1234g 56s / 56s 7c / 7c
function ns.Money(copper)
	if not copper then return "?" end
	local neg = copper < 0
	copper = math.floor(math.abs(copper) + 0.5)
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local out
	if g > 0 then
		out = string.format("|cffffd700%s|rg |cffc7c7cf%d|rs", BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g, s)
	elseif s > 0 then
		out = string.format("|cffc7c7cf%d|rs |cffeda55f%d|rc", s, c)
	else
		out = string.format("|cffeda55f%d|rc", c)
	end
	return neg and ("-" .. out) or out
end

function ns.GetItemInfoCompat(item)
	if C_Item and C_Item.GetItemInfo then
		return C_Item.GetItemInfo(item)
	end
	return GetItemInfo(item)
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame
ns.handlers = {}

function ns.On(event, fn)
	local list = ns.handlers[event]
	if not list then
		list = {}
		ns.handlers[event] = list
		-- Unknown events (e.g. on a client without them) are skipped instead of erroring.
		pcall(frame.RegisterEvent, frame, event)
	end
	table.insert(list, fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = ns.handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end)

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	FlipFinderDB = FlipFinderDB or {}
	local db = FlipFinderDB
	db.settings = db.settings or {}
	CopyDefaults(db.settings, ns.defaults)
	db.history = db.history or {}     -- key -> { [day] = lowest unit price seen that day }
	db.watchlist = db.watchlist or {} -- array of { id = itemID, name = string }
	db.tracked = db.tracked or {}     -- itemName -> { buy = unit price, sell = unit price, t = time }
	db.sales = db.sales or {}         -- array of sale records from AH mail
	db.salesSeen = db.salesSeen or {} -- dedupe keys for sales already logged
	ns.db = db
	ns.s = db.settings
	ns.PruneHistory()
end)
