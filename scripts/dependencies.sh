#!/bin/bash
# Sourced by build.sh or the parser test. Downloads stay outside the repository.

TUBITAK_CACHE_HOME=${TUBITAK_CACHE_HOME:-"$HOME/Library/Caches/TubitakSigningHelper"}
TUBITAK_JAVA_VERSION=8.512.09.1
TUBITAK_JAVA_URL="https://corretto.aws/downloads/resources/$TUBITAK_JAVA_VERSION/amazon-corretto-$TUBITAK_JAVA_VERSION-macosx-aarch64.tar.gz"
TUBITAK_JAVA_SHA256=30c7edb7134712148cc323d4ccfc816758e7f1e4bb8aa1287795872fa5eca610
TUBITAK_JAR_URL=https://e-imza.tubitak.gov.tr/sublimity-ess/jnlp/sublimity-esign-client-swingui-1.21.0-SNAPSHOT-jar-with-dependencies.jar
TUBITAK_JAR_SHA256=416f247a015e30e05d156b04382b7c56f03bc4459c68b45442370ac4dc769391

tubitak_verify() {
    local actual
    actual=$(shasum -a 256 "$1")
    actual=${actual%% *}
    [ "$actual" = "$2" ]
}

tubitak_fetch() {
    local url="$1" destination="$2" checksum="$3"
    if [ -f "$destination" ]; then
        if tubitak_verify "$destination" "$checksum"; then return 0; fi
        echo "Checksum mismatch for $destination. Remove this cached download and retry." >&2
        return 1
    fi
    mkdir -p "$(dirname "$destination")"
    curl -fL --retry 2 --connect-timeout 20 --max-time 600 --continue-at - \
        "$url" -o "$destination.part"
    if ! tubitak_verify "$destination.part" "$checksum"; then
        echo 'The download does not match the reviewed version. No code was run.' >&2
        echo 'The official package may have changed; check this repository for an update.' >&2
        return 1
    fi
    mv "$destination.part" "$destination"
}

tubitak_prepare_jar() {
    if [ -z "${TUBITAK_OFFICIAL_JAR:-}" ]; then
        TUBITAK_OFFICIAL_JAR="$TUBITAK_CACHE_HOME/tubitak-esign-1.21.0.jar"
        tubitak_fetch "$TUBITAK_JAR_URL" "$TUBITAK_OFFICIAL_JAR" "$TUBITAK_JAR_SHA256"
    fi
    tubitak_verify "$TUBITAK_OFFICIAL_JAR" "$TUBITAK_JAR_SHA256" || {
        echo 'The official TÜBİTAK JAR does not match the reviewed SHA-256.' >&2
        return 1
    }
}

tubitak_prepare_runtime() {
    if [ -n "${TUBITAK_JDK8_HOME:-}" ]; then return 0; fi
    local archive="$TUBITAK_CACHE_HOME/corretto8-arm64.tar.gz"
    local marker="$TUBITAK_CACHE_HOME/runtime/reviewed-sha256"
    tubitak_fetch "$TUBITAK_JAVA_URL" "$archive" "$TUBITAK_JAVA_SHA256"
    TUBITAK_JDK8_HOME="$TUBITAK_CACHE_HOME/runtime/amazon-corretto-8.jdk/Contents/Home"
    if [ ! -x "$TUBITAK_JDK8_HOME/bin/java" ] || \
        [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$TUBITAK_JAVA_SHA256" ]; then
        mkdir -p "$TUBITAK_CACHE_HOME/runtime"
        tar -xzf "$archive" -C "$TUBITAK_CACHE_HOME/runtime"
        printf '%s\n' "$TUBITAK_JAVA_SHA256" > "$marker"
    fi
}
