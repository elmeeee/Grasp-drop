#!/bin/bash
set -e

echo "=================================================="
echo "          Building Otter Native Swift App         "
echo "=================================================="

mkdir -p bin
mkdir -p bin/Otter.app/Contents/MacOS
mkdir -p bin/Otter.app/Contents/Resources

echo "[1/3] Packaging Resources & Icons..."
if [ -d "Resources/AppIcon.iconset" ]; then
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns bin/Otter.app/Contents/Resources/AppIcon.icns
fi
for icon in otter-menubar.png otter-menubar@2x.png; do
    if [ -f "Resources/Otter/$icon" ]; then
        cp "Resources/Otter/$icon" "bin/Otter.app/Contents/Resources/$icon"
    fi
done

echo "[2/3] Compiling Native Swift Application with SPM..."
swift build --build-path ./build_spm

echo "[3/3] Packaging Otter.app Bundle..."
APP_DIR="bin/Otter.app"

BIN_PATH="$(find build_spm -name OtterExecutable -type f | head -n 1)"
if [ -z "$BIN_PATH" ]; then
    echo "ERROR: OtterExecutable not found under build_spm/"
    exit 1
fi
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/Otter"

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.plist">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Otter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.kamy.Otter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Otter</string>
    <key>CFBundleDisplayName</key>
    <string>Otter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Otter needs Bluetooth to discover Nearby Share devices.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Otter needs Local Network access to receive files via Quick Share and Web Receiver.</string>
</dict>
</plist>
EOF

chmod +x "$APP_DIR/Contents/MacOS/Otter"
chmod +x build_mac_app.sh

echo "--------------------------------------------------"
echo "BUILD SUCCESSFUL! Otter.app ready at:"
echo "  $(pwd)/bin/Otter.app"
echo "--------------------------------------------------"

