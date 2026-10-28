#ifndef STRADDLE_REENTRY_ENGINE_MQH
#define STRADDLE_REENTRY_ENGINE_MQH

double FindEntryPrice(const ulong positionId)
{
   if(!HistorySelect(TimeCurrent() - 86400 * 30, TimeCurrent()))
      return 0.0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID) != positionId)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         return HistoryDealGetDouble(ticket, DEAL_PRICE);
   }
   return 0.0;
}

void HandleTrailingStopExit(const ulong deal)
{
   if(HistoryDealGetDouble(deal, DEAL_PROFIT) <= 0.0)
      return;

   double entryPrice = FindEntryPrice((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID));
   if(entryPrice <= 0.0)
      entryPrice = HistoryDealGetDouble(deal, DEAL_PRICE);

   long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
   int exitedSide = (dealType == DEAL_TYPE_SELL) ? 1 : -1;
   int level = LevelFromPrice(entryPrice);

   if(level >= 1 && level <= InpLevelsPerSide)
   {
      // Do not create extra opposite-side re-entry orders. The closed base
      // slot is now empty, and GridEngine will refill only that base slot
      // if its price is still valid and the ATR/fixed-distance refill gate passes.
      g_status = StringFormat("Trailing banked %s level %d; refill base grid only",
                              exitedSide > 0 ? "BUY" : "SELL", level);
   }
}

#endif
