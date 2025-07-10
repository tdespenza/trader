#property indicator_chart_window
#property indicator_buffers 0

//+------------------------------------------------------------------+
//|   TimeframeStatus Indicator                                      |
//|   Shows trend status for D1 and H1 and displays ATR values       |
//|   for H1 and H4 timeframes.                                      |
//+------------------------------------------------------------------+

input int EMA_Period = 200;   // EMA period for trend detection
input int ATR_Period = 14;    // ATR period

// Indicator handles
int emaHandleD1 = INVALID_HANDLE;
int emaHandleH1 = INVALID_HANDLE;
int atrHandleH1 = INVALID_HANDLE;
int atrHandleH4 = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
  {
   emaHandleD1 = iMA(_Symbol, PERIOD_D1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   emaHandleH1 = iMA(_Symbol, PERIOD_H1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandleH1 = iATR(_Symbol, PERIOD_H1, ATR_Period);
   atrHandleH4 = iATR(_Symbol, PERIOD_H4, ATR_Period);

   if(emaHandleD1==INVALID_HANDLE || emaHandleH1==INVALID_HANDLE ||
      atrHandleH1==INVALID_HANDLE || atrHandleH4==INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(emaHandleD1!=INVALID_HANDLE) IndicatorRelease(emaHandleD1);
   if(emaHandleH1!=INVALID_HANDLE) IndicatorRelease(emaHandleH1);
   if(atrHandleH1!=INVALID_HANDLE) IndicatorRelease(atrHandleH1);
   if(atrHandleH4!=INVALID_HANDLE) IndicatorRelease(atrHandleH4);
   Comment("");
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   double emaD1[1], emaH1[1], atrH1[1], atrH4[1];

   if(CopyBuffer(emaHandleD1,0,0,1,emaD1)<1) return(0);
   if(CopyBuffer(emaHandleH1,0,0,1,emaH1)<1) return(0);
   if(CopyBuffer(atrHandleH1,0,0,1,atrH1)<1) return(0);
   if(CopyBuffer(atrHandleH4,0,0,1,atrH4)<1) return(0);

   double closeD1 = iClose(_Symbol, PERIOD_D1, 0);
   double closeH1 = iClose(_Symbol, PERIOD_H1, 0);

   string d1Trend = (closeD1 > emaD1[0]) ? "UP" : "DOWN";
   string h1Trend = (closeH1 > emaH1[0]) ? "UP" : "DOWN";

   string text = StringFormat("D1 Trend: %s\nH1 Trend: %s\nATR H1: %.2f\nATR H4: %.2f",
                              d1Trend,h1Trend,atrH1[0],atrH4[0]);
   Comment(text);

   return(rates_total);
  }
//+------------------------------------------------------------------+
