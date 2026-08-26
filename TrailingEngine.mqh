#ifndef STRADDLE_TRAILING_ENGINE_MQH
#define STRADDLE_TRAILING_ENGINE_MQH

bool IsTrailingAllowedByEquity()
{
   if(InpTrailEvenIfEquityBelowBalance)
      return true;
   return AccountInfoDouble(ACCOUNT_EQUITY) >=
          AccountInfoDouble(ACCOUNT_BALANCE) + InpEquityGreenGateUSD;
}

bool CanArmTrailing(const ENUM_POSITION_TYPE type,
                    const double entry,
                    const MqlTick &tick)
{
   double favorable = (type == POSITION_TYPE_BUY)
      ? tick.bid - entry
      : entry - tick.ask;
   return favorable >= InpProfitGridsToArmTrail * g_step;
}

double ProposedTrailingSL(const ENUM_POSITION_TYPE type,
                          const double entry,
                          const MqlTick &tick)
{
   double minDistance = MinimumStopDistance();
   double proposed = 0.0;

   if(type == POSITION_TYPE_BUY)
   {
      proposed = NormalizeDouble(MathMin(tick.bid - minDistance,
                                         tick.bid - InpTrailDistanceAfterArmGrids * g_step),
                                 _Digits);
      if(proposed <= entry + _Point)
         return 0.0;
   }
   else
   {
      proposed = NormalizeDouble(MathMax(tick.ask + minDistance,
                                         tick.ask + InpTrailDistanceAfterArmGrids * g_step),
                                 _Digits);
      if(proposed >= entry - _Point)
         return 0.0;
   }

   return proposed;
}

bool IsBetterSL(const ENUM_POSITION_TYPE type,
                const double oldSL,
                const double proposedSL)
{
   if(proposedSL <= 0.0)
      return false;
   if(type == POSITION_TYPE_BUY)
      return oldSL <= 0.0 || proposedSL > oldSL + _Point;
   return oldSL <= 0.0 || proposedSL < oldSL - _Point;
}

void ManageTrailingStops()
{
   if(!InpTrailEachInProfitLegOnly || g_step <= 0.0)
      return;
   if(!IsTrailingAllowedByEquity())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL = PositionGetDouble(POSITION_SL);

      if(!CanArmTrailing(type, entry, tick))
         continue;

      double proposed = ProposedTrailingSL(type, entry, tick);
      if(!IsBetterSL(type, oldSL, proposed))
         continue;

      ModifyPositionSL(ticket, proposed);
      return;
   }
}

#endif
