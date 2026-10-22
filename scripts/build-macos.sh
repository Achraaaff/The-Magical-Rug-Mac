#!/bin/bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[[ $(uname -s) == Darwin ]] || { echo 'Build this app on macOS, or download the ready-made DMG from Releases.' >&2; exit 1; }
app="$root/build/The Magical Rug.app"
mkdir -p "$root/build/objects" "$app/Contents/MacOS" "$app/Contents/Resources"
sdk=$(xcrun --sdk macosx --show-sdk-path)
for arch in x86_64 arm64; do
  xcrun --sdk macosx clang++ -std=c++17 -O2 -DNDEBUG -fobjc-arc -fblocks \
    -arch "$arch" -mmacosx-version-min=14.0 -isysroot "$sdk" \
    -Werror=return-type -Werror=unguarded-availability-new \
    -framework AppKit -framework Metal -framework MetalKit -framework QuartzCore \
    -framework Carbon -framework ServiceManagement -framework CoreGraphics \
    "$root/Sources/MagicalRug.mm" -o "$root/build/objects/MagicalRug-$arch"
done
xcrun lipo -create "$root/build/objects/MagicalRug-x86_64" "$root/build/objects/MagicalRug-arm64" -output "$app/Contents/MacOS/MagicalRug"
xcrun --sdk macosx metal -std=metal2.4 -mmacosx-version-min=14.0 -c "$root/Resources/Rug.metal" -o "$root/build/objects/Rug.air"
xcrun --sdk macosx metallib "$root/build/objects/Rug.air" -o "$app/Contents/Resources/Rug.metallib"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/persian.jpg" "$root/Resources/AppIcon.icns" "$root/Resources/INSTALL.html" "$app/Contents/Resources/"
cp "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MAC_SIGN_IDENTITY" "$app"
else
  codesign --force --timestamp=none --sign - "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"
xcrun lipo -verify_arch x86_64 arm64 "$app/Contents/MacOS/MagicalRug"
plutil -lint "$app/Contents/Info.plist"
echo "Built and verified universal app: $app"
