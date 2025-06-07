import pandas as pd
import numpy as np
import datetime
import requests
import json
import os

# === CONFIG ===
MATCHTRADER_REST_API = "https://api.match-trader.yourbroker.com"
API_KEY = "your_api_key_here"
SYMBOL = "NAS100"
TIMEFRAME = "M5"
MAX_RISK_PER_TRADE = 0.01  # 1%
ACCOUNT_BALANCE = 100000
VWAP_LOOKBACK = 20
LIQUIDITY_ZONE_PIPS = 50
TRAILING_DRAWDOWN_PCT = 0.05
DAILY_MAX_LOSS_PCT = 0.03
DAILY_RESET_HOUR = 21  # 5 PM EST
LOG_FILE = "equity_log.csv"

# === Global State ===
state = {
    "peak_equity": ACCOUNT_BALANCE,
    "account_balance": ACCOUNT_BALANCE,
    "trades_today": [],
    "daily_equity_log": []
}

# === Helper Functions ===
def fetch_ohlcv(symbol, timeframe, limit=100):
    url = f"{MATCHTRADER_REST_API}/candles?symbol={symbol}&tf={timeframe}&limit={limit}"
    headers = {"Authorization": f"Bearer {API_KEY}"}
    r = requests.get(url, headers=headers)
    data = r.json()["candles"]
    df = pd.DataFrame(data)
    df.columns = ["timestamp", "open", "high", "low", "close", "volume"]
    df["timestamp"] = pd.to_datetime(df["timestamp"], unit='ms')
    return df

def calculate_vwap(df):
    typical_price = (df["high"] + df["low"] + df["close"]) / 3
    df["tpv"] = typical_price * df["volume"]
    df["cum_tpv"] = df["tpv"].cumsum()
    df["cum_vol"] = df["volume"].cumsum()
    df["vwap"] = df["cum_tpv"] / df["cum_vol"]
    return df

def detect_liquidity_grab(df):
    prev_high = df["high"][-5:-1].max()
    prev_low = df["low"][-5:-1].min()
    current_high = df.iloc[-1]["high"]
    current_low = df.iloc[-1]["low"]
    if current_high > prev_high + LIQUIDITY_ZONE_PIPS:
        return "short"
    elif current_low < prev_low - LIQUIDITY_ZONE_PIPS:
        return "long"
    return None

def determine_entry(df):
    vwap = df.iloc[-1]["vwap"]
    close = df.iloc[-1]["close"]
    signal = detect_liquidity_grab(df)
    if signal == "short" and close < vwap:
        return "short"
    elif signal == "long" and close > vwap:
        return "long"
    return None

def calculate_lot_size(risk_percent, balance, sl_pips):
    dollar_risk = balance * risk_percent
    pip_value = 1
    lots = dollar_risk / (sl_pips * pip_value)
    return round(lots, 2)

def place_order(direction, symbol, lot_size, sl, tp):
    url = f"{MATCHTRADER_REST_API}/orders"
    headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
    payload = {
        "symbol": symbol,
        "type": "market",
        "side": direction,
        "volume": lot_size,
        "sl": sl,
        "tp": tp
    }
    r = requests.post(url, headers=headers, data=json.dumps(payload))
    return r.json()

# === Equity & Risk Checks ===
def get_equity():
    return np.random.uniform(97000, 103000)

def update_peak_equity(current_equity):
    if current_equity > state["peak_equity"]:
        state["peak_equity"] = current_equity

def get_trailing_drawdown_limit():
    return state["peak_equity"] * (1 - TRAILING_DRAWDOWN_PCT)

def get_daily_max_loss_limit():
    if state["daily_equity_log"]:
        return state["daily_equity_log"][-1]["equity"] * (1 - DAILY_MAX_LOSS_PCT)
    return state["account_balance"] * (1 - DAILY_MAX_LOSS_PCT)

def reset_daily_metrics(current_equity):
    state["daily_equity_log"].append({
        "timestamp": datetime.datetime.utcnow().isoformat(),
        "equity": current_equity
    })
    state["trades_today"] = []

def can_trade(current_equity):
    trailing_limit = get_trailing_drawdown_limit()
    daily_limit = get_daily_max_loss_limit()
    if current_equity <= trailing_limit:
        return False, f"Trailing drawdown hit: {current_equity:.2f} <= {trailing_limit:.2f}"
    if current_equity <= daily_limit:
        return False, f"Daily loss limit hit: {current_equity:.2f} <= {daily_limit:.2f}"
    return True, "Allowed"

def log_equity_snapshot(time, current_equity, peak_equity, trailing_limit, daily_limit, can_trade, reason):
    log_entry = {
        "time": time,
        "current_equity": current_equity,
        "peak_equity": peak_equity,
        "trailing_limit": trailing_limit,
        "daily_limit": daily_limit,
        "can_trade": can_trade,
        "reason": reason
    }
    df = pd.DataFrame([log_entry])
    if not os.path.isfile(LOG_FILE):
        df.to_csv(LOG_FILE, index=False)
    else:
        df.to_csv(LOG_FILE, mode='a', header=False, index=False)

# === Main Bot Logic ===
def run_bot():
    now = datetime.datetime.utcnow()
    current_equity = get_equity()

    if not state["daily_equity_log"] or datetime.datetime.fromisoformat(state["daily_equity_log"][-1]["timestamp"]).date() < now.date():
        if now.hour >= DAILY_RESET_HOUR:
            reset_daily_metrics(current_equity)

    update_peak_equity(current_equity)
    allowed, reason = can_trade(current_equity)
    log_equity_snapshot(now.isoformat(), current_equity, state["peak_equity"], get_trailing_drawdown_limit(), get_daily_max_loss_limit(), allowed, reason)

    if not allowed:
        print(f"🚫 Trade blocked: {reason}")
        return

    df = fetch_ohlcv(SYMBOL, TIMEFRAME)
    df = calculate_vwap(df)
    signal = determine_entry(df)

    if signal:
        sl_pips = 100
        tp_pips = 150
        lot_size = calculate_lot_size(MAX_RISK_PER_TRADE, ACCOUNT_BALANCE, sl_pips)
        price = df.iloc[-1]["close"]

        sl = price - sl_pips if signal == "long" else price + sl_pips
        tp = price + tp_pips if signal == "long" else price - tp_pips

        result = place_order(signal, SYMBOL, lot_size, sl, tp)
        print(f"✅ Placed {signal.upper()} trade: {result}")
    else:
        print("No valid setup.")

if __name__ == "__main__":
    run_bot()
