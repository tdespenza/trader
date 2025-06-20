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
double leverageFactors[] = {1.0,1.0,1.0,0.2,0.2,0.1,0.01};

bool targetAchieved = false;

int OnInit()
{
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
   int idx = ArrayBsearch(symbols,sym);
   if(idx<0)
      return;

   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now,tm);
   int mins = tm.hour*60+tm.min;

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
   double lot = CalculateRiskAdjustedLot(sym,idx,50);
   if(p<=lower)
      trade.Buy(lot,sym);
   else if(p>=upper)
      trade.Sell(lot,sym);
}

void TradeCryptoTrend(string sym,int idx)
{
   double ma = GetMA(sym,PERIOD_H1,50);
   double p = iClose(sym,PERIOD_H1,0);
   double lot = CalculateRiskAdjustedLot(sym,idx,300);
   if(p>ma)
      trade.Buy(lot,sym);
   else if(p<ma)
      trade.Sell(lot,sym);
}

//+------------------------------------------------------------------+
double CalculateRiskAdjustedLot(string symbol,int idx,double slPips)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance*RiskPercent/100.0;
   double tickVal = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double riskPerLot = slPips*tickVal*leverageFactors[idx];
   double lots = risk/riskPerLot;
   return(MathMax(LotSizeMin,NormalizeDouble(lots,2)));
}

bool IsTradingHalted()
{
   static datetime lastDay=0;
   datetime now=TimeCurrent();
   if(TimeDay(now)!=TimeDay(lastDay))
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
//+------------------------------------------------------------------+
