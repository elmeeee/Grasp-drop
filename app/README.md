# Otter Apps

Otter ships as native applications on every platform, all built on the shared
**Rust core** (`core/otter-core`).

## Architecture

```
        ┌─────────────────────────────────────────────┐
        │              core/otter-core (Rust)          │
        │  protocol · TLS identity · HTTPS server       │
        │  multicast discovery · file sender · web hub  │
        │  C FFI (cbindgen) · Android JNI               │
        └───────────────┬───────────────┬──────────────┘
                        │               │
        ┌───────────────▼───┐   ┌───────▼──────────────┐
        │   macOS (Swift)   │   │   Android (Capacitor) │
        │  native menu bar  │   │  JNI → libotter_core   │
        └───────────────────┘   └───────────────────────┘
                        │               │
        ┌───────────────▼───────────────▼──────────────┐
        │        Windows (Electron + Capacitor UI)      │
        │   renderer ⇄ preload bridge ⇄ otter.exe       │
        └───────────────────────────────────────────────┘
```

## Layout

```
app/
├── www/                     # Shared web UI used by the Android and Windows shells
├── capacitor.config.json    # Capacitor config (appId org.otter.app)
├── android/                 # Capacitor Android project (.apk)
│   └── app/src/main/
│       ├── java/org/otter/app/
│       │   ├── MainActivity.java
│       │   ├── OtterNativePlugin.java         # JS ⇄ Rust bridge (JNI)
│       │   └── OtterForegroundService.java    # keeps node alive + multicast lock
│       └── jniLibs/                           # libotter_core.so (per ABI)
└── electron/                # Electron Windows shell (.exe)
    ├── lib/index.js         # main process
    ├── lib/core.js          # spawns the Rust sidecar
    ├── lib/preload.js       # OtterNative bridge for the renderer
    └── resources/bin/       # otter.exe sidecar
```

## Building

```bash
./scripts/build_core.sh      # Rust core for every platform
./scripts/build_android.sh   # → bin/otter-android-debug.apk
./scripts/build_windows.sh   # → app/electron/dist/Otter-<version>-x64.exe
```

| Output | Target |
|---|---|
| `bin/otter` | macOS (host) |
| `bin/otter-windows-x64.exe` | Windows x64 |
| `bin/otter-linux-x64` | Linux x64 |
| `app/electron/resources/bin/otter.exe` | Windows sidecar |
| `app/android/app/src/main/jniLibs/*/libotter_core.so` | Android ABIs |

Prerequisites: Rust targets `x86_64-pc-windows-gnu`, `x86_64-unknown-linux-gnu`,
`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`;
`cargo-ndk` with the Android NDK; `mingw-w64`; `cargo-zigbuild` with `zig`.

## Permissions (Android)

- `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE`: required for UDP multicast discovery
- `NEARBY_WIFI_DEVICES`: Android 13+ Wi-Fi device access
- `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_DATA_SYNC`: keep the node running
- Media read permissions: to pick files to send
