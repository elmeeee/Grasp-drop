#!/bin/bash
# Package the Grasp Windows .exe (Electron shell + Rust sidecar).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Ensuring the Rust Windows binary is staged…"
"$ROOT/scripts/build_core.sh"

echo "==> Packaging with electron-builder…"
(cd "$ROOT/app/electron" && npm install && npx electron-builder --win)
echo "==> Windows installer written under app/electron/dist/"
