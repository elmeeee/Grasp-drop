#!/usr/bin/env bash
# Grasp CLI — Cross-Platform File Transfer Utility for Linux & macOS
# Usage:
#   ./grasp-cli.sh send <file_path> [host:port]
#   ./grasp-cli.sh list [host:port]
# Example:
#   ./grasp-cli.sh send photo.jpg 192.168.1.15:7456

COMMAND=$1
TARGET=$2
HOST=$3

if [ -z "$COMMAND" ]; then
  echo "Usage:"
  echo "  ./grasp-cli.sh send <file> [host:7456]"
  echo "  ./grasp-cli.sh list [host:7456]"
  exit 1
fi

if [ "$COMMAND" = "send" ]; then
  FILE_PATH=$2
  SERVER=$3
  if [ -z "$SERVER" ]; then
    SERVER="127.0.0.1:7456"
  fi
  if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File '$FILE_PATH' not found!"
    exit 1
  fi
  echo "Uploading '$FILE_PATH' to Grasp Hub ($SERVER)..."
  curl -F "file=@$FILE_PATH" "http://$SERVER/upload"
  echo ""
elif [ "$COMMAND" = "list" ]; then
  SERVER=$2
  if [ -z "$SERVER" ]; then
    SERVER="127.0.0.1:7456"
  fi
  echo "Fetching files from Grasp Hub ($SERVER)..."
  curl -s "http://$SERVER/api/files"
  echo ""
else
  echo "Unknown command: $COMMAND"
  exit 1
fi
