#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK="${MAIL_SDK:-$(xcrun --show-sdk-path)}"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then SDK="${MAIL_SDK_OVERRIDE:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"; fi
swift test --build-system native --sdk "$SDK"
