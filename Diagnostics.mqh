#ifndef STRADDLE_DIAGNOSTICS_MQH
#define STRADDLE_DIAGNOSTICS_MQH

void UpdatePanel()
{
   if(!InpChartUiEnabled)
   {
      Comment("");
      return;
   }

   ExposureStats stats = RefreshExposureStats();
   int positions = stats.buyPositions + stats.sellPositions;
   int orders = stats.buyOrders + stats.sellOrders;

   Comment("Straddle Replica v2",
           "\nStatus: ", g_status,
           "\nAnchor: ", DoubleToString(g_anchor, _Digits),
           "  Step: ", DoubleToString(g_step, _Digits),
           "\nCycle target: $", DoubleToString(CycleTargetUSD(), 2),
           "  Cycle net: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY) - g_cycleStartBalance, 2),
           "\nPositions: ", positions,
           "  Orders: ", orders,
           "\nBuy count: ", stats.buyPositions + stats.buyOrders,
           "  Sell count: ", stats.sellPositions + stats.sellOrders,
           "\nBuy lots: ", DoubleToString(stats.buyLots, 2),
           "  Sell lots: ", DoubleToString(stats.sellLots, 2),
           "\nDaily anchor: $", DoubleToString(g_dayEquityAnchor, 2),
           "  Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
           g_dailyLocked ? "\nDAILY LOCKED" : "",
           TimeCurrent() < g_noTradeUntil ? "\nNO-TRADE PAUSE" : "");
}

#endif
