#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# A certificate-backed identity preserves the designated requirement across rebuilds.
# Explicit '-' remains available for portable, intentionally ad-hoc builds.
touchbar_signing_identity="${TOUCHBAR_SIGNING_IDENTITY:-}"
if [[ -z "$touchbar_signing_identity" ]]; then
  touchbar_identities=("${(@f)$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]{40}) .*/\1/p')}")
  touchbar_identities=("${(@)touchbar_identities:#}")
  if (( ${#touchbar_identities} != 1 )); then
    print -u2 'Set TOUCHBAR_SIGNING_IDENTITY to a valid code signing identity. Use - only for an intentional ad-hoc build; privacy permissions may reset.'
    exit 1
  fi
  touchbar_signing_identity="$touchbar_identities[1]"
fi
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
<key>CFBundleVersion</key><string>15</string>
<key>CFBundleShortVersionString</key><string>0.8.3</string>
<key>LSUIElement</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ ! -f config.json ]]; then
  cp config.example.json config.json
fi
if [[ ! -f build/config.json ]]; then
  cp config.json build/config.json
fi
mkdir -p build/TouchbarTool.app/Contents/Resources
cp Assets/AppIcon.icns build/TouchbarTool.app/Contents/Resources/AppIcon.icns
codesign --force --sign "$touchbar_signing_identity" build/TouchbarTool.app
codesign --verify --strict build/TouchbarTool.app
echo "Built $PWD/build/TouchbarTool.app"
