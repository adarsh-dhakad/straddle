#ifndef STRADDLE_DAILY_LIMITS_MQH
#define STRADDLE_DAILY_LIMITS_MQH

datetime DayStart(const datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

void InitDailyLimits()
{
   g_dayStart = DayStart(TimeCurrent());
   g_dayEquityAnchor = AccountInfoDouble(ACCOUNT_EQUITY);
   PrintFormat("Straddle: DAILY LIMITS - new day equity anchor=%.2f", g_dayEquityAnchor);
}

void RefreshDailyLimits()
{
   datetime today = DayStart(TimeCurrent());
   if(today != g_dayStart)
   {
      g_dayStart = today;
      g_dayEquityAnchor = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyLocked = false;
      if(TimeCurrent() >= g_boostUntilDay)
         g_thisCycleBoosted = false;
      PrintFormat("Straddle: DAILY LIMITS - new day equity anchor=%.2f", g_dayEquityAnchor);
   }

   if(!InpUseDailyHardStop || g_dailyLocked)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double openProfit = OpenProfit();

   double profitLimit = InpDailyLimitsUsePercent
      ? g_dayEquityAnchor * InpDailyProfitCapPercentDayStartEquity / 100.0
      : InpDayEquityProfitCapUSD;
   double lossLimit = InpDailyLimitsUsePercent
      ? g_dayEquityAnchor * InpHardDailyLossCapPercentDayStartEq / 100.0
      : InpHardDayEquityLossCapUSD;

   bool profitHit = (profitLimit > 0.0 && equity >= g_dayEquityAnchor + profitLimit);
   bool lossHit = (lossLimit > 0.0 && equity <= g_dayEquityAnchor - lossLimit);
   if(InpUseIndependentFloatingPLStop && lossLimit > 0.0 && openProfit <= -lossLimit)
      lossHit = true;

   if(profitHit)
   {
      g_dailyLocked = true;
      StartCloseAll("Daily equity profit cap reached");
      PrintFormat("Straddle: DAILY LIMITS - profit cap hit, anchor %.2f, balance %.2f, equity %.2f",
                  g_dayEquityAnchor, balance, equity);
   }
   else if(lossHit)
   {
      g_dailyLocked = true;
      g_noTradeUntil = g_dayStart + NormalizedDailyPauseDays() * 86400;
      if(InpAfterLossNextDayLotsAndTarget2x)
         g_boostUntilDay = g_noTradeUntil + 86400;
      StartCloseAll("Hard daily equity loss cap reached");
      PrintFormat("Straddle: DAILY LIMITS - hard loss cap hit, anchor %.2f, balance %.2f, equity %.2f",
                  g_dayEquityAnchor, balance, equity);
   }
}

#endif
