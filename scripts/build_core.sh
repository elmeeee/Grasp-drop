#!/bin/bash
# Build the Grasp Rust core for every target platform and stage the artifacts
# where the desktop and mobile apps expect them.
#
# Requires: rustup (with the targets below), cargo-ndk + Android NDK for Android,
# mingw-w64 for the Windows GNU target, and cargo-zigbuild + zig for Linux.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core/grasp-core"
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"

echo "==> Building Grasp core (host)…"
cargo build --manifest-path "$CORE/Cargo.toml" --release
mkdir -p "$ROOT/bin"
cp "$CORE/target/release/grasp" "$ROOT/bin/grasp"

echo "==> Cross-compiling Windows core…"
if rustup target list --installed | grep -q x86_64-pc-windows-gnu; then
  cargo build --manifest-path "$CORE/Cargo.toml" --release --target x86_64-pc-windows-gnu
  mkdir -p "$ROOT/app/electron/resources/bin"
  cp "$CORE/target/x86_64-pc-windows-gnu/release/grasp.exe" "$ROOT/bin/grasp-windows-x64.exe"
  cp "$CORE/target/x86_64-pc-windows-gnu/release/grasp.exe" "$ROOT/app/electron/resources/bin/grasp.exe"
else
  echo "   (skipped: run 'rustup target add x86_64-pc-windows-gnu' and install mingw-w64)"
fi

echo "==> Cross-compiling Linux core…"
if rustup target list --installed | grep -q x86_64-unknown-linux-gnu; then
  cargo zigbuild --manifest-path "$CORE/Cargo.toml" --release --target x86_64-unknown-linux-gnu
  cp "$CORE/target/x86_64-unknown-linux-gnu/release/grasp" "$ROOT/bin/grasp-linux-x64"
else
  echo "   (skipped: run 'rustup target add x86_64-unknown-linux-gnu' and install cargo-zigbuild + zig)"
fi

echo "==> Building Android core (arm64-v8a, armeabi-v7a, x86_64)…"
if command -v cargo-ndk >/dev/null 2>&1; then
  NDK_DIR="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* 2>/dev/null | head -1)}"
  if [ -n "$NDK_DIR" ]; then
    export ANDROID_NDK_HOME="$NDK_DIR"
    cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
      -o "$ROOT/app/android/app/src/main/jniLibs" \
      build --manifest-path "$CORE/Cargo.toml" --release
  else
    echo "   (skipped: Android NDK not found; set ANDROID_NDK_HOME)"
  fi
else
  echo "   (skipped: install with 'cargo install cargo-ndk')"
fi

echo "==> Core build complete."
