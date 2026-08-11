#!/bin/bash
set -e

echo "=================================================="
echo "          Building Grasp Native Swift App         "
echo "=================================================="

mkdir -p bin
mkdir -p bin/Grasp.app/Contents/MacOS
mkdir -p bin/Grasp.app/Contents/Resources

echo "[1/3] Generating Icons..."
if [ -f "/Users/phincon/.gemini/antigravity-ide/brain/2bbd33d1-60f5-4d3a-a1f9-bb83d8f296c0/scratch/render_icons.swift" ]; then
    swift /Users/phincon/.gemini/antigravity-ide/brain/2bbd33d1-60f5-4d3a-a1f9-bb83d8f296c0/scratch/render_icons.swift .
fi
iconutil -c icns AppIcon.iconset -o AppIcon.icns
cp AppIcon.icns bin/Grasp.app/Contents/Resources/AppIcon.icns
if [ -f "BarIcon.png" ]; then
    cp BarIcon.png bin/Grasp.app/Contents/Resources/BarIcon.png
fi
if [ -f "BarIcon@2x.png" ]; then
    cp BarIcon@2x.png bin/Grasp.app/Contents/Resources/BarIcon@2x.png
fi

echo "[2/3] Compiling Native Swift Application with SPM..."
swift build --build-path ./build_spm

echo "[3/3] Packaging Grasp.app Bundle..."
APP_DIR="bin/Grasp.app"

cp build_spm/arm64-apple-macosx/debug/GraspExecutable "$APP_DIR/Contents/MacOS/Grasp"

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.plist">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Grasp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.kamy.Grasp</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Grasp</string>
    <key>CFBundleDisplayName</key>
    <string>Grasp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Grasp needs Bluetooth to discover Nearby Share devices.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Grasp needs Local Network access to receive files via Quick Share and Web Receiver.</string>
</dict>
</plist>
EOF

chmod +x "$APP_DIR/Contents/MacOS/Grasp"
chmod +x build_mac_app.sh

echo "--------------------------------------------------"
echo "BUILD SUCCESSFUL! Grasp.app ready at:"
echo "  $(pwd)/bin/Grasp.app"
echo "--------------------------------------------------"

