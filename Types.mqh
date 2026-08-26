#ifndef STRADDLE_TYPES_MQH
#define STRADDLE_TYPES_MQH

enum ENUM_STR_LOT_MODE
{
   LOT_MODE_FIXED = 0,
   LOT_MODE_AUTO_BALANCE = 1
};

struct ExposureStats
{
   int buyPositions;
   int sellPositions;
   int buyOrders;
   int sellOrders;
   double buyLots;
   double sellLots;
   double floatingProfit;
};

#endif
