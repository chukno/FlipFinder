# FlipFinder

A World of Warcraft addon for **WoW Forever** that points out auction house
"flips": listings priced well below an item's normal market price, which you
can buy and relist for a profit.

FlipFinder only **reads** auction house data and **suggests**. It never buys,
bids or posts anything. You always click the Blizzard "Buy Now" button
yourself.

## Install

The addon's files live in `C:\FlipFinder` (a git repo). The game loads it
through a folder link in your AddOns folder:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\FlipFinder  ->  C:\FlipFinder
```

If you ever need to recreate that link, close WoW, open **Command Prompt**
(not PowerShell) and run:

```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\FlipFinder" "C:\FlipFinder"
```

Or just copy the `C:\FlipFinder` folder into `...\_forever_\Interface\AddOns\`.

Then in game: on the character select screen click **AddOns** and make sure
**FlipFinder** is ticked. Auctionator is optional but recommended.

## Use

1. Open the auction house. The FlipFinder panel appears on its right.
2. Search as you normally would (type a name, pick a category, or use an
   Auctionator shopping list).
3. Rows fill in as results arrive, sorted by profit:
   - **Item**: what to buy
   - **Buy**: the highest price per unit you'd pay
   - **Sell**: the price to relist each unit at
   - **Qty**: how many units to buy
   - **Profit**: total profit after the 5% AH cut and the deposit
   - **Conf**: how much price history backs it (Low / Med / High)
4. Hover a row for details. **Click it** to open that item's buy page, then
   buy by hand and relist at the Sell price.

Click a column header to sort by it (for example **%** to sort by profit
percentage); click it again to reverse the order.

Rows marked `?` with a profit ending in `/ea` are *possible* flips from the
search list, where only the cheapest price is known. Click one to load the
full listings and get the real numbers (it then either becomes a full row or
disappears).

### How a flip is decided

- **Market price** is the median of the lowest prices seen on earlier days
  (up to 14 days), from FlipFinder's own records plus Auctionator's price
  database. Today's prices are left out on purpose: Auctionator updates its
  price as soon as you search, so comparing a listing against it would compare
  the listing to itself.
- FlipFinder works out how many of the cheapest listings to buy so that total
  profit is largest. The relist price is just under the next listing you
  *didn't* buy, and never above the market price.
- A flip is shown only if profit clears **both** the minimum gold and the
  minimum percentage. Items with stale or no history are skipped.

### Below vendor tab

The **Below vendor** tab lists auctions priced under what a merchant pays for
the item. Buy them and sell them to any vendor: no AH cut, no deposit and no
waiting for a buyer, so no price history is needed and they're marked
**Safe**. Set the minimum profit for this tab with `/ff vendormin`
(default 20 silver).

### Watchlist ("snipe")

Add items you like to flip:

```
/ff watch add [shift-click the item]
```

Then press **Search watchlist** on the panel (or type `/ff snipe`) while at
the auction house. It searches each item once (up to 25), waiting for the
server's search throttle between them. It only searches; buying is still up
to you.

### Sales log

When you click a flip row, FlipFinder remembers what it cost. When you open
your mailbox, it reads the "Auction successful" mails and logs each sale. Sales
of items you flipped show their profit. Type `/ff sales` to see the log.

## Settings

| Command | What it does | Default |
|---|---|---|
| `/ff` | Show or hide the panel | |
| `/ff settings` | Show current settings | |
| `/ff minprofit 50` | Minimum profit per flip, in gold | 50g |
| `/ff minpct 20` | Minimum profit as % of what you spend | 20% |
| `/ff maxage 3` | Skip items whose newest price is older than this many days | 3 |
| `/ff history 14` | Days of price history to use | 14 |
| `/ff samples 1` | Days of price data needed (raise to 2–3 to be safer) | 1 |
| `/ff duration 24` | Relist duration used for the deposit (12/24/48) | 24 |
| `/ff maxinvest 0` | Most you'd spend on one flip, in gold (0 = no limit) | 0 |
| `/ff vendormin 0.2` | Minimum profit for the Below vendor tab, in gold | 20s |
| `/ff gaps on` | Also flag big price gaps on items with no history (riskier) | off |
| `/ff watch add/remove/list/clear` | Manage the watchlist | |
| `/ff snipe` | Search the watchlist | |
| `/ff sales` | Show the sales log | |
| `/ff reset` | Restore default settings | |

## Tips and limits

- The more days you visit the auction house (or run an Auctionator full scan),
  the better the market prices get, and Conf moves from Low to High.
- A Low-confidence flip is based on one day of data. Check the item's price
  history in Auctionator before buying a lot of it.
- The deposit is the game's figure for stackable goods and an estimate for
  gear.
- Profit assumes everything sells at the Sell price. Slow-selling items can
  take days to sell.

## Troubleshooting

- **No panel?** Type `/ff` while the auction house is open.
- **Lua errors?** Install BugSack + BugGrabber to capture them, or turn on
  error display with `/console scriptErrors 1`. Then share the error text.
- **Nothing is flagged?** On the first day there is little history. Search
  the items you care about once a day, or lower `/ff minprofit` and
  `/ff minpct` to see more.
