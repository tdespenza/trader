import subprocess
import sys
from pathlib import Path
from typing import List

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost", "tauri://localhost"],
    allow_methods=["*"],
    allow_headers=["*"],
)

BOT_PROCESS: subprocess.Popen | None = None
ROOT_DIR = Path(__file__).resolve().parents[1]
BOT_PATH = ROOT_DIR / "prop_firm_bot.py"
LOG_FILE = Path(__file__).parent / "logs" / "trading.log"
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)


def _is_running() -> bool:
    return BOT_PROCESS is not None and BOT_PROCESS.poll() is None


@app.post("/start")
async def start_bot() -> JSONResponse:
    """Launch the trading bot."""
    global BOT_PROCESS
    if _is_running():
        return JSONResponse({"running": True})
    with LOG_FILE.open("a") as f:
        BOT_PROCESS = subprocess.Popen(
            [sys.executable, str(BOT_PATH)],
            stdout=f,
            stderr=subprocess.STDOUT,
            cwd=str(ROOT_DIR),
        )
    return JSONResponse({"running": True})


@app.post("/stop")
async def stop_bot() -> JSONResponse:
    """Stop the trading bot if running."""
    global BOT_PROCESS
    if _is_running():
        BOT_PROCESS.terminate()
        BOT_PROCESS.wait(timeout=5)
    BOT_PROCESS = None
    return JSONResponse({"running": False})


@app.get("/status")
async def status() -> JSONResponse:
    return JSONResponse({"running": _is_running()})


@app.get("/logs")
async def get_logs() -> JSONResponse:
    if LOG_FILE.exists():
        lines: List[str] = LOG_FILE.read_text().splitlines()[-200:]
    else:
        lines = []
    return JSONResponse({"logs": lines})


@app.get("/chart-data")
async def chart_data() -> JSONResponse:
    """Return placeholder chart data."""
    # Real implementation would stream prices from exchange
    if LOG_FILE.exists():
        timestamps = list(range(0, 10))
        prices = [i * 100 for i in range(10)]
    else:
        timestamps = []
        prices = []
    return JSONResponse({"timestamps": timestamps, "prices": prices})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
