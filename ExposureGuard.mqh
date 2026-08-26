#ifndef STRADDLE_EXPOSURE_GUARD_MQH
#define STRADDLE_EXPOSURE_GUARD_MQH

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
         count++;
   }
   return count;
}

int CountOurOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(IsOurOrder(ticket))
         count++;
   }
   return count;
}

double OpenProfit()
{
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
      {
         profit += PositionGetDouble(POSITION_PROFIT);
         profit += PositionGetDouble(POSITION_SWAP);
      }
   }
   return profit;
}

ExposureStats RefreshExposureStats()
{
   ExposureStats stats;
   stats.buyPositions = 0;
   stats.sellPositions = 0;
   stats.buyOrders = 0;
   stats.sellOrders = 0;
   stats.buyLots = 0.0;
   stats.sellLots = 0.0;
   stats.floatingProfit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      stats.floatingProfit += PositionGetDouble(POSITION_PROFIT);
      stats.floatingProfit += PositionGetDouble(POSITION_SWAP);

      if(type == POSITION_TYPE_BUY)
      {
         stats.buyPositions++;
         stats.buyLots += volume;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         stats.sellPositions++;
         stats.sellLots += volume;
      }
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurOrder(ticket))
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);

      if(type == ORDER_TYPE_BUY_STOP)
      {
         stats.buyOrders++;
         stats.buyLots += volume;
      }
      else if(type == ORDER_TYPE_SELL_STOP)
      {
         stats.sellOrders++;
         stats.sellLots += volume;
      }
   }

   return stats;
}

bool ExposureAllowsSide(const ExposureStats &stats, const int side, const double newVolume)
{
   int total = stats.buyPositions + stats.sellPositions + stats.buyOrders + stats.sellOrders;
   if(InpMaxTotalOrdersAndPositions > 0 && total + 1 > InpMaxTotalOrdersAndPositions)
      return false;

   int sideCount = side > 0
      ? stats.buyPositions + stats.buyOrders
      : stats.sellPositions + stats.sellOrders;
   if(InpMaxSameSideOrdersAndPositions > 0 &&
      sideCount + 1 > InpMaxSameSideOrdersAndPositions)
      return false;

   double sideLots = side > 0 ? stats.buyLots : stats.sellLots;
   if(InpMaxSameSideLots > 0.0 && sideLots + newVolume > InpMaxSameSideLots + 1e-8)
      return false;

   return true;
}

bool AllowNewBaseOrder(const int side, const double volume)
{
   ExposureStats stats = RefreshExposureStats();
   int sideCount = side > 0
      ? stats.buyPositions + stats.buyOrders
      : stats.sellPositions + stats.sellOrders;
   if(sideCount + 1 > InpLevelsPerSide)
      return false;

   return ExposureAllowsSide(stats, side, volume);
}

#endif
