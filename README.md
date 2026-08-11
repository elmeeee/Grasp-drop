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
  <a href="https://go.dev"><img src="https://img.shields.io/badge/Go-1.24-00ADD8?style=for-the-badge&logo=go" alt="Go"></a>
</p>

---

## Overview

**Grasp** is an open-source, lightweight file-sharing solution that connects your **MacBook**, **Android**, **iPhone**, **Windows PC**, and **Linux** machines on your local Wi-Fi network without requiring third-party cloud services or internet access.

It features a **native macOS Menu Bar app** with full **Android Quick Share (Nearby Share)** protocol support, plus an **Instant Cross-Platform Web Hub** and standalone single-binary executables for **Windows** and **Linux**.

---

## Key Features

- **Zero Setup on Android**: Uses Android’s built-in **Quick Share (Nearby Share)** protocol over Bluetooth LE and local Wi-Fi. No Android apps needed!
- **Instant Cross-Platform Web Hub**: Share files to and from **iPhone, iPad, Windows, and Linux** using a modern, responsive Web Portal with QR Code scanning.
- **Bidirectional File Sharing**: Send files from your Mac to Android/Web devices or receive files seamlessly with real-time transfer progress.
- **Privacy-First & 100% Local**: Files travel directly across your local Wi-Fi network with end-to-end encryption support. Zero cloud dependency.
- **Modern macOS Native UI**: Built with Swift 5.9, SwiftUI, and AppKit featuring translucent glassmorphic popovers, PIN verification badges, and recent transfer history.
- **Standalone Windows & Linux Binaries**: Single zero-dependency executables (`grasp-windows-x64.exe` & `grasp-linux-x64`) for non-macOS machines.
- **Terminal & CLI Ready**: Includes 1-line terminal installers and simple `curl` / `PowerShell` commands for power users.

---

## Quick Installation

### macOS (Homebrew Terminal Install)

Install Grasp as a native macOS application via Homebrew Cask:

```bash
brew tap elmeeee/grasp-drop
brew install --cask grasp
```

Or download `Grasp.app` from the [Releases](https://github.com/elmeeee/Grasp-drop/releases) page.

---

### Windows (1-Line PowerShell Terminal Install)

Run this single command in Windows PowerShell to install Grasp:

```powershell
iwr -useb https://raw.githubusercontent.com/elmeeee/Grasp-drop/main/install.ps1 | iex
```

*This downloads `grasp.exe`, adds it to your User PATH, and allows you to type `grasp` in any terminal.*

Alternatively, install via Winget:
```powershell
winget install Grasp
```

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

---

## Building from Source

### Prerequisites
- macOS 13.0+
- Xcode 15+ / Swift 5.9+
- Go 1.24+ (for Windows/Linux cross-compilation)

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

### Cross-Compile Standalone Windows & Linux Binaries
```bash
# Compile for Windows (64-bit .exe)
GOOS=windows GOARCH=amd64 go build -o bin/grasp-windows-x64.exe ./cmd/grasp-server

# Compile for Linux (64-bit binary)
GOOS=linux GOARCH=amd64 go build -o bin/grasp-linux-x64 ./cmd/grasp-server
```

---

## Repository Structure

```
Grasp/
├── Casks/
│   └── grasp.rb               # Homebrew Cask formula for macOS
├── Sources/
│   ├── Grasp/                 # Swift source code (SwiftUI, CoreBluetooth, Nearby Share)
│   │   ├── Models/            # Transfer & Connection Data Models
│   │   ├── NearbyShare/       # Native Google Quick Share Protobuf & ECC Engine
│   │   ├── Services/          # TransferManager state coordinator
│   │   ├── UI/                # MenuBarView, WebShareModalView, GraspTheme
│   │   └── WebReceiver/       # Swift WebReceiverServer (HTTP Engine)
│   └── NDHackery/             # Objective-C bridge for native macOS notification center
├── cmd/
│   └── grasp-server/          # Standalone Go server for Windows & Linux
├── bin/                       # Output build directory (Grasp.app, .exe, CLI scripts)
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
