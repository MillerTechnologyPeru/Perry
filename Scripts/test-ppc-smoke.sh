#!/bin/sh
# Checks the ppc loader and C providers that Scripts/build-ppc-loader.sh and
# build-ppc-carbon.sh build, under qemu-ppc as a G4 (-cpu 7400), as CI runs
# them. ppc Mac programs are built with Xcode 3.2.6 (build-ppc-fixtures.sh),
# which CI cannot fetch, so no program runs here: perry starts, reads its
# options, and refuses a file that is not a ppc Mach-O, and every library in
# .build/ppc/bin resolves what it links against.
#
# PPC_SYSROOT names the target's libraries for qemu-ppc (default
# /usr/powerpc-linux-gnu, where Debian's and Ubuntu's libc6-powerpc-cross
# install them). QEMU_PPC names qemu-ppc (default: qemu-ppc, or
# qemu-ppc-static).
# Usage: Scripts/test-ppc-smoke.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
sysroot=${PPC_SYSROOT:-/usr/powerpc-linux-gnu}
qemu=${QEMU_PPC:-$(command -v qemu-ppc || command -v qemu-ppc-static)}
bin=$root/.build/ppc/bin
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
run() { "$qemu" -cpu 7400 -L "$sysroot" "$@"; }
fail() { echo "test-ppc-smoke: $*" >&2; exit 1; }

run "$bin/perry" --help > "$work/out" || fail "perry --help failed"
grep -q '^usage: perry' "$work/out" || fail "perry --help printed no usage"
run "$bin/perry" --settings > "$work/out" || fail "perry --settings failed"
grep -q PERRY_ "$work/out" || fail "perry --settings listed no settings"
echo "perry --help and --settings"

# perry itself is ELF, not Mach-O.
if run "$bin/perry" "$bin/perry" > "$work/out" 2>&1; then fail "perry ran an ELF file"; fi
grep -q 'not a 32-bit Mach-O' "$work/out" || fail "perry refused an ELF file without saying why: $(cat "$work/out")"
echo "perry refuses a file that is not Mach-O"

for library in "$bin"/*.so; do
    run "$sysroot/lib/ld.so.1" --list "$library" > "$work/out" 2>&1 || fail "$library: $(cat "$work/out")"
    if grep -q 'not found' "$work/out"; then fail "$library: $(grep 'not found' "$work/out")"; fi
    echo "$(basename "$library") resolves its libraries"
done
