# Perry
Cross Platform Darwin App Loader and Runtime

Perry runs prebuilt arm64 iOS (and macOS) Mach-O binaries natively on arm64
Linux, without CPU emulation. The loader maps Mach-O images in-process and
binds their imports to Linux libraries ("providers") that implement the
Darwin ABI. Frameworks are Linux ELF code; only the ABI boundary is Darwin.

## Status

The loader runs C-only iOS binaries and `.app` bundles.

- Thin and universal arm64 Mach-O executables, dylibs and bundles
- Chained fixups (`DYLD_CHAINED_PTR_64`, `_64_OFFSET`) and classic dyld
  info opcodes (rebase, bind, lazy and weak binds)
- Two-level namespace, flat and weak lookups, export tries with
  re-exports and resolvers
- `@rpath`, `@executable_path` and `@loader_path` dylibs inside the app
- `__mod_init_func` and `__init_offsets` initializers, dependency-first
- `.app` bundles (iOS and macOS layouts) with XML or binary `Info.plist`
- `LC_BUILD_VERSION` / `LC_VERSION_MIN_*` platforms; encrypted binaries
  (`cryptid != 0`) and arm64e are rejected with a clear error
- Unresolved imports bind to stubs that name the missing symbol when called

Not yet supported: arm64e, thread-local variables (`__thread_vars`),
`dlopen` from Mach-O code, Objective-C, Swift.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/PerryLoaderCore` | Mach-O loader library (C) |
| `Sources/PerryLoader` | `perry` executable |
| `Sources/PerrySystem` | `libPerrySystem.so`: Darwin libSystem over glibc (C, assembly) |
| `Sources/PerryInterface` | Loader/provider interface header |
| `Tests/PerryLoaderTests` | Swift Testing suite |
| `Tests/Fixtures` | arm64 iOS test programs and stub `.tbd` link libraries |
| `Tests/Fixtures/Darwin` | Objective-C apps built on a Mac with the real iPhoneOS SDK |
| `Scripts` | Docker test runner and the Mac fixture build |

## Building

Perry is a Swift package. On arm64 Linux:

```sh
swift build
.build/debug/perry path/to/App.app [arguments...]
```

The tests build Mach-O fixtures, which needs `clang` and `ld64.lld` from
upstream LLVM. The lld in Swift's Linux toolchains cannot link Mach-O.
Tests look for LLVM in `$PERRY_LLVM_BIN`, then `.toolchains/LLVM-*/bin`,
then `$PATH`, and are skipped if it is missing.

```sh
swift test
```

### Docker

On a Mac (or any arm64 host), `Scripts/docker-test.sh` builds an arm64
Linux image with Swift 6.4 and Ubuntu's LLVM, then runs `swift build` and
`swift test` in it. Linux build products go to `.build/linux`, apart from a
macOS build. Extra arguments are passed to `swift test`:

```sh
Scripts/docker-test.sh --filter DarwinFixtureTests
```

### Objective-C apps from Xcode

Linux has no Apple SDK, so Objective-C apps that use Foundation are built on
a Mac with Xcode, and the Linux tests run them:

```sh
Scripts/build-darwin-fixtures.sh   # on the Mac: .build/perry-fixtures/darwin/*.app
Scripts/docker-test.sh             # DarwinFixtureTests picks them up
```

`DarwinFixtureTests` is skipped when the apps have not been built.

## Usage

```sh
perry [--report] [--strict] <executable | App.app> [arguments...]
```

- `--report` loads and binds without running and prints one line per fact:
  dependencies, `unresolved` and `weak-missing` imports grouped by library,
  and Objective-C classes, categories, protocols, class and category
  protocol conformances, and selectors. This is the API to-do
  list for an app.
- `--strict` fails on the first unresolved non-weak import.
- `PERRY_TRACE=load,bind,init` (or `all`) traces loading.
- `PERRY_LIBRARY_PATH` adds directories to search for providers.

## Design

**Providers.** A system library's install name maps to a Linux shared
library by convention: `/usr/lib/libSystem.B.dylib` → `libPerrySystem.so`,
`/usr/lib/libc++.1.dylib` → `libPerryc++.so`,
`…/UIKit.framework/UIKit` → `libPerryUIKit.so`. Providers export ELF
symbols with the exact Mach-O names (`_printf`, `___stdoutp`,
`_OBJC_CLASS_$_UIView`), so binding is a `dlsym` by name. Only symbols
defined in the provider itself count, so a Darwin name can never bind to
an unrelated glibc symbol by accident.

**Low addresses.** Images are placed upward from 4 GB, below 64 GB, as dyld
does. Linux hands out `mmap` addresses just under 2^48, but Darwin code
assumes smaller pointers: Apple's Objective-C runtime masks class data
pointers to 47 bits, and iOS processes normally live below 64 GB.

**Darwin ABI at the boundary.** Apple's arm64 ABI passes variadic arguments
on the stack. `PerrySystem/thunks.S` wraps glibc's `v*` functions in thunks
that build an AAPCS64 `va_list` over the caller's stack slots. Functions
whose ABI is identical are a single branch to glibc. `errno` uses Darwin
numbering through `__error()`, synchronised with glibc's errno.

Known ABI gaps: struct layouts (`stat`, `dirent`, pthread types),
`open`/`fcntl` flag values, ctype tables, locale, and stack-passed
non-variadic arguments narrower than 8 bytes, which Apple packs.

**Licensing.** The loader is written from Apple's published Mach-O format
descriptions. It does not use code from Machismo (GPL-3.0), so Perry stays
MIT.
