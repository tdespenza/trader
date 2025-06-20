//+------------------------------------------------------------------+
//| Expert Advisor for MDTC Challenge – Updated for 12% Target       |
//| Trades: EURUSD, USDJPY, GBPUSD, US500, US30, XAUUSD, BTCUSD     |
//| Strategies with adjusted goal and risk control                  |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

// Global Inputs
input double RiskPercent = 1.0;          // Risk per trade
input double TargetPercent = 12.0;       // Updated profit target
input double DailyLossLimitPercent = 3.0;// Daily drawdown max
input double LotSizeMin = 0.01;

// Monitored symbols
string symbols[] = {"EURUSD", "USDJPY", "GBPUSD", "US500", "US30", "XAUUSD", "BTCUSD"};
double leverageFactors[] = {1.0, 1.0, 1.0, 0.2, 0.2, 0.1, 0.01};

// State tracking
bool targetAchieved = false;

//+------------------------------------------------------------------+
int OnInit() { return INIT_SUCCEEDED; }

void OnTick()
{
   if (targetAchieved || IsTradingHalted()) return;

   double targetBalance = AccountBalance() * (1.0 + TargetPercent / 100.0);
   if (AccountEquity() >= targetBalance)
   {
      Print("🎯 Profit target of ", TargetPercent, "% reached. Trading halted.");
      targetAchieved = true;
      return;
   }

   string sym = Symbol();
   int idx = ArrayBsearch(symbols, sym);
   if (idx < 0) return;

   datetime now = TimeCurrent();
   MqlDateTime tm; TimeToStruct(now, tm);
   int mins = tm.hour * 60 + tm.min;

   if ((sym == "EURUSD" || sym == "USDJPY") && mins >= 480 && mins <= 720)
      TradeSessionBreakout(sym, idx);

   if (sym == "GBPUSD" && mins == 480)
      TradeLondonBreakout(sym, idx);

   if ((sym == "US500" || sym == "US30") && mins >= 570 && mins <= 630)
      TradeNYMomentum(sym, idx);

   if (sym == "XAUUSD" && mins >= 570 && mins <= 690)
      TradeGoldRange(sym, idx);

   if (sym == "BTCUSD" && tm.hour % 6 == 0)
      TradeCryptoTrend(sym, idx);
}

void TradeSessionBreakout(string sym, int idx)
{
   double high = iHigh(sym, PERIOD_H1, 1);
   double low = iLow(sym, PERIOD_H1, 1);
   double offset = 10 * _Point;
   double buy = high + offset;
   double sell = low - offset;
   double lot = CalculateRiskAdjustedLot(sym, idx, 20);
   trade.BuyStop(lot, buy, sym, buy - 20 * _Point, buy + 40 * _Point);
   trade.SellStop(lot, sell, sym, sell + 20 * _Point, sell - 40 * _Point);
}

void TradeLondonBreakout(string sym, int idx)
{
   double h = iHigh(sym, PERIOD_M15, 4);
   double l = iLow(sym, PERIOD_M15, 4);
   double lot = CalculateRiskAdjustedLot(sym, idx, 30);
   double buy = h + 5 * _Point;
   double sell = l - 5 * _Point;
   trade.BuyStop(lot, buy, sym, buy - 30 * _Point, buy + 60 * _Point);
   trade.SellStop(lot, sell, sym, sell + 30 * _Point, sell - 60 * _Point);
}

void TradeNYMomentum(string sym, int idx)
{
   double ma1 = iMA(sym, PERIOD_M5, 5, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ma2 = iMA(sym, PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
   double price = iClose(sym, PERIOD_M5, 0);
   double lot = CalculateRiskAdjustedLot(sym, idx, 100);
   if (ma1 > ma2) trade.Buy(lot, sym, price, price - 100 * _Point, price + 200 * _Point);
   else if (ma1 < ma2) trade.Sell(lot, sym, price, price + 100 * _Point, price - 200 * _Point);
}

void TradeGoldRange(string sym, int idx)
{
   double u, m, d; BollingerBands(sym, PERIOD_M15, 20, 2.0, u, m, d);
   double p = iClose(sym, PERIOD_M15, 0);
   double lot = CalculateRiskAdjustedLot(sym, idx, 50);
   if (p <= d) trade.Buy(lot, sym);
   else if (p >= u) trade.Sell(lot, sym);
}

void TradeCryptoTrend(string sym, int idx)
{
   double ma = iMA(sym, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
   double p = iClose(sym, PERIOD_H1, 0);
   double lot = CalculateRiskAdjustedLot(sym, idx, 300);
   if (p > ma) trade.Buy(lot, sym);
   else if (p < ma) trade.Sell(lot, sym);
}

//+------------------------------------------------------------------+
double CalculateRiskAdjustedLot(string symbol, int idx, double slPips)
{
   double risk = AccountBalance() * RiskPercent / 100.0;
   double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double riskPerLot = slPips * tickVal * leverageFactors[idx];
   double lots = risk / riskPerLot;
   return MathMax(LotSizeMin, NormalizeDouble(lots, 2));
}

bool IsTradingHalted()
{
   static datetime lastDay = 0;
   datetime now = TimeCurrent();
   if (TimeDay(now) != TimeDay(lastDay))
   {
      lastDay = now;
      if ((AccountBalance() - AccountEquity()) / AccountBalance() * 100.0 >= DailyLossLimitPercent)
      {
         Print("🚫 Daily drawdown exceeded. Trading halted for today.");
         return true;
      }
   }
   return false;
}

void BollingerBands(string s, ENUM_TIMEFRAMES tf, int p, double d, double &u, double &m, double &l)
{
   m = iBands(s, tf, p, d, 0, PRICE_CLOSE, MODE_MAIN, 0);
   u = iBands(s, tf, p, d, 0, PRICE_CLOSE, MODE_UPPER, 0);
   l = iBands(s, tf, p, d, 0, PRICE_CLOSE, MODE_LOWER, 0);
} //+------------------------------------------------------------------+
