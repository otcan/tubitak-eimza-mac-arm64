#!/bin/zsh
set -euo pipefail
repo_root=${0:A:h:h}
source "$repo_root/scripts/dependencies.sh"
: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to a Developer ID Application identity.}"
profile=${NOTARY_PROFILE:-tubitak-release}
release_root="$TUBITAK_CACHE_HOME/releases/0.2.0"
app="$release_root/TUBITAK Signing Helper.app"
dmg="$release_root/Tubitak-Signing-Helper-0.2.0-arm64.dmg"

if [[ ${1:-} == prepare ]]; then
    zsh "$repo_root/build.sh"
    mkdir -p "$release_root"
    if [[ -e "$app" ]]; then rm -rf -- "$app"; fi
    built_app=$(cd "$repo_root/build/TUBITAK Signing Helper.app" && pwd -P)
    ditto --norsrc --noextattr "$built_app" "$app"
    python3 "$repo_root/scripts/sign-app.py" "$app"
    "$app/Contents/Resources/Runtime/bin/java" -version
    echo "Prepared Developer ID app: $app"
    exit 0
fi
if [[ ${1:-} != notarize ]]; then
    echo 'Usage: scripts/release.sh prepare|notarize' >&2; exit 1
fi
[[ -d "$app" ]] || { echo 'Run prepare first.' >&2; exit 1; }

notarize() {
    local artifact="$1" name="$2"
    xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait \
        --output-format json > "$release_root/$name-submission.json"
    local submission_id
    submission_id=$(python3 - "$release_root/$name-submission.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; inspect the private submission log.')
print(result['id'])
PY
)
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" \
        "$release_root/$name-notary-log.json"
}

codesign --verify --deep --strict "$app"
ditto -c -k --keepParent --norsrc "$app" "$release_root/app-for-notarization.zip"
notarize "$release_root/app-for-notarization.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

stage_root=$(mktemp -d "${TMPDIR:-/tmp}/tubitak-dmg.XXXXXX")
trap '/bin/rm -rf -- "$stage_root"' EXIT
ditto --norsrc --noextattr "$app" "$stage_root/TUBITAK Signing Helper.app"
ln -s /Applications "$stage_root/Applications"
cp "$repo_root/assets/DMG-Read-Me.txt" "$stage_root/Read Me.txt"
hdiutil create -ov -volname 'TUBITAK Signing Helper' -srcfolder "$stage_root" \
    -format UDZO "$dmg"
codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$dmg"
notarize "$dmg" dmg
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
hdiutil verify "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
echo "Signed and notarized release: $dmg"
