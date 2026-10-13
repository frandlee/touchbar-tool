#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Sources/Configuration.swift Tests/main.swift -o build/config-tests
build/config-tests
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --probe
