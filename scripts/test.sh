#!/bin/zsh
set -eu
cd "${0:A:h:h}"
touchbar_cache="$PWD/build/module-cache-$(printf '%s' "$PWD" | shasum -a 256 | cut -c 1-12)"
mkdir -p "$touchbar_cache"
xcrun swiftc -module-cache-path "$touchbar_cache" Sources/Configuration.swift Tests/main.swift -o build/config-tests
build/config-tests
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --probe

xcrun swiftc -module-cache-path "$touchbar_cache" Sources/Configuration.swift Sources/AutoSendGate.swift Tests/AutoSend/main.swift -framework AppKit -o build/auto-send-tests
build/auto-send-tests

xcrun swiftc -module-cache-path "$touchbar_cache" Sources/Configuration.swift Sources/ConfigurationStore.swift Sources/AutoSendGate.swift Tests/Reload/main.swift -o build/reload-tests
build/reload-tests

xcrun swiftc -module-cache-path "$touchbar_cache" Sources/Configuration.swift Sources/ButtonTitleLayout.swift Tests/TitleLayout/main.swift -framework AppKit -o build/title-layout-tests
build/title-layout-tests

xcrun swiftc -module-cache-path "$touchbar_cache" Sources/Configuration.swift Sources/ButtonTitleLayout.swift Tests/IconLibrary/main.swift -framework AppKit -o build/icon-library-tests
build/icon-library-tests
