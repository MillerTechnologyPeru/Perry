#!/bin/sh
# Builds armv7 iOS test programs from the C and Objective-C fixtures with clang
# and Apple's ld64 (cctools-port, installed under .toolchains/cctools), which
# supports armv7 where lld's Mach-O port does not. ld64 here has no TAPI, so
# each system library is a stub dylib built from the symbols and classes the
# .tbd in Tests/Fixtures/sdk lists.
#
# usage: build-armv7-fixtures.sh [minimum iOS version, default 6.0] [fixture ...]
#   fixtures are file names in Tests/Fixtures: hello.c, runtime.m, foundation_abi.m
#   (default: hello.c)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
llvm=$(ls -d "$root"/.toolchains/LLVM-*/bin | head -1)
ld=$root/.toolchains/cctools/bin/arm-apple-darwin11-ld
out=$root/.build/perry-fixtures/armv7
min=${1:-6.0}
[ $# -gt 0 ] && shift
mkdir -p "$out"

# stub NAME INSTALL-NAME [SYMBOL ...]: a dylib exporting what
# Tests/Fixtures/sdk/NAME.tbd lists, and the symbols given. Its object is named
# exit-asm.o, which ld64 lets a dylib omit libSystem for.
stub() {
    name=$1 install=$2
    shift 2
    extra="$*"
    mkdir -p "$out/$name"
    python3 -I - "$root/Tests/Fixtures/sdk/$name.tbd" "$out/$name/stub.c" $extra <<'PY'
import re, sys
text = open(sys.argv[1]).read()
lines = []
symbols = re.search(r'symbols:\s*\[(.*?)\]', text, re.S)
for name in (s.strip() for s in symbols.group(1).replace('\n', ' ').split(',') if s.strip()) if symbols else []:
    if name == 'dyld_stub_binder':
        lines.append('void binder(void) __asm__("dyld_stub_binder"); void binder(void) {}')
    elif name.startswith('_'):
        lines.append('void sym_%d(void) __asm__("%s"); void sym_%d(void) {}' % (len(lines), name, len(lines)))
classes = re.search(r'objc-classes:\s*\[(.*?)\]', text, re.S)
for name in (s.strip() for s in classes.group(1).split(',') if s.strip()) if classes else []:
    for prefix in ('_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'):
        lines.append('char cls_%d[64] __asm__("%s%s");' % (len(lines), prefix, name))
for name in sys.argv[3:]:
    lines.append('void sym_%d(void) __asm__("%s"); void sym_%d(void) {}' % (len(lines), name, len(lines)))
open(sys.argv[2], 'w').write('\n'.join(lines) + '\n')
PY
    "$llvm/clang" -target "armv7-apple-ios$min" -fno-builtin -w -c "$out/$name/stub.c" -o "$out/$name/exit-asm.o"
    "$ld" -arch armv7 -dylib -install_name "$install" -ios_version_min "$min" -o "$out/$name/$name.dylib" \
        "$out/$name/exit-asm.o" 2>&1 | grep -v 'directory not found' || true
}
# armv7 code unwinds with setjmp and longjmp: functions with cleanups register
# a context with the unwinder, which libSystem provides.
stub libSystem /usr/lib/libSystem.B.dylib __Unwind_SjLj_Register __Unwind_SjLj_Unregister \
    __Unwind_SjLj_Resume __Unwind_SjLj_RaiseException
# Structures too big for r0 come back through a pointer: the _stret sends,
# which arm64 does not have.
stub libobjc /usr/lib/libobjc.A.dylib _objc_msgSend_stret _objc_msgSendSuper2_stret \
    _objc_exception_throw _objc_exception_rethrow _objc_begin_catch _objc_end_catch _objc_terminate \
    _OBJC_EHTYPE_id _objc_ehtype_vtable _objc_retainAutorelease
stub Foundation /System/Library/Frameworks/Foundation.framework/Foundation
stub CoreGraphics /System/Library/Frameworks/CoreGraphics.framework/CoreGraphics

fixtures=${*:-hello.c}
for file in $fixtures; do
    name=${file%.*}
    case $file in
    *.m) flags="-fobjc-arc -fobjc-exceptions -fblocks"
        libs="$out/libSystem/libSystem.dylib $out/libobjc/libobjc.dylib"
        grep -q NSString "$root/Tests/Fixtures/$file" && libs="$libs $out/Foundation/Foundation.dylib" ;;
    *) flags=""; libs="$out/libSystem/libSystem.dylib"
        grep -q CGContext "$root/Tests/Fixtures/$file" && libs="$libs $out/CoreGraphics/CoreGraphics.dylib" ;;
    esac
    # softfp, as Apple's armv7 code is built: VFP instructions, with floating
    # point passed in core registers.
    # shellcheck disable=SC2086
    "$llvm/clang" -target "armv7-apple-ios$min" -mfloat-abi=softfp -mfpu=vfpv3 -fno-stack-protector $flags -c "$root/Tests/Fixtures/$file" \
        -o "$out/$name.o" -isystem "$root/Tests/Fixtures/include"
    # Before iOS 6 an executable starts at crt1's start; Perry calls _main.
    entry=""
    case $min in [0-5]*) entry="-e _main" ;; esac
    # shellcheck disable=SC2086
    "$ld" -arch armv7 -ios_version_min "$min" $entry -o "$out/$name" "$out/$name.o" $libs \
        2>&1 | grep -v 'directory not found' || true
    echo "$out/$name"
done
