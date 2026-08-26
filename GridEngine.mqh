#ifndef STRADDLE_GRID_ENGINE_MQH
#define STRADDLE_GRID_ENGINE_MQH

double CalculateStep(const double anchor)
{
   double step = InpReferenceSpacingUSD;
   if(InpScaleSpacingByCurrentPrice)
      step *= anchor / InpGridStepReferencePrice;
   return NormalizeDouble(step, _Digits);
}

string SlotComment(const int side, const int level)
{
   return StringFormat("STR %s%d", side > 0 ? "B" : "S", level);
}

double SlotPrice(const int side, const int level)
{
   return NormalizeDouble(g_anchor + side * level * g_step, _Digits);
}

bool RefillOppositeMovePassed(const int side, const double slotPrice)
{
   if(InpGridRefillOppositeMoveUSD <= 0.0)
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   if(side > 0)
      return tick.ask <= slotPrice - InpGridRefillOppositeMoveUSD;
   return tick.bid >= slotPrice + InpGridRefillOppositeMoveUSD;
}

bool HasSlot(const int side, const int level)
{
   string comment = SlotComment(side, level);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket) && PositionGetString(POSITION_COMMENT) == comment)
         return true;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(IsOurOrder(ticket) && OrderGetString(ORDER_COMMENT) == comment)
         return true;
   }
   return false;
}

bool HasComment(const string comment)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket) && PositionGetString(POSITION_COMMENT) == comment)
         return true;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(IsOurOrder(ticket) && OrderGetString(ORDER_COMMENT) == comment)
         return true;
   }
   return false;
}

int LevelFromPrice(const double price)
{
   if(g_step <= 0.0)
      return 0;
   return (int)MathRound(MathAbs(price - g_anchor) / g_step);
}

bool PlaceGridOrder(const int side, const int level)
{
   if(HasSlot(side, level))
      return false;

   double price = SlotPrice(side, level);
   if(!PendingPriceValid(side, price))
      return false;

   double volume = LotForLevel(level);
   if(volume <= 0.0)
      return false;

   if(!AllowNewBaseOrder(side, volume))
   {
      if(InpLogMode >= 1)
         PrintFormat("Straddle: exposure cap blocked base %s level %d",
                     side > 0 ? "BUY" : "SELL", level);
      return false;
   }

   return PlaceStopOrder(side, volume, price, SlotComment(side, level));
}

int PlaceInitialGridOrders()
{
   int placed = 0;
   for(int level = 1; level <= InpLevelsPerSide; level++)
   {
      if(PlaceGridOrder(1, level))
         placed++;
      if(PlaceGridOrder(-1, level))
         placed++;
   }
   return placed;
}

void PlaceMissingGridOrders()
{
   if(g_anchor <= 0.0 || g_step <= 0.0)
      return;

   for(int level = 1; level <= InpLevelsPerSide; level++)
   {
      if(!HasSlot(1, level))
      {
         double buyPrice = SlotPrice(1, level);
         if(RefillOppositeMovePassed(1, buyPrice))
            PlaceGridOrder(1, level);
      }
      if(!HasSlot(-1, level))
      {
         double sellPrice = SlotPrice(-1, level);
         if(RefillOppositeMovePassed(-1, sellPrice))
            PlaceGridOrder(-1, level);
      }
   }
}

void StartCycle()
{
   double mid = MidPrice();
   if(mid <= 0.0)
      return;

   g_anchor = NormalizeDouble(mid, _Digits);
   g_step = CalculateStep(g_anchor);
   if(g_step <= 0.0)
      return;

   g_cycleStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_cycleStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_cycleActive = true;
   g_thisCycleBoosted = (InpAfterLossNextDayLotsAndTarget2x &&
                         g_boostUntilDay > 0 &&
                         TimeCurrent() < g_boostUntilDay);

   int placed = PlaceInitialGridOrders();
   int requested = InpLevelsPerSide * 2;
   double gridMin = NormalizeDouble(g_anchor - InpLevelsPerSide * g_step, _Digits);
   double gridMax = NormalizeDouble(g_anchor + InpLevelsPerSide * g_step, _Digits);

   g_status = StringFormat("Cycle anchor %.3f, step %.3f, orders %d/%d",
                           g_anchor, g_step, placed, requested);
   PrintFormat("Straddle: cycle started, anchor %.3f, gridMin %.3f, gridMax %.3f - %d of %d stop orders placed",
               g_anchor, gridMin, gridMax, placed, requested);
}

void RecoverState()
{
   if(CountOurPositions() == 0 && CountOurOrders() == 0)
      return;

   double mid = MidPrice();
   if(mid <= 0.0)
      mid = InpGridStepReferencePrice;

   g_step = CalculateStep(mid);
   g_cycleStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_cycleStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_cycleActive = true;
   g_status = "Recovered existing exposure";

   string buyOne = SlotComment(1, 1);
   string sellOne = SlotComment(-1, 1);
   double sum = 0.0;
   int samples = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurOrder(ticket))
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(comment == buyOne)
      {
         sum += price - g_step;
         samples++;
      }
      else if(comment == sellOne)
      {
         sum += price + g_step;
         samples++;
      }
   }

   if(samples > 0)
   {
      g_anchor = NormalizeDouble(sum / samples, _Digits);
      g_step = CalculateStep(g_anchor);
      g_status = "Recovered existing cycle";
   }
}

#endif
