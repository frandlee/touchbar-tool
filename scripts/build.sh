#!/bin/zsh
set -eu
cd "${0:A:h:h}"
touchbar_cache="$PWD/build/module-cache-$(printf '%s' "$PWD" | shasum -a 256 | cut -c 1-12)"
mkdir -p build/TouchbarTool.app/Contents/MacOS "$touchbar_cache"
xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$touchbar_cache" -c Sources/Bridge.m -o build/Bridge.o
xcrun swiftc -swift-version 5 -module-cache-path "$touchbar_cache" -import-objc-header Sources/Bridge.h Sources/Configuration.swift Sources/ConfigurationStore.swift Sources/ConfigurationEditor.swift Sources/ButtonTitleLayout.swift Sources/AutoSendGate.swift Sources/main.swift build/Bridge.o -framework AppKit -framework ApplicationServices -o build/TouchbarTool.app/Contents/MacOS/CodexTouchBar
cat > build/TouchbarTool.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex-touchbar.prototype</string>
<key>CFBundleName</key><string>Touchbar Tool</string>
<key>CFBundleDisplayName</key><string>Touchbar Tool</string>
<key>CFBundleExecutable</key><string>CodexTouchBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleShortVersionString</key><string>0.6.1</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ ! -f config.json ]]; then
  cp config.example.json config.json
fi
if [[ ! -f build/config.json ]]; then
  cp config.json build/config.json
fi
codesign --force --sign - build/TouchbarTool.app
echo "Built $PWD/build/TouchbarTool.app"
