#!/bin/bash
# Builds and packages locally. Never pushes, creates a release, or replaces an installed app.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 3 ]]; then
  echo 'Usage: prepare-release.sh "Developer ID Application: …" NOTARY_KEYCHAIN_PROFILE OUTPUT_DIRECTORY' >&2
  echo 'This submits the signed archive to Apple for notarization; run only after approval.' >&2
  exit 2
fi
signing_identity=$1
notary_profile=$2
output_dir=$3
[[ "$signing_identity" == 'Developer ID Application:'* ]] || { echo 'A Developer ID Application identity is required.' >&2; exit 2; }
[[ ! -e "$output_dir" ]] || { echo 'Use a new output directory; existing exports are never overwritten.' >&2; exit 2; }

release_dir=$(mktemp -d "${TMPDIR:-/tmp}/procaine-release.XXXXXX")
export CLANG_MODULE_CACHE_PATH="$release_dir/module-cache"
xcodebuild -project Procaine.xcodeproj -scheme Procaine -configuration Release \
  -derivedDataPath "$release_dir/build" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGN_STYLE=Manual ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
app="$release_dir/build/Build/Products/Release/Procaine.app"
# No embedded helper/framework remains. Timestamp and hardened runtime are required for notarization.
codesign --force --options runtime --timestamp --sign "$signing_identity" \
  --entitlements Procaine/Procaine.entitlements "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" "$release_dir/Procaine.zip"
xcrun notarytool submit "$release_dir/Procaine.zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"

mkdir -p "$output_dir"
ditto -c -k --keepParent "$app" "$output_dir/Procaine.zip"
shasum -a 256 "$output_dir/Procaine.zip" > "$output_dir/Procaine.zip.sha256"
python3 scripts/write-cask.py "$output_dir/Procaine.zip" "$app/Contents/Info.plist" "$output_dir/aplombie-procaine.rb"
echo 'Prepared locally. Before publishing, test an actual quarantined download and complete the release checklist.'
