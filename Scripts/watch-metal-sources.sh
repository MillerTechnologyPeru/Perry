#!/bin/sh
# Compiles Metal sources for an app running on another machine as it writes
# them: watches the app's source cache there (PERRY_METAL_SOURCES, or
# metal-sources beside the app) over ssh, compiles each new <key>.metal on
# this Mac, and puts <key>.metallib back. With PERRY_METAL_WAIT=<seconds> set
# for the app, it waits for the library instead of failing, so a shader is
# drawn the first time it is used.
# Usage: Scripts/watch-metal-sources.sh <user@host> <remote directory> [iOS deployment target]
set -eu
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
host=${1:?usage: $0 <user@host> <remote directory> [iOS version]}
remote=${2:?usage: $0 <user@host> <remote directory> [iOS version]}
min=${3:-16.0}
work=$(mktemp -d)
control="-o ControlMaster=auto -o ControlPath=/tmp/perry-metal-watch-%C -o ControlPersist=10m"
trap 'rm -rf "$work"; ssh $control -O exit "$host" 2>/dev/null || true' EXIT
echo "watching $host:$remote"
while :; do
    pending=$(ssh $control "$host" "cd '$remote' 2>/dev/null && for s in *.metal; do [ -e \"\$s\" ] && [ ! -e \"\${s%.metal}.metallib\" ] && echo \"\${s%.metal}\"; done" || true)
    for key in $pending; do
        # What failed once fails again: it is reported the once.
        [ -e "$work/$key.failed" ] && continue
        ssh $control "$host" "cat '$remote/$key.metal'" > "$work/$key.metal"
        if xcrun -sdk iphoneos metal -mios-version-min="$min" -include metal_stdlib -w -o "$work/$key.metallib" "$work/$key.metal" 2>"$work/$key.log"; then
            ssh $control "$host" "cat > '$remote/$key.metallib.partial' && mv '$remote/$key.metallib.partial' '$remote/$key.metallib'" < "$work/$key.metallib"
            echo "compiled $key"
        else
            echo "failed $key: $(head -3 "$work/$key.log")" >&2
            : > "$work/$key.failed"
        fi
        rm -f "$work/$key.metal" "$work/$key.metallib" "$work/$key.log"
    done
    sleep 0.3
done
