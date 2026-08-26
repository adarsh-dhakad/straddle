#ifndef STRADDLE_INPUTS_MQH
#define STRADDLE_INPUTS_MQH

input group "1. Account"
input long   InpMagicNumber                         = 26011001;
input int    InpLogMode                             = 0;       // 0=errors+cycle banks, 1=state events, 2=debug

input group "2. Grid and Lots"
input int    InpLevelsPerSide                       = 30;      // 20 buy stops + 20 sell stops = 40 total
input double InpReferenceSpacingUSD                 = 1.0;
input bool   InpScaleSpacingByCurrentPrice          = true;
input double InpGridStepReferencePrice              = 3000.0;
input bool   InpKeepBuySellStopsOnChart             = true;
input double InpNearTierLots                        = 0.01;
input double InpMidTierLots                         = 0.06;
input double InpFarTierLots                         = 0.15;
input int    InpNearTierLevels                      = 10;
input int    InpMidTierLevels                       = 10;

input group "2b. Lot Mode"
input ENUM_STR_LOT_MODE InpLotMode                  = LOT_MODE_FIXED;
input double InpReferenceBalanceForAutoLots         = 5000.0;
input double InpAutoBaseNearTierLots                = 0.01;
input double InpAutoBaseMidTierLots                 = 0.05;
input double InpAutoBaseFarTierLots                 = 0.15;

input group "2c. Grid Refill"
input double InpGridRefillOppositeMoveUSD           = 2.0;     // refill empty slot only after price moves opposite by this USD amount

input group "3. Profit Targets"
input double InpFixedModeCycleNetBankTargetUSD      = 50.0;
input double InpWholeBookGreenBankUSD               = 0.0;     // 0=off

input group "3b. Daily Limits"
input bool   InpUseDailyHardStop                    = true;
input bool   InpUseIndependentFloatingPLStop        = false;
input bool   InpDailyLimitsUsePercent               = false;   // false=USD caps
input double InpDayEquityProfitCapUSD               = 6000;
input double InpHardDayEquityLossCapUSD             = 3000.0;
input double InpAutoModeCycleTargetPercentBalance   = 0.1;
input double InpDailyProfitCapPercentDayStartEquity = 2;
input double InpHardDailyLossCapPercentDayStartEq   = 20.0;
input bool   InpAfterLossNextDayLotsAndTarget2x     = true;
input int    InpNoTradeDaysAfterDailyLoss           = 1;

input group "4. Trend (detection + optional one-side)"
input bool   InpBothSidesAlways                     = false;
input bool   InpAllowNewCycleWhenFlat               = false;
input int    InpBarsForTrendMove                    = 6;
input double InpUsdMoveToCallTrend                  = 30.0;
input bool   InpDoubleWithTrendLotsDeepDDTrend      = true;
input double InpDeepDDTrendThresholdUSD             = 800.0;

input group "5. Trailing (per-leg only; whole basket waits for TargetUSD)"
input bool   InpTrailEachInProfitLegOnly            = true;
input int    InpProfitGridsToArmTrail               = 8;
input int    InpTrailDistanceAfterArmGrids          = 1;
input bool   InpTrailEvenIfEquityBelowBalance       = true;
input double InpEquityGreenGateUSD                  = 0.0;

input group "6. Extra engines (OFF = pure straddle)"
input bool   InpUseBasketRecovery                   = false;
input double InpBasketRecoveryTargetUSD             = 0.0;
input int    InpBasketRecoveryMaxOrders             = 20;
input double InpBasketRecoveryLot                   = 0.0;
input double InpBasketRecoveryStepUSD               = 0.0;
input bool   InpUseEquityRecovery                   = false;
input double InpEquityRecoveryDDUSD                 = 80.0;
input bool   InpHoldLosersUntilCycleNetTarget       = true;
input int    InpFloatSleeperMaxHours                = 24;
input bool   InpUseRescueHedge                      = false;

input group "6b. Exposure Guard"
input int    InpMaxTotalOrdersAndPositions          = 0;       // optional extra cap; 0=off
input int    InpMaxSameSideOrdersAndPositions       = 0;       // optional extra cap; 0=off
input double InpMaxSameSideLots                     = 0.0;     // optional extra cap; 0=off

input group "7. Chart"
input bool   InpChartUiEnabled                      = false;

input group "8. Execution"
input int    InpMaxSpreadPoints                     = 500;
input ulong  InpMaxSlippagePoints                   = 50;
input int    InpTimerMilliseconds                   = 1000;    // normal open-market engine timer
input int    InpClosedMarketTimerMilliseconds       = 300000;  // 5 minutes while market/session is closed
input bool   InpUseMarketSessionFilter              = true;
input bool   InpRunEngineOncePerTick                = true;    // tester speed: skip repeated timer passes on same tick

bool ValidateInputs()
{
   if(InpLevelsPerSide < 1 || InpLevelsPerSide > 200)
      return false;
   if(InpReferenceSpacingUSD <= 0.0 || InpGridStepReferencePrice <= 0.0)
      return false;
   if(InpNearTierLots <= 0.0 || InpMidTierLots <= 0.0 || InpFarTierLots <= 0.0)
      return false;
   if(InpNearTierLevels < 0 || InpMidTierLevels < 0)
      return false;
   if(InpProfitGridsToArmTrail < -1 || InpTrailDistanceAfterArmGrids < 1)
      return false;
   if(InpTimerMilliseconds < 100 || InpClosedMarketTimerMilliseconds < 1000)
      return false;
   if(InpMaxTotalOrdersAndPositions < 0 ||
      InpMaxSameSideOrdersAndPositions < 0 ||
      InpMaxSameSideLots < 0.0)
      return false;
   return true;
}

int NormalizedDailyPauseDays()
{
   int days = InpNoTradeDaysAfterDailyLoss;
   if(days < 1)
      days = 1;
   if(days > 4)
      days = 4;
   return days;
}

#endif
