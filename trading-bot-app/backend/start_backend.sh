#!/bin/sh
cd "$(dirname "$0")"
exec uvicorn main:app --host 127.0.0.1 --port 8000
