# === Imports ===
import json
import yaml
import logging
from dataclasses import dataclass, field
from typing import Any, Dict, List
from pathlib import Path
from datetime import datetime
import os

import pandas as pd
import requests

try:
    import MetaTrader5 as mt5
except ImportError:  # pragma: no cover - optional dependency
    mt5 = None

from transformers import pipeline

# === Config & Prop Firm Rule Loader ===
@dataclass
class PropFirmRules:
    account_size: float
    leverage: int
    daily_loss: float
    total_drawdown: float
    profit_target: float


def load_rules(path: str) -> PropFirmRules:
    """Load prop firm rules from a YAML or JSON file."""
    with open(path, "r", encoding="utf-8") as f:
        if path.endswith((".yaml", ".yml")):
            data = yaml.safe_load(f)
        else:
            data = json.load(f)
    return PropFirmRules(**data)


def load_ftmo_rules() -> PropFirmRules:
    return PropFirmRules(account_size=100000, leverage=100, daily_loss=5000,
                         total_drawdown=10000, profit_target=10000)


def load_tft_rules() -> PropFirmRules:
    return PropFirmRules(account_size=100000, leverage=100, daily_loss=5000,
                         total_drawdown=10000, profit_target=10000)


def load_mff_rules() -> PropFirmRules:
    return PropFirmRules(account_size=100000, leverage=100, daily_loss=5000,
                         total_drawdown=10000, profit_target=10000)


# === MT5 Setup & Price Feed ===

def init_mt5(login: int, password: str, server: str, path: str) -> bool:
    if mt5 is None:
        logging.warning("MetaTrader5 package not installed")
        return False
    if not mt5.initialize(path=path, login=login, password=password, server=server):
        logging.error("MT5 initialization failed")
        return False
    return True


def shutdown_mt5() -> None:
    if mt5:
        mt5.shutdown()


def get_prices(symbol: str, timeframe: int = 60, bars: int = 100) -> pd.DataFrame:
    if mt5 is None:
        raise RuntimeError("MT5 not available")
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)
    return pd.DataFrame(rates)


# === Hugging Face Sentiment + News Models ===
class NLPModels:
    def __init__(self) -> None:
        self.sentiment = pipeline(
            "sentiment-analysis",
            model="cardiffnlp/twitter-roberta-base-sentiment",
        )
        self.news = pipeline(
            "text-classification",
            model="facebook/bart-large-mnli",
        )

    def market_sentiment(self, text: str) -> float:
        result = self.sentiment(text)[0]
        label = result["label"].lower()
        score = result["score"]
        if label == "positive":
            return score
        if label == "negative":
            return -score
        return 0.0

    def classify_news(self, text: str, labels: List[str]) -> Dict[str, Any]:
        return self.news(text, candidate_labels=labels)


# === Signal Generator ===
class SignalEngine:
    def __init__(self, ema_period: int = 20) -> None:
        self.ema_period = ema_period

    def generate(self, prices: pd.DataFrame, sentiment: float) -> str | None:
        prices = prices.copy()
        prices["EMA"] = prices["close"].ewm(span=self.ema_period, adjust=False).mean()
        latest = prices.iloc[-1]
        signal = None
        if sentiment > 0 and latest["close"] > latest["EMA"]:
            signal = "buy"
        elif sentiment < 0 and latest["close"] < latest["EMA"]:
            signal = "sell"
        return signal


# === Risk & Compliance Engine ===
@dataclass
class RiskManager:
    rules: PropFirmRules
    equity: float
    daily_pl: float = 0.0
    trading_enabled: bool = True

    def update_equity(self, new_equity: float) -> None:
        self.daily_pl += new_equity - self.equity
        self.equity = new_equity
        if self.equity <= self.rules.account_size - self.rules.total_drawdown:
            logging.warning("Max drawdown hit. Trading disabled.")
            self.trading_enabled = False
        if self.daily_pl <= -self.rules.daily_loss:
            logging.warning("Daily loss limit hit. Trading disabled.")
            self.trading_enabled = False

    def position_size(self, stop_points: float, risk_per_trade: float = 0.01) -> float:
        risk_amount = self.equity * risk_per_trade
        lot = max(risk_amount / stop_points, 0)
        return lot


# === Trade Executor (MT5) ===
class Executor:
    def __init__(self, slippage: int = 5) -> None:
        self.slippage = slippage

    def place_order(
        self, symbol: str, lot: float, order_type: str, sl: float | None = None, tp: float | None = None
    ) -> bool:
        if mt5 is None:
            logging.info("Mock order: %s %s", order_type, symbol)
            return True
        if order_type == "buy":
            order_type_mt5 = mt5.ORDER_TYPE_BUY
        else:
            order_type_mt5 = mt5.ORDER_TYPE_SELL
        price = mt5.symbol_info_tick(symbol).ask if order_type_mt5 == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(symbol).bid
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": lot,
            "type": order_type_mt5,
            "price": price,
            "sl": sl,
            "tp": tp,
            "deviation": self.slippage,
            "magic": 234000,
            "comment": "prop firm bot",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_FOK,
        }
        result = mt5.order_send(request)
        logging.info("Order send result: %s", result)
        return result.retcode == mt5.TRADE_RETCODE_DONE


# === Telegram Alert Bot ===
class AlertBot:
    def __init__(self, token: str, chat_id: str) -> None:
        self.token = token
        self.chat_id = chat_id

    def send(self, message: str) -> None:
        if not self.token or not self.chat_id:
            return
        url = f"https://api.telegram.org/bot{self.token}/sendMessage"
        try:
            requests.post(url, data={"chat_id": self.chat_id, "text": message}, timeout=5)
        except Exception as exc:  # pragma: no cover - network errors
            logging.error("Telegram send failed: %s", exc)


# === Logger (CSV + JSON) ===
class TradeLogger:
    def __init__(self, csv_path: str, json_path: str) -> None:
        self.csv_path = Path(csv_path)
        self.json_path = Path(json_path)
        if not self.csv_path.exists():
            self.csv_path.write_text("timestamp,action,symbol,lot,reason\n")
        if not self.json_path.exists():
            self.json_path.write_text("[]")

    def log(self, record: Dict[str, Any]) -> None:
        line = f"{record['timestamp']},{record['action']},{record['symbol']},{record['lot']},{record['reason']}\n"
        with self.csv_path.open("a") as f:
            f.write(line)
        data = json.loads(self.json_path.read_text())
        data.append(record)
        self.json_path.write_text(json.dumps(data, indent=2))


# === Main Trading Loop ===
def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    rules_path = os.environ.get("RULES_FILE", "rules.yaml")
    if os.path.exists(rules_path):
        rules = load_rules(rules_path)
    else:
        rules = load_ftmo_rules()
    nlp = NLPModels()
    signal_engine = SignalEngine()
    risk = RiskManager(rules=rules, equity=rules.account_size)
    executor = Executor()
    logger_obj = TradeLogger("trades.csv", "trades.json")
    alert = AlertBot(os.environ.get("TG_TOKEN", ""), os.environ.get("TG_CHAT", ""))

    login = int(os.environ.get("MT5_LOGIN", "0"))
    password = os.environ.get("MT5_PASSWORD", "")
    server = os.environ.get("MT5_SERVER", "")
    terminal_path = os.environ.get("MT5_PATH", "")
    if not init_mt5(login, password, server, terminal_path):
        logging.error("Unable to initialize MT5. Exiting.")
        return

    symbol = os.environ.get("SYMBOL", "BTCUSD")
    try:
        while risk.trading_enabled:
            try:
                prices = get_prices(symbol)
            except Exception as exc:
                logging.error("Price fetch failed: %s", exc)
                break

            sentiment = nlp.market_sentiment("Bitcoin is great today!")
            signal = signal_engine.generate(prices, sentiment)
            if signal:
                lot = risk.position_size(stop_points=100)  # placeholder stop distance
                executed = executor.place_order(symbol, lot, signal)
                timestamp = datetime.utcnow().isoformat()
                reason = f"sentiment={sentiment:.2f}"
                logger_obj.log({
                    "timestamp": timestamp,
                    "action": signal,
                    "symbol": symbol,
                    "lot": lot,
                    "reason": reason,
                })
                if executed:
                    alert.send(f"Executed {signal} {lot} {symbol} due to {reason}")
            else:
                logging.info("No signal")
            break  # Remove or modify for continuous trading
    finally:
        shutdown_mt5()


if __name__ == "__main__":
    main()
