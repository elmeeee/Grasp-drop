# Grasp Apps

Grasp ships as native applications on every platform, all built on the shared
**Rust core** (`core/grasp-core`), which implements the LocalSend v2 protocol so
Grasp devices and the official LocalSend app interoperate.

## Architecture

```
        ┌─────────────────────────────────────────────┐
        │              core/grasp-core (Rust)          │
        │  protocol · TLS identity · HTTPS server       │
        │  multicast discovery · file sender · FFI/JNI  │
        └───────────────┬───────────────┬──────────────┘
                        │               │
        ┌───────────────▼───┐   ┌───────▼──────────────┐
        │   macOS (Swift)   │   │   Android (Capacitor) │
        │  native menu bar  │   │  JNI → libgrasp_core   │
        └───────────────────┘   └───────────────────────┘
                        │               │
        ┌───────────────▼───────────────▼──────────────┐
        │        Windows (Electron + Capacitor UI)      │
        │   renderer ⇄ preload bridge ⇄ grasp.exe       │
        └───────────────────────────────────────────────┘
```

## Layout

```
app/
├── www/                     # Shared Web UI (HTML/CSS/JS) used by all shells
├── capacitor.config.json    # Capacitor configuration
├── android/                 # Capacitor Android project (.apk)
│   └── app/src/main/
│       ├── java/org/grasp/app/
│       │   ├── MainActivity.java
│       │   ├── GraspNativePlugin.java        # JS ⇄ Rust bridge (JNI)
│       │   └── GraspForegroundService.java   # keeps node alive + multicast lock
│       └── jniLibs/                          # libgrasp_core.so (per ABI)
└── electron/                # Capacitor/Electron Windows shell (.exe)
    ├── lib/index.js         # main process
    ├── lib/core.js          # spawns the Rust sidecar
    ├── lib/preload.js       # GraspNative bridge for the renderer
    └── resources/bin/       # grasp.exe sidecar
```

## Building

### 1. Build the Rust core for every platform

```bash
./scripts/build_core.sh
```

This cross-compiles the core and stages binaries:

| Output | Target |
|---|---|
| `bin/grasp` | host (macOS) |
| `bin/grasp-windows-x64.exe` | Windows x64 |
| `bin/grasp-linux-x64` | Linux x64 |
| `app/electron/resources/bin/grasp.exe` | Windows sidecar |
| `app/android/app/src/main/jniLibs/*/libgrasp_core.so` | Android ABIs |

Prerequisites: `rustup` targets `x86_64-pc-windows-gnu`, `x86_64-unknown-linux-gnu`,
`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`;
`cargo-ndk` + Android NDK; `mingw-w64`; `cargo-zigbuild` + `zig`.

### 2. Android APK

```bash
./scripts/build_android.sh
# → bin/grasp-android-debug.apk
```

Requires JDK 17 (`JAVA_HOME` pointing at it) and the Android SDK.

### 3. Windows .exe

```bash
./scripts/build_windows.sh
# → app/electron/dist/Grasp-<version>-x64.exe
```

`electron-builder` produces the NSIS installer and a portable executable. On
Windows this runs directly; from macOS it needs Wine or a Windows CI runner.

## Permissions

The Android app requests:

- `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE` — required for UDP multicast discovery
- `NEARBY_WIFI_DEVICES` — Android 13+ Wi-Fi device access
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` — keep the node running
- media read permissions — for selecting files to send
