//+------------------------------------------------------------------+
//|                                                      TrendMaster BTC Pro (Example) |
//|                        Educational MQL5 Expert Advisor Example   |
//+------------------------------------------------------------------+
#property strict

//--- input parameters
input int      EMA_Period = 200;
input int      ADX_Period = 14;
input double   ADX_Threshold = 20.0;
input int      ATR_Period = 14;
input double   ATR_Multiplier_TP = 1.5;
input double   ATR_Multiplier_SL = 1.0;
input double   LotSize = 0.10;
input double   DailyStopLoss = 500.0;
input int      TradeSessionStart = 7;
input int      TradeSessionEnd = 20;

//--- Global variables
double DailyPnL = 0.0;
int TradesToday = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- initialization
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check if within trading hours
   if(!IsWithinTradingSession()) return;

//--- Check daily stop loss
   if(DailyPnL <= -DailyStopLoss) return;

//--- Check market conditions
   if(CheckBuyConditions())
     {
      OpenTrade(ORDER_TYPE_BUY);
     }
   else if(CheckSellConditions())
     {
      OpenTrade(ORDER_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Functions                                                        |
//+------------------------------------------------------------------+

bool IsWithinTradingSession()
  {
   datetime now = TimeCurrent();
   int hour = TimeHour(now);
   return(hour >= TradeSessionStart && hour < TradeSessionEnd);
  }

bool CheckBuyConditions()
  {
//--- Dummy checks for educational example
   return(TrendDirectionCheck(PERIOD_D1, MODE_EMA) &&
          TrendDirectionCheck(PERIOD_H4, MODE_EMA));
  }

bool CheckSellConditions()
  {
//--- Dummy checks for educational example
   return(!TrendDirectionCheck(PERIOD_D1, MODE_EMA) &&
          !TrendDirectionCheck(PERIOD_H4, MODE_EMA));
  }

bool TrendDirectionCheck(ENUM_TIMEFRAMES timeframe, int mode)
  {
   int handle = iMA(_Symbol, timeframe, EMA_Period, 0, mode, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
     {
      Print("Failed to create iMA handle");
      return(false);
     }

   double buffer[];
   if(CopyBuffer(handle, 0, 0, 1, buffer) < 1)
     {
      Print("CopyBuffer for iMA failed");
      IndicatorRelease(handle);
      return(false);
     }
   IndicatorRelease(handle);

   double ema = buffer[0];
   double price = iClose(_Symbol, timeframe, 0);
   return(price > ema);
  }

void OpenTrade(ENUM_ORDER_TYPE type)
  {
   int atr_handle = iATR(_Symbol, PERIOD_H4, ATR_Period);
   if(atr_handle == INVALID_HANDLE)
     {
      Print("Failed to create iATR handle");
      return;
     }

   double atr_buffer[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) < 1)
     {
      Print("CopyBuffer for iATR failed");
      IndicatorRelease(atr_handle);
      return;
     }
   IndicatorRelease(atr_handle);
   double atr = atr_buffer[0];
   double sl = atr * ATR_Multiplier_SL;
   double tp = atr * ATR_Multiplier_TP;
   double price = SymbolInfoDouble(_Symbol, (type == ORDER_TYPE_BUY) ? SYMBOL_ASK : SYMBOL_BID);

   double sl_price = (type == ORDER_TYPE_BUY) ? price - sl : price + sl;
   double tp_price = (type == ORDER_TYPE_BUY) ? price + tp : price - tp;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = type;
   request.price = price;
   request.sl = sl_price;
   request.tp = tp_price;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = "TrendMaster BTC Pro Example";
   request.type_filling = ORDER_FILLING_IOC;
   request.type_time = ORDER_TIME_GTC;

   if(!OrderSend(request,result))
     {
      PrintFormat("OrderSend failed: %s", result.comment);
     }
   else
     {
      PrintFormat("Trade opened successfully: Ticket #%d", result.order);
      TradesToday++;
     }
  }

//+------------------------------------------------------------------+
