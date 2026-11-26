#!/bin/sh
# Runs one program of a poured prefix (Scripts/homebrew/pour.rb) under Perry
# in the perry-dev container: the runner for Scripts/homebrew/run-cli.rb on
# a machine that is not Linux.
#   ruby Scripts/homebrew/run-cli.rb --bin /opt/homebrew/bin --runner Scripts/homebrew/docker-runner.sh
# The test's directory (the current one, with its HOME and PERRY_CONTAINER
# inside) is mounted at the same path. The prefix is .build/homebrew/prefix,
# or $PERRY_HOMEBREW_PREFIX, as /opt/homebrew; Perry is the Linux build in
# .build/linux/out/Products/Release-linux-aarch64, or $PERRY_BIN (a path as seen in the container).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
prefix=${PERRY_HOMEBREW_PREFIX:-$root/.build/homebrew/prefix}
perry=${PERRY_BIN:-/perry/.build/linux/out/Products/Release-linux-aarch64/perry}
case $(uname -m) in
    x86_64) platform=linux/amd64 ;;
    *) platform=linux/arm64 ;;
esac
exec docker run --rm -i --init --platform "$platform" \
    -e HOME -e PERRY_CONTAINER -e PERRY_CRASH_REPORT -e LC_ALL -e LANG \
    -v "$root:/perry:ro" -v "$prefix:/opt/homebrew:ro" \
    -v "$PWD:$PWD" -w "$PWD" \
    "${PERRY_IMAGE:-perry-dev}" "$perry" "$@"
