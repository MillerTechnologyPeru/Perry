#!/bin/sh
# Builds i386 Mac test programs from the C fixtures with clang and Apple's ld64
# (cctools-port, installed under .toolchains/cctools), which supports i386
# where lld's Mach-O port does not. ld64 here has no TAPI, so each system
# library is a stub dylib built from the symbols the .tbd in Tests/Fixtures/sdk
# lists. They start above Linux's default vm.mmap_min_addr (-pagezero_size).
#
# usage: build-i386-fixtures.sh [minimum macOS version, default 10.6] [fixture ...]
#   (default fixture: hello.c)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
min=${1:-10.6}
[ $# -gt 0 ] && shift
fixtures=${*:-hello.c}
mkdir -p "$root/.build/perry-fixtures/i386/libSystem"
python3 -I - "$root/Tests/Fixtures/sdk/libSystem.tbd" "$root/.build/perry-fixtures/i386/libSystem/stub.c" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
lines = []
symbols = re.search(r'symbols:\s*\[(.*?)\]', text, re.S)
for name in (s.strip() for s in symbols.group(1).replace('\n', ' ').split(',') if s.strip()) if symbols else []:
    if name.startswith('_') or name == 'dyld_stub_binder':
        lines.append('void sym_%d(void) __asm__("%s"); void sym_%d(void) {}' % (len(lines), name, len(lines)))
open(sys.argv[2], 'w').write('\n'.join(lines) + '\n')
PY
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e MIN="$min" -e FIXTURES="$fixtures" -v "$root:/perry" -w /perry --entrypoint sh perry-dev -euc '
    ld=/perry/.toolchains/cctools/bin/i386-apple-darwin11-ld out=.build/perry-fixtures/i386
    clang -target i386-apple-macosx$MIN -fno-builtin -w -c $out/libSystem/stub.c -o $out/libSystem/exit-asm.o
    $ld -arch i386 -dylib -install_name /usr/lib/libSystem.B.dylib -macosx_version_min $MIN \
        -o $out/libSystem/libSystem.dylib $out/libSystem/exit-asm.o 2>&1 | grep -v "directory not found" || true
    # What crt1.o has for images from before 10.6, which name it in their stubs.
    echo "void helper(void) __asm__(\"dyld_stub_binding_helper\"); void helper(void) {}" > $out/crt.c
    clang -target i386-apple-macosx$MIN -w -c $out/crt.c -o $out/crt.o
    for file in $FIXTURES; do
        name=${file%.*}
        rm -f $out/$name
        clang -target i386-apple-macosx$MIN -fno-stack-protector -c Tests/Fixtures/$file -o $out/$name.o -isystem Tests/Fixtures/include
        $ld -arch i386 -macosx_version_min $MIN -e _main -pagezero_size 0x10000 -o $out/$name $out/$name.o $out/crt.o \
            $out/libSystem/libSystem.dylib 2>&1 | grep -v "directory not found" || true
        echo $out/$name
    done'
