#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h}
if [[ $(uname -s) != Darwin ]]; then echo 'macOS is required.' >&2; exit 1; fi
if [[ $(uname -m) != arm64 ]]; then
    if [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]]; then
        exec /usr/bin/arch -arm64 /bin/zsh "$0" "$@"
    fi
    echo 'This helper requires an Apple Silicon Mac.' >&2; exit 1
fi
source "$repo_root/scripts/dependencies.sh"
tubitak_prepare_runtime
tubitak_prepare_jar
runtime_home=$TUBITAK_JDK8_HOME
official_jar=$TUBITAK_OFFICIAL_JAR
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/tubitak-helper-build.XXXXXX")
trap '/bin/rm -rf -- "$stage_root"' EXIT
app="$stage_root/TUBITAK Signing Helper.app"
output_app="$repo_root/build/TUBITAK Signing Helper.app"
build_id=$(printf '%s' "$repo_root" | shasum -a 256 | cut -c 1-12)
cached_app="$TUBITAK_CACHE_HOME/builds/$build_id/TUBITAK Signing Helper.app"

"$runtime_home/bin/java" -version
"$runtime_home/bin/jarsigner" -verify "$official_jar"
/usr/bin/lipo -archs "$runtime_home/jre/bin/java" | /usr/bin/grep -q arm64

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Java" "$app/Contents/Resources/Licenses"
"$runtime_home/bin/javac" -cp "$official_jar" -d "$app/Contents/Resources/Java" "$repo_root/src/TubitakJnlpLauncher.java"
swiftc -swift-version 5 -target arm64-apple-macosx13.0 -O -framework Cocoa "$repo_root/src/Launcher.swift" -o "$app/Contents/MacOS/TubitakSigningHelper"
/usr/bin/ditto --norsrc --noextattr "$runtime_home/jre" "$app/Contents/Resources/Runtime"
/usr/bin/ditto --norsrc --noextattr "$official_jar" "$app/Contents/Resources/Java/tubitak-esign-1.21.0.jar"
for license_name in LICENSE ASSEMBLY_EXCEPTION THIRD_PARTY_README; do
    cp "$runtime_home/$license_name" "$app/Contents/Resources/Licenses/$license_name"
done

python3 - "$app" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'local.otcan.TubitakSigningHelper',
    'CFBundleName':'TUBITAK Signing Helper',
    'CFBundleDisplayName':'TÜBİTAK Signing Helper',
    'CFBundleExecutable':'TubitakSigningHelper',
    'CFBundlePackageType':'APPL',
    'CFBundleShortVersionString':'0.1.0',
    'CFBundleVersion':'1',
    'LSMinimumSystemVersion':'13.0',
    'NSHighResolutionCapable':True,
    'NSDownloadsFolderUsageDescription':'Open the TÜBİTAK signing request you choose from Downloads.',
    'CFBundleDocumentTypes':[{
        'CFBundleTypeName':'TÜBİTAK signing request',
        'CFBundleTypeRole':'Viewer',
        'LSHandlerRank':'Alternate',
        'CFBundleTypeExtensions':['jnlp'],
        'LSItemContentTypes':['com.sun.java-web-start','local.otcan.tubitak-jnlp'],
    }],
    'UTImportedTypeDeclarations':[{
        'UTTypeIdentifier':'local.otcan.tubitak-jnlp',
        'UTTypeDescription':'Java Network Launch Protocol',
        'UTTypeConformsTo':['public.xml'],
        'UTTypeTagSpecification':{
            'public.filename-extension':['jnlp'],
            'public.mime-type':['application/x-java-jnlp-file'],
        },
    }],
}))
PY

# Finder can attach these metadata attributes while inspecting generated bundles.
# Remove only packaging metadata from this newly generated app before signing it.
xattr -r -d com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -r -d com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$repo_root/build"
mkdir -p "${cached_app:h}"
if [[ -e "$cached_app" ]]; then /bin/rm -rf -- "$cached_app"; fi
/bin/mv "$app" "$cached_app"
codesign --verify --deep --strict "$cached_app"
if [[ -e "$output_app" || -L "$output_app" ]]; then /bin/rm -rf -- "$output_app"; fi
ln -s "$cached_app" "$output_app"
echo "Built: $output_app"
