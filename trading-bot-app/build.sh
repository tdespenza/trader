#!/bin/sh
# Build frontend
cd frontend && npm install && npm run build && cd ..
# Start backend & tauri build
cd src-tauri && tauri build && cd ..
