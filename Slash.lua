-- FlipFinder: /ff and /flipfinder commands.
local _, ns = ...

local function Help()
	ns.Print("Commands:")
	print("  /ff  - show or hide the panel")
	print("  /ff settings  - show current settings")
	print("  /ff minprofit <gold>  - minimum profit per flip (e.g. /ff minprofit 25)")
	print("  /ff minpct <percent>  - minimum profit as % of cost (e.g. /ff minpct 30)")
	print("  /ff maxage <days>  - ignore items whose newest price is older than this")
	print("  /ff history <days>  - how many days of price history to use")
	print("  /ff samples <n>  - days of price data needed before flagging an item")
	print("  /ff duration 12|24|48  - relist duration used for the deposit")
	print("  /ff maxinvest <gold>  - most you'd spend on one flip (0 = no limit)")
	print("  /ff gaps on|off  - also flag price gaps for items with no history (riskier)")
	print("  /ff watch add <item link or ID> | remove <link or ID> | list | clear")
	print("  /ff snipe  - search your watchlist now (auction house must be open)")
	print("  /ff sales  - show the sales log from your auction house mail")
	print("  /ff reset  - restore default settings")
end

local function ShowSettings()
	local s = ns.s
	ns.Print("Settings:")
	print(string.format("  Min profit: %s   Min %%: %d%%   Max price age: %d day(s)",
		ns.Money(s.minProfit), s.minPct, s.maxAgeDays))
	print(string.format("  History used: %d days   Min data days: %d   Relist: %dh   Max invest: %s   Price gaps: %s",
		s.historyDays, s.minSamples, ({ 12, 24, 48 })[s.duration] or 24,
		s.maxInvest > 0 and ns.Money(s.maxInvest) or "no limit", s.allowNoHistory and "on" or "off"))
	local hasAtr = Auctionator and Auctionator.API and Auctionator.API.v1 and "found" or "not found (using FlipFinder's own history)"
	print("  Auctionator: " .. hasAtr)
end

local function ParseItem(arg)
	if not arg or arg == "" then return nil end
	local id = tonumber(arg:match("item:(%d+)") or arg:match("^%s*(%d+)%s*$"))
	if id then return id end
	local _, link = ns.GetItemInfoCompat(arg)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

local function Watch(rest)
	local sub, arg = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	local list = ns.db.watchlist
	if sub == "add" then
		local id = ParseItem(arg)
		if not id then return ns.Print("Usage: /ff watch add [shift-click an item]") end
		for _, e in ipairs(list) do
			if e.id == id then return ns.Print("Already on the watchlist.") end
		end
		local name = ns.GetItemInfoCompat(id) or (arg:match("%[(.-)%]")) or ("item " .. id)
		table.insert(list, { id = id, name = name })
		ns.Print("Added " .. name .. " to the watchlist.")
	elseif sub == "remove" or sub == "del" then
		local id = ParseItem(arg)
		for i, e in ipairs(list) do
			if e.id == id or (arg ~= "" and e.name:lower() == arg:lower()) then
				table.remove(list, i)
				return ns.Print("Removed " .. e.name .. ".")
			end
		end
		ns.Print("Not on the watchlist.")
	elseif sub == "clear" then
		wipe(list)
		ns.Print("Watchlist cleared.")
	else
		if #list == 0 then return ns.Print("Watchlist is empty. /ff watch add [item link]") end
		ns.Print("Watchlist:")
		for i, e in ipairs(list) do print(string.format("  %d. %s (%d)", i, e.name, e.id)) end
	end
end

local function Number(arg, name)
	local n = tonumber(arg)
	if not n or n < 0 then
		ns.Print("Please give a number for " .. name .. ".")
		return nil
	end
	return n
end

local function Slash(msg)
	if not ns.db then return end
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	local s = ns.s

	if cmd == "" or cmd == "show" or cmd == "toggle" then
		ns.TogglePanel()
	elseif cmd == "help" or cmd == "?" then
		Help()
	elseif cmd == "settings" or cmd == "config" or cmd == "options" then
		ShowSettings()
	elseif cmd == "minprofit" then
		local n = Number(rest, "gold"); if not n then return end
		s.minProfit = math.floor(n * 10000)
		ns.Print("Minimum profit set to " .. ns.Money(s.minProfit) .. ".")
	elseif cmd == "minpct" then
		local n = Number(rest, "percent"); if not n then return end
		s.minPct = n
		ns.Print(string.format("Minimum profit set to %d%% of cost.", n))
	elseif cmd == "maxage" then
		local n = Number(rest, "days"); if not n then return end
		s.maxAgeDays = math.floor(n)
		ns.Print(string.format("Prices older than %d day(s) are treated as stale.", s.maxAgeDays))
	elseif cmd == "history" then
		local n = Number(rest, "days"); if not n then return end
		s.historyDays = math.max(1, math.floor(n))
		ns.Print(string.format("Using %d day(s) of price history.", s.historyDays))
	elseif cmd == "samples" then
		local n = Number(rest, "days"); if not n then return end
		s.minSamples = math.max(1, math.floor(n))
		ns.Print(string.format("Items need %d day(s) of price data.", s.minSamples))
	elseif cmd == "duration" then
		local map = { ["12"] = 1, ["24"] = 2, ["48"] = 3 }
		if not map[rest] then return ns.Print("Use /ff duration 12, 24 or 48") end
		s.duration = map[rest]
		ns.Print("Relist duration set to " .. rest .. "h.")
	elseif cmd == "maxinvest" then
		local n = Number(rest, "gold"); if not n then return end
		s.maxInvest = math.floor(n * 10000)
		ns.Print(n > 0 and ("Max spend per flip: " .. ns.Money(s.maxInvest)) or "No spending limit per flip.")
	elseif cmd == "gaps" then
		s.allowNoHistory = rest:lower() == "on"
		ns.Print("Price gaps without history: " .. (s.allowNoHistory and "on" or "off"))
	elseif cmd == "watch" then
		Watch(rest)
	elseif cmd == "snipe" then
		ns.StartSnipe()
	elseif cmd == "sales" then
		ns.PrintSales()
	elseif cmd == "reset" then
		for k, v in pairs(ns.defaults) do s[k] = v end
		ns.Print("Settings reset to defaults.")
	else
		Help()
	end
	ns.RefreshUI()
end

SLASH_FLIPFINDER1 = "/ff"
SLASH_FLIPFINDER2 = "/flipfinder"
SlashCmdList.FLIPFINDER = Slash
