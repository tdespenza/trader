//+------------------------------------------------------------------+
//|                                                 PropEdge BTC EA  |
//+------------------------------------------------------------------+
#property strict
#include "Trend Status Indicator.mqh"

//--- input parameters
input int      EMA_Period            = 200;
input int      ATR_Period            = 14;
input int      ADX_Period            = 14;
input double   ADX_Threshold         = 25.0;
input bool     UseADXFilter         = false;   // set true to enable ADX filter
input double   LotSize               = 0.10;
input double   DailyStopLoss         = 500.0;
input int      TradeSessionStart     = 7;
input int      TradeSessionEnd       = 20;
input int      MagicNumber           = 123456;
input ENUM_ORDER_TYPE_FILLING FillMode = ORDER_FILLING_IOC;   // default fill mode
input double   StopLoss_ATR_Mult     = 1.5;     // initial SL ATR multiplier (H4)
input double   Trail_ATR_Mult        = 1.5;     // trailing SL ATR multiplier (H1)
input double   Trail_Start_Mult      = 2.0;     // start trailing after price moves this many ATR
input double   PartialCloseVolume1   = 0.05;    // volume to close at each TP

//--- indicator handles
int emaHandleD1, emaHandleH1, atrHandleH4, atrHandleH1, adxHandle;

//--- state variables
datetime lastBarTime = 0;   // last H1 bar time
datetime lastBarTimeM5 = 0; // last M5 bar time
double   DailyPnL    = 0.0;
int      TradesToday = 0;
int      lastResetDate; // stores the last day statistics were reset

//+------------------------------------------------------------------+
//| Utility: return the day of month from a datetime value            |
//+------------------------------------------------------------------+
int GetDay(datetime time)
  {
   MqlDateTime tm;
   TimeToStruct(time,tm);
   return(tm.day);
  }

//+------------------------------------------------------------------+
//| Utility: select a position by its index                           |
//+------------------------------------------------------------------+
bool SelectPositionByIndex(int index)
  {
   ulong ticket=PositionGetTicket(index);
   if(ticket==0)
      return(false);
   return(PositionSelectByTicket(ticket));
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
  emaHandleD1 = iMA(_Symbol, PERIOD_D1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
  emaHandleH1 = iMA(_Symbol, PERIOD_H1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
  atrHandleH4 = iATR(_Symbol, PERIOD_H4, ATR_Period);
  atrHandleH1 = iATR(_Symbol, PERIOD_H1, ATR_Period);
   if(UseADXFilter)
      adxHandle = iADX(_Symbol, PERIOD_H4, ADX_Period);
   else
      adxHandle = INVALID_HANDLE;

  if(emaHandleD1==INVALID_HANDLE || emaHandleH1==INVALID_HANDLE ||
     atrHandleH4==INVALID_HANDLE || atrHandleH1==INVALID_HANDLE ||
     (UseADXFilter && adxHandle==INVALID_HANDLE))
     {
      Print("Failed to create indicator handle");
      return(INIT_FAILED);
     }

   if(!TSI_Init())
      return(INIT_FAILED);

   lastResetDate = GetDay(TimeCurrent());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  IndicatorRelease(emaHandleD1);
  IndicatorRelease(emaHandleH1);
  IndicatorRelease(atrHandleH4);
  IndicatorRelease(atrHandleH1);
   if(UseADXFilter && adxHandle!=INVALID_HANDLE)
      IndicatorRelease(adxHandle);

   TSI_Deinit();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   TSI_Update();
   ResetDailyStats();
   UpdateDailyPnL();
   ManageTradeRisk();

   if(!IsWithinTradingSession())
      return;
   if(DailyPnL <= -DailyStopLoss)
      return;
   if(!CheckSpread())
      return;

   if(!NewBarM5())
      return;
   if(HasOpenPosition())
      return;

   int signal = GetCandleSignal();
   if(signal==1 && IsStrongTrend() && CheckBuyConditions())
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double atrH4[1];
      if(CopyBuffer(atrHandleH4,0,0,1,atrH4)<1)
         return;
      double sl    = price - atrH4[0]*StopLoss_ATR_Mult;
      if(!SendOrder(price, sl, 0, ORDER_TYPE_BUY))
         Print("Buy order failed");
     }
   else if(signal==-1 && IsStrongTrend() && CheckSellConditions())
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double atrH4[1];
      if(CopyBuffer(atrHandleH4,0,0,1,atrH4)<1)
         return;
      double sl    = price + atrH4[0]*StopLoss_ATR_Mult;
      if(!SendOrder(price, sl, 0, ORDER_TYPE_SELL))
         Print("Sell order failed");
     }
  }

//+------------------------------------------------------------------+
//| Utility: check session hours                                      |
//+------------------------------------------------------------------+
bool IsWithinTradingSession()
  {
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(),tm);
   int hour = tm.hour;
   return(hour >= TradeSessionStart && hour < TradeSessionEnd);
  }

//+------------------------------------------------------------------+
//| Detect new H1 bar                                                |
//+------------------------------------------------------------------+
bool NewBar()
  {
   datetime current = iTime(_Symbol, PERIOD_H1, 0);
   if(lastBarTime!=current)
     {
      lastBarTime=current;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Detect new M5 bar                                                |
//+------------------------------------------------------------------+
bool NewBarM5()
  {
   datetime current = iTime(_Symbol, PERIOD_M5, 0);
   if(lastBarTimeM5!=current)
     {
      lastBarTimeM5=current;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Check if there is open position                                   |
//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      if(SelectPositionByIndex(i) && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| ADX confirmation                                                  |
//+------------------------------------------------------------------+
bool IsStrongTrend()
  {
   if(!UseADXFilter)
      return(true);
   double adx[];
   if(CopyBuffer(adxHandle,0,0,1,adx)<1)
      return(false);
   return(adx[0] > ADX_Threshold);
  }

//+------------------------------------------------------------------+
//| Update DailyPnL                                                  |
//+------------------------------------------------------------------+
void UpdateDailyPnL()
  {
   double profit=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      if(SelectPositionByIndex(i) && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT);
     }
   DailyPnL = profit;
  }

//+------------------------------------------------------------------+
//| Reset daily statistics                                           |
//+------------------------------------------------------------------+
void ResetDailyStats()
  {
   if(GetDay(TimeCurrent())!=lastResetDate)
     {
      TradesToday = 0;
      DailyPnL    = 0;
      lastResetDate = GetDay(TimeCurrent());
     }
  }

//+------------------------------------------------------------------+
//| Check spread before trading                                      |
//+------------------------------------------------------------------+
bool CheckSpread()
  {
   // Retrieve the current spread in points
   // SYMBOL_SPREAD returns a long value, explicitly cast to double
   double spread     = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   // Some brokers provide the minimal spread via MarketInfo in MQL4, but
   // in MQL5 this function is unavailable.  Use the current spread value
   // as the baseline and allow trading only if the real-time spread is not
   // excessively wide (1.5x of the baseline).
   double max_spread = spread * 1.5;

   return(spread <= max_spread);
  }

//+------------------------------------------------------------------+
//| Evaluate buy conditions (trend alignment)                         |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
  {
   return(TrendDirectionCheck(PERIOD_D1, MODE_EMA) &&
          TrendDirectionCheck(PERIOD_H1, MODE_EMA));
  }

//+------------------------------------------------------------------+
//| Evaluate sell conditions (trend alignment)                        |
//+------------------------------------------------------------------+
bool CheckSellConditions()
  {
   return(!TrendDirectionCheck(PERIOD_D1, MODE_EMA) &&
          !TrendDirectionCheck(PERIOD_H1, MODE_EMA));
  }

//+------------------------------------------------------------------+
//| Trend direction helper                                           |
//+------------------------------------------------------------------+
bool TrendDirectionCheck(ENUM_TIMEFRAMES tf, ENUM_MA_METHOD mode)
  {
   double buf[];
   int handle = (tf==PERIOD_D1 ? emaHandleD1 : emaHandleH1);
   if(CopyBuffer(handle,0,0,1,buf)<1)
     {
      Print("CopyBuffer for iMA failed");
      return(false);
     }
   double ema = buf[0];
   double price = iClose(_Symbol, tf, 0);
   return(price>ema);
  }

//+------------------------------------------------------------------+
//| Candlestick pattern detection on M5                              |
//+------------------------------------------------------------------+
bool IsBullishEngulfing()
  {
   double o1=iOpen(_Symbol,PERIOD_M5,2), c1=iClose(_Symbol,PERIOD_M5,2);
   double o2=iOpen(_Symbol,PERIOD_M5,1), c2=iClose(_Symbol,PERIOD_M5,1);
   return(c1<o1 && c2>o2 && o2<c1 && c2>o1);
  }

bool IsBearishEngulfing()
  {
   double o1=iOpen(_Symbol,PERIOD_M5,2), c1=iClose(_Symbol,PERIOD_M5,2);
   double o2=iOpen(_Symbol,PERIOD_M5,1), c2=iClose(_Symbol,PERIOD_M5,1);
   return(c1>o1 && c2<o2 && o2>c1 && c2<o1);
  }

bool IsHammer()
  {
   double o=iOpen(_Symbol,PERIOD_M5,1), c=iClose(_Symbol,PERIOD_M5,1);
   double h=iHigh(_Symbol,PERIOD_M5,1), l=iLow(_Symbol,PERIOD_M5,1);
   double body=MathAbs(c-o);
   double lower=MathMin(o,c)-l;
   double upper=h-MathMax(o,c);
   return(lower>=2*body && upper<=0.3*body);
  }

bool IsShootingStar()
  {
   double o=iOpen(_Symbol,PERIOD_M5,1), c=iClose(_Symbol,PERIOD_M5,1);
   double h=iHigh(_Symbol,PERIOD_M5,1), l=iLow(_Symbol,PERIOD_M5,1);
   double body=MathAbs(c-o);
   double lower=MathMin(o,c)-l;
   double upper=h-MathMax(o,c);
   return(upper>=2*body && lower<=0.3*body);
  }

int GetCandleSignal()
  {
   if(IsBullishEngulfing() || IsHammer())
      return(1);
   if(IsBearishEngulfing() || IsShootingStar())
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| Send trade order with retry                                      |
//+------------------------------------------------------------------+
bool SendOrder(double price,double sl,double tp,ENUM_ORDER_TYPE type)
  {
   if(HasOpenPosition())
      return(false);

   MqlTradeRequest request; 
   MqlTradeResult  result;  
   ZeroMemory(request);
   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = LotSize;
   request.type     = type;
   request.price    = price;
   request.sl       = sl;
   request.tp       = tp;
   request.magic    = MagicNumber;
   request.type_filling = FillMode;
   request.deviation = (int)(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*1.5);

   int attempts=0;
   bool success=false;
   while(attempts<3 && !success)
     {
      if(OrderSend(request,result) && result.retcode==TRADE_RETCODE_DONE)
         success=true;
      else
        {
         PrintFormat("OrderSend attempt %d failed: %d | %d",attempts+1,GetLastError(),result.retcode);
         Sleep(1000);
        }
      attempts++;
     }
   if(success)
      TradesToday++;
   return(success);
  }

//+------------------------------------------------------------------+
//| Manage open position risk                                        |
//+------------------------------------------------------------------+
void ManageTradeRisk()
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      if(!SelectPositionByIndex(i))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;

      ulong  ticket     = PositionGetInteger(POSITION_TICKET);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double volume     = PositionGetDouble(POSITION_VOLUME);
      int    type       = (int)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                                     : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double atrH1[1];
      if(CopyBuffer(atrHandleH1,0,0,1,atrH1)<1)
         return;

      double slDist = atrH1[0]*StopLoss_ATR_Mult;

      // partial TP 1 at 1.5x ATR distance on H1
      if(volume==LotSize && MathAbs(currentPrice-openPrice)>=1.5*slDist)
         ClosePartial(ticket,PartialCloseVolume1);

      // partial TP 2 at 3.0x ATR distance on H1
      if(volume==LotSize-PartialCloseVolume1 && MathAbs(currentPrice-openPrice)>=3.0*slDist)
         ClosePartial(ticket,PartialCloseVolume1);

      // breakeven at 1.2x SL distance
      if(MathAbs(currentPrice-openPrice)>=1.2*slDist)
        {
         double newSL = (type==POSITION_TYPE_BUY) ? openPrice+2*_Point : openPrice-2*_Point;
         if((type==POSITION_TYPE_BUY && sl<newSL) || (type==POSITION_TYPE_SELL && sl>newSL))
            ModifyStopLoss(ticket,newSL);
        }

      // trailing stop using H1 ATR
      if(MathAbs(currentPrice-openPrice)>=Trail_Start_Mult*atrH1[0])
        {
         double trailSL = (type==POSITION_TYPE_BUY) ? currentPrice-atrH1[0]*Trail_ATR_Mult
                                                   : currentPrice+atrH1[0]*Trail_ATR_Mult;
         if((type==POSITION_TYPE_BUY && trailSL>sl) || (type==POSITION_TYPE_SELL && trailSL<sl))
            ModifyStopLoss(ticket,trailSL);
        }
     }
  }

//+------------------------------------------------------------------+
//| Close part of a position                                         |
//+------------------------------------------------------------------+
void ClosePartial(ulong ticket,double volume)
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = volume;
   request.type     = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   request.position = ticket;
   request.price    = (request.type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   request.magic    = MagicNumber;
   request.type_filling = FillMode;

   if(!OrderSend(request,result) || result.retcode!=TRADE_RETCODE_DONE)
      PrintFormat("Partial close failed: %d | %d",GetLastError(),result.retcode);
   else
      PrintFormat("Partial position closed: %.2f",volume);
  }

//+------------------------------------------------------------------+
//| Modify stop loss                                                 |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket,double newSL)
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.sl       = NormalizeDouble(newSL,_Digits);
   request.tp       = PositionGetDouble(POSITION_TP);

   if(!OrderSend(request,result) || result.retcode!=TRADE_RETCODE_DONE)
      PrintFormat("SL modify failed: %d | %d",GetLastError(),result.retcode);
   else
      PrintFormat("Stop loss moved to %.5f",newSL);
  }

//+------------------------------------------------------------------+
