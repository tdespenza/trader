//+------------------------------------------------------------------+
//|            PropEdge Trinity EA                                   |
//|   Unified VWAP, Breakout & Pullback Strategy for Prop Firms      |
//|   Built for MDTC, FTMO, MyFF & similar one-phase challenges      |
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property version   "3.0"
#property strict
#property description "Multi-strategy prop firm bot: VWAP Reversal, London Breakout, and Trend Pullback with full risk control, broker behavior detection, equity scaling, logging, exit intelligence, and full prop challenge automation."

#include <Trade/Trade.mqh>
CTrade trade;
#include <stdlib.mqh>
#include <Wininet.dll>
#import "kernel32.dll"
int GetTickCount();
#import

// === INPUT CONFIGURATION ===
input string TradeSymbols = "NAS100,XAUUSD,US30";
input double RiskPerTradeVWAP = 0.4;
input double RiskPerTradeBreakout = 0.3;
input double RiskPerTradePullback = 0.3;
input bool EnableVWAP = true;
input bool EnableBreakout = true;
input bool EnablePullback = true;
input double DailyLossLimitPct = 3.0;
input double MaxDrawdownPct = 10.0;
input int VWAPPeriod = 20;
input int BreakoutRangeBars = 12;
input double SL_Pips = 100;
input double TP_Pips = 150;
input int MagicVWAP = 1001;
input int MagicBreakout = 1002;
input int MagicPullback = 1003;
input double ATRThreshold = 0.0008;

input bool EnableGrowToGoal = true;
input double GrowStartPct = 0.0;
input double GrowEndPct = 8.0;
input double GrowRiskMultiplier = 2.0;
input bool EnableSymbolReallocation = true;
input int PauseDurationHours = 24;

input int MaxConsecutiveLosses = 3;
int ConsecutiveLosses = 0;
bool LossStreakLock = false;
datetime LastLossTime = 0;
input int CooldownMinutesAfterLoss = 60;

input bool EnablePropChallengeMode = true;
input string VWAPSymbols = "NAS100";
input string BreakoutSymbols = "NAS100,US30";
input string PullbackSymbols = "NAS100";

input double EquityLockPercent = 9.0;
input int PauseAfterGainMinutes = 360;
bool IsPausedAfterGain = false;
datetime LastEquityGainTime = 0;

input string LogFileName = "PropEdgeJournal.csv";

// === GLOBAL STATE ===
input int ConfidenceThreshold = 70;
bool EquityLockHit = false;
input bool EnableNewsFilter = true;
input int NewsBufferMinutes = 15;
string NewsCurrencyList[] = {"USD", "XAU", "NAS"};
string RedNewsTimes[];

// === FUNCTION: LOG TRADE TO FILE ===
void LogTrade(string sym, string type, double lot, double sl, double tp, string result) {
    int handle = FileOpen(LogFileName, FILE_CSV|FILE_READ|FILE_WRITE, ',');
    if (handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, type, lot, sl, tp, result, DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        FileClose(handle);
    }
}

// === FUNCTION: BROKER BEHAVIOR CHECK ===
bool IsBrokerSpiking(string sym) {
    double spread = (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / _Point;
    return (spread > 50);
}

// === TIME FILTERS ===
bool IsTimeRestricted() {
    datetime now = TimeCurrent();
    if (TimeDayOfWeek(now) == 1 && TimeHour(now) < 4) return true;
    if (TimeDayOfWeek(now) == 5 && TimeHour(now) > 16) return true;
    return false;
}

// === FUNCTION: ADJUST RISK FOR EQUITY GROWTH ===
double AdjustedRisk(string sym, double baseRisk) {
    if (!EnableGrowToGoal) return baseRisk;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double growth = 100.0 * (equity - AccountInfoDouble(ACCOUNT_BALANCE)) / AccountInfoDouble(ACCOUNT_BALANCE);
    if (growth < GrowStartPct) return baseRisk;
    if (growth >= GrowEndPct) return baseRisk * GrowRiskMultiplier;
    double scale = 1.0 + (GrowRiskMultiplier - 1.0) * ((growth - GrowStartPct) / (GrowEndPct - GrowStartPct));
    return baseRisk * scale;
}

// === SYMBOL REALLOCATION LOGIC ===
bool IsSymbolPaused(string sym) {
    if (!EnableSymbolReallocation) return false;
    if (sym == "NAS100" && ConsecutiveLosses >= 2 && TimeCurrent() - LastLossTime < PauseDurationHours * 3600) return true;
    return false;
}

// === TRADE OUTCOME TRACKING ===
void TrackTradeResult(string sym, bool win) {
    if (win) ConsecutiveLosses = 0;
    else {
        ConsecutiveLosses++;
        LastLossTime = TimeCurrent();
        if (ConsecutiveLosses >= MaxConsecutiveLosses) LossStreakLock = true;
    }
}

// === SMART EXIT LOGIC ===
void ManageSmartExit(string sym, ulong ticket, int type, double entryPrice, double sl, double tp) {
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
    double rr = MathAbs(price - entryPrice) / (MathAbs(entryPrice - sl));
    if (rr >= 2.0) trade.PositionClose(ticket);
    else if (rr >= 1.5) trade.PositionClosePartial(ticket, 0.5);
    else if (AccountInfoDouble(ACCOUNT_EQUITY) > AccountInfoDouble(ACCOUNT_BALANCE) * 1.05) {
        double newSL = (type == ORDER_TYPE_BUY) ? price - 10 * _Point : price + 10 * _Point;
        trade.PositionModify(sym, newSL, tp);
    }
}

// === END OF HEADER ===

void LoadRedNewsTimes() {
    string url = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";
    char result[];
    int timeout = 5000;
    int res = WebRequest("GET", url, NULL, NULL, 0, result, timeout);
    if (res != 200) {
        Print("Failed to fetch ForexFactory RSS: ", res);
        return;
    }
    string xml = CharArrayToString(result);
    int pos = 0;
    int i = 0;
    while ((pos = StringFind(xml, "<event>", pos)) != -1 && i < 100) {
        string segment = StringSubstr(xml, pos, 300);
        string impact = ExtractBetween(segment, "<impact>", "</impact>");
        string currency = ExtractBetween(segment, "<currency>", "</currency>");
        string datetime = ExtractBetween(segment, "<date>", "</date>") + " " + ExtractBetween(segment, "<time>", "</time>");

        for (int c = 0; c < ArraySize(NewsCurrencyList); c++) {
            if (StringFind(currency, NewsCurrencyList[c]) != -1 && StringFind(impact, "High") != -1) {
                RedNewsTimes[i++] = datetime;
                break;
            }
        }
        pos += 10;
    }
}

string ExtractBetween(string source, string fromTag, string toTag) {
    int start = StringFind(source, fromTag);
    if (start == -1) return "";
    start += StringLen(fromTag);
    int end = StringFind(source, toTag, start);
    if (end == -1) return "";
    return StringSubstr(source, start, end - start);
}
#include <stdlib.mqh>
input string TelegramBotToken = "";
input string TelegramChatID = "";
input bool EnableTelegram = false;
#include <stdlib.mqh>
#include <Wininet.dll>
#import "kernel32.dll"
int GetTickCount();
#import

input double DailyProfitTargetPct = 2.5;
input double BreakEvenTriggerR = 1.0;
input double TrailStartR = 1.2;
input double TrailStopBufferPips = 20;
bool DailyProfitHit = false;
bool DailyLossHit = false;

datetime LastTradeTimeVWAP = 0;
datetime LastTradeTimeBreakout = 0;
datetime LastTradeTimePullback = 0;
int TradesTodayVWAP = 0;
int TradesTodayBreakout = 0;
int TradesTodayPullback = 0;

double DayStartEquity;
double MaxEquity;
double MinEquity;
bool TradeLock = false;

int OnInit() {
    TimeZoneAdjustment();
    LoadRedNewsTimes();
    ResetDailyCounters();
    DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    MaxEquity = DayStartEquity;
    MinEquity = DayStartEquity;
    return INIT_SUCCEEDED;
}

void OnTick() {
    datetime now = TimeCurrent();
    if (TimeDayOfWeek(now) == 1 && TimeHour(now) < 4) return;
    if (TimeDayOfWeek(now) == 5 && TimeHour(now) > 16) return;
    if (IsPausedAfterGain && (now - LastEquityGainTime) < PauseAfterGainMinutes * 60) return;
    if (LossStreakLock) return;
    if (EquityLockHit) return;
    if (EnableNewsFilter && IsNearRedNews()) return;
    if (TimeDay(TimeCurrent()) != TimeDay(LastTradeTimeVWAP)) ResetDailyCounters();
    if (TradeLock) return;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (equity > MaxEquity) MaxEquity = equity;
    if (equity < MinEquity) MinEquity = equity;

    double dailyLoss = 100.0 * (DayStartEquity - equity) / DayStartEquity;
    double totalDD = 100.0 * (MaxEquity - equity) / MaxEquity;

    if (dailyLoss > DailyLossLimitPct || totalDD > MaxDrawdownPct || DailyProfitHit || DailyLossHit) {
        Print("🚫 Risk guard triggered. No trading today.");
        TradeLock = true;
        return;
    }

    string symbols[];
    StringSplit(TradeSymbols, ',', symbols);

    double gainPct = 100.0 * (equity - DayStartEquity) / DayStartEquity;
if (gainPct >= EquityLockPercent) {
    IsPausedAfterGain = true;
    LastEquityGainTime = TimeCurrent();
    EquityLockHit = true;
    Print("🛑 Equity lock reached (" + DoubleToString(gainPct, 2) + "%). Stopping all trading.");
    return;
}
if (gainPct >= DailyProfitTargetPct) {
    IsPausedAfterGain = true;
    LastEquityGainTime = TimeCurrent();
    DailyProfitHit = true;
    Print("✅ Daily profit target hit. Disabling trading.");
    return;
}
if (dailyLoss >= DailyLossLimitPct) {
    DailyLossHit = true;
    Print("🚫 Daily loss limit hit. Disabling trading.");
    return;
}
for (int i = 0; i < ArraySize(symbols); i++) {
    string sym = symbols[i];
    if (EnableVWAP && StringFind(VWAPSymbols, sym) != -1) StrategyVWAP(sym);
    if (EnableBreakout && StringFind(BreakoutSymbols, sym) != -1) StrategyBreakout(sym);
    if (EnablePullback && StringFind(PullbackSymbols, sym) != -1) StrategyPullback(sym);
        if (EnableVWAP) StrategyVWAP(sym);
        if (EnableBreakout) StrategyBreakout(sym);
        if (EnablePullback) StrategyPullback(sym);
    }
}
        FileClose(handle);
    }
}

// === VOLATILITY CHECK ===
bool IsVolatilitySufficient(string sym, ENUM_TIMEFRAMES tf = PERIOD_M15) {
    double atr = iATR(sym, tf, 14, 0);
    return atr >= ATRThreshold;
}

// === STRATEGY 1: VWAP + LIQUIDITY ===
void StrategyVWAP(string sym) {
    if (!IsVolatilitySufficient(sym)) return;
    if (TradesTodayVWAP >= 2 || TimeHour(TimeCurrent()) < 4 || TimeHour(TimeCurrent()) > 11) return;
    if (!IsSpreadAcceptable(sym, 30)) return;
    MqlRates rates[];
    if (!CopyRates(sym, PERIOD_M5, 0, VWAPPeriod + 10, rates)) return;
    ArraySetAsSeries(rates, true);

    double vwap = 0, tpv = 0, vol = 0;
    for (int i = 0; i < VWAPPeriod; i++) {
        double typical = (rates[i].high + rates[i].low + rates[i].close) / 3;
        tpv += typical * rates[i].tick_volume;
        vol += rates[i].tick_volume;
    }
    if (vol == 0) return;
    vwap = tpv / vol;

    double recentHigh = rates[1].high;
    double recentLow = rates[1].low;
    for (int i = 2; i <= 5; i++) {
        if (rates[i].high > recentHigh) recentHigh = rates[i].high;
        if (rates[i].low < recentLow) recentLow = rates[i].low;
    }
    double close = rates[0].close;

    if (rates[0].high > recentHigh + 50 * _Point && close < vwap && IsBearishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_SELL, RiskPerTradeVWAP, MagicVWAP);
    else if (rates[0].low < recentLow - 50 * _Point && close > vwap && IsBullishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_BUY, RiskPerTradeVWAP, MagicVWAP);
}

// === STRATEGY 2: LONDON BREAKOUT ===
void StrategyBreakout(string sym) {
    if (!IsVolatilitySufficient(sym)) return;
    if (TradesTodayBreakout >= 2 || TimeHour(TimeCurrent()) < 2 || TimeHour(TimeCurrent()) > 5) return;
    if (!IsSpreadAcceptable(sym, 30)) return;
    MqlRates rates[];
    if (!CopyRates(sym, PERIOD_M15, 0, BreakoutRangeBars + 1, rates)) return;
    ArraySetAsSeries(rates, true);

    double high = rates[1].high;
    double low = rates[1].low;
    for (int i = 2; i <= BreakoutRangeBars; i++) {
        if (rates[i].high > high) high = rates[i].high;
        if (rates[i].low < low) low = rates[i].low;
    }

    double bid = SymbolInfoDouble(sym, SYMBOL_BID);
    double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

    if (bid > high && IsBullishEngulfing(rates[1], rates[0])) OpenTrade(sym, ORDER_TYPE_BUY, RiskPerTradeBreakout, MagicBreakout);
    if (ask < low && IsBearishEngulfing(rates[1], rates[0])) OpenTrade(sym, ORDER_TYPE_SELL, RiskPerTradeBreakout, MagicBreakout);
}

// === STRATEGY 3: TREND PULLBACK ===
void StrategyPullback(string sym) {
    if (!IsVolatilitySufficient(sym)) return;
    int hour = TimeHour(TimeCurrent());
    if (TradesTodayPullback >= 2 || (hour < 7 || (hour > 13 && hour < 14) || hour > 16)) return;
    if (!IsSpreadAcceptable(sym, 30)) return;
    double emaFast = iMA(sym, PERIOD_M15, 10, 0, MODE_EMA, PRICE_CLOSE, 0);
    double emaSlow = iMA(sym, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE, 0);
    double price = iClose(sym, PERIOD_M15, 0);

    if (emaFast > emaSlow && price < emaFast - 20 * _Point) {
        MqlRates rates[];
        if (!CopyRates(sym, PERIOD_M15, 0, 3, rates)) return;
        ArraySetAsSeries(rates, true);
        if (IsBullishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_BUY, RiskPerTradePullback, MagicPullback);
    else if (emaFast < emaSlow && price > emaFast + 20 * _Point) {
        MqlRates rates[];
        if (!CopyRates(sym, PERIOD_M15, 0, 3, rates)) return;
        ArraySetAsSeries(rates, true);
        if (IsBearishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_SELL, RiskPerTradePullback, MagicPullback);
}

// === LEVERAGE-AWARE LOT SIZE ===
double CalculateLotSize(string sym, double riskPct, double slPips) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskUSD = balance * riskPct / 100.0;

    double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
    double pipValue = tickValue / tickSize * _Point;

    double lots = riskUSD / (slPips * pipValue);

    double contractSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
    double leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    double marginPerLot = contractSize / leverage;
    double freeMargin = AccountFreeMargin();
    double maxAllowedLots = freeMargin / marginPerLot;

    return NormalizeDouble(MathMin(lots, maxAllowedLots), 2);
}

// === NEWS FILTER ===
bool IsNearRedNews() {
    datetime now = TimeCurrent();
    for (int i = 0; i < ArraySize(RedNewsTimes); i++) {
        datetime newsTime;
        if (StringToTime(RedNewsTimes[i], newsTime)) {
            if (MathAbs((int)(now - newsTime)) < NewsBufferMinutes * 60) return true;
        }
    }
    return false;
}

// === DAILY COUNTER RESET ===
int CalculateConfidenceScore(string sym) {
    double atr = iATR(sym, PERIOD_M15, 14, 0);
    double spread = (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / _Point;
    int score = 100;
    if (atr < ATRThreshold) score -= 30;
    if (spread > 30) score -= 30;
    return score;
}
void ResetDailyCounters() {
    ConsecutiveLosses = 0;
    LossStreakLock = false;
    TradesTodayVWAP = 0;
    TradesTodayBreakout = 0;
    TradesTodayPullback = 0;
}

// === TRAILING STOP + BREAKEVEN ===
void UpdateTrailingStop(string sym, ulong ticket, double entryPrice, int type, double slPips, double tpPips) {
    double currentPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
    double rr = MathAbs(currentPrice - entryPrice) / (slPips * _Point);
    double trailPrice = (type == ORDER_TYPE_BUY) ? currentPrice - TrailStopBufferPips * _Point : currentPrice + TrailStopBufferPips * _Point;

    if (rr >= BreakEvenTriggerR) {
        double newSL = (type == ORDER_TYPE_BUY) ? entryPrice : entryPrice;
        trade.PositionModify(sym, newSL, tpPips);
    }
    if (rr >= TrailStartR) {
        double newSL = trailPrice;
        trade.PositionModify(sym, newSL, tpPips);
    }
}

// === TELEGRAM ALERT ===
void SendTelegram(string message) {
    if (!EnableTelegram || StringLen(TelegramBotToken) == 0 || StringLen(TelegramChatID) == 0) return;
    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + TelegramChatID + "&text=" + message;
    char post[];
    char result[];
    int timeout = 5000;
    int res = WebRequest("GET", url, NULL, 10, post, result, timeout);
    if (res != 200) Print("Telegram error: ", res);
}

// === SPREAD CHECK ===
bool IsSpreadAcceptable(string sym, double maxSpreadPips) {
    double spread = (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / _Point;
    return spread <= maxSpreadPips;
}

// === CANDLE PATTERN FILTER ===
bool IsBullishEngulfing(MqlRates r1, MqlRates r2) {
    return r2.close > r2.open && r1.close < r1.open && r2.open < r1.close && r2.close > r1.open;
}
bool IsBearishEngulfing(MqlRates r1, MqlRates r2) {
    return r2.close < r2.open && r1.close > r1.open && r2.open > r1.close && r2.close < r1.open;
}

// === TRADE EXECUTION ===
int ServerTimeOffset = 0;
void TimeZoneAdjustment() {
    datetime localTime = TimeLocal();
    datetime serverTime = TimeCurrent();
    ServerTimeOffset = (int)(serverTime - localTime) / 3600;
    Print("Server Time Offset: ", ServerTimeOffset);
}
void OpenTrade(string sym, int type, double riskPct, int magic) {
    if ((TimeCurrent() - LastLossTime) < CooldownMinutesAfterLoss * 60) {
        Print("⏸ Cooldown active after loss. Skipping trade.");
        return;
    }
    if (CalculateConfidenceScore(sym) < ConfidenceThreshold) {
        Print("❌ Trade confidence too low. Skipping.");
        return;
    }
    if ((TimeCurrent() - LastLossTime) < CooldownMinutesAfterLoss * 60) {
        Print("⏸ Cooldown active after loss. Skipping trade.");
        return;
    }
    datetime now = TimeCurrent();
    if (magic == MagicVWAP) { LastTradeTimeVWAP = now; TradesTodayVWAP++; }
    else if (magic == MagicBreakout) { LastTradeTimeBreakout = now; TradesTodayBreakout++; }
    else if (magic == MagicPullback) { LastTradeTimePullback = now; TradesTodayPullback++; }
    double slPips = SL_Pips;
    double tpPips = TP_Pips;
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
    double sl = (type == ORDER_TYPE_BUY) ? price - slPips * _Point : price + slPips * _Point;
    double tp = (type == ORDER_TYPE_BUY) ? price + tpPips * _Point : price - tpPips * _Point;

    double lot = CalculateLotSize(sym, riskPct, slPips);
    if (lot < SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN)) return;

    trade.SetExpertMagicNumber(magic);
    trade.SetDeviationInPoints(10);
    if (type == ORDER_TYPE_BUY) {
    int retries = 3;
    while (retries-- > 0 && !trade.Buy(lot, sym, price, sl, tp)) {
        Sleep(1000);
    }
    if (retries <= 0) {
        LastLossTime = TimeCurrent();
        ConsecutiveLosses++;
        if (ConsecutiveLosses >= MaxConsecutiveLosses) LossStreakLock = true;
        return;
    }
        LastLossTime = TimeCurrent();
        ConsecutiveLosses++;
        if (ConsecutiveLosses >= MaxConsecutiveLosses) LossStreakLock = true;
        return;
            LastLossTime = TimeCurrent();
            return;
        }
        SendTelegram("BUY " + sym + " | Lot: " + DoubleToString(lot, 2) + " SL: " + DoubleToString(sl, 2) + " TP: " + DoubleToString(tp, 2));
    }
    else {
    int retries = 3;
    while (retries-- > 0 && !trade.Sell(lot, sym, price, sl, tp)) {
        Sleep(1000);
    }
    if (retries <= 0) {
        LastLossTime = TimeCurrent();
        ConsecutiveLosses++;
        if (ConsecutiveLosses >= MaxConsecutiveLosses) LossStreakLock = true;
        return;
    }
        LastLossTime = TimeCurrent();
        ConsecutiveLosses++;
        if (ConsecutiveLosses >= MaxConsecutiveLosses) LossStreakLock = true;
        return;
            LastLossTime = TimeCurrent();
            return;
        }
        SendTelegram("SELL " + sym + " | Lot: " + DoubleToString(lot, 2) + " SL: " + DoubleToString(sl, 2) + " TP: " + DoubleToString(tp, 2));
    }
}
