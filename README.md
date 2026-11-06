<p align="center">
  <img src="Resources/BarIcon@2x.png" width="80" height="80" alt="Grasp Logo">
</p>

<h1 align="center">Grasp</h1>

<p align="center">
  <b>Lightning-Fast, Seamless Cross-Platform File Sharing for macOS, Android, iOS, Windows & Linux.</b>
</p>

<p align="center">
  <a href="#-quick-installation"><img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-indigo?style=for-the-badge" alt="Platforms"></a>
  <a href="#-license"><img src="https://img.shields.io/badge/License-MIT-06B6D4?style=for-the-badge" alt="License"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift" alt="Swift"></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/Rust-1.75-000000?style=for-the-badge&logo=rust" alt="Rust"></a>
  <a href="https://capacitorjs.com"><img src="https://img.shields.io/badge/Capacitor-6-53B9EA?style=for-the-badge&logo=capacitor" alt="Capacitor"></a>
</p>

---

## Overview

**Grasp** is an open-source, lightweight file-sharing solution that connects your **MacBook**, **Android**, **iPhone**, **Windows PC**, and **Linux** machines on your local Wi-Fi network without requiring third-party cloud services or internet access.

It is built on a shared **Rust core** that speaks the **LocalSend Protocol v2.2**, so Grasp devices interoperate with the official LocalSend app on every platform. Native applications ship for **macOS** (Swift menu bar app), **Windows** (Electron shell), and **Android** (Capacitor app), plus standalone CLI binaries for **Windows** and **Linux**. A built-in **Instant Cross-Platform Web Hub** covers iPhone, iPad, and any browser.

---

## Key Features

- **Shared Rust Core**: One transfer engine (`core/grasp-core`) powers macOS, Windows, Android, and Linux. Wire-compatible with the [LocalSend Protocol v2.2](https://github.com/localsend/protocol).
- **Native Apps on Every Platform**: macOS menu bar app (Swift), Windows desktop app (Electron + Capacitor UI), Android app (Capacitor + JNI), plus standalone CLI binaries.
- **LocalSend Interoperable**: Discover, send, and receive files with the official LocalSend app and any LocalSend-compatible device over HTTPS on port `53317`.
- **Zero Setup on Android**: Also uses Android’s built-in **Quick Share (Nearby Share)** protocol over Bluetooth LE and local Wi-Fi.
- **Instant Cross-Platform Web Hub**: Share files to and from **iPhone, iPad, Windows, and Linux** using a modern, responsive Web Portal with QR Code scanning.
- **Privacy-First & 100% Local**: Files travel directly across your local Wi-Fi network with end-to-end encryption support. Zero cloud dependency.
- **Terminal & CLI Ready**: Includes 1-line terminal installers and simple `curl` / `PowerShell` commands for power users.

---

## Quick Installation

### macOS (Homebrew Terminal Install)

Install Grasp as a native macOS application via Homebrew Cask:

```bash
brew tap elmeeee/grasp-drop https://github.com/elmeeee/Grasp-drop.git
brew trust elmeeee/grasp-drop
brew install --cask grasp
```

Or download `Grasp.app` from the [Releases](https://github.com/elmeeee/Grasp-drop/releases) page.

---

### Windows (1-Line PowerShell Terminal Install)

Run this single command in **Windows PowerShell** to install Grasp:

```powershell
iwr -useb https://raw.githubusercontent.com/elmeeee/Grasp-drop/main/install.ps1 | iex
```

*This downloads `grasp-windows-x64.exe` as `grasp.exe`, adds it to your User PATH, and allows you to type `grasp` in any terminal.*

> **Note on Winget**: Direct `winget install Grasp` requires submitting a manifest PR to `microsoft/winget-pkgs`. Until submitted, please use the 1-line PowerShell installer above or download `grasp-windows-x64.exe` directly from [Releases](https://github.com/elmeeee/Grasp-drop/releases).


---

### Linux (1-Line Bash Terminal Install)

Run this single command in your Linux Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/elmeeee/Grasp-drop/main/install.sh | sh
```

*This installs the `grasp` standalone binary to `~/.local/bin/grasp`.*

---

## How to Use

### Android to Mac (Quick Share)
1. Ensure **Bluetooth** and **Wi-Fi** are enabled on both your Mac and Android phone.
2. Open **Grasp** on your Mac.
3. On your Android phone, pick any photo/video/document and tap **Share ➔ Quick Share**.
4. Select your MacBook (e.g., `MacBook Pro`).
5. Confirm the Security PIN if prompted. The file will automatically save to `~/Downloads/Grasp`!

### iPhone / iPad to Mac (Instant Web QR)
1. Click **Instant Web QR** in the Grasp macOS Menu Bar popup.
2. Scan the QR Code with your iPhone camera or open `http://<Mac-IP>:7456` in Safari.
3. Select files on your iPhone to send them straight to your Mac!

### Windows / Linux to Mac (Browser & Terminal)
- **Web Browser**: Open `http://<Mac-IP>:7456` in Chrome, Edge, or Firefox to upload or download files.
- **Linux Terminal (`curl`)**:
  ```bash
  curl -F "file=@photo.jpg" http://<Mac-IP>:7456/upload
  ```
- **Windows PowerShell**:
  ```powershell
  Invoke-RestMethod -Uri "http://<Mac-IP>:7456/upload" -Method Post -InFile "photo.jpg"
  ```

### Android / iPhone to PC Windows (Standalone Windows Server)
1. Run `grasp-windows-x64.exe` on your Windows PC.
2. Open the displayed Web URL on your phone browser.
3. Uploaded files will land directly in `C:\Users\<User>\Downloads\Grasp`.

### LocalSend-Compatible Transfers (All Platforms)

Grasp speaks the **LocalSend Protocol v2.2**, so it interoperates directly with the
official [LocalSend](https://localsend.org) app on Android, iOS, Windows, and Linux.

- **Discovery**: Multicast UDP on `224.0.0.167:53317`, with an HTTP subnet scan fallback.
- **Transport**: HTTPS on port `53317` using a self-signed certificate; the fingerprint
  is the SHA-256 hash of the DER certificate and is persisted across restarts.
- **Endpoints**: `/api/localsend/v2/info`, `/register`, `/prepare-upload`, `/upload`,
  `/cancel`, `/prepare-download`, `/download`.
- **Integrity**: Every transfer carries a SHA-256 hash that the receiver verifies
  (mismatches return `422`).

From a terminal, send files directly to a peer IP:

```bash
# Linux / macOS
grasp --send 192.168.1.42 photo.jpg video.mp4

# Windows
grasp.exe --send 192.168.1.42 photo.jpg
```

On macOS, nearby LocalSend-compatible devices appear automatically in the menu bar
popover under **NEARBY DEVICES**; click a device to send files to it.

> Firewall note: allow TCP and UDP on port `53317`, and disable AP isolation on your router.

---

## Building from Source

### Prerequisites
- macOS 13.0+ (for the native macOS app)
- Xcode 15+ / Swift 5.9+
- Rust 1.75+ with `cargo` (shared core)
- Node.js 18+ (Capacitor apps)

### Build the Shared Rust Core
```bash
./scripts/build_core.sh
```
Cross-compiles the core for macOS, Windows, Linux, and every Android ABI.

### Build Native macOS App
```bash
# Clone the repository
git clone https://github.com/elmeeee/Grasp-drop.git
cd Grasp-drop

# Build Grasp.app bundle
./build_mac_app.sh

# Run Grasp.app
open bin/Grasp.app
```

### Build the Android App (.apk)
```bash
./scripts/build_android.sh
# → bin/grasp-android-debug.apk
```

### Build the Windows App (.exe)
```bash
./scripts/build_windows.sh
# → app/electron/dist/Grasp-<version>-x64.exe
```

### Cross-Compile Standalone Windows & Linux CLI
```bash
./scripts/build_core.sh
# → bin/grasp-windows-x64.exe, bin/grasp-linux-x64, bin/grasp
```

The Rust CLI also serves the browser Web Hub (port `7456`) so any phone or PC on
the network can exchange files through a browser:

```bash
grasp                 # LocalSend node + Web Hub
grasp --no-web        # LocalSend node only
grasp --send <ip> file # one-shot send
```

---

## Repository Structure

```
Grasp/
├── core/
│   └── grasp-core/            # Shared Rust transfer core (LocalSend v2 compatible)
│       └── src/
│           ├── protocol.rs    # Wire data model & endpoints
│           ├── identity.rs    # Self-signed TLS identity (+ persistence)
│           ├── server.rs      # HTTPS server on :53317
│           ├── discovery.rs   # Multicast UDP + subnet scan
│           ├── sender.rs      # File sender
│           ├── webhub.rs      # Browser Web Hub on :7456
│           ├── ffi.rs         # C ABI
│           └── jni.rs         # Android JNI bindings
├── app/
│   ├── www/                   # Shared Web UI (Capacitor renderer)
│   ├── android/               # Capacitor Android app (.apk)
│   └── electron/              # Electron Windows app (.exe)
├── Casks/
│   └── grasp.rb               # Homebrew Cask formula for macOS
├── Sources/
│   ├── Grasp/                 # Swift source code (SwiftUI, CoreBluetooth, Nearby Share)
│   │   ├── Models/            # Transfer & Connection Data Models
│   │   ├── NearbyShare/       # Native Google Quick Share Protobuf & ECC Engine
│   │   ├── GraspShare/        # LocalSend v2 protocol (HTTPS server, discovery, sender)
│   │   ├── Services/          # TransferManager state coordinator
│   │   ├── UI/                # MenuBarView, WebShareModalView, GraspTheme
│   │   └── WebReceiver/       # Swift WebReceiverServer (HTTP Engine)
│   └── NDHackery/             # Objective-C bridge for native macOS notification center
├── scripts/
│   ├── build_core.sh          # Cross-compile the Rust core
│   ├── build_android.sh       # Build the Android APK
│   └── build_windows.sh       # Package the Windows .exe
├── bin/                       # Output build directory
├── install.ps1                # Windows 1-line PowerShell installer
├── install.sh                 # Linux & macOS 1-line Bash installer
├── build_mac_app.sh           # Native macOS app build script
└── Package.swift              # Swift Package Manager manifest
```

---

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Designed & Built with ❤️ by <b>Elmee / KaMy Studio</b>
</p>
