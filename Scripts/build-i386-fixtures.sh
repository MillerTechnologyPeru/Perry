#!/bin/sh
# Builds i386 Mac test programs from the C and Objective-C fixtures with clang and Apple's ld64
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
# @try calls setjmp itself on i386.
for name in ('__setjmp', '__longjmp', '_statfs', '_stat$INODE64', '_lstat$INODE64', '_fstat$INODE64', '_statfs$INODE64',
             '_readdir$INODE64', '_stat64', '_getenv', '_fflush', '_usleep'):
    if not any('"%s"' % name in line for line in lines):
        lines.append('void sym_%d(void) __asm__("%s"); void sym_%d(void) {}' % (len(lines), name, len(lines)))
open(sys.argv[2], 'w').write('\n'.join(lines) + '\n')
PY
# libobjc: what its .tbd lists, and the old ABI's entry points and the absolute
# symbols classes of that ABI are referred to by.
mkdir -p "$root/.build/perry-fixtures/i386/libobjc"
python3 -I - "$root/Tests/Fixtures/sdk/libobjc.tbd" "$root/.build/perry-fixtures/i386/libobjc/stub.c" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
names = set()
for match in re.finditer(r'symbols:\s*\[(.*?)\]', text, re.S):
    names.update(s.strip() for s in match.group(1).replace('\n', ' ').split(',') if s.strip().startswith('_'))
names.discard('__objc_empty_cache'); names.discard('__objc_empty_vtable')
names.update(['_objc_msgSend', '_objc_msgSend_stret', '_objc_msgSend_fpret', '_objc_msgSendSuper', '_objc_msgSendSuper_stret',
              '_objc_exception_try_enter', '_objc_exception_try_exit', '_objc_exception_extract', '_objc_exception_throw',
              '_objc_exception_match', '_objc_getClass', '_objc_getMetaClass', '_class_addMethod', '_imp_implementationWithBlock', '_imp_getBlock', '_imp_removeBlock', '_sel_registerName', '_objc_sync_enter', '_objc_sync_exit', '.objc_class_name_NSObject'])
lines = ['void sym_%d(void) __asm__("%s"); void sym_%d(void) {}' % (i, n, i) for i, n in enumerate(sorted(names))]
open(sys.argv[2], 'w').write('\n'.join(lines) + '\n')
PY
# Foundation: what its .tbd lists, with its classes as the old ABI refers to them.
mkdir -p "$root/.build/perry-fixtures/i386/Foundation"
python3 -I - "$root/Tests/Fixtures/sdk/Foundation.tbd" "$root/.build/perry-fixtures/i386/Foundation/stub.c" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
names = set()
for match in re.finditer(r'symbols:\s*\[(.*?)\]', text, re.S):
    names.update(s.strip() for s in match.group(1).replace('\n', ' ').split(',') if s.strip().startswith('_'))
names = {n for n in names if not n.startswith('_OBJC_EHTYPE')}
classes = set(['NSAutoreleasePool'])
for match in re.finditer(r'objc-classes:\s*\[(.*?)\]', text, re.S):
    classes.update(s.strip() for s in match.group(1).replace('\n', ' ').split(',') if s.strip())
names.update('.objc_class_name_' + c for c in classes)
names.update(['_NSInsetRect', '_NSPointInRect'])
lines = ['void sym_%d(void) __asm__("%s"); void sym_%d(void) {}' % (i, n, i) for i, n in enumerate(sorted(names))]
open(sys.argv[2], 'w').write('\n'.join(lines) + '\n')
PY
# AppKit: the classes the fixtures use.
mkdir -p "$root/.build/perry-fixtures/i386/AppKit"
for class in NSView NSColor NSApplication NSWindow; do
    printf 'void c_%s(void) __asm__(".objc_class_name_%s"); void c_%s(void) {}\n' "$class" "$class" "$class"
done > "$root/.build/perry-fixtures/i386/AppKit/stub.c"
echo 'void NSRectFill(void) {}' >> "$root/.build/perry-fixtures/i386/AppKit/stub.c"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e MIN="$min" -e FIXTURES="$fixtures" -v "$root:/perry" -w /perry --entrypoint sh perry-dev -euc '
    ld=/perry/.toolchains/cctools/bin/i386-apple-darwin11-ld out=.build/perry-fixtures/i386
    clang -target i386-apple-macosx$MIN -fno-builtin -w -c $out/libSystem/stub.c -o $out/libSystem/exit-asm.o
    $ld -arch i386 -dylib -install_name /usr/lib/libSystem.B.dylib -macosx_version_min $MIN \
        -o $out/libSystem/libSystem.dylib $out/libSystem/exit-asm.o 2>&1 | grep -v "directory not found" || true
    clang -target i386-apple-macosx$MIN -fno-builtin -w -c $out/libobjc/stub.c -o $out/libobjc/exit-asm.o
    $ld -arch i386 -dylib -install_name /usr/lib/libobjc.A.dylib -macosx_version_min $MIN \
        -o $out/libobjc/libobjc.dylib $out/libobjc/exit-asm.o $out/libSystem/libSystem.dylib 2>&1 | grep -v "directory not found" || true
    clang -target i386-apple-macosx$MIN -fno-builtin -w -c $out/Foundation/stub.c -o $out/Foundation/exit-asm.o
    $ld -arch i386 -dylib -install_name /System/Library/Frameworks/Foundation.framework/Foundation -macosx_version_min $MIN \
        -o $out/Foundation/Foundation.dylib $out/Foundation/exit-asm.o $out/libSystem/libSystem.dylib 2>&1 | grep -v "directory not found" || true
    clang -target i386-apple-macosx$MIN -fno-builtin -w -c $out/AppKit/stub.c -o $out/AppKit/exit-asm.o
    $ld -arch i386 -dylib -install_name /System/Library/Frameworks/AppKit.framework/Versions/C/AppKit -macosx_version_min $MIN \
        -o $out/AppKit/AppKit.dylib $out/AppKit/exit-asm.o $out/libSystem/libSystem.dylib 2>&1 | grep -v "directory not found" || true
    # CoreAudio: the calls legacy_audio makes.
    mkdir -p $out/CoreAudio
    i=0
    for name in AudioHardwareGetProperty AudioDeviceAddIOProc AudioDeviceRemoveIOProc AudioDeviceStart AudioDeviceStop \
        AudioDeviceGetCurrentTime AudioComponentFindNext AudioComponentInstanceNew AudioUnitInitialize AudioUnitSetProperty \
        AudioUnitSetParameter AudioUnitGetParameter AudioUnitRender; do
        echo "void sym_$i(void) __asm__(\"_$name\"); void sym_$i(void) {}"
        i=$((i + 1))
    done > $out/CoreAudio/stub.c
    clang -target i386-apple-macosx$MIN -fno-builtin -w -c $out/CoreAudio/stub.c -o $out/CoreAudio/exit-asm.o
    $ld -arch i386 -dylib -install_name /System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio -macosx_version_min $MIN \
        -o $out/CoreAudio/CoreAudio.dylib $out/CoreAudio/exit-asm.o $out/libSystem/libSystem.dylib 2>&1 | grep -v "directory not found" || true
    # What crt1.o has for images from before 10.6, which name it in their stubs.
    echo "void helper(void) __asm__(\"dyld_stub_binding_helper\"); void helper(void) {}" > $out/crt.c
    clang -target i386-apple-macosx$MIN -w -c $out/crt.c -o $out/crt.o
    for file in $FIXTURES; do
        name=${file%.*}
        rm -f $out/$name
        libs=$out/libSystem/libSystem.dylib flags=""
        case $file in *.m) libs="$libs $out/libobjc/libobjc.dylib" flags="-fobjc-exceptions -fblocks" ;; esac
        grep -q -E "NSString|NSAutoreleasePool|NSInsetRect" Tests/Fixtures/$file && libs="$libs $out/Foundation/Foundation.dylib"
        grep -q NSView Tests/Fixtures/$file && libs="$libs $out/AppKit/AppKit.dylib"
        grep -q AudioDeviceAddIOProc Tests/Fixtures/$file && libs="$libs $out/CoreAudio/CoreAudio.dylib"
        clang -target i386-apple-macosx$MIN -fno-stack-protector $flags -c Tests/Fixtures/$file -o $out/$name.o -isystem Tests/Fixtures/include
        # legacy_start links as Mac programs do: at 0x1000, from crt1'"'"'s start.
        layout="-e _main -pagezero_size 0x10000"
        [ "$name" = legacy_start ] && layout="-e start -no_pie"
        $ld -arch i386 -macosx_version_min $MIN $layout -o $out/$name $out/$name.o $out/crt.o \
            $libs 2>&1 | grep -v "directory not found" || true
        echo $out/$name
    done'
