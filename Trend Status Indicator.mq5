//+------------------------------------------------------------------+
//| TimeframeStatus Utility                                          |
//| Provides helper functions to display the current trend status    |
//| for D1 and H1 along with ATR values for H1 and H4.  Designed to  |
//| be included from an Expert Advisor without causing event         |
//| function conflicts.                                              |
//+------------------------------------------------------------------+

// Use unique names to avoid conflicts with Expert Advisor globals
input int TSI_EMA_Period = 200;   // EMA period for trend detection
input int TSI_ATR_Period = 14;    // ATR period

// Indicator handles
int tsiEmaHandleD1 = INVALID_HANDLE;
int tsiEmaHandleH1 = INVALID_HANDLE;
int tsiAtrHandleH1 = INVALID_HANDLE;
int tsiAtrHandleH4 = INVALID_HANDLE;

//+------------------------------------------------------------------+
bool TSI_Init()
  {
   tsiEmaHandleD1 = iMA(_Symbol, PERIOD_D1, TSI_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   tsiEmaHandleH1 = iMA(_Symbol, PERIOD_H1, TSI_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   tsiAtrHandleH1 = iATR(_Symbol, PERIOD_H1, TSI_ATR_Period);
   tsiAtrHandleH4 = iATR(_Symbol, PERIOD_H4, TSI_ATR_Period);

   if(tsiEmaHandleD1==INVALID_HANDLE || tsiEmaHandleH1==INVALID_HANDLE ||
      tsiAtrHandleH1==INVALID_HANDLE || tsiAtrHandleH4==INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
void TSI_Deinit()
  {
   if(tsiEmaHandleD1!=INVALID_HANDLE) IndicatorRelease(tsiEmaHandleD1);
   if(tsiEmaHandleH1!=INVALID_HANDLE) IndicatorRelease(tsiEmaHandleH1);
   if(tsiAtrHandleH1!=INVALID_HANDLE) IndicatorRelease(tsiAtrHandleH1);
   if(tsiAtrHandleH4!=INVALID_HANDLE) IndicatorRelease(tsiAtrHandleH4);
   Comment("");
  }

//+------------------------------------------------------------------+
void TSI_Update()
  {
   double emaD1[1], emaH1[1], atrH1[1], atrH4[1];

   if(CopyBuffer(tsiEmaHandleD1,0,0,1,emaD1)<1) return;
   if(CopyBuffer(tsiEmaHandleH1,0,0,1,emaH1)<1) return;
   if(CopyBuffer(tsiAtrHandleH1,0,0,1,atrH1)<1) return;
   if(CopyBuffer(tsiAtrHandleH4,0,0,1,atrH4)<1) return;

   double closeD1 = iClose(_Symbol, PERIOD_D1, 0);
   double closeH1 = iClose(_Symbol, PERIOD_H1, 0);

   string d1Trend = (closeD1 > emaD1[0]) ? "UP" : "DOWN";
   string h1Trend = (closeH1 > emaH1[0]) ? "UP" : "DOWN";

   string text = StringFormat("D1 Trend: %s\nH1 Trend: %s\nATR H1: %.2f\nATR H4: %.2f",
                              d1Trend,h1Trend,atrH1[0],atrH4[0]);
   Comment(text);

   return;
  }
//+------------------------------------------------------------------+
