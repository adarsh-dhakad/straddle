#ifndef STRADDLE_GRID_ENGINE_MQH
#define STRADDLE_GRID_ENGINE_MQH

input group "2c. Grid Refill"
input double InpGridRefillOppositeMoveUSD           = 2.0;     // refill empty slot only after price moves opposite by this USD amount
input bool            InpGridRefillUseAtrDistance   = true;    // true=use ATR distance for refill gate; false=use fixed USD above
input ENUM_TIMEFRAMES InpGridRefillAtrTimeframe     = PERIOD_M15;
input int             InpGridRefillAtrPeriod        = 14;
input double          InpGridRefillAtrMultiplier    = 1.0;
input bool            InpGridRefillAtrUseClosedBar  = true;

input group "2d. Cycle Anchor"
input double InpCycleAnchorModuloUSD                = 30.0;    // 0=use current mid; >0 snap/wait for price modulo step

int g_gridRefillAtrHandle = INVALID_HANDLE;

bool ValidateGridInputs()
{
   if(InpGridRefillOppositeMoveUSD < 0.0 || InpCycleAnchorModuloUSD < 0.0)
      return false;
   if(InpGridRefillUseAtrDistance &&
      (InpGridRefillAtrPeriod < 1 || InpGridRefillAtrMultiplier <= 0.0))
      return false;
   return true;
}

bool InitGridEngine()
{
   if(!InpGridRefillUseAtrDistance)
      return true;

   g_gridRefillAtrHandle = iATR(_Symbol, InpGridRefillAtrTimeframe, InpGridRefillAtrPeriod);
   if(g_gridRefillAtrHandle == INVALID_HANDLE)
   {
      Print("Straddle: failed to create ATR handle for grid refill");
      return false;
   }
   return true;
}

void ReleaseGridEngine()
{
   if(g_gridRefillAtrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_gridRefillAtrHandle);
      g_gridRefillAtrHandle = INVALID_HANDLE;
   }
}

double CurrentGridRefillAtr()
{
   if(!InpGridRefillUseAtrDistance || g_gridRefillAtrHandle == INVALID_HANDLE)
      return 0.0;

   double values[1];
   int shift = InpGridRefillAtrUseClosedBar ? 1 : 0;
   if(CopyBuffer(g_gridRefillAtrHandle, 0, shift, 1, values) != 1)
      return 0.0;

   return values[0];
}

double GridRefillDistance()
{
   if(InpGridRefillUseAtrDistance)
   {
      double atr = CurrentGridRefillAtr();
      if(atr > 0.0)
         return atr * InpGridRefillAtrMultiplier;
   }
   return InpGridRefillOppositeMoveUSD;
}

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

double CycleAnchorFromPrice(const double price)
{
   if(InpCycleAnchorModuloUSD <= 0.0)
      return NormalizeDouble(price, _Digits);

   double snapped = MathRound(price / InpCycleAnchorModuloUSD) * InpCycleAnchorModuloUSD;
   return NormalizeDouble(snapped, _Digits);
}

bool CycleAnchorReady(const double anchor, const double step)
{
   if(InpCycleAnchorModuloUSD <= 0.0)
      return true;
   if(anchor <= 0.0 || step <= 0.0)
      return false;

   double firstBuy = NormalizeDouble(anchor + step, _Digits);
   double firstSell = NormalizeDouble(anchor - step, _Digits);
   return PendingPriceValid(1, firstBuy) && PendingPriceValid(-1, firstSell);
}

bool RefillOppositeMovePassed(const int side, const double slotPrice)
{
   double refillDistance = GridRefillDistance();
   if(refillDistance <= 0.0)
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   if(side > 0)
      return tick.ask <= slotPrice - refillDistance;
   return tick.bid >= slotPrice + refillDistance;
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

   double candidateAnchor = CycleAnchorFromPrice(mid);
   double candidateStep = CalculateStep(candidateAnchor);
   if(candidateStep <= 0.0)
      return;

   if(!CycleAnchorReady(candidateAnchor, candidateStep))
   {
      g_status = StringFormat("Waiting for cycle anchor %.3f, mid %.3f",
                              candidateAnchor, mid);
      return;
   }

   g_anchor = candidateAnchor;
   g_step = candidateStep;

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
