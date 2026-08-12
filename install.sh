#!/bin/sh
# Grasp — Linux & macOS 1-Line Terminal Installer
# Usage in Terminal:
#   curl -fsSL https://raw.githubusercontent.com/username/Grasp/main/install.sh | sh

set -e

VERSION="1.0.0"
INSTALL_DIR="$HOME/.local/bin"
TARGET="$INSTALL_DIR/grasp"

echo "=================================================="
echo "   🚀 Installing Grasp Standalone Server..."
echo "=================================================="

mkdir -p "$INSTALL_DIR"

OS="$(uname -s)"
case "$OS" in
  Linux*)
    URL="https://github.com/elmeeee/Grasp-drop/releases/download/v$VERSION/grasp-linux-x64"
    ;;
  Darwin*)
    URL="https://github.com/elmeeee/Grasp-drop/releases/download/v$VERSION/grasp-server"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    URL="https://github.com/elmeeee/Grasp-drop/releases/download/v$VERSION/grasp-windows-x64.exe"
    TARGET="$INSTALL_DIR/grasp.exe"
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
echo "✓ Grasp installed successfully at $TARGET!"
echo "  Run 'grasp' in terminal to start the server."
echo "=================================================="
