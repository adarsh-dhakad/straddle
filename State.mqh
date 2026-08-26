#ifndef STRADDLE_STATE_MQH
#define STRADDLE_STATE_MQH

double   g_anchor = 0.0;
double   g_step = 0.0;
double   g_cycleStartBalance = 0.0;
double   g_cycleStartEquity = 0.0;
bool     g_cycleActive = false;
bool     g_closeAll = false;
string   g_closeReason = "";
string   g_status = "Waiting for cycle";

datetime g_dayStart = 0;
double   g_dayEquityAnchor = 0.0;
bool     g_dailyLocked = false;
datetime g_noTradeUntil = 0;
datetime g_boostUntilDay = 0;
bool     g_thisCycleBoosted = false;
int      g_activeTimerMilliseconds = 0;
long     g_lastEngineTickMsc = 0;
datetime g_lastEngineTickTime = 0;

void ResetCycleState()
{
   g_anchor = 0.0;
   g_step = 0.0;
   g_cycleStartBalance = 0.0;
   g_cycleStartEquity = 0.0;
   g_cycleActive = false;
   g_closeAll = false;
   g_closeReason = "";
   g_status = "Cycle reset";
}

#endif
