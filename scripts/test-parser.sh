#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/scripts/dependencies.sh"
tubitak_prepare_jar
if [ "$(uname -s)" = Darwin ] && [ -z "${TUBITAK_JDK8_HOME:-}" ]; then
    tubitak_prepare_runtime
fi
jdk_home=${TUBITAK_JDK8_HOME:-${JAVA_HOME:-}}
if [ ! -x "$jdk_home/bin/javac" ]; then
    echo 'Set TUBITAK_JDK8_HOME or JAVA_HOME to Java 8.' >&2
    exit 1
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
"$jdk_home/bin/javac" -cp "$TUBITAK_OFFICIAL_JAR" -d "$scratch" "$repo_root/src/TubitakJnlpLauncher.java"
python3 "$repo_root/tests/test_parser.py" "$jdk_home/bin/java" "$scratch:$TUBITAK_OFFICIAL_JAR"
