#!/bin/sh
# Builds armv7 iOS test programs from the C fixtures with clang and Apple's
# ld64 (cctools-port, installed under .toolchains/cctools), which supports
# armv7 where lld's Mach-O port does not. ld64 here has no TAPI, so libSystem is
# a stub dylib built from the symbols Tests/Fixtures/sdk/libSystem.tbd lists.
#
# usage: build-armv7-fixtures.sh [minimum iOS version, default 6.0] [fixture ...]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
llvm=$(ls -d "$root"/.toolchains/LLVM-*/bin | head -1)
ld=$root/.toolchains/cctools/bin/arm-apple-darwin11-ld
out=$root/.build/perry-fixtures/armv7
min=${1:-6.0}
[ $# -gt 0 ] && shift
mkdir -p "$out"

# The stub libSystem: every symbol the .tbd exports, as an empty function.
# Its object is named exit-asm.o, which ld64 lets a dylib omit libSystem for.
python3 -I - "$root/Tests/Fixtures/sdk/libSystem.tbd" "$out/stub.c" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
body = re.search(r'symbols:\s*\[(.*?)\]', text, re.S).group(1)
names = [s.strip() for s in body.replace('\n', ' ').split(',') if s.strip()]
lines = []
for name in names:
    if name == 'dyld_stub_binder':
        lines.append('void binder(void) __asm__("dyld_stub_binder"); void binder(void) {}')
    elif name.startswith('_'):
        lines.append('void %s(void) {}' % name[1:])
open(sys.argv[2], 'w').write('\n'.join(lines) + '\n')
PY
"$llvm/clang" -target "armv7-apple-ios$min" -fno-builtin -w -c "$out/stub.c" -o "$out/exit-asm.o"
"$ld" -arch armv7 -dylib -install_name /usr/lib/libSystem.B.dylib -ios_version_min "$min" \
    -o "$out/libSystem.B.dylib" "$out/exit-asm.o" 2>&1 | grep -v 'directory not found' || true

fixtures=${*:-hello}
for name in $fixtures; do
    "$llvm/clang" -target "armv7-apple-ios$min" -mfloat-abi=soft -c "$root/Tests/Fixtures/$name.c" \
        -o "$out/$name.o" -isystem "$root/Tests/Fixtures/include"
    # Before iOS 6 an executable starts at crt1's start; Perry calls _main.
    entry=""
    case $min in [0-5]*) entry="-e _main" ;; esac
    # shellcheck disable=SC2086
    "$ld" -arch armv7 -ios_version_min "$min" $entry -o "$out/$name" "$out/$name.o" \
        "$out/libSystem.B.dylib" 2>&1 | grep -v 'directory not found' || true
    echo "$out/$name"
done
