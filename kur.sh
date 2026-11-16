#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != Darwin ] || [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]; then
    echo 'This installer requires an Apple Silicon Mac.' >&2
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install
    echo 'Finish installing Xcode Command Line Tools, then run this installer again.'
    exit 1
fi

source_dir=${TUBITAK_HELPER_SOURCE_DIR:-"$HOME/.local/share/tubitak-eimza-mac-arm64"}
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    candidate=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if [ -f "$candidate/src/Launcher.swift" ]; then source_dir=$candidate; fi
fi
if [ ! -f "$source_dir/src/Launcher.swift" ]; then
    mkdir -p "$(dirname "$source_dir")"
    git clone https://github.com/otcan/tubitak-eimza-mac-arm64.git "$source_dir"
elif [ -d "$source_dir/.git" ] && [ "${BASH_SOURCE[0]:-}" = '' ]; then
    git -C "$source_dir" pull --ff-only
fi

zsh "$source_dir/build.sh"
install_dir=${TUBITAK_HELPER_INSTALL_DIR:-"$HOME/Applications"}
app="$install_dir/TUBITAK Signing Helper.app"
mkdir -p "$install_dir"
if pgrep -x TubitakSigningHelper >/dev/null 2>&1; then
    echo 'Quit TUBITAK Signing Helper before updating it, then run the installer again.' >&2
    exit 1
fi
built_app=$(cd "$source_dir/build/TUBITAK Signing Helper.app" && pwd -P)
ditto --norsrc --noextattr "$built_app" "$app"
codesign --verify --deep --strict "$app"
'/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister' -f "$app"
echo "Installed: $app"
echo 'Open the helper and choose Open JNLP… to select a fresh TÜBİTAK signing request.'
