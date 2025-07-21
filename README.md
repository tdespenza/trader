# Crypto AI Trading Bot

This repository contains an experimental crypto trading bot that integrates sentiment analysis,
reinforcement learning and MetaTrader 5. The main entry point is the `prop_firm_bot.py` script.

## Installation

1. Create and activate a Python 3.8+ virtual environment.
2. Install the required packages:
   ```bash
   pip install pandas requests transformers MetaTrader5 stable-baselines3 gym
   ```
   The MetaTrader5 package requires a local MetaTrader 5 terminal installation.

## Configuration

The bot uses environment variables for configuration:

- `RULE_SET` &ndash; `ftmo` (default), `tft`, or `mff`.
- `SYMBOL` &ndash; trading instrument symbol, e.g. `BTCUSD`.
- `MT5_LOGIN`, `MT5_PASSWORD`, `MT5_SERVER`, `MT5_PATH` &ndash; MetaTrader 5 credentials and path.
- `TG_TOKEN`, `TG_CHAT` &ndash; Telegram bot token and chat ID for alerts (optional).

Example on Linux/macOS:
```bash
export MT5_LOGIN=1234567
export MT5_PASSWORD="your_password"
export MT5_SERVER="Broker-Server"
export MT5_PATH="/path/to/terminal64.exe"
export RULE_SET=ftmo
```

## Running the Crypto-AI Bot

Run the trading bot with:
```bash
python prop_firm_bot.py
```
The script will initialise MetaTrader 5, fetch market data and execute trades if signals are generated.
