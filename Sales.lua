-- FlipFinder: sales log built from auction house mail, to learn which flips really sold.
local _, ns = ...

-- Called when you click a flip row: remember what you planned to pay and sell for.
function ns.TrackFlip(flip)
	if not flip or not flip.name then return end
	ns.db.tracked[flip.name] = {
		buy = flip.buyAvg, sell = flip.sell, qty = flip.qty, t = time(),
	}
end

local function PruneTracked()
	local cutoff = time() - 21 * 86400
	for name, t in pairs(ns.db.tracked) do
		if t.t < cutoff then ns.db.tracked[name] = nil end
	end
	-- Keep the sales log to a sensible size.
	while #ns.db.sales > 500 do table.remove(ns.db.sales, 1) end
end

local function ScanInbox()
	if not ns.db or not GetInboxNumItems then return end
	local now = time()
	local n = GetInboxNumItems()
	local added = 0
	for i = 1, n do
		local invoiceType, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
		if invoiceType == "seller" and itemName and bid then
			local daysLeft = select(7, GetInboxHeaderInfo(i)) or 30
			-- AH sale mail lasts 30 days; estimate when it arrived to tell sales apart.
			local hour = math.floor((now - (30 - daysLeft) * 86400) / 3600)
			local base = string.format("%s|%d|%d|", itemName, bid, count or 1)
			local seen = ns.db.salesSeen
			if not (seen[base .. hour] or seen[base .. (hour - 1)] or seen[base .. (hour + 1)]) then
				seen[base .. hour] = now
				local qty = count or 1
				local net = bid - (consignment or 0)
				local rec = { t = now, name = itemName, qty = qty, gross = bid, net = net }
				local tr = ns.db.tracked[itemName]
				if tr and tr.buy then
					rec.flip = true
					rec.profit = net - tr.buy * qty
				end
				table.insert(ns.db.sales, rec)
				added = added + 1
			end
		end
	end
	if added > 0 then
		PruneTracked()
		ns.Print(string.format("Logged %d new auction sale(s). Type /ff sales to see them.", added))
	end
end

ns.On("MAIL_INBOX_UPDATE", ScanInbox)

-- Old dedupe keys can go once the mail they refer to has expired.
ns.On("PLAYER_LOGIN", function()
	if not ns.db then return end
	local cutoff = time() - 31 * 86400
	for k, t in pairs(ns.db.salesSeen) do
		if t < cutoff then ns.db.salesSeen[k] = nil end
	end
end)

function ns.PrintSales()
	local sales = ns.db.sales
	if #sales == 0 then
		ns.Print("No sales logged yet. Sales are read from your auction house mail when you open your mailbox.")
		return
	end
	local flips, flipProfit, total = 0, 0, 0
	for _, r in ipairs(sales) do
		total = total + r.net
		if r.flip then
			flips = flips + 1
			flipProfit = flipProfit + (r.profit or 0)
		end
	end
	ns.Print(string.format("%d sale(s) logged, %s after the AH cut. Flips: %d sold, %s profit.",
		#sales, ns.Money(total), flips, ns.Money(flipProfit)))
	for i = #sales, math.max(1, #sales - 9), -1 do
		local r = sales[i]
		local line = string.format("  %s x%d  %s", r.name, r.qty, ns.Money(r.net))
		if r.flip then line = line .. "  |cff33ff99flip|r " .. ns.Money(r.profit) end
		print(line)
	end
end
