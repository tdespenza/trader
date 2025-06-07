//+------------------------------------------------------------------+
//|            PropEdge Trinity EA                                   |
//|   Unified VWAP, Breakout & Pullback Strategy for Prop Firms      |
//|   Built for MDTC, FTMO, MyFF & similar one-phase challenges      |
//+------------------------------------------------------------------+
#property copyright "Tyshawn Despenza"
#property version   "3.5"
#property strict
#property description "Multi-strategy prop firm bot: VWAP Reversal, London Breakout, and Trend Pullback with full risk control, broker behavior detection, equity scaling, logging, exit intelligence, and full prop challenge automation."

#include <Trade/Trade.mqh>

// === ENUM & PROP FIRM MODES ===
enum PropFirmType { FTMO, MFF, E8, MDTC };
input PropFirmType FirmMode = MDTC;
bool MultiPhase = true;
int CurrentPhase = 1;

// === INPUT PARAMETERS ===
input string TradeSymbols = "USTEC,XAUUSD,US30,EURUSD";
input double RiskPerTradeVWAP = 0.4;
input double RiskPerTradeBreakout = 0.3;
input double RiskPerTradePullback = 0.3;

double CurrRiskPerTradeVWAP;
double CurrRiskPerTradeBreakout;
double CurrRiskPerTradePullback;
input bool EnableVWAP = true;
input bool EnableBreakout = true;
input bool EnablePullback = true;
input double DailyLossLimitPct = 3.0;
input double MaxDrawdownPct = 10.0;

double CurrDailyLossLimitPct;
double CurrMaxDrawdownPct;
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
input int CooldownMinutesAfterLoss = 60;

input bool EnablePropChallengeMode = true;
input string VWAPSymbols = "NAS100";
input string BreakoutSymbols = "NAS100,US30";
input string PullbackSymbols = "NAS100";

input double EquityLockPercent = 9.0;
input int PauseAfterGainMinutes = 360;

input string LogFileName = "PropEdgeJournal.csv";

// === NEW INPUTS ===
input bool EnableMinTradeDays = true;
input int RequiredMinDays = 10;
input bool EnableDynamicWinLossAdjustment = true;
input bool EnableEquityCurveProtection = true;
input double MaxEquityDropPercent = 5.0;
input int EquityDropWindowHours = 48;
input bool EnableNYSessionOnly = false;
input int NYStartHour = 13; // 8 AM EST
input int NYEndHour = 20;   // 3 PM EST

input int ConfidenceThreshold = 70;
input bool EnableNewsFilter = true;
input int NewsBufferMinutes = 15;
input string ImportantCurrencies = "USD,EUR,GBP,XAU";
input bool EnableLondonSessionOnly = false;
input int LondonStartHour = 7;
input int LondonEndHour = 16;

input string TelegramBotToken = "";
input string TelegramChatID = "";
input bool EnableTelegram = false;

input double DailyProfitTargetPct = 3.0;
input double BreakEvenTriggerR = 1.0;
input double TrailStartR = 1.2;
input double TrailStopBufferPips = 20;

input bool EnableDynamicRisk = true;
input double WinStreakMultiplier = 1.5;
input double LossStreakReducer = 0.5;

input bool EnableAutoTradeDay = true;
input int ForceTradeHour = 22;

input int MaxTradeDurationMinutes = 120;
input int SnapshotIntervalMinutes = 120;
string EquityLogFile = "EquitySnapshots.csv";
input double MaxTotalDailyRiskPct = 1.5;
input double MaxRiskPerTradePct = 0.5;
input int MaxAllowedSpreadPoints = 60;
input bool EnableSlippageLog = true;
string SlippageLogFile = "SlippageLog.csv";

// === GLOBAL VARIABLES ===
CTrade trade;
int ConsecutiveLosses = 0;
bool LossStreakLock = false;
datetime LastLossTime = 0;
bool IsPausedAfterGain = false;
datetime LastEquityGainTime = 0;
bool EquityLockHit = false;
string RedNewsTimes[100];
int RedNewsLevels[100];
int RedNewsCount = 0;
#ifdef __MQL5_TESTER__
bool mockNews = true;
#else
bool mockNews = false;
#endif
datetime LastSnapshotTime = 0;
string NewsCurrencyList[] = {"USD", "XAU", "NAS"};
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
double DailyTradeRiskTotal = 0;
int ServerTimeOffset = 0;
int TotalTradesExecuted = 0;

int GetHour(datetime t){ MqlDateTime s; TimeToStruct(t, s); return s.hour; }
int GetDay(datetime t){ MqlDateTime s; TimeToStruct(t, s); return s.day; }
int GetDayOfWeek(datetime t){ MqlDateTime s; TimeToStruct(t, s); return s.day_of_week; }

// === DYNAMIC RISK TRACKING ===
int winStreak = 0;
int lossStreak = 0;

// === EQUITY CURVE TRACKING ===
double equityCurve[100];
datetime equityTimestamps[100];
int equityIdx = 0;
input int EquitySlopeHours = 6;
input double MaxEquitySlopeDropPct = 3.0;

// === TRACK TRADE DAYS ===
datetime LastTradeDay = 0;
int TradeDayCount = 0;
bool TradeMadeToday = false;

// === TRACK EQUITY HISTORY FOR CURVE PROTECTION ===
double EquityHistory[100];
datetime EquityTimestamps[100];
int EquityIndex = 0;

// === FUNCTION: LOG TRADE TO FILE ===
void LogTrade(string sym, string type, double lot, double sl, double tp, string result) {
    int handle = FileOpen(LogFileName, FILE_CSV|FILE_READ|FILE_WRITE, ',');
    if (handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, type, lot, sl, tp, result,
                  DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
                  DoubleToString(SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID), 2),
                  IntegerToString(GetTickCount()));
        FileClose(handle);
    }
    if (GetDay(LastTradeDay) != GetDay(TimeCurrent())) TradeDayCount++;
    LastTradeDay = TimeCurrent();
    TradeMadeToday = true;
}

// === FUNCTION: BROKER BEHAVIOR CHECK ===
bool IsBrokerSpiking(string sym) {
    double spread = (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / _Point;
    return (spread > 50);
}

// === TIME FILTERS ===
bool IsTimeRestricted() {
    datetime now = TimeCurrent();
    if (GetDayOfWeek(now) == 1 && GetHour(now) < 4) return true;
    if (GetDayOfWeek(now) == 5 && GetHour(now) > 16) return true;
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

// === FUNCTION: CHECK MINIMUM TRADE DAY COMPLIANCE ===
void CheckMinTradeDayRequirement() {
    if (EnableMinTradeDays && !TradeMadeToday) {
        // force a micro trade if no trade made today
        trade.Buy(0.01, TradeSymbols);
    }
    TradeMadeToday = false;
}

// === FUNCTION: CHECK EQUITY CURVE ===
bool IsEquityCurveFailing() {
    if (!EnableEquityCurveProtection) return false;
    datetime now = TimeCurrent();
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    for (int i = 0; i < EquityIndex; i++) {
        if (now - EquityTimestamps[i] <= EquityDropWindowHours * 3600) {
            double drop = 100.0 * (EquityHistory[i] - currentEquity) / EquityHistory[i];
            if (drop >= MaxEquityDropPercent) return true;
        }
    }
    EquityHistory[EquityIndex] = currentEquity;
    EquityTimestamps[EquityIndex] = now;
    EquityIndex = (EquityIndex + 1) % 100;
    return false;
}

// === FUNCTION: CHECK IF IN NY SESSION ===
bool IsInNYSession() {
    int hour = GetHour(TimeCurrent());
    return (!EnableNYSessionOnly || (hour >= NYStartHour && hour <= NYEndHour));
}

// === PROP FIRM CONFIGURATION ===
void ApplyFirmSettings() {
    CurrDailyLossLimitPct = DailyLossLimitPct;
    CurrMaxDrawdownPct = MaxDrawdownPct;
    CurrRiskPerTradeVWAP = RiskPerTradeVWAP;
    CurrRiskPerTradeBreakout = RiskPerTradeBreakout;
    CurrRiskPerTradePullback = RiskPerTradePullback;

    switch(FirmMode) {
        case FTMO:
            CurrDailyLossLimitPct = 5.0;
            CurrMaxDrawdownPct = 10.0;
            break;
        case MFF:
            CurrDailyLossLimitPct = 4.0;
            CurrMaxDrawdownPct = 8.0;
            break;
        case E8:
            CurrDailyLossLimitPct = 5.0;
            CurrMaxDrawdownPct = 8.0;
            break;
        case MDTC:
            CurrDailyLossLimitPct = 3.0;
            CurrMaxDrawdownPct = 10.0;
            break;
    }
    if (MultiPhase && CurrentPhase == 2) {
        CurrRiskPerTradeVWAP *= 0.75;
        CurrRiskPerTradeBreakout *= 0.75;
        CurrRiskPerTradePullback *= 0.75;
    }
}

// === TRADE DURATION MONITOR ===
void CheckTradeDuration() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            datetime opentime = (datetime)PositionGetInteger(POSITION_TIME);
            if ((TimeCurrent() - opentime) > MaxTradeDurationMinutes * 60) {
                Print("[Alert] Trade open too long: ", PositionGetString(POSITION_SYMBOL));
            }
        }
    }
}

// === EQUITY SNAPSHOT LOGGING ===
void LogEquitySnapshot() {
    datetime now = TimeCurrent();
    if ((now - LastSnapshotTime) >= SnapshotIntervalMinutes * 60) {
        int handle = FileOpen(EquityLogFile, FILE_CSV|FILE_READ|FILE_WRITE, ',');
        if (handle != INVALID_HANDLE) {
            FileSeek(handle, 0, SEEK_END);
            FileWrite(handle, TimeToString(now, TIME_DATE|TIME_MINUTES),
                      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
                      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
            FileClose(handle);
        }
        LastSnapshotTime = now;
    }
}

// === END OF HEADER ===

void LoadRedNewsTimes() {
#ifdef __MQL5_TESTER__
    int handle = FileOpen("news.csv", FILE_READ|FILE_CSV);
    RedNewsCount = 0;
    if(handle == INVALID_HANDLE) {
        Print("news.csv not found for tester");
        return;
    }
    while(!FileIsEnding(handle) && RedNewsCount < 100) {
        string datetimeStr = FileReadString(handle);
        string impact = FileReadString(handle);
        int level = (StringFind(impact, "High") != -1) ? 3 : (StringFind(impact, "Medium") != -1 ? 2 : 1);
        if(StringLen(datetimeStr) > 0) {
            RedNewsTimes[RedNewsCount] = datetimeStr;
            RedNewsLevels[RedNewsCount] = level;
            RedNewsCount++;
        }
    }
    FileClose(handle);
#else
    string url = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";
    char data[];
    char result[];
    string result_headers;
    int timeout = 5000;
    int res = WebRequest("GET", url, "", "", timeout, data, 0, result, result_headers);
    if (res != 200) {
        Print("Failed to fetch news: ", res);
        return;
    }
    string xml = CharArrayToString(result);
    int pos = 0;
    RedNewsCount = 0;
    while ((pos = StringFind(xml, "<event>", pos)) != -1 && RedNewsCount < 100) {
        string segment = StringSubstr(xml, pos, 500);
        string currency = ExtractBetween(segment, "<currency>", "</currency>");
        string impact = ExtractBetween(segment, "<impact>", "</impact>");
        string datetimeStr = ExtractBetween(segment, "<date>", "</date>") + " " + ExtractBetween(segment, "<time>", "</time>");

        if (StringFind(ImportantCurrencies, currency) != -1) {
            int level = (StringFind(impact, "High") != -1) ? 3 : (StringFind(impact, "Medium") != -1 ? 2 : 1);
            RedNewsTimes[RedNewsCount] = datetimeStr;
            RedNewsLevels[RedNewsCount] = level;
            RedNewsCount++;
        }
        pos += 10;
    }
#endif
}

string ExtractBetween(string source, string fromTag, string toTag) {
    int start = StringFind(source, fromTag);
    if (start == -1) return "";
    start += StringLen(fromTag);
    int end = StringFind(source, toTag, start);
    if (end == -1) return "";
    return StringSubstr(source, start, end - start);
}

int OnInit() {
    ApplyFirmSettings();
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
    if (GetDayOfWeek(now) == 1 && GetHour(now) < 4) return;
    if (GetDayOfWeek(now) == 5 && GetHour(now) > 16) return;
    if (IsPausedAfterGain && (now - LastEquityGainTime) < PauseAfterGainMinutes * 60) return;
    if (LossStreakLock) return;
    if (EquityLockHit) return;
    if (EnableNewsFilter && IsNearRedNews()) return;
    if (GetDay(TimeCurrent()) != GetDay(LastTradeTimeVWAP)) ResetDailyCounters();
    if (TradeLock) return;
    CheckTradeDuration();
    LogEquitySnapshot();
    // === TO CALL IN MAIN LOOP ===
    // CheckServerOffset();
    // if (IsMajorEventToday()) { Print("[Block] Trading paused due to macroeconomic event"); return; }
    // if (!IsSpreadAcceptable(Symbol())) return;
    // if (!CanTradeRiskToday(calculatedTradeRisk)) return;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (equity > MaxEquity) MaxEquity = equity;
    if (equity < MinEquity) MinEquity = equity;

    double dailyLoss = 100.0 * (DayStartEquity - equity) / DayStartEquity;
    double totalDD = 100.0 * (MaxEquity - equity) / MaxEquity;

    if (dailyLoss > CurrDailyLossLimitPct || totalDD > CurrMaxDrawdownPct || DailyProfitHit || DailyLossHit) {
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
if (dailyLoss >= CurrDailyLossLimitPct) {
    DailyLossHit = true;
    Print("🚫 Daily loss limit hit. Disabling trading.");
    return;
}
for (int i = 0; i < ArraySize(symbols); i++) {
    string sym = symbols[i];
    if (EnableVWAP && StringFind(VWAPSymbols, sym) != -1) StrategyVWAP(sym);
    if (EnableBreakout && StringFind(BreakoutSymbols, sym) != -1) StrategyBreakout(sym);
    if (EnablePullback && StringFind(PullbackSymbols, sym) != -1) StrategyPullback(sym);
    }
}


// === VOLATILITY CHECK ===
double CalcATRManual(string sym, ENUM_TIMEFRAMES tf, int period) {
    MqlRates rates[];
    if (CopyRates(sym, tf, 0, period + 1, rates) <= period)
        return 0.0;
    ArraySetAsSeries(rates, true);
    double sumTR = 0.0;
    for (int i = 1; i <= period; i++) {
        double high = rates[i - 1].high;
        double low = rates[i - 1].low;
        double prevClose = rates[i].close;
        double tr = MathMax(high - low,
                            MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
        sumTR += tr;
    }
    return sumTR / period;
}

double GetATR(string sym, ENUM_TIMEFRAMES tf, int period) {
    return CalcATRManual(sym, tf, period);
}

// Utility: get EMA value for specified shift
double GetEMA(string sym, ENUM_TIMEFRAMES tf, int period, int shift=0) {
    int h = iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE);
    if(h==INVALID_HANDLE) return 0.0;
    double buf[];
    if(CopyBuffer(h, 0, shift, 1, buf) <= 0) {
        IndicatorRelease(h);
        return 0.0;
    }
    IndicatorRelease(h);
    return buf[0];
}

bool IsVolatilitySufficient(string sym, ENUM_TIMEFRAMES tf = PERIOD_M15) {
    double atr = GetATR(sym, tf, 14);
    return atr >= ATRThreshold;
}

// === STRATEGY 1: VWAP + LIQUIDITY ===
void StrategyVWAP(string sym) {
    if (!IsVolatilitySufficient(sym)) return;
    if (TradesTodayVWAP >= 2 || GetHour(TimeCurrent()) < 4 || GetHour(TimeCurrent()) > 11) return;
    if (!IsSpreadAcceptable(sym)) return;
    MqlRates rates[];
    if (!CopyRates(sym, PERIOD_M5, 0, VWAPPeriod + 10, rates)) return;
    ArraySetAsSeries(rates, true);

    double vwap = 0, tpv = 0, vol = 0;
    for (int i = 0; i < VWAPPeriod; i++) {
        double typical = (rates[i].high + rates[i].low + rates[i].close) / 3;
        tpv += typical * (double)rates[i].tick_volume;
        vol += (double)rates[i].tick_volume;
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
        OpenTrade(sym, ORDER_TYPE_SELL, CurrRiskPerTradeVWAP, MagicVWAP);
    else if (rates[0].low < recentLow - 50 * _Point && close > vwap && IsBullishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_BUY, CurrRiskPerTradeVWAP, MagicVWAP);
}

// === STRATEGY 2: LONDON BREAKOUT ===
void StrategyBreakout(string sym) {
    if (!IsVolatilitySufficient(sym)) return;
    if (TradesTodayBreakout >= 2 || GetHour(TimeCurrent()) < 2 || GetHour(TimeCurrent()) > 5) return;
    if (!IsSpreadAcceptable(sym)) return;
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

    if (bid > high && IsBullishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_BUY, CurrRiskPerTradeBreakout, MagicBreakout);
    if (ask < low && IsBearishEngulfing(rates[1], rates[0]))
        OpenTrade(sym, ORDER_TYPE_SELL, CurrRiskPerTradeBreakout, MagicBreakout);
}

// === STRATEGY 3: TREND PULLBACK ===
void StrategyPullback(string sym) {
    if (!IsVolatilitySufficient(sym)) return;
    int hour = GetHour(TimeCurrent());
    if (TradesTodayPullback >= 2 || (hour < 7 || (hour > 13 && hour < 14) || hour > 16)) return;
    if (!IsSpreadAcceptable(sym)) return;
    double emaFast = GetEMA(sym, PERIOD_M15, 10);
    double emaSlow = GetEMA(sym, PERIOD_M15, 21);
    double price = iClose(sym, PERIOD_M15, 0);

    if (emaFast > emaSlow && price < emaFast - 20 * _Point) {
        MqlRates rates[];
        if (!CopyRates(sym, PERIOD_M15, 0, 3, rates)) return;
        ArraySetAsSeries(rates, true);
        if (IsBullishEngulfing(rates[1], rates[0]))
            OpenTrade(sym, ORDER_TYPE_BUY, CurrRiskPerTradePullback, MagicPullback);
    }
    else if (emaFast < emaSlow && price > emaFast + 20 * _Point) {
        MqlRates rates[];
        if (!CopyRates(sym, PERIOD_M15, 0, 3, rates)) return;
        ArraySetAsSeries(rates, true);
        if (IsBearishEngulfing(rates[1], rates[0]))
            OpenTrade(sym, ORDER_TYPE_SELL, CurrRiskPerTradePullback, MagicPullback);
    }
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
    double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
    double marginPerLot = contractSize / leverage;
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double maxAllowedLots = freeMargin / marginPerLot;

    return NormalizeDouble(MathMin(lots, maxAllowedLots), 2);
}

// === NEWS FILTER ===
bool IsNearRedNews(int minImpact = 2) {
#ifdef __MQL5_TESTER__
    return false;
#endif
    datetime now = TimeCurrent();
    for (int i = 0; i < RedNewsCount; i++) {
        if (RedNewsLevels[i] >= minImpact) {
            datetime newsTime = StringToTime(RedNewsTimes[i]);
            if (newsTime > 0) {
                if (MathAbs((int)(now - newsTime)) < NewsBufferMinutes * 60)
                    return true;
            }
        }
    }
    return false;
}

// === DAILY COUNTER RESET ===
int CalculateConfidenceScore(string sym) {
    double atr = GetATR(sym, PERIOD_M15, 14);
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

// === PROP RISK SETTINGS ===
bool CanTradeRiskToday(double newRisk) {
    if (newRisk > MaxRiskPerTradePct) {
        Print("[Block] Trade risk exceeds maximum allowed per trade: ", newRisk, "%");
        return false;
    }
    datetime now = TimeCurrent();
    if (GetDay(LastTradeDay) != GetDay(now)) {
        DailyTradeRiskTotal = 0;
        LastTradeDay = now;
    }
    if ((DailyTradeRiskTotal + newRisk) <= MaxTotalDailyRiskPct) {
        DailyTradeRiskTotal += newRisk;
        return true;
    } else {
        Print("[Block] Risk cap hit for today: ", DailyTradeRiskTotal, "%");
        return false;
    }
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
#ifdef __MQL5_TESTER__
    Print("[TG] ", message);
    return;
#else
    string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + TelegramChatID + "&text=" + message;
    char data[];
    char result[];
    string result_headers;
    int timeout = 5000;
    int res = WebRequest("GET", url, "", "", timeout, data, 0, result, result_headers);
    if (res != 200) Print("Telegram error: ", res);
#endif
}

bool IsEquitySlopeFailing() {
    datetime now = TimeCurrent();
    double currEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    for (int i = 0; i < equityIdx; i++) {
        if ((now - equityTimestamps[i]) < EquitySlopeHours * 3600) {
            double drop = 100.0 * (equityCurve[i] - currEquity) / equityCurve[i];
            if (drop >= MaxEquitySlopeDropPct)
                return true;
        }
    }
    equityCurve[equityIdx] = currEquity;
    equityTimestamps[equityIdx] = now;
    equityIdx = (equityIdx + 1) % 100;
    return false;
}

bool InSessionWindow() {
    int h = GetHour(TimeCurrent());
    if (EnableLondonSessionOnly && (h < LondonStartHour || h > LondonEndHour)) return false;
    if (EnableNYSessionOnly && (h < NYStartHour || h > NYEndHour)) return false;
    return true;
}

void AdjustRisk() {
    if (!EnableDynamicRisk) return;
    if (winStreak >= 2) {
        CurrRiskPerTradeVWAP *= WinStreakMultiplier;
        CurrRiskPerTradeBreakout *= WinStreakMultiplier;
        CurrRiskPerTradePullback *= WinStreakMultiplier;
    } else if (lossStreak >= 2) {
        CurrRiskPerTradeVWAP *= LossStreakReducer;
        CurrRiskPerTradeBreakout *= LossStreakReducer;
        CurrRiskPerTradePullback *= LossStreakReducer;
    }
}

void ForceMinimumDailyTrade() {
    datetime now = TimeCurrent();
    if (EnableAutoTradeDay && GetHour(now) >= ForceTradeHour) {
        static bool traded = false;
        if (!traded) {
            trade.Buy(0.01, TradeSymbols);
            traded = true;
        }
    }
}

void LogDetailedTrade(string symbol, string type, double lot, double sl, double tp, double entryPrice, double exitPrice, string result) {
    int handle = FileOpen(LogFileName, FILE_CSV|FILE_READ|FILE_WRITE, ',');
    if (handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                  symbol, type, lot, sl, tp, entryPrice, exitPrice,
                AccountInfoDouble(ACCOUNT_EQUITY),
                (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD),
                  GetTickCount(), result);
        FileClose(handle);
    }
}

void LogSlippage(string symbol, double requested, double executed) {
    if(!EnableSlippageLog) return;
    double slip = MathAbs(executed - requested) / _Point;
    int handle = FileOpen(SlippageLogFile, FILE_CSV|FILE_READ|FILE_WRITE, ',');
    if(handle!=INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), symbol, requested, executed, slip);
        FileClose(handle);
    }
}

// === SPREAD MONITORING ===
bool IsSpreadAcceptable(string symbol) {
    double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    if (spread > MaxAllowedSpreadPoints) {
        Print("[Block] Spread too high on ", symbol, ": ", spread);
        return false;
    }
    return true;
}

// === MARKET CONDITIONS FILTER ===
bool IsMajorEventToday() {
    string highImpactEvents[] = {"NFP", "FOMC", "CPI"};
    for (int i = 0; i < RedNewsCount; i++) {
        for (int j = 0; j < ArraySize(highImpactEvents); j++) {
            if (StringFind(RedNewsTimes[i], highImpactEvents[j]) != -1)
                return true;
        }
    }
    return false;
}

// === SERVER TIME OFFSET CHECK ===
void CheckServerOffset() {
    datetime now = TimeLocal();
    datetime broker = TimeCurrent();
    int offset = (int)((broker - now) / 3600);
    Print("[Info] Broker vs VPS time offset: ", offset, " hours (check weekends manually)");
}

// === CANDLE PATTERN FILTER ===
bool IsBullishEngulfing(const MqlRates &r1, const MqlRates &r2) {
    return r2.close > r2.open && r1.close < r1.open && r2.open < r1.close && r2.close > r1.open;
}
bool IsBearishEngulfing(const MqlRates &r1, const MqlRates &r2) {
    return r2.close < r2.open && r1.close > r1.open && r2.open > r1.close && r2.close < r1.open;
}

// === TRADE EXECUTION ===
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

    int retries = 3;
    bool success = false;
    while (retries-- > 0 && !success) {
        if (type == ORDER_TYPE_BUY)
            success = trade.Buy(lot, sym, price, sl, tp);
        else
            success = trade.Sell(lot, sym, price, sl, tp);
        if (!success) Sleep(1000);
    }

    if (!success) {
        LastLossTime = TimeCurrent();
        ConsecutiveLosses++;
        if (ConsecutiveLosses >= MaxConsecutiveLosses) LossStreakLock = true;
        return;
    }

    LogSlippage(sym, price, trade.ResultPrice());
    TotalTradesExecuted++;

    string action = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
    SendTelegram(action + " " + sym + " | Lot: " + DoubleToString(lot, 2) +
                 " SL: " + DoubleToString(sl, 2) + " TP: " + DoubleToString(tp, 2));
}
