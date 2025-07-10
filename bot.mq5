//+------------------------------------------------------------------+
//|                                             TrendMaster BTC Pro  |
//|                                     Enhanced Educational Example |
//+------------------------------------------------------------------+
#property strict

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
input ENUM_ORDER_TYPE_FILLING FillMode = ORDER_FILLING_FOK;
input double   RValue                = 100.0;   // distance for 1R in points
input double   PartialCloseVolume1   = 0.05;    // first partial close volume
input double   PartialCloseVolume2   = 0.025;   // second partial close volume

//--- indicator handles
int emaHandleD1, emaHandleH1, atrHandle, adxHandle;

//--- state variables
datetime lastBarTime = 0;   // last H1 bar time
datetime lastBarTimeM5 = 0; // last M5 bar time
double   DailyPnL    = 0.0;
int      TradesToday = 0;
int      lastResetDate;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   emaHandleD1 = iMA(_Symbol, PERIOD_D1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   emaHandleH1 = iMA(_Symbol, PERIOD_H1, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle   = iATR(_Symbol, PERIOD_H4, ATR_Period);
   if(UseADXFilter)
      adxHandle = iADX(_Symbol, PERIOD_H4, ADX_Period);
   else
      adxHandle = INVALID_HANDLE;

   if(emaHandleD1==INVALID_HANDLE || emaHandleH1==INVALID_HANDLE ||
      atrHandle==INVALID_HANDLE   || (UseADXFilter && adxHandle==INVALID_HANDLE))
     {
      Print("Failed to create indicator handle");
      return(INIT_FAILED);
     }

   lastResetDate = TimeDay(TimeCurrent());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(emaHandleD1);
   IndicatorRelease(emaHandleH1);
   IndicatorRelease(atrHandle);
   if(UseADXFilter && adxHandle!=INVALID_HANDLE)
      IndicatorRelease(adxHandle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
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
   if(signal==1 && IsStrongTrend())
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = price - RValue*_Point;
      if(!SendOrder(price, sl, 0, ORDER_TYPE_BUY))
         Print("Buy order failed");
     }
   else if(signal==-1 && IsStrongTrend())
     {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl    = price + RValue*_Point;
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
      if(PositionSelectByIndex(i) && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
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
      if(PositionSelectByIndex(i) && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT);
     }
   DailyPnL = profit;
  }

//+------------------------------------------------------------------+
//| Reset daily statistics                                           |
//+------------------------------------------------------------------+
void ResetDailyStats()
  {
   if(TimeDay(TimeCurrent())!=lastResetDate)
     {
      TradesToday = 0;
      DailyPnL    = 0;
      lastResetDate = TimeDay(TimeCurrent());
     }
  }

//+------------------------------------------------------------------+
//| Check spread before trading                                      |
//+------------------------------------------------------------------+
bool CheckSpread()
  {
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return(spread <= MarketInfo(_Symbol, MODE_SPREAD)*1.5);
  }

//+------------------------------------------------------------------+
//| Evaluate buy conditions                                          |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
  {
   return(TrendDirectionCheck(PERIOD_D1, MODE_EMA) &&
          TrendDirectionCheck(PERIOD_H1, MODE_EMA));
  }

//+------------------------------------------------------------------+
//| Evaluate sell conditions                                         |
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
      if(!PositionSelectByIndex(i))
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
      double atr[];
      if(CopyBuffer(atrHandle,0,0,1,atr)<1)
         return;

      double rDist = MathAbs(openPrice - sl);

      // partial TP 1 at 1.5R
      if(volume==LotSize && MathAbs(currentPrice-openPrice)>=1.5*rDist)
         ClosePartial(ticket,PartialCloseVolume1);

      // partial TP 2 at 3.0R
      if(volume==LotSize-PartialCloseVolume1 && MathAbs(currentPrice-openPrice)>=3.0*rDist)
         ClosePartial(ticket,PartialCloseVolume2);

      // breakeven at 1.2R
      if(MathAbs(currentPrice-openPrice)>=1.2*rDist)
        {
         double newSL = (type==POSITION_TYPE_BUY) ? openPrice+2*_Point : openPrice-2*_Point;
         if((type==POSITION_TYPE_BUY && sl<newSL) || (type==POSITION_TYPE_SELL && sl>newSL))
            ModifyStopLoss(ticket,newSL);
        }

      // trailing stop at 2.0R
      if(MathAbs(currentPrice-openPrice)>=2.0*rDist)
        {
         double trailSL = (type==POSITION_TYPE_BUY) ? currentPrice-atr[0]*1.5
                                                   : currentPrice+atr[0]*1.5;
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
