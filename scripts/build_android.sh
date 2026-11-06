#!/bin/bash
# Build the Otter Android APK. The Rust core must be built first with
# scripts/build_core.sh so that jniLibs contains libotter_core.so.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null)}"
export JAVA_HOME

echo "==> Syncing Capacitor web assets…"
(cd "$ROOT/app" && npx cap sync android)

echo "==> Building debug APK…"
(cd "$ROOT/app/android" && ./gradlew assembleDebug)

APK="$ROOT/app/android/app/build/outputs/apk/debug/app-debug.apk"
cp "$APK" "$ROOT/bin/otter-android-debug.apk"
echo "==> APK ready: $ROOT/bin/otter-android-debug.apk"
