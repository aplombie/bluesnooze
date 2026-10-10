#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/procaine-check.XXXXXX")
export CLANG_MODULE_CACHE_PATH="$check_dir/module-cache"
export SWIFT_MODULECACHE_PATH="$check_dir/module-cache"
swift test --scratch-path "$check_dir/tests" --cache-path "$check_dir/package-cache"
plutil -lint Procaine/Info.plist Procaine/Procaine.entitlements Procaine.xcodeproj/project.pbxproj
xcodebuild -project Procaine.xcodeproj -scheme Procaine -configuration Release \
  -derivedDataPath "$check_dir/app" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
codesign --verify --deep --strict "$check_dir/app/Build/Products/Release/Procaine.app"
git diff --check
echo "Checks passed. Local ad-hoc build: $check_dir/app/Build/Products/Release/Procaine.app"
