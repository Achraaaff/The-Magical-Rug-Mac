#!/bin/bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$root/build/The Magical Rug.app"
[[ -x "$app/Contents/MacOS/MagicalRug" ]] || { echo 'Run scripts/build-macos.sh first.' >&2; exit 1; }
mkdir -p "$root/dist" "$root/build/dmg-root"
# ditto preserves the signed bundle and handles its spaces without shell expansion.
ditto "$app" "$root/build/dmg-root/The Magical Rug.app"
cp "$root/Resources/INSTALL.html" "$root/build/dmg-root/START HERE.html"
ln -sfn /Applications "$root/build/dmg-root/Applications"
hdiutil create -volname 'The Magical Rug' -srcfolder "$root/build/dmg-root" -format UDZO -ov "$root/dist/The-Magical-Rug-Mac-universal.dmg"
ditto -c -k --keepParent "$app" "$root/dist/The-Magical-Rug-Mac-universal.zip"
(cd "$root/dist" && shasum -a 256 The-Magical-Rug-Mac-universal.dmg The-Magical-Rug-Mac-universal.zip > SHA256SUMS.txt)
echo 'Ready-to-install Intel + Apple Silicon downloads are in dist/'
