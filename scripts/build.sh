#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Override MAIL_SDK for another installed macOS SDK (14 or newer).
MAIL_SDK="${MAIL_SDK:-$(xcrun --show-sdk-path)}"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  MAIL_SDK="${MAIL_SDK_OVERRIDE:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
fi
mkdir -p dist .build/icon
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
xcrun swiftc -sdk "$MAIL_SDK" scripts/icon.swift -o .build/icon/draw
.build/icon/draw .build/icon/CosmicMail.iconset
mkdir -p docs/assets
cp .build/icon/CosmicMail.iconset/icon_256x256.png docs/assets/cosmic-mail.png
if [ -d web/assets ]; then cp docs/assets/cosmic-mail.png web/assets/icon.png; fi
iconutil -c icns .build/icon/CosmicMail.iconset -o Resources/AppIcon.icns
for arch in arm64 x86_64; do
  swift build -c release --build-system native --scratch-path ".build/$arch" --sdk "$MAIL_SDK" --triple "$arch-apple-macosx14.0"
done
lipo -create .build/arm64/arm64-apple-macosx/release/CosmicMail .build/x86_64/x86_64-apple-macosx/release/CosmicMail -output dist/CosmicMail
python3 scripts/package.py
