#ifndef STRADDLE_CYCLE_CLOSE_ENGINE_MQH
#define STRADDLE_CYCLE_CLOSE_ENGINE_MQH

double CycleTargetUSD()
{
   double target = InpFixedModeCycleNetBankTargetUSD;
   if(InpLotMode == LOT_MODE_AUTO_BALANCE)
      target = AccountInfoDouble(ACCOUNT_BALANCE) * InpAutoModeCycleTargetPercentBalance / 100.0;
   if(g_thisCycleBoosted)
      target *= 2.0;
   return target;
}

void StartCloseAll(const string reason)
{
   if(g_closeAll)
      return;
   g_closeAll = true;
   g_closeReason = reason;
   g_status = reason;
}

bool CheckProfitTargets()
{
   double cycleNet = AccountInfoDouble(ACCOUNT_EQUITY) - g_cycleStartBalance;
   double target = CycleTargetUSD();

   if(target > 0.0 && cycleNet >= target)
   {
      StartCloseAll("Cycle net bank target reached");
      PrintFormat("Straddle: cycle bank target reached, target %.2f, net %.2f",
                  target, cycleNet);
      return true;
   }

   if(InpWholeBookGreenBankUSD > 0.0 &&
      AccountInfoDouble(ACCOUNT_EQUITY) >= AccountInfoDouble(ACCOUNT_BALANCE) + InpWholeBookGreenBankUSD)
   {
      StartCloseAll("Whole-book green bank reached");
      return true;
   }
   return false;
}

void ProcessCloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket))
         continue;
      ClosePositionByTicket(ticket);
      return;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!IsOurOrder(ticket))
         continue;
      DeleteOrderByTicket(ticket);
      return;
   }

   PrintFormat("Straddle: cycle closed - %s, balance %.2f, equity %.2f",
               g_closeReason, AccountInfoDouble(ACCOUNT_BALANCE),
               AccountInfoDouble(ACCOUNT_EQUITY));
   ResetCycleState();
}

#endif
