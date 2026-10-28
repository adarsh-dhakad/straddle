//+------------------------------------------------------------------+
//| XAUUSD_Straddle_Replica_v2.mq5                                   |
//| Modular straddle-grid replica. MT5 hedging account required.      |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"

#include "modules/Types.mqh"
#include "modules/Inputs.mqh"
#include "modules/State.mqh"
#include "modules/Broker.mqh"
#include "modules/ExposureGuard.mqh"
#include "modules/LotEngine.mqh"
#include "modules/GridEngine.mqh"
#include "modules/CycleCloseEngine.mqh"
#include "modules/DailyLimits.mqh"
#include "modules/TrailingEngine.mqh"
#include "modules/ReentryEngine.mqh"
#include "modules/Diagnostics.mqh"

void SetEngineTimer(const int milliseconds)
{
   int nextTimer = milliseconds;
   if(nextTimer < 100)
      nextTimer = 100;

   if(g_activeTimerMilliseconds == nextTimer)
      return;

   EventKillTimer();
   EventSetMillisecondTimer(nextTimer);
   g_activeTimerMilliseconds = nextTimer;
}

bool EngineHasNewTick()
{
   if(!InpRunEngineOncePerTick)
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return true;

   if(tick.time_msc > 0)
   {
      if(g_lastEngineTickMsc == tick.time_msc)
         return false;
      g_lastEngineTickMsc = tick.time_msc;
      g_lastEngineTickTime = tick.time;
      return true;
   }

   if(g_lastEngineTickTime == tick.time)
      return false;
   g_lastEngineTickTime = tick.time;
   return true;
}

int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   if(!ValidateGridInputs() || !ValidateTrailingInputs())
      return INIT_PARAMETERS_INCORRECT;

   if(!InitBroker())
      return INIT_FAILED;
   if(!InitGridEngine())
      return INIT_FAILED;
   if(!InitTrailingEngine())
      return INIT_FAILED;

   InitDailyLimits();
   RecoverState();
   SetEngineTimer(InpTimerMilliseconds);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseGridEngine();
   ReleaseTrailingEngine();
   Comment("");
}

void OnTick()
{
   UpdatePanel();
}

void OnTimer()
{
   RefreshDailyLimits();

   bool marketOpen = MarketOpenForNewOrders();
   SetEngineTimer(marketOpen ? InpTimerMilliseconds : InpClosedMarketTimerMilliseconds);

   if(!marketOpen)
   {
      g_status = "Market/session closed; sleeping";
      UpdatePanel();
      return;
   }

   if(!EngineHasNewTick() && !g_closeAll)
   {
      UpdatePanel();
      return;
   }

   if(g_closeAll)
   {
      ProcessCloseAll();
      UpdatePanel();
      return;
   }

   if(g_dailyLocked || TimeCurrent() < g_noTradeUntil)
   {
      UpdatePanel();
      return;
   }

   if(!SpreadOK())
   {
      g_status = "Waiting for acceptable spread";
      UpdatePanel();
      return;
   }

   if(!g_cycleActive && CountOurPositions() == 0 && CountOurOrders() == 0)
      StartCycle();

   if(!g_cycleActive)
   {
      UpdatePanel();
      return;
   }

   if(CheckProfitTargets())
   {
      UpdatePanel();
      return;
   }

   ManageTrailingStops();

   if(InpKeepBuySellStopsOnChart)
      PlaceMissingGridOrders();

   UpdatePanel();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol ||
      HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber)
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
      if(reason == DEAL_REASON_SL && g_cycleActive && !g_closeAll)
         HandleTrailingStopExit(trans.deal);
   }
}

//+------------------------------------------------------------------+
