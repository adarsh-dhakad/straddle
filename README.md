# XAUUSD Straddle Modular Architecture

Date: 2026-08-22

Current EA: `XAUUSD_Straddle_Replica_v2.mq5`

Goal: define the module boundaries before coding v2.

Implementation status:

```text
v1 remains as the original single-file replica.
v2 has been created as a modular EA with .mqh modules.
v2 refills only empty base grid slots.
v2 caps each side to the configured grid size: `InpLevelsPerSide` buy-side objects and `InpLevelsPerSide` sell-side objects.
```

## Why We Need Modules

The strategy has many separate responsibilities:

- cycle start
- grid placement
- lot sizing
- trailing
- re-entry
- daily limits
- exposure caps
- close-all logic
- broker execution
- journal/debugging

If all logic stays inside one file and every method directly reads global variables, changes become risky. A small change to trailing can accidentally change grid replacement, daily limits, or close-all behavior.

The v2 rule should be:

```text
Each module owns one job.
The main EA only controls sequence.
Trading decisions must be testable by reading one module at a time.
```

## Recommended File Layout

MQL5 allows us to keep the EA entry file small and move logic into `.mqh` include files.

Recommended structure:

```text
XAUUSD_Straddle_Replica_v2.mq5
modules/Types.mqh
modules/Inputs.mqh
modules/Broker.mqh
modules/State.mqh
modules/DailyLimits.mqh
modules/GridEngine.mqh
modules/LotEngine.mqh
modules/ExposureGuard.mqh
modules/TrailingEngine.mqh
modules/ReentryEngine.mqh
modules/CycleCloseEngine.mqh
modules/Diagnostics.mqh
```

This structure now exists in the `straddle/` folder.

If we want maximum simplicity, we can still keep one `.mq5` file, but organize it with the same module sections. For a big project, the `.mqh` layout is better.

## Module Map

| Module | Responsibility | Should Not Do |
| --- | --- | --- |
| `Types` | Shared enums, structs, constants | Trading decisions |
| `Inputs` | User inputs and validation | Place orders |
| `Broker` | MT5 account, symbol, order send/close wrappers | Strategy decisions |
| `State` | Current cycle and daily state | Calculate strategy rules |
| `DailyLimits` | Day equity anchor, daily profit/loss lock | Grid placement |
| `GridEngine` | Anchor, grid step, base grid slots | Close basket |
| `LotEngine` | Lot tier and auto-lot calculation | Place orders directly |
| `ExposureGuard` | Max orders, max same-side lots, safety checks | Trail SLs |
| `TrailingEngine` | Per-position profitable trailing | Start new cycles |
| `ReentryEngine` | Handle profitable trailing-SL exit events; no extra orders | Daily hard stop |
| `CycleCloseEngine` | Cycle target and close-all sequence | Create new grid |
| `Diagnostics` | Journal messages, chart panel, debug counters | Trading decisions |

## Main EA Responsibilities

The main `.mq5` file should only contain MT5 event handlers and high-level orchestration.

### `OnInit()`

Purpose:

- Validate inputs.
- Confirm the account is hedging.
- Initialize `CTrade`.
- Initialize daily state.
- Recover existing EA state if positions/orders already exist.
- Start timer.

Should call:

```text
Inputs.Validate()
Broker.Init()
DailyLimits.Init()
State.Recover()
```

Should not:

- Calculate grid levels.
- Place orders.
- Modify stops.

### `OnDeinit(reason)`

Purpose:

- Stop timer.
- Clear chart comments.
- Release indicators if v2 adds ATR.

Should call:

```text
Diagnostics.ClearPanel()
```

### `OnTick()`

Purpose:

- Keep the chart panel updated.
- Optional: store latest tick snapshot.

In v2, `OnTick()` should not contain the full engine. The engine should stay in `OnTimer()` unless we later decide to make the EA strictly tick-driven.

### `OnTimer()`

Purpose:

- Run one controlled management pass.

Recommended sequence:

```text
1. DailyLimits.Refresh()
2. Broker.MarketOpenForNewOrders()
3. If market/session is closed, switch to closed-market timer and stop.
4. If enabled, skip duplicate timer passes on the same tick.
5. CycleCloseEngine.ProcessCloseQueue()
6. If locked or paused, stop.
7. ExposureGuard.Refresh()
8. If flat, start cycle.
9. CycleCloseEngine.CheckCycleTarget()
10. TrailingEngine.Manage()
11. ReentryEngine records profitable SL exits only.
12. GridEngine.PlaceMissingGridOrders()
13. Diagnostics.UpdatePanel()
```

Important rule:

```text
OnTimer should decide order of modules.
Modules should decide their own local rule only.
```

Timer policy:

```text
InpTimerMilliseconds = normal open-market timer
InpClosedMarketTimerMilliseconds = slow timer used while the market/session is closed
InpRunEngineOncePerTick = skip repeated management passes on the same tick
```

### `OnTradeTransaction(...)`

Purpose:

- Detect position exits.
- Detect SL exits.
- Pass trailing-stop exits to the re-entry module.
- Record deal history for diagnostics.

Should call:

```text
ReentryEngine.HandleTrailingStopExit(...)
Diagnostics.LogDeal(...)
```

Should not:

- Place new orders directly.
- Close all positions directly.

## Shared Types

The `Types` module should define simple shared structures.

### `CycleState`

Stores one active cycle.

Fields:

```text
bool active
double anchor
double gridStep
double gridMin
double gridMax
double startBalance
double startEquity
datetime startTime
bool boosted
```

### `DailyState`

Stores daily limit state.

Fields:

```text
datetime dayStart
double equityAnchor
bool locked
datetime noTradeUntil
datetime boostUntilDay
```

### `SlotId`

Identifies a grid slot.

Fields:

```text
int side       // +1 buy, -1 sell
int level      // 1..levelsPerSide
```

### `ExposureStats`

Stores current exposure.

Fields:

```text
int buyPositions
int sellPositions
int buyOrders
int sellOrders
double buyLots
double sellLots
double floatingProfit
```

### `TradeAction`

Optional future abstraction for queued trade requests.

Fields:

```text
actionType     // buy stop, sell stop, close position, delete order, modify SL
side
ticket
volume
price
sl
tp
comment
reason
```

## Inputs Module

### `ValidateInputs()`

Purpose:

- Reject invalid inputs before trading starts.

Checks:

```text
levelsPerSide between 1 and 200
reference spacing > 0
reference price > 0
lot sizes > 0
trail arm >= 1
trail distance >= 1
timer >= 100 ms
max order caps >= base grid requirements
```

Output:

```text
true  = valid
false = fail init
```

### `NormalizeConfig()`

Purpose:

- Clamp user inputs that can be safely clamped.

Example:

```text
NoTradeDaysAfterDailyLoss: clamp to 1..4
```

## Broker Module

The Broker module is the only module that should call `CTrade` directly.

### `InitBroker()`

Purpose:

- Set magic number.
- Set slippage.
- Set filling mode.
- Check hedging account.

### `RefreshTick()`

Purpose:

- Store bid, ask, spread, and mid price.

Output:

```text
true if tick is valid
```

### `IsSpreadAllowed()`

Purpose:

- Check `SYMBOL_SPREAD` against `InpMaxSpreadPoints`.

### `MarketOpenForNewOrders()`

Purpose:

- Avoid sending new order requests when trading is disabled or the symbol session is closed.
- Prevent repeated tester journal lines such as broker reject `[Market closed]`.

Checks:

```text
terminal trading permission
EA trading permission
account trading permission
symbol trade mode
symbol trade session schedule
```

### `MinimumStopDistance()`

Purpose:

- Return broker minimum distance from `SYMBOL_TRADE_STOPS_LEVEL` and `SYMBOL_TRADE_FREEZE_LEVEL`.

### `PlaceStopOrder(side, volume, price, comment)`

Purpose:

- Send buy stop or sell stop.
- Return success/failure.
- Skip silently when market/session is closed.
- Log broker reject reason only for real broker rejections after the market-open guard.

Should not:

- Decide whether the order is allowed by strategy. That belongs to `ExposureGuard` and `GridEngine`.

### `ModifyPositionSL(ticket, sl)`

Purpose:

- Modify one position stop loss.

### `ClosePosition(ticket)`

Purpose:

- Close one position.

### `DeleteOrder(ticket)`

Purpose:

- Delete one pending order.

## State Module

### `RecoverState()`

Purpose:

- If EA restarts while positions/orders exist, recover cycle state.
- Reconstruct anchor from `STR B1` or `STR S1` when possible.

Risk:

- If anchor cannot be recovered, v2 should not place new grid orders. It should manage exits only until flat.

### `ResetCycle()`

Purpose:

- Clear active cycle, anchor, step, and close reason.

## DailyLimits Module

### `InitDailyLimits()`

Purpose:

- Set day start.
- Store day equity anchor.
- Print journal line:

```text
Straddle: DAILY LIMITS - new day equity anchor=...
```

### `RefreshDailyLimits()`

Purpose:

- Detect a new trading day.
- Reset daily lock.
- Set new equity anchor.
- Check daily profit cap.
- Check daily hard loss cap.

### `IsDailyProfitHit()`

Formula:

```text
equity >= dayEquityAnchor + profitLimit
```

### `IsDailyLossHit()`

Formula:

```text
equity <= dayEquityAnchor - lossLimit
```

### `ApplyDailyLossPause()`

Purpose:

- Set `noTradeUntil`.
- Set next-day boost window if enabled.

## GridEngine Module

### `CalculateGridStep(anchor)`

Formula:

```text
if scaleByPrice:
    gridStep = referenceSpacing * anchor / referencePrice
else:
    gridStep = referenceSpacing
```

### `BuildGridPlan(anchor)`

Purpose:

- Calculate all base grid prices before placing orders.

Output:

```text
buy level 1..N prices
sell level 1..N prices
gridMin
gridMax
```

### `CycleAnchorFromPrice(price)`

Purpose:

- Prevent random cycle anchors.
- If `InpCycleAnchorModuloUSD > 0`, snap the candidate anchor to the nearest modulo price.
- If `InpCycleAnchorModuloUSD = 0`, use the current mid-price as before.

Formula:

```text
candidateAnchor = round(currentMid / InpCycleAnchorModuloUSD) * InpCycleAnchorModuloUSD
```

Example:

```text
InpCycleAnchorModuloUSD = 30
currentMid = 4589.64
candidateAnchor = 4590.00
```

### `CycleAnchorReady(anchor, step)`

Purpose:

- Wait until price is close enough to the snapped anchor that level 1 buy and level 1 sell stop orders are both valid.
- Avoid starting a cycle from an anchor that is too far away from current price.

Rule:

```text
first buy  = anchor + gridStep must be a valid buy stop
first sell = anchor - gridStep must be a valid sell stop
```

### `StartCycle()`

Purpose:

- Create new cycle state only after the anchor is ready.
- Store balance/equity.
- Build grid plan.
- Ask `GridEngine.PlaceInitialGrid()` to place base orders.

### `PlaceInitialGrid()`

Purpose:

- Place all base buy and sell stops at cycle start.

Should check:

```text
ExposureGuard.AllowNewBaseOrder(side, volume)
Broker.IsPendingPriceValid(side, price)
```

### `PlaceMissingGridOrders()`

Purpose:

- Replace missing base pending orders only when allowed.
- Do not refill immediately at the same breakout area.
- Require price to move opposite from the empty slot by the refill distance.
- By default the refill distance is ATR-based:

```text
refillDistance = M15 ATR(14) * InpGridRefillAtrMultiplier
```

- If `InpGridRefillUseAtrDistance=false`, or if ATR is not available yet, the EA falls back to `InpGridRefillOppositeMoveUSD`.

Refill gate:

```text
empty buy slot refills only if ask <= buySlotPrice - refillDistance
empty sell slot refills only if bid >= sellSlotPrice + refillDistance
```

With default `InpGridRefillUseAtrDistance=true`, `InpGridRefillAtrTimeframe=M15`, `InpGridRefillAtrPeriod=14`, and `InpGridRefillAtrMultiplier=1.0`, if ATR is `7.50`, a buy level at `4610.00` can be refilled only after ask is `4602.50` or lower. A sell level at `4590.00` can be refilled only after bid is `4597.50` or higher.

Should not replace:

```text
slots already represented by a position
slots already represented by a pending order
slots outside the original base grid
```

### `SlotComment(side, level)`

Returns:

```text
STR B1 ... STR B20
STR S1 ... STR S20
```

### `HasSlot(side, level)`

Purpose:

- Check both open positions and pending orders for this base slot.

## LotEngine Module

### `LotForLevel(level)`

Purpose:

- Calculate lot size from tier or auto-balance mode.

Default:

```text
level <= nearLevels              -> near lot
level <= nearLevels + midLevels  -> mid lot
else                             -> far lot
```

### `ApplyBoostLot(volume)`

Purpose:

- Double lots after daily loss if enabled.

### `NormalizeVolume(volume)`

Purpose:

- Clamp to broker min/max/step.

## ExposureGuard Module

This module is required for v2 before longer demo testing.

### `RefreshExposureStats()`

Purpose:

- Count current buy/sell positions.
- Count current buy/sell pending orders.
- Sum buy/sell lots.
- Sum floating P/L.

### `AllowNewBaseOrder(side, volume)`

Purpose:

- Decide if a normal base grid order is allowed.
- Hard-cap same-side exposure so positions plus pending orders do not exceed `InpLevelsPerSide`.

Should check:

```text
side positions + side pending orders <= InpLevelsPerSide
max total orders/positions
max same-side orders/positions
max same-side lots
margin availability
```

### `ShouldBlockNewOrders()`

Purpose:

- Return true if daily lock, spread block, margin issue, or exposure cap is active.

## TrailingEngine Module

### `ManageTrailingStops()`

Purpose:

- Iterate positions.
- Find one position eligible for profitable trailing.
- Use ATR-based distance when enabled.
- Modify only one position per pass to reduce broker request pressure.

Default ATR settings:

```text
InpUseAtrTrailing = true
InpTrailAtrTimeframe = PERIOD_M15
InpTrailAtrPeriod = 14
InpTrailAtrArmMultiplier = 1.0
InpTrailAtrDistanceMultiplier = 1.0
InpTrailAtrUseClosedBar = true
```

### `CanArmTrailing(position)`

ATR formula when enabled and ATR is available:

Buy:

```text
bid - entry >= ATR * InpTrailAtrArmMultiplier
```

Sell:

```text
entry - ask >= ATR * InpTrailAtrArmMultiplier
```

Fallback formula:

```text
favorable move >= profitGridsToArmTrail * gridStep
```

### `ProposedTrailingSL(position)`

ATR formula when enabled and ATR is available:

Buy:

```text
sl = bid - ATR * InpTrailAtrDistanceMultiplier
sl must be > entry
```

Sell:

```text
sl = ask + ATR * InpTrailAtrDistanceMultiplier
sl must be < entry
```

Fallback formula:

Buy:

```text
sl = bid - trailDistanceAfterArmGrids * gridStep
sl must be > entry
```

Sell:

```text
sl = ask + trailDistanceAfterArmGrids * gridStep
sl must be < entry
```

### `IsBetterSL(position, proposedSL)`

Purpose:

- Buy: proposed SL must be greater than current SL.
- Sell: proposed SL must be lower than current SL.

### `IsTrailingAllowedByEquity()`

Current rule:

```text
if trailEvenIfEquityBelowBalance == false:
    require equity >= balance + equityGreenGate
```

Open decision:

```text
The original may trail profitable legs even when total basket equity is below balance.
We need journal/screenshot proof before finalizing this rule.
```

## ReentryEngine Module

### `OnTrailingStopExit(deal)`

Purpose:

- Confirm the deal was a stop-loss exit.
- Confirm the stopped position was profitable.
- Leave the original base slot available for refill.
- Do not create extra opposite-side orders.

Rule:

```text
Buy orders are only base STR B1..STR BN levels above anchor.
Sell orders are only base STR S1..STR SN levels below anchor.
No STR RB / STR RS extra orders are created in v2.
```

Grid refill is handled by `GridEngine.PlaceMissingGridOrders()`.

### Re-entry invariant

```text
No extra re-entry order family exists in v2.
No STR RB / STR RS comments are used.
If a profitable trailed position closes, its original base slot becomes empty.
GridEngine may refill only that same base slot.
The slot is refilled only after price moves opposite from that level by the configured refill distance.
```

This means:

```text
Buy level N price  = anchor + N * gridStep
Sell level N price = anchor - N * gridStep
```

So the EA must not place:

- buy orders below `anchor`
- sell orders above `anchor`
- more than `InpLevelsPerSide` buy-side objects
- more than `InpLevelsPerSide` sell-side objects

## CycleCloseEngine Module

### `CheckCycleTarget()`

Current formula:

```text
cycleNet = AccountEquity - cycleStartBalance
close if cycleNet >= cycleTarget
```

### `CycleTargetUSD()`

Fixed mode:

```text
target = fixedModeCycleNetBankTargetUSD
```

Auto mode:

```text
target = balance * autoModeCycleTargetPercent / 100
```

Boost mode:

```text
target *= 2
```

### `StartCloseAll(reason)`

Purpose:

- Set close-all mode.
- Store reason.
- Do not close all immediately inside other modules.

### `ProcessCloseQueue()`

Purpose:

- Close positions and delete orders one at a time.
- Continue on each timer pass until flat.

Order:

```text
1. Close open positions.
2. Delete pending orders.
3. Reset cycle state.
```

Open decision:

```text
Should daily profit cap close all positions, or only stop new orders?
```

## Diagnostics Module

### `LogCycleStarted()`

Required format:

```text
Straddle: cycle started, anchor ..., gridMin ..., gridMax ... - X of Y stop orders placed
```

### `LogDailyAnchor()`

Required format:

```text
Straddle: DAILY LIMITS - new day equity anchor=...
```

### `LogCloseReason(reason)`

Purpose:

- Every material balance drop must have a journal reason.

### `UpdatePanel()`

Purpose:

- Show concise chart status when UI is enabled.

Should include:

```text
status
anchor
grid step
cycle target
cycle net
positions
pending orders
daily anchor
equity
daily lock status
```

## Current Method Mapping From v1

| Current Method | Future Module | Notes |
| --- | --- | --- |
| `OnInit` | Main EA | Keep as orchestration only |
| `OnDeinit` | Main EA / Diagnostics | Clear timer and panel |
| `OnTick` | Main EA / Diagnostics | Panel only |
| `OnTimer` | Main EA | Sequence modules |
| `OnTradeTransaction` | Main EA / ReentryEngine | Route deal events |
| `DayStart` | DailyLimits | Utility |
| `RefreshDailyLimits` | DailyLimits | Move out of main file |
| `SpreadOK` | Broker | Broker condition |
| `IsOurPosition` | Broker or State | Prefer Broker query helper |
| `IsOurOrder` | Broker or State | Prefer Broker query helper |
| `CountOurPositions` | ExposureGuard | Replace with full stats |
| `CountOurOrders` | ExposureGuard | Replace with full stats |
| `MidPrice` | Broker | Tick snapshot |
| `CalculateStep` | GridEngine | Confirmed formula |
| `StartCycle` | GridEngine / State | Split into build plan and place orders |
| `RecoverState` | State | Recovery only |
| `PlaceInitialGridOrders` | GridEngine | Use ExposureGuard before sending |
| `PlaceMissingGridOrders` | GridEngine | Refill empty base slots only, using exposure caps |
| `PlaceGridOrder` | GridEngine + Broker | Strategy part in GridEngine, send part in Broker |
| `PendingPriceValid` | Broker | Broker min distance check |
| `MinimumStopDistance` | Broker | Broker min distance check |
| `SlotComment` | GridEngine | Naming convention |
| `HasSlot` | State / GridEngine | Query slot existence |
| `HasComment` | State | Generic query |
| `LotForLevel` | LotEngine | Tier or auto lot |
| `NormalizeVolume` | LotEngine / Broker | Broker volume normalization |
| `TradeAccepted` | Broker | Broker retcode handling |
| `ManageTrailingStops` | TrailingEngine | Needs helper split |
| `LevelFromPrice` | GridEngine | Slot math |
| `FindEntryPrice` | State / Broker history | Deal history helper |
| `HandleTrailingStopExit` | ReentryEngine | Log profitable SL exits; no order creation |
| `CheckProfitTargets` | CycleCloseEngine | Cycle target only |
| `CycleTargetUSD` | CycleCloseEngine | Target calculation |
| `OpenProfit` | ExposureGuard | Part of exposure stats |
| `StartCloseAll` | CycleCloseEngine | Queue close |
| `ProcessCloseAll` | CycleCloseEngine + Broker | Send one close/delete per pass |
| `UpdatePanel` | Diagnostics | No trading logic |

## Current v2 Coding Target

The current target is not extra exposure caps. It is base-slot correctness.

Required behavior:

```text
InpLevelsPerSide = N
maximum buy-side objects  = N
maximum sell-side objects = N
maximum total objects     = 2N
```

Objects means:

```text
open positions + pending stop orders
```

Default optional extra caps:

```text
InpMaxTotalOrdersAndPositions = 0
InpMaxSameSideOrdersAndPositions = 0
InpMaxSameSideLots = 0.0
```

`0` means the optional cap is disabled. The non-optional cap is still `InpLevelsPerSide`.
