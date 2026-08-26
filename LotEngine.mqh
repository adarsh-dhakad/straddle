#ifndef STRADDLE_LOT_ENGINE_MQH
#define STRADDLE_LOT_ENGINE_MQH

double NormalizeVolume(const double requested)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minVolume <= 0.0 || maxVolume <= 0.0 || volumeStep <= 0.0)
      return 0.0;

   double volume = MathMax(minVolume, MathMin(maxVolume, requested));
   double steps = MathFloor((volume - minVolume) / volumeStep + 1e-9);
   return NormalizeDouble(minVolume + steps * volumeStep, 8);
}

double LotForLevel(const int level)
{
   double nearLot = InpNearTierLots;
   double midLot = InpMidTierLots;
   double farLot = InpFarTierLots;

   if(InpLotMode == LOT_MODE_AUTO_BALANCE && InpReferenceBalanceForAutoLots > 0.0)
   {
      double multiplier = AccountInfoDouble(ACCOUNT_BALANCE) / InpReferenceBalanceForAutoLots;
      nearLot = InpAutoBaseNearTierLots * multiplier;
      midLot = InpAutoBaseMidTierLots * multiplier;
      farLot = InpAutoBaseFarTierLots * multiplier;
   }

   double volume = farLot;
   if(level <= InpNearTierLevels)
      volume = nearLot;
   else if(level <= InpNearTierLevels + InpMidTierLevels)
      volume = midLot;

   if(g_thisCycleBoosted)
      volume *= 2.0;

   return NormalizeVolume(volume);
}

#endif
