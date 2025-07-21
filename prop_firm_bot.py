# === Imports ===
import json
import yaml
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

import pandas as pd
import requests

try:
    import MetaTrader5 as mt5
except ImportError:  # pragma: no cover - optional dependency
    mt5 = None

from transformers import pipeline
from transformers import AutoModelForSequenceClassification, AutoTokenizer
from transformers import TextClassificationPipeline

try:
    from stable_baselines3 import PPO
    import gym
except ImportError:  # pragma: no cover
    PPO = None  # type: ignore
    gym = None  # type: ignore

try:
    from peft import PeftModel
except ImportError:  # pragma: no cover
    PeftModel = None

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


def get_prices(symbol: str, timeframe: int = mt5.TIMEFRAME_H1 if mt5 else 60,
               bars: int = 100) -> pd.DataFrame:
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


# === Custom LLM Reasoning Module ===

class LLMModule:
    """A lightweight reasoning module using a distilled transformer."""

    def __init__(self) -> None:
        model_name = "distilbert-base-uncased"
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.model = AutoModelForSequenceClassification.from_pretrained(model_name)
        self.pipeline = TextClassificationPipeline(model=self.model, tokenizer=self.tokenizer)

    def reason(self, prompt: str) -> str:
        out = self.pipeline(prompt, return_all_scores=False)
        label = out[0]["label"]
        score = out[0]["score"]
        return f"{label} ({score:.2f})"


# === Signal Generator ===

class SignalEngine:
    def __init__(self, ema_period: int = 20) -> None:
        self.ema_period = ema_period

    def generate(self, prices: pd.DataFrame, sentiment: float) -> Optional[str]:
        prices = prices.copy()
        prices["EMA"] = prices["close"].ewm(span=self.ema_period, adjust=False).mean()
        latest = prices.iloc[-1]
        signal: Optional[str] = None
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
        self, symbol: str, lot: float, order_type: str, sl: Optional[float] = None, tp: Optional[float] = None
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


# === Backtesting Engine ===

def backtest(prices: pd.DataFrame, sentiment_series: pd.Series, engine: SignalEngine) -> pd.DataFrame:
    records = []
    for ts, sentiment in sentiment_series.items():
        historical = prices.loc[:ts]
        if len(historical) < engine.ema_period:
            continue
        signal = engine.generate(historical, sentiment)
        if signal:
            records.append({"timestamp": ts, "signal": signal, "sentiment": sentiment})
    return pd.DataFrame(records)


# === Reinforcement Learning Environment & Agent ===

class PropFirmEnv(gym.Env if gym else object):
    """Gym environment modeling prop firm rules."""

    def __init__(self, rules: PropFirmRules, price_series: pd.DataFrame) -> None:
        super().__init__()
        self.rules = rules
        self.price_series = price_series
        self.current_step = 0
        self.equity = rules.account_size
        self.action_space = gym.spaces.Discrete(3) if gym else None  # buy, sell, hold
        self.observation_space = gym.spaces.Box(low=-1, high=1, shape=(2,)) if gym else None

    def reset(self) -> Any:
        self.current_step = 0
        self.equity = self.rules.account_size
        return self._get_obs()

    def _get_obs(self):
        price = self.price_series.iloc[self.current_step]["close"]
        return [price, self.equity]

    def step(self, action: int):
        done = False
        reward = 0.0
        price = self.price_series.iloc[self.current_step]["close"]
        self.current_step += 1
        if action == 1:  # buy
            reward = 1.0
        elif action == 2:  # sell
            reward = -1.0
        if self.current_step >= len(self.price_series):
            done = True
        return self._get_obs(), reward, done, {}


class RLAgent:
    def __init__(self, env: PropFirmEnv) -> None:
        if PPO is None:
            self.model = None
        else:
            self.model = PPO("MlpPolicy", env, verbose=0)

    def train(self, timesteps: int = 1000) -> None:
        if self.model:
            self.model.learn(total_timesteps=timesteps)

    def act(self, obs: Any) -> int:
        if self.model:
            action, _ = self.model.predict(obs)
            return int(action)
        return 0


# === Continual Learning & Feedback Integration ===

def continual_learning_loop(data_path: str, model_name: str = "distilbert-base-uncased") -> None:
    if not Path(data_path).exists():
        return
    data = pd.read_csv(data_path)
    texts = data["text"].tolist()
    labels = data["label"].tolist()
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForSequenceClassification.from_pretrained(model_name)
    # Placeholder: fine-tuning code would go here
    logging.info("Continual learning loop executed on %d samples", len(texts))


# === Main Trading Loop ===

def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    # Rule set selection
    rule_set = os.environ.get("RULE_SET", "ftmo").lower()
    if rule_set == "tft":
        rules = load_tft_rules()
    elif rule_set == "mff":
        rules = load_mff_rules()
    else:
        rules = load_ftmo_rules()

    # NLP and LLM models
    nlp = NLPModels()
    llm = LLMModule()

    # Engine and management classes
    signal_engine = SignalEngine()
    risk = RiskManager(rules=rules, equity=rules.account_size)
    executor = Executor()
    logger_obj = TradeLogger("trades.csv", "trades.json")
    alert = AlertBot(os.environ.get("TG_TOKEN", ""), os.environ.get("TG_CHAT", ""))

    # MT5 credentials
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
            reasoning = llm.reason(
                f"Current sentiment is {'POSITIVE' if sentiment > 0 else 'NEGATIVE'}, "
                f"{symbol} has EMA crossover, rule set is {rule_set.upper()}, equity is ${risk.equity:.2f}. Should I open a position?"
            )
            logging.info("LLM reasoning: %s", reasoning)
            if signal:
                lot = risk.position_size(stop_points=100)
                executed = executor.place_order(symbol, lot, signal)
                timestamp = datetime.utcnow().isoformat()
                reason = f"sentiment={sentiment:.2f}; llm={reasoning}"
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
