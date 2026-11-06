#!/bin/sh
# Otter — Linux & macOS 1-Line Terminal Installer
# Usage in Terminal:
#   curl -fsSL https://raw.githubusercontent.com/username/Otter/main/install.sh | sh

set -e

VERSION="1.0.0"
INSTALL_DIR="$HOME/.local/bin"
TARGET="$INSTALL_DIR/otter"

echo "=================================================="
echo "   🚀 Installing Otter Standalone Server..."
echo "=================================================="

mkdir -p "$INSTALL_DIR"

OS="$(uname -s)"
case "$OS" in
  Linux*)
    URL="https://github.com/elmeeee/Grasp-drop/releases/download/v$VERSION/otter-linux-x64"
    ;;
  Darwin*)
    URL="https://github.com/elmeeee/Grasp-drop/releases/download/v$VERSION/otter-macos"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    URL="https://github.com/elmeeee/Grasp-drop/releases/download/v$VERSION/otter-windows-x64.exe"
    TARGET="$INSTALL_DIR/otter.exe"
    ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

echo "Downloading binary from GitHub..."
curl -fsSL "$URL" -o "$TARGET"
chmod +x "$TARGET"

echo "--------------------------------------------------"
echo "✓ Otter installed successfully at $TARGET!"
echo "  Run 'otter' in terminal to start the server."
echo "=================================================="
