#ifndef STRADDLE_BROKER_MQH
#define STRADDLE_BROKER_MQH

#include <Trade/Trade.mqh>

CTrade trade;

bool InitBroker()
{
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) !=
      ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("Straddle: this EA requires an MT5 hedging account.");
      return false;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints((int)InpMaxSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   return true;
}

bool TradeAccepted()
{
   uint code = trade.ResultRetcode();
   return code == TRADE_RETCODE_DONE ||
          code == TRADE_RETCODE_PLACED ||
          code == TRADE_RETCODE_DONE_PARTIAL ||
          code == TRADE_RETCODE_NO_CHANGES;
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
}

int SessionSeconds(const datetime value)
{
   long raw = (long)value;
   if(raw >= 0 && raw <= 86400)
      return (int)raw;

   MqlDateTime dt;
   TimeToStruct(value, dt);
   return dt.hour * 3600 + dt.min * 60 + dt.sec;
}

bool SymbolSessionOpenNow()
{
   if(!InpUseMarketSessionFilter)
      return true;

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int nowSeconds = dt.hour * 3600 + dt.min * 60 + dt.sec;

   bool hasSessions = false;
   datetime fromTime = 0;
   datetime toTime = 0;

   for(uint session = 0; session < 24; session++)
   {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week,
                                 session, fromTime, toTime))
         break;

      hasSessions = true;
      int fromSeconds = SessionSeconds(fromTime);
      int toSeconds = SessionSeconds(toTime);

      if(fromSeconds == toSeconds)
         return true;

      if(fromSeconds < toSeconds)
      {
         if(nowSeconds >= fromSeconds && nowSeconds < toSeconds)
            return true;
      }
      else
      {
         if(nowSeconds >= fromSeconds || nowSeconds < toSeconds)
            return true;
      }
   }

   if(!hasSessions)
      return dt.day_of_week != 0 && dt.day_of_week != 6;

   return false;
}

bool MarketOpenForNewOrders()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;

   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      return false;

   return SymbolSessionOpenNow();
}

bool IsOurPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

bool IsOurOrder(const ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket))
      return false;
   return OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_MAGIC) == InpMagicNumber;
}

double MidPrice()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return 0.0;
   return (tick.bid + tick.ask) * 0.5;
}

double MinimumStopDistance()
{
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stops, freeze) * _Point + _Point;
}

bool PendingPriceValid(const int side, const double price)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double minDistance = MinimumStopDistance();
   if(side > 0)
      return price >= tick.ask + minDistance;
   return price <= tick.bid - minDistance;
}

bool PlaceStopOrder(const int side,
                    const double volume,
                    const double price,
                    const string comment)
{
   if(!MarketOpenForNewOrders())
   {
      static datetime lastClosedLog = 0;
      if(InpLogMode >= 1 && TimeCurrent() - lastClosedLog >= 3600)
      {
         Print("Straddle: market/session closed, pending order request skipped");
         lastClosedLog = TimeCurrent();
      }
      return false;
   }

   bool ok = (side > 0)
      ? trade.BuyStop(volume, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, comment)
      : trade.SellStop(volume, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, comment);

   if(!ok || !TradeAccepted())
   {
      uint retcode = trade.ResultRetcode();
      if(retcode == TRADE_RETCODE_MARKET_CLOSED)
      {
         static datetime lastMarketClosedRejectLog = 0;
         if(InpLogMode >= 1 && TimeCurrent() - lastMarketClosedRejectLog >= 3600)
         {
            PrintFormat("Straddle: pending skipped after broker market-closed reject price %.3f lot %.2f",
                        price, volume);
            lastMarketClosedRejectLog = TimeCurrent();
         }
         return false;
      }

      if(InpLogMode >= 0)
         PrintFormat("Straddle: pending failed %s price %.3f lot %.2f ret=%u %s",
                     side > 0 ? "BUY" : "SELL", price, volume,
                     retcode, trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

bool ModifyPositionSL(const ulong ticket, const double sl)
{
   bool ok = trade.PositionModify(ticket, sl, 0.0);
   if(!ok || !TradeAccepted())
   {
      if(InpLogMode >= 1)
         PrintFormat("Straddle: trailing modify failed ticket %I64u ret=%u %s",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

bool ClosePositionByTicket(const ulong ticket)
{
   bool ok = trade.PositionClose(ticket);
   if(!ok || !TradeAccepted())
   {
      if(InpLogMode >= 0)
         PrintFormat("Straddle: close failed ticket %I64u ret=%u %s",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

bool DeleteOrderByTicket(const ulong ticket)
{
   bool ok = trade.OrderDelete(ticket);
   if(!ok || !TradeAccepted())
   {
      if(InpLogMode >= 0)
         PrintFormat("Straddle: delete failed ticket %I64u ret=%u %s",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

#endif
