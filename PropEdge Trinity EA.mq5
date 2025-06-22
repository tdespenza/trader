//+------------------------------------------------------------------+
//| PropEdge Trinity EA - Sample Expert Advisor                      |
//| Simplified version using MQL5 native functions                   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double RiskPercent = 1.0;
input double TargetPercent = 12.0;
input double DailyLossLimitPercent = 3.0;
input double LotSizeMin = 0.01;

string symbols[] = {"EURUSD","USDJPY","GBPUSD","US500","US30","XAUUSD","BTCUSD"};
// Margin requirement factors (1/leverage) for each symbol above
double leverageFactors[] = {1.0,1.0,1.0,0.2,0.2,0.1,0.05};

// Track if partial profits were taken for each symbol
bool  partialTaken[];

// Return index of symbol in the symbols array or -1 if not found
int FindSymbolIndex(string symbol)
{
   for(int i=0;i<ArraySize(symbols);i++)
   {
      if(symbols[i]==symbol)
         return(i);
   }
   return(-1);
}

// Extract day of month from a datetime value
int DayOfDate(datetime t)
{
   MqlDateTime stm;
   TimeToStruct(t,stm);
   return(stm.day);
}

bool targetAchieved = false;

int OnInit()
{
   ArrayResize(partialTaken,ArraySize(symbols));
   for(int i=0;i<ArraySize(partialTaken);i++)
      partialTaken[i]=false;
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(targetAchieved || IsTradingHalted())
      return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double targetBalance = balance*(1.0+TargetPercent/100.0);
   if(equity>=targetBalance)
   {
      Print("\xF3AF Profit target reached. Trading halted.");
      targetAchieved = true;
      return;
   }

string sym = Symbol();
int idx = FindSymbolIndex(sym);
   if(idx<0)
      return;

   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now,tm);
   int mins = tm.hour*60+tm.min;

   if(!HasOpenTrade(sym))
   {
      if((sym=="EURUSD" || sym=="USDJPY") && mins>=480 && mins<=720)
         TradeSessionBreakout(sym,idx);
      if(sym=="GBPUSD" && mins==480)
         TradeLondonBreakout(sym,idx);
      if((sym=="US500" || sym=="US30") && mins>=570 && mins<=630)
         TradeNYMomentum(sym,idx);
      if(sym=="XAUUSD" && mins>=570 && mins<=690)
         TradeGoldRange(sym,idx);
      if(sym=="BTCUSD" && tm.hour%6==0)
         TradeCryptoTrend(sym,idx);
   }

   ManageTradeExit(sym);
}

//+------------------------------------------------------------------+
void TradeSessionBreakout(string sym,int idx)
{
   double high = iHigh(sym,PERIOD_H1,1);
   double low  = iLow(sym,PERIOD_H1,1);
   double offset = 10*_Point;
   double buy = high+offset;
   double sell = low-offset;
   double lot = CalculateRiskAdjustedLot(sym,idx,20);
   trade.BuyStop(lot,buy,sym,buy-20*_Point,buy+40*_Point);
   trade.SellStop(lot,sell,sym,sell+20*_Point,sell-40*_Point);
}

void TradeLondonBreakout(string sym,int idx)
{
   double h = iHigh(sym,PERIOD_M15,4);
   double l = iLow(sym,PERIOD_M15,4);
   double lot = CalculateRiskAdjustedLot(sym,idx,30);
   double buy = h+5*_Point;
   double sell = l-5*_Point;
   trade.BuyStop(lot,buy,sym,buy-30*_Point,buy+60*_Point);
   trade.SellStop(lot,sell,sym,sell+30*_Point,sell-60*_Point);
}

void TradeNYMomentum(string sym,int idx)
{
   double ma1 = GetMA(sym,PERIOD_M5,5);
   double ma2 = GetMA(sym,PERIOD_M5,20);
   double price = iClose(sym,PERIOD_M5,0);
   double lot = CalculateRiskAdjustedLot(sym,idx,100);
   if(ma1>ma2)
      trade.Buy(lot,sym,price,price-100*_Point,price+200*_Point);
   else if(ma1<ma2)
      trade.Sell(lot,sym,price,price+100*_Point,price-200*_Point);
}

void TradeGoldRange(string sym,int idx)
{
   double upper,mid,lower;
   GetBollinger(sym,PERIOD_M15,20,2.0,upper,mid,lower);
   double p = iClose(sym,PERIOD_M15,0);
   double atr = GetATR(sym,PERIOD_H1,14,0);
   double sl = 2.0*atr;
   double tp = 4.0*atr;
   double lot = CalculateRiskAdjustedLot(sym,idx,sl/SymbolInfoDouble(sym,SYMBOL_POINT));
   double ask = SymbolInfoDouble(sym,SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym,SYMBOL_BID);
   if(p<=lower)
      trade.Buy(lot,sym,ask,ask-sl,ask+tp);
   else if(p>=upper)
      trade.Sell(lot,sym,bid,bid+sl,bid-tp);
}

void TradeCryptoTrend(string sym,int idx)
{
   double ma = GetMA(sym,PERIOD_H1,50);
   double p = iClose(sym,PERIOD_H1,0);
   double atr = GetATR(sym,PERIOD_H1,14,0);
   double sl  = 2.0*atr;
   double tp  = 4.0*atr;
   double lot = CalculateRiskAdjustedLot(sym,idx,sl/SymbolInfoDouble(sym,SYMBOL_POINT));
   double ask = SymbolInfoDouble(sym,SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym,SYMBOL_BID);
   if(p>ma)
      trade.Buy(lot,sym,ask,ask-sl,ask+tp);
   else if(p<ma)
      trade.Sell(lot,sym,bid,bid+sl,bid-tp);
}

//+------------------------------------------------------------------+
double CalculateRiskAdjustedLot(string symbol,int idx,double slPips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * RiskPercent / 100.0;

   // Obtain pricing details
   double tickVal   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double contract  = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // Determine pip size (0.0001 for 5 digits, 0.01 for 3 digits, etc.)
   double pipSize = (digits==3 || digits==5) ? point*10.0 : point;

   // Pip value for one lot using tick value and contract size
   double pipValue = 0.0;
   if(tickVal>0.0 && tickSize>0.0)
      pipValue = (tickVal/tickSize) * pipSize;
   else
      pipValue = contract * pipSize;

   // Margin requirement factor for the symbol (1/leverage)
   double marginFactor = (idx>=0 && idx<ArraySize(leverageFactors)) ?
                         leverageFactors[idx] : 1.0;

   double riskPerLot = slPips * pipValue * marginFactor;
   if(riskPerLot <= 0.0)
      return(LotSizeMin);

   double lots = risk / riskPerLot;

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = MathMin(100.0, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX));
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   lots = MathFloor(lots/step) * step;
   lots = NormalizeDouble(lots,2);

   if(lots < minLot)
      lots = minLot;

   return(lots);
}

bool IsTradingHalted()
{
   static datetime lastDay=0;
   datetime now=TimeCurrent();
   if(DayOfDate(now)!=DayOfDate(lastDay))
   {
      lastDay=now;
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if((balance-equity)/balance*100.0>=DailyLossLimitPercent)
      {
         Print("\xF6D1 Daily drawdown exceeded. Trading halted for today.");
         return(true);
      }
   }
   return(false);
}

bool HasOpenTrade(string sym)
{
   if(PositionSelect(sym))
      return(true);
   for(int i=0;i<OrdersTotal();i++)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0)
         continue;
      if(OrderGetString(ORDER_SYMBOL)==sym)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
double GetMA(string sym,ENUM_TIMEFRAMES tf,int period)
{
   int handle=iMA(sym,tf,period,0,MODE_EMA,PRICE_CLOSE);
   if(handle==INVALID_HANDLE)
      return(0);
   double buf[];
   if(CopyBuffer(handle,0,0,1,buf)<1)
   {
      IndicatorRelease(handle);
      return(0);
   }
   double val=buf[0];
   IndicatorRelease(handle);
   return(val);
}

void GetBollinger(string sym,ENUM_TIMEFRAMES tf,int period,double deviation,double &upper,double &mid,double &lower)
{
   int handle=iBands(sym,tf,period,0,deviation,PRICE_CLOSE);
   if(handle==INVALID_HANDLE)
   {
      upper=mid=lower=0.0;
      return;
   }
   double bufUpper[];
   double bufMid[];
   double bufLower[];
   if(CopyBuffer(handle,1,0,1,bufUpper)<1 ||
      CopyBuffer(handle,0,0,1,bufMid)<1 ||
      CopyBuffer(handle,2,0,1,bufLower)<1)
   {
      IndicatorRelease(handle);
      upper=mid=lower=0.0;
      return;
   }
   upper=bufUpper[0];
   mid=bufMid[0];
   lower=bufLower[0];
  IndicatorRelease(handle);
}

double GetATR(string sym,ENUM_TIMEFRAMES tf,int period,int shift)
{
   int handle=iATR(sym,tf,period);
   if(handle==INVALID_HANDLE)
      return(0);
   double buf[];
   if(CopyBuffer(handle,0,shift,1,buf)<1)
   {
      IndicatorRelease(handle);
      return(0);
   }
   double val=buf[0];
   IndicatorRelease(handle);
   return(val);
}

double GetSAR(string sym,ENUM_TIMEFRAMES tf,double step,double maximum,int shift)
{
   int handle=iSAR(sym,tf,step,maximum);
   if(handle==INVALID_HANDLE)
      return(0);
   double buf[];
   if(CopyBuffer(handle,0,shift,1,buf)<1)
   {
      IndicatorRelease(handle);
      return(0);
   }
   double val=buf[0];
   IndicatorRelease(handle);
   return(val);
}

//+------------------------------------------------------------------+
void ManageTradeExit(string sym)
{
   int idx=FindSymbolIndex(sym);
   if(idx<0)
      return;

   if(!PositionSelect(sym))
   {
      partialTaken[idx]=false;
      return;
   }

   ulong   ticket    = (ulong)PositionGetInteger(POSITION_TICKET);
   long    type      = PositionGetInteger(POSITION_TYPE);
   double  volume    = PositionGetDouble(POSITION_VOLUME);
   double  openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double  sl        = PositionGetDouble(POSITION_SL);
   double  tp        = PositionGetDouble(POSITION_TP);
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   ENUM_TIMEFRAMES tf = PERIOD_M15;
   double atr = GetATR(sym,tf,14,0);
   if(atr<=0)
      atr=SymbolInfoDouble(sym,SYMBOL_POINT)*10.0;

   // Chandelier-style trailing stop
   double highest=openPrice;
   double lowest=openPrice;
   for(int i=1;i<=14;i++)
   {
      double h=iHigh(sym,tf,i);
      double l=iLow(sym,tf,i);
      if(h>highest) highest=h;
      if(l<lowest)  lowest=l;
   }
   double newSL=sl;
   if(type==POSITION_TYPE_BUY)
   {
      double trail=highest-2.0*atr;
      if(sl==0 || trail>sl)
         newSL=trail;
   }
   else
   {
      double trail=lowest+2.0*atr;
      if(sl==0 || trail<sl)
         newSL=trail;
   }
   if(newSL!=sl)
   {
      trade.PositionModify(sym,newSL,tp);
      Print(sym+" trailing stop updated at "+TimeToString(TimeCurrent()));
   }

   double price=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(sym,SYMBOL_BID):SymbolInfoDouble(sym,SYMBOL_ASK);

   // Partial profit taking at 2*ATR
   if(!partialTaken[idx])
   {
      double target=2.0*atr;
      if((type==POSITION_TYPE_BUY && price-openPrice>=target) ||
         (type==POSITION_TYPE_SELL && openPrice-price>=target))
      {
         if(trade.PositionClosePartial(ticket,volume/2.0))
         {
            partialTaken[idx]=true;
            double eq=AccountInfoDouble(ACCOUNT_EQUITY);
            Print(sym+" partial profit taken at "+TimeToString(TimeCurrent())+" Equity:"+DoubleToString(eq,2));
         }
      }
   }

   double sar  = GetSAR(sym,tf,0.02,0.2,0);
   double fast = GetMA(sym,tf,5);
   double slow = GetMA(sym,tf,20);

   bool reverse=false;
   if(type==POSITION_TYPE_BUY)
   {
      if(price<sar || fast<slow)
         reverse=true;
   }
   else
   {
      if(price>sar || fast>slow)
         reverse=true;
   }

   if(reverse)
   {
      if(trade.PositionClose(sym))
      {
         partialTaken[idx]=false;
         double eq=AccountInfoDouble(ACCOUNT_EQUITY);
         Print(sym+" Signal reversed - exit at "+TimeToString(TimeCurrent())+" Equity:"+DoubleToString(eq,2));
      }
      return;
   }

   int holdSecs=12*PeriodSeconds(tf);
   if(sym=="XAUUSD" || sym=="BTCUSD")
      holdSecs=3*24*3600; // approx 3 days

   if(TimeCurrent()-openTime>=holdSecs)
   {
      if(trade.PositionClose(sym))
      {
         partialTaken[idx]=false;
         double eq=AccountInfoDouble(ACCOUNT_EQUITY);
         Print(sym+" Timeout reached - exit at "+TimeToString(TimeCurrent())+" Equity:"+DoubleToString(eq,2));
      }
   }
}
//+------------------------------------------------------------------+
