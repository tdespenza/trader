$ErrorActionPreference = 'Stop'

# Build frontend
Push-Location frontend
npm install
npm run build
Pop-Location

# Start backend & tauri build
Push-Location src-tauri
tauri build
Pop-Location
