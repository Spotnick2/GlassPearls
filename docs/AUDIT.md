# Audit: the pearls that sell, buy, pick or destroy

Issue #61, branch `audit`, on `main` at `7d7c5c0` (after hunter pet care, #38), API build 70532,
2026-10-31 to 2026-11-01. Four pearls end in an action the game can't undo: **sell junk & repair**
(`C_Container.UseContainerItem`, `RepairAllItems`), **restock** (`BuyMerchantItem`), **auto gossip**
(`C_GossipInfo.SelectOption` / `SelectOptionByIndex`) and the **bags-full helper**
(`PickupContainerItem` + `DeleteCursorItem`, then `LootSlot`), over `Core\Merchant.lua` and
`Core\Bags.lua`. The training reminder spends nothing (no `BuyTrainerService`; "Train all", #39, is
its own PR with its own review). Offline: reading, and witness tests on the stubs; a claim only the
client can settle is a day-one line (§5), never a finding. The plan was reviewed with Codex
gpt-6-astra (high) in three rounds to consensus (2026-10-31); its first round added three findings
(J9, R6, R7) and dropped two candidates (§2).

The property audited, as one sentence: **before each irreversible call, the pearl holds a current
authorization and re-establishes identity: the settings that allow the operation and, where the
design asks for one, the player's confirmation of the displayed action, which bounds what may
follow and which broader settings never enlarge; every fact that identity, eligibility and those
bounds rest on is re-read just before the call, an unreadable or stale fact stops the operation, one
operation is in flight at a time, and the next starts only on the documented completion evidence.**

- **Identity**: a bag stack is bag + slot + item ID + count + link + GUID; a merchant offer is index
  + item ID + price + pack; a gossip option its ID (else its index on that page); a visit is
  `Core\Merchant.lua`'s session; a conversation is auto gossip's chain.
- **Authorization, and what revokes it**: the pearl on, the kind's switch, the lists, the targets
  and limits, the lone rule, all re-read per operation (by hand or by sync). Shift and the Ask
  window's Buy are read once, at the show and at the click: a visit's decision (§3).
- **The operation unit**: one stack's sale, one repair stage, one purchase chunk, one gossip pick,
  one delete and the loot it was made for.
- **Completion evidence**: a slot that reads empty or holds another GUID (the stack is gone); a
  count that reaches exactly the expected (the chunk landed); a repair cost that fell (the repair
  landed); a new page or a close (the pick went through). Buyback growth alone identifies nothing
  (J6); a count that grew by more than the chunk identifies nothing either (R1).

Facts met on the way, not fixed here:
- `BuyMerchantItem`'s count is in items, multiples of `stackCount`: Blizzard's Mainline merchant
  frame, which Forever loads, computes it so (`MerchantFrame.lua:719, 806-812`). A day-one smoke
  test ("one pack first"), not an open question.
- The stubs can't make a truth test or `==` on a secret throw (the porting guide, Lua 5.1), so a
  secret misused that way is a static finding plus a day-one line, never a witness (R5).
- The stubs hid two things: `UseContainerItem` with no merchant open did nothing (the client uses
  the item), and a stack with a pending sale read unlocked (the client locks it). Both are modelled
  now (`WoW.usedItems`, a pending sale's slot locked).
- A `MERCHANT_CLOSED` the client never sends at all can't be seen offline: day one (§5).

## 1. Trace matrix

Per irreversible call: the trigger and its gates, what is re-read just before the call, the
completion evidence and its timeout, what ends a run and what is left in flight, and what the player
is told. Lines are as of this branch. A cell that fell short was a finding (§2) or is a declared
exception (§3).

| Path | Trigger and its gates | Re-read just before the call | The call | Completion evidence, timeout | What ends a run; left in flight | Told |
|---|---|---|---|---|---|---|
| Sell | `MERCHANT_SHOW` → Shift (once) → 0.2 s on the same visit → combat, the pearl on, `autoSell` (`Junk.lua:493-499`); the queue: every stack `Judge` accepts, cheapest first, cut to the buyback room with `safe` (`:472-491`) | the pearl on and the visit current (J1, J3), `autoSell` (J2), combat, the cursor plainly empty, the page (`safe`), the slot (`Bags.Slot`) and a full `Judge` again (the lock known and off (J7), the lists, quest, cache, quality, refund, binding, use), ID + count + link + GUID equal (`:441-466`) | `C_Container.UseContainerItem` in a pcall | the slot empty or another GUID there, or the page grew with this sale as its newest entry (J6), on `BAG_UPDATE_DELAYED`; 1 s on the same visit → "unconfirmed" stops (`:417-439`) | close (the client's, a second show's or a loading screen's: J3, J1), combat, cursor, a refusal named while ours is in flight, buyback-safe, unconfirmed, off; the in-flight sale lands or not, counted by nobody; the visit "skip" for restock (`:396-415`, `:501-514`) | "Sold n items (m stacks): your money ±x" as observed; the reason; nothing after a close (§3) |
| Repair, guild funds | after selling settled (0.5 s quiet, 2 s at most, on the same visit): the pearl on (J9), the visit, combat, `autoRepair`, `CanMerchantRepair`, a plain cost above 0, the guild in one, allowed, no `[noautorepair]` (unreadable: never charged) (`:337-349`) | the same reads, at the call | `RepairAllItems(true)` in a pcall | the cost read again **fell** on `UPDATE_INVENTORY_DURABILITY` (J5); 2 s → "couldn't be confirmed", "skip" (`:298-315`) | a close clears the repair; the guild call lands or not | "Repaired with guild funds." / "Repaired, guild funds first: your money −x" / "couldn't be confirmed" |
| Repair, the player's money | the guild step settled with a rest, or no guild funds | the pearl on, the visit, `autoRepair`, combat (J4), the money covering the rest (`:350-357`) | `RepairAllItems(false)` | as above | as above | "Repaired: your money −x" / "Not enough money…" / "Combat: the repair stopped." |
| Buy, automatic | `MERCHANT_SHOW` → Shift (once) → the junk seller's "ready" (10 s, else nothing) or 0.3 s → the pearl on, the visit, combat → `R.Plan`, with the limits captured (`Restock.lua:472-494`) | the pearl on and the visit current (R8), combat, the cursor plainly empty (a throw or a secret is unknown, R7), the offer at its index equal in ID + price + pack, the kind's switch and target, the recount (nil skips), the chunk within the max stack and the stock, both limits (the stricter of captured and current, R4) on the money now and the money observed spent, room on a strict snapshot (R2), the count before (`:402-455`) | `BuyMerchantItem(index, items)` in a pcall | the count reaches exactly before + chunk (R1) on `BAG_UPDATE_DELAYED`; smaller: wait, 2 s → "unconfirmed" stops; larger: recorded, "more arrived" stops (`:376-396`) | close, combat, cursor, a named refusal while ours is in flight, unconfirmed, more, off; the purchase lands or not (`:341-355`) | "Bought …: your money −x" as observed; the reason; each skipped line's note |
| Buy, from the Ask window | the plan shown, every line (R6), the total, the limits captured at the plan; Buy's click → `R.Run` with those lines and limits, refused when the visit changed (`RestockFrame.lua:80-114`, `Restock.lua:457-469`) | as the automatic row (the lines are the most; a lower target or a changed offer counts) | as above | as above | as above; the window hides on close | the window's lines, "Total", "At most n% of your money and ng this visit." |
| Select by ID | `GOSSIP_SHOW` (textureKit plainly nil, an NPC) or a refresh → a frame later: the pearl on, the page unchanged and unselected, combat, Shift, the chain under its cap, the decision (no quest business, not Blizzard's lone pick, one always option or the lone rule's) (`AutoGossip.lua:447-479`) | the same decision on fresh state, the same ID and index; never the same ID twice in a chain | `C_GossipInfo.SelectOption(id)`, never `confirmed` | a page or a close; a confirmation names the option (`GOSSIP_CONFIRM`) or, nameless, the player's pending pick else our own last pick, 10 s (G1): the option off the always list, said | the chain ends at a terminal close, the NPC gone, 60 s, a loading screen, off | `/gpearls gossip`, `gossip trace` |
| Select by index | as above, for an option without an ID | as above | `SelectOptionByIndex(index)` | as above; the chain locks after it | as above | |
| Delete | the window's button, a hardware click: the pearl on, combat, the cursor; the whole decision again (the loot row by slot + link + quantity, the stack by bag + slot + ID + count + link + value, eligibility and the never-suggest list, not "by hand"); white armed by a second click within 3 s (`BagsFull.lua:244-291`) | after the pickup: the cursor holds "item" with that ID, the slot reads plainly locked (`:292-300`) | `DeleteCursorItem` | the cursor empty and no `ADDON_ACTION_FORBIDDEN` naming us (`:301-309`); refused: the item back, "by hand" for the session | | "Couldn't pick … up; nothing was destroyed." / "The game didn't let Glass Pearls destroy it: …" |
| The loot after a delete | `BAG_UPDATE_DELAYED` with a delete pending (2 s): the slot reads "empty" (never "unreadable"), the same loot window, the row's link and presence (`:323-338`) | those | `LootSlot(row)` in a pcall | the client's own | `LOOT_CLOSED` cancels it | |

## 2. Findings and fixes

Read first, confirmed by a test that fails with the fix reverted (§4). The hazards applied to every
row: a stale item cache, a wrong merchant or NPC, a changed price or offer, a changed slot,
unattributed completion evidence, an incomplete preview, settings changed mid-run, the pearl switched
off, combat / Shift / cursor / a loading screen, secret values, refusals, the money limits,
re-entrancy. In order: authorization and continuation gates, then identity, then consistency.

| # | Finding | Fix | Witness (reverted → red) |
|---|---|---|---|
| J9 | A repair could start after the pearl was switched off: `endRun`'s settle wait (0.5 to 2 s) called `J.Repair`, which checked the visit, combat and `autoRepair`, never the pearl; `disable` can't cancel a scheduled callback | `J.Repair` and the personal step require `J.enabled` | `test_junk_audit` "switched off during the settle wait: no repair" (2, with both checks reverted: M10) |
| R6 | The Ask window showed at most 8 lines and Buy bought every line: a rogue's plan has 10 (nine reagents and food, the rank filter applied) | 12 rows: the largest reagent set plus water, food and ammunition, asserted against the data | `test_restock_audit` "every line has a row in the window", "within the window's rows", the data check (3, M15) |
| R7 | A cursor read that threw counted as an empty cursor (`call` returned nil and `step` went on); the junk seller's `cursorEmpty` stopped | the pcall's success kept apart from the value: a throw or a secret is unknown, "cursor" stops | "a cursor read that throws: stopped", "said as a cursor stop" (2, M11) |
| J5 | A repair settled on **any** cost change: a cost that rose (a hit at the vendor, a gear swap) started the personal payment while the guild step was unresolved, against the header's "never a second payment on stale data" | settled only when the cost fell; unchanged or risen waits for the timeout | "a cost that rose: not settled, no payment from the player" (1, M8); "a cost that fell: settled, the rest from my money" still passes |
| J6 | Buyback growth confirmed a sale it couldn't attribute, and the page check (`safe`) is off by default: the player's own sale in the 1 s window started the next sale with ours still in flight | growth counts only with this sale's link and count as the page's newest entry (the highest index, as Blizzard's buyback button reads it) | "the page grew by the player's own sale: ours isn't taken as sold", "then the next one" (2, M7); growth with ours newest still confirms |
| J3 | A second `MERCHANT_SHOW` with no close between (a vendor opened straight from another) bumped the session and orphaned the old run with a sale in flight: its landing sale started the next one before the new visit's run, under a timeout that never fires | the core: a show while a visit is open first tells every listener `MERCHANT_CLOSED` for it; `nextSale` also requires the visit current | `test_merchant_audit` "a second show closes the first visit first" (6, M1); `test_junk_audit` "a replaced visit: the old run sells nothing more" (3, with the core and the dispatch check both reverted: M2) |
| R8 | The same for restock: `R.Run` refused a second run but kept the old one, whose next step never checked the visit and could buy at the new merchant | the core fix; `step` requires the visit current | `test_restock_audit` "a replaced visit: the old run buys nothing more" (3, both reverted: M3) |
| J1 | Nothing closed a visit at a loading screen, and `nextSale` never asked whether the visit was still open; `UseContainerItem` with no merchant open **uses** the item (the stub returned silently) | `PLAYER_ENTERING_WORLD` closes an open visit the same way; the visit required before every sale; the stub records a use | `test_merchant_audit` "a loading screen closes the open visit" (3); `test_junk_audit` "no item is used by a sale sent to no merchant" (3) (M4) |
| J7 | A lock that couldn't be read sold: `Bags.Slot` reports `lockKnown`, `Judge` read `locked` only, against "anything unknown is not junk" | `lockKnown` required | "a lock that can't be read: not junk", "never sold; the rest is" (2, M6) |
| J2 | `autoSell` was read once at the show while the lists and `sellGrey` are re-read each sale: a sync switching it off mid-run didn't stop the queue (which may hold listed rares) | re-read before every sale; the run ends cleanly and the repair runs | "selling switched off mid-run: no more sales" (1, M5) |
| J4 | The personal repair step, from `onDurability`, re-checked neither the visit, the setting nor combat | the three, and the pearl | "setting after the guild step: no personal payment", "combat …", "and said" (5, M9) |
| R1 | A count of **at least** before + chunk confirmed a purchase: something else of that item arriving in the same two seconds was taken as the chunk, and the next count had no baseline; the header named only a smaller increase as a stop | exactly the chunk confirms; more is recorded as bought and stops the run ("More arrived than was bought") | "more arrived than was bought: stopped", "the chunk recorded as bought", "the reason said" (3, M12); `test_restock_buy`'s recount now has its arrival between chunks |
| R4 | The Ask window's limits weren't the limits that ran: the text showed the settings at the Ask, `allowance` read them at each step; a limit raised between Ask and Buy (a sync) spent more than shown | the two settings captured with the plan and carried into the run; each step uses the stricter of the captured and the current value | "raised after the window: the shown 1g still holds", "1g spent" (2, M14); lowered still holds |
| R2 | Room from a non-strict `Bags.Snapshot()` where the contract reserves strict for an automatic action: a bag whose family can't be read counted as room and a purchase was attempted | strict | "a bag whose family can't be read: no room, nothing attempted", "and said" (2, M13) |
| G1 | A confirmation that names no option (`CONFIRM_BINDER`, `_TALENT_WIPE`, `_XP_LOSS`) after **our own** pick named nothing: `confirmedPending` read the player's pending pick only, so an always-listed binder (listed by `always <id>`, by sync, or by the prompt should Forever's binder icon be neither of the two known) stayed listed and asked at every inn. Not irreversible (Blizzard's popup guards); a gap in the rule "a confirmation takes it off the always list" | our own last pick remembered 10 s for those events, the player's pending pick first | `test_autogossip_audit` "a confirmation after our own pick takes it off the always list", "marks it confirmed", "says which", "never picked again", "after the close still names our pick" (5, M16) |

Dropped after reading (not defects):
- **R3, `MERCHANT_UPDATE` unhandled**: the offer is re-read at its index in the same execution as
  the call (`Restock.lua:417-420`: ID, price and pack equal); nothing interleaves inside one Lua run.
  The remaining race is the one Blizzard's own buy has.
- **G3, the never list not consulted by the decision**: "Never" is "Never ask: don't offer this
  option again" (`AutoGossipFrame.lua:72`, the panel's "Never offered"), enforced by `Offerable`. A
  selection denylist would be another design.
- **R5, raw truth tests on `GetCursorInfo`**: `Restock.lua` (now R7's form) and `BagsFull.lua:265`
  stop in the safe direction either way (a secret is truthy, nil isn't); no witness is possible in
  Lua 5.1; day one asks whether the read is ever secret.
- **B1, the delete**: the fresh decision re-reads eligibility, the never-suggest list, quality and
  the target row; the cursor kind, ID and the slot's lock are read after the pickup; a silent delete
  leaving the item on the cursor is refused. What remains is declared (§3).
- **Changed eligibility between the plan and a purchase** (a hunter swapping bow for gun between
  Ask and Buy; the reagent addon's list): a confirmed line is bought as confirmed; automatic mode
  plans and runs in one step.

Deferred on purpose, its own issue: **G2**, the default lone rule `most` picks any lone Available
option but the binder's and healer's icons, and an encounter starter or a hand-in has the plain
gossip icon and no confirmation (#62: a default of `services`, no lone picks in a raid or at an
elite, or the curated list #46; decided after day one with the real options in hand).

## 3. Declared exceptions, in one list

What a pearl knowingly does, and where the player is told:
1. Shift is read once, at the merchant's show (both pearls) and at the gossip attempt: a visit's or a
   page's decision (the help texts: "Hold Shift when you open the merchant").
2. A sale's price is the client's: never pre-checked, reported as the money observed.
3. The same-execution race between a re-read and its call is Blizzard's own.
4. An in-flight sale or purchase lands or not after the pearl is switched off or the visit closes,
   counted by nobody; the visit is "skip" for restock (`disable` reports it).
5. A count that grew by exactly the chunk for another reason within 2 s confirms a purchase (R1
   narrows it; nothing attributes a count).
6. The buyback page's newest entry is a link-and-count match, not proof (two identical stacks).
7. A visit the client closed without `MERCHANT_CLOSED`, and without a show or a loading screen after
   it, can't be seen: a day-one question.
8. Raised limits wait for the next visit; lowered ones count at once (the Ask window's text).
9. A confirmed Ask line is bought as confirmed, even when the character's eligibility changed
   meanwhile.
10. The bags-full helper's second click (white) destroys the stack at that bag and slot with that
    item, count, link and value: another stack of the same item moved there within 3 s is the same
    thing asked; the loot session isn't compared (the same row, link and quantity are); a loot that
    needs more room than one deletion frees prompts again; the loot takes the row as it stands at
    the bag update, the same slot and link, whatever its quantity reads then.
11. `ADDON_ACTION_FORBIDDEN` is read right after `DeleteCursorItem`; fired a frame later, the cursor
    still holding the item is what catches it (day one).
12. An always-listed option overrides the lone rule's icon policy by design (the prompt never offers
    the binder or healer; `always <id>` and sync can list anything; G1 takes it off at its first popup).
13. A visit closed mid-run says nothing of what was sold (the settle wait ends with the visit).

## 4. Mutation witnesses

Each guard reverted in turn (`sed` on the committed branch), its test file run, the guard restored
(`restored: all green` after every run; the script stays out of the repo).

| Mutation | Reverted | Result |
|---|---|---|
| M1 | the core's close on a second `MERCHANT_SHOW` | `test_merchant_audit` 6 red; the pearls' files stay green (their own visit checks hold) |
| M2 | M1 and `nextSale`'s visit check | `test_junk_audit` 3 red (J3) |
| M3 | M1 and `step`'s visit check | `test_restock_audit` 3 red (R8) |
| M4 | `PLAYER_ENTERING_WORLD` not closing a visit | `test_merchant_audit` 3 red, `test_junk_audit` 3 red: one item used (J1) |
| M5 | `autoSell` read once | 1 red (J2) |
| M6 | `lockKnown` not required | 2 red (J7) |
| M7 | buyback growth alone confirms | 2 red (J6) |
| M8 | a repair settles on any cost change | 1 red (J5) |
| M9 | the personal step unchecked | 5 red (J4) |
| M10 | `J.Repair`'s enabled check alone | 0 red: the personal step's check (J4) holds; with both reverted, 2 red (J9) |
| M11 | a throwing cursor read is empty | 2 red (R7) |
| M12 | at least the chunk confirms | 3 red (R1) |
| M13 | a non-strict snapshot | 2 red (R2) |
| M14 | the limits read live | 2 red (R4) |
| M15 | eight rows | 3 red (R6) |
| M16 | our own pick forgotten | 5 red (G1) |

Also observed while building the witnesses: `test_restock_buy`'s "fifteen more arrived meanwhile"
modelled items arriving **during** a purchase as an ordinary recount; under R1 that stops the run, so
the test now has them arrive between chunks, the recount it meant to cover.

## 5. In game (build 70532)

Added to `docs/PLAN.md`'s day-one checklist, marked "audit #61":
- `MERCHANT_CLOSED` when the client never says so: a second vendor clicked with the first window
  open; a hearth or portal with it open.
- `UPDATE_INVENTORY_DURABILITY` from a hit with the merchant window open: the cost rises, the repair
  stays unsettled.
- The buyback page's newest entry is the highest index.
- One pack first at the first automatic purchase; `GetCursorInfo` ever secret or throwing; a rogue's
  ten-line Ask window.
- `CONFIRM_BINDER` after our own always pick (an innkeeper listed by hand): the option off the list.
- `/gpearls gossip` at a raid boss or event NPC, with Shift held: #62's evidence.
- `ADDON_ACTION_FORBIDDEN`'s timing inside `DeleteCursorItem`.

_Results: pending the owner's session; they go here and to `docs/PLAN.md`._
