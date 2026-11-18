#!/bin/zsh
set -euo pipefail
repo_root=${0:A:h:h}
destination=${1:?Pass an output .icns path}
icon_root=$(mktemp -d "${TMPDIR:-/tmp}/tubitak-icon.XXXXXX")
trap '/bin/rm -rf -- "$icon_root"' EXIT
mkdir "$icon_root/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$repo_root/assets/app-icon.png" \
        --out "$icon_root/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -s format png -z "$doubled" "$doubled" "$repo_root/assets/app-icon.png" \
        --out "$icon_root/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_root/AppIcon.iconset" -o "$destination"
