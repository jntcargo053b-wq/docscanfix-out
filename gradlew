#!/usr/bin/env sh
set -e
exec "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/android/gradlew" "$@"
