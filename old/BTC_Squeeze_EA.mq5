//+------------------------------------------------------------------+
//|                                               BTC Squeeze EA    |
//|                                         https://example.com      |
//+------------------------------------------------------------------+
#property strict
#property copyright ""
#property link      ""
#property version   "1.00"
#property description "Strategy using H1 trend and M5 Bollinger Band squeeze"

//--- input parameters
input int      EMA1_Period       = 8;
input int      EMA2_Period       = 13;
input int      EMA3_Period       = 21;
input int      EMA4_Period       = 34;
input int      EMA5_Period       = 55;

input int      BB_Period        = 20;      // Bollinger Band period on M30
input double   BB_Deviation     = 2.0;     // Bollinger Band deviation

input double   RiskPercent      = 1.0;     // risk per trade (percent)
input double   FixedLotSize     = 0.10;    // fixed lot size

input int      TradeStartHour   = 7;       // trading session start (UTC)
input int      TradeEndHour     = 17;      // trading session end (UTC)

input int      MagicNumber      = 987654;

//--- indicator handles
int ema1Handle = INVALID_HANDLE;
int ema2Handle = INVALID_HANDLE;
int ema3Handle = INVALID_HANDLE;
int ema4Handle = INVALID_HANDLE;
int ema5Handle = INVALID_HANDLE;
int bbHandle   = INVALID_HANDLE;

//--- state variables
datetime lastM5Bar = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ema1Handle = iMA(_Symbol, PERIOD_H1, EMA1_Period, 0, MODE_EMA, PRICE_CLOSE);
   ema2Handle = iMA(_Symbol, PERIOD_H1, EMA2_Period, 0, MODE_EMA, PRICE_CLOSE);
   ema3Handle = iMA(_Symbol, PERIOD_H1, EMA3_Period, 0, MODE_EMA, PRICE_CLOSE);
   ema4Handle = iMA(_Symbol, PERIOD_H1, EMA4_Period, 0, MODE_EMA, PRICE_CLOSE);
   ema5Handle = iMA(_Symbol, PERIOD_H1, EMA5_Period, 0, MODE_EMA, PRICE_CLOSE);
   bbHandle   = iBands(_Symbol, PERIOD_M30, BB_Period, 0, BB_Deviation, PRICE_CLOSE);

   if(ema1Handle==INVALID_HANDLE || ema2Handle==INVALID_HANDLE ||
      ema3Handle==INVALID_HANDLE || ema4Handle==INVALID_HANDLE ||
      ema5Handle==INVALID_HANDLE || bbHandle==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(ema1Handle);
   IndicatorRelease(ema2Handle);
   IndicatorRelease(ema3Handle);
   IndicatorRelease(ema4Handle);
   IndicatorRelease(ema5Handle);
   IndicatorRelease(bbHandle);
}

//+------------------------------------------------------------------+
//| Check if a new M5 bar has formed                                  |
//+------------------------------------------------------------------+
bool NewBarM5()
{
   datetime t = iTime(_Symbol, PERIOD_M5, 0);
   if(lastM5Bar!=t)
   {
      lastM5Bar = t;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Check trading session hours                                       |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   int hour = tm.hour;
   return(hour>=TradeStartHour && hour<TradeEndHour);
}

//+------------------------------------------------------------------+
//| Determine trend on H1 using EMAs                                  |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   double ema1[1],ema2[1],ema3[1],ema4[1],ema5[1];
   if(CopyBuffer(ema1Handle,0,0,1,ema1)<1) return 0;
   if(CopyBuffer(ema2Handle,0,0,1,ema2)<1) return 0;
   if(CopyBuffer(ema3Handle,0,0,1,ema3)<1) return 0;
   if(CopyBuffer(ema4Handle,0,0,1,ema4)<1) return 0;
   if(CopyBuffer(ema5Handle,0,0,1,ema5)<1) return 0;

   if(ema1[0]>ema2[0] && ema2[0]>ema3[0] && ema3[0]>ema4[0] && ema4[0]>ema5[0])
      return(1); // bullish
   if(ema1[0]<ema2[0] && ema2[0]<ema3[0] && ema3[0]<ema4[0] && ema4[0]<ema5[0])
      return(-1); // bearish
   return(0);
}

//+------------------------------------------------------------------+
//| Check M5 candle close relative to M30 Bollinger Bands              |
//+------------------------------------------------------------------+
int CheckSqueezeSignal(int trend)
{
   if(trend==0) return 0;
   // we evaluate the close of the previous completed M5 candle
   double closeM5 = iClose(_Symbol, PERIOD_M5, 1);

   double upper[1], lower[1];
   if(CopyBuffer(bbHandle,1,1,1,upper)<1) return 0; // 1-upper band, 2-lower band
   if(CopyBuffer(bbHandle,2,1,1,lower)<1) return 0;

   if(trend==1 && closeM5>upper[0])
      return(1);
   if(trend==-1 && closeM5<lower[0])
      return(-1);
   return(0);
}

//+------------------------------------------------------------------+
//| Calculate stop loss based on last H1 swing                         |
//+------------------------------------------------------------------+
double GetStopLoss(int direction)
{
   // use the low/high of previous H1 candle as swing level
   double swing;
   if(direction==1)
      swing = iLow(_Symbol,PERIOD_H1,1);
   else
      swing = iHigh(_Symbol,PERIOD_H1,1);
   return(swing);
}

//+------------------------------------------------------------------+
//| Send order with fixed lot size                                     |
//+------------------------------------------------------------------+
bool OpenPosition(int direction,double sl,double tp1,double tp2)
{
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = _Symbol;
   req.volume   = FixedLotSize;
   req.type     = (direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   req.price    = (direction==1)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.sl       = NormalizeDouble(sl,_Digits);
   req.tp       = 0; // we handle TPs manually
   req.deviation= 10;
   req.magic    = MagicNumber;

   if(!OrderSend(req,res) || res.retcode!=TRADE_RETCODE_DONE)
   {
      Print("OrderSend failed: ",res.retcode);
      return(false);
   }

   Print("Trade opened, ticket: ",res.order," trend=",direction);
   return(true);
}

//+------------------------------------------------------------------+
//| Manage open positions - partial TP and trailing                    |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      ulong ticket     = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      int    type      = (int)PositionGetInteger(POSITION_TYPE);
      double sl        = PositionGetDouble(POSITION_SL);

      int direction = (type==POSITION_TYPE_BUY)?1:-1;
      double risk   = MathAbs(openPrice - sl);

      double current = (direction==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double tp1 = (direction==1)?openPrice + risk:openPrice - risk;
      double tp2 = (direction==1)?openPrice + 2*risk:openPrice - 2*risk;

      // Partial closes
      if(volume==FixedLotSize && ((direction==1 && current>=tp1) || (direction==-1 && current<=tp1)))
         ClosePartial(ticket,FixedLotSize/3.0);
      if(volume==FixedLotSize*2.0/3.0 && ((direction==1 && current>=tp2) || (direction==-1 && current<=tp2)))
         ClosePartial(ticket,FixedLotSize/3.0);

      // Trailing stop for last third using EMA34 of H1
      double ema34[1];
      if(CopyBuffer(ema4Handle,0,0,1,ema34)<1) continue;
      double trail = (direction==1)?ema34[0]:ema34[0];

      if(direction==1 && trail>sl)
         ModifyStopLoss(ticket,trail);
      if(direction==-1 && trail<sl)
         ModifyStopLoss(ticket,trail);
   }
}

//+------------------------------------------------------------------+
//| Close part of a position                                           |
//+------------------------------------------------------------------+
void ClosePartial(ulong ticket,double volume)
{
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action   = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.volume   = volume;
   req.type     = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price    = (req.type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.deviation=10;
   req.magic    = MagicNumber;

   if(!OrderSend(req,res) || res.retcode!=TRADE_RETCODE_DONE)
      Print("Partial close failed ",res.retcode);
   else
      Print("Partial close success, vol=",volume);
}

//+------------------------------------------------------------------+
//| Modify stop loss                                                   |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket,double newSL)
{
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = _Symbol;
   req.position = ticket;
   req.sl       = NormalizeDouble(newSL,_Digits);
   req.tp       = PositionGetDouble(POSITION_TP);

   if(!OrderSend(req,res) || res.retcode!=TRADE_RETCODE_DONE)
      Print("SL modify failed ",res.retcode);
   else
      Print("Trailing SL updated to ",newSL);
}

//+------------------------------------------------------------------+
//| Has EA position                                                    |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!PositionSelectByIndex(i)) continue;
      if(PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();

   if(!IsTradingTime()) return;
   if(HasOpenPosition()) return;
   if(!NewBarM5()) return;

   int trend = GetTrendDirection();
   int signal = CheckSqueezeSignal(trend);

   if(signal==0) return;

   double sl = GetStopLoss(signal);
   double risk = MathAbs(((signal==1)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID)) - sl);
   double tp1 = (signal==1)?SymbolInfoDouble(_Symbol,SYMBOL_ASK)+risk:SymbolInfoDouble(_Symbol,SYMBOL_BID)-risk;
   double tp2 = (signal==1)?SymbolInfoDouble(_Symbol,SYMBOL_ASK)+2*risk:SymbolInfoDouble(_Symbol,SYMBOL_BID)-2*risk;

   if(OpenPosition(signal,sl,tp1,tp2))
      Print("Entry executed. Trend=",trend);
}

//+------------------------------------------------------------------+
