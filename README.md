# Perry
Cross Platform Darwin App Loader and Runtime

Perry runs prebuilt arm64 iOS (and macOS) Mach-O binaries natively on arm64
Linux, without CPU emulation. The loader maps Mach-O images in-process and
binds their imports to Linux libraries ("providers") that implement the
Darwin ABI. Frameworks are Linux ELF code; only the ABI boundary is Darwin.

## Status

The loader runs C and Objective-C iOS binaries and `.app` bundles that use
libSystem, libobjc, a first subset of Foundation and the start of UIKit.

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
- An Objective-C runtime for Apple's arm64 ABI (`libPerryobjc`): classes,
  categories, protocols, `+load` and `+initialize`, message caching, ARC,
  `__weak`, autorelease pools, associated objects and blocks
- Foundation (`libPerryFoundation`, also standing in for CoreFoundation):
  `NSString` and `NSMutableString` with string literals and
  `stringWithFormat:`, `NSNumber` with number literals and `@YES`/`@NO`,
  `NSArray`, `NSDictionary` and `NSSet` with their mutable subclasses,
  constant collection literals, sorting, blocks and fast enumeration,
  Foundation's description format, `NSDate`, `NSTimer`, `NSRunLoop` and
  `CFRunLoop` (timers only), `NSNotificationCenter`, `NSData`, `NSURL`,
  `NSUUID`, `NSJSONSerialization`, `NSError`, `NSNull`, `NSString`'s
  encodings, paths and searching, `NSBundle` with Info.plist and resources,
  `NSProcessInfo`, `NSThread` with performs between threads,
  `NSUserDefaults`, `NSFileManager`, and `NSLog`
- UIKit (`libPerryUIKit`), headless so far: `UIApplicationMain` with the
  app delegate's launch callbacks, the scene lifecycle from the Info.plist's
  scene manifest (`UIWindowScene`, `UISceneSession`,
  `UISceneConfiguration`), application and scene states, launch
  notifications and the responder chain

Not yet supported: arm64e, thread-local variables (`__thread_vars`),
`dlopen` from Mach-O code, Objective-C exceptions, most of Foundation
(operation queues, GCD, run loop input sources, formatters, localization),
most of UIKit (views, windows, drawing, events), Swift.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/PerryLoaderCore` | Mach-O loader library (C) |
| `Sources/PerryLoader` | `perry` executable |
| `Sources/PerrySystem` | `libPerrySystem.so`: Darwin libSystem over glibc, and the blocks runtime (C, assembly) |
| `Sources/PerryObjC` | `libPerryobjc.so`: libobjc's C API under Darwin names (Swift) |
| `Sources/PerryObjCRuntime` | Objective-C runtime engine (Swift) |
| `Sources/CPerryObjC` | Runtime metadata layouts, exported class storage, `objc_msgSend` (C, assembly) |
| `Sources/PerryFoundation` | `libPerryFoundation.so`: Foundation and CoreFoundation (Swift) |
| `Sources/CPerryFoundation` | Foundation's exported class storage and variadic entry points (C, assembly) |
| `Sources/PerryUIKit` | `libPerryUIKit.so`: UIKit (Swift) |
| `Sources/PerryObjCInterop` | `@ObjCClass`, `@ObjCCategory`, `@ObjCConstants`, `@ObjCMethod` and `@ObjCProperty`: Objective-C classes in Swift, and calls into Objective-C |
| `Sources/PerryObjCMacros` | The macros' implementation (swift-syntax) |
| `Plugins/PerryProviderPlugin` | Build plugin that generates a provider's entry points from its declarations |
| `Sources/PerryProviderGenerator` | The plugin's generator (swift-syntax) |
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

The script also builds each app as a macOS app, with the fixture's other
files as resources, and records its output with Apple's Foundation; apps
that use UIKit are built for Mac Catalyst, which runs iOS's UIKit.
`DarwinFixtureTests` requires Perry's output to match it byte for byte. The
suite is skipped when the apps have not been built.

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
an unrelated glibc symbol by accident. Providers start in Darwin's layer
order, libSystem, libobjc, Foundation, then the frameworks above them,
whatever order the app lists them in.

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

**Objective-C.** `libPerryobjc` reads the metadata clang and ld64 emit
into Mach-O images: class lists, `class_ro_t`, relative and absolute method
lists, categories, protocols and ivar offsets. The loader calls
`perry_provider_image_init` for each image before its initializers, where
dyld would notify the runtime; the runtime uniques selector references,
realizes classes, attaches categories and calls `+load`. Each class's
`cache` field points at the runtime's state, whose first word is a method
cache that `objc_msgSend` (assembly) probes before calling into Swift.
Retain counts live in a side table. The runtime, `NSObject` and the block
classes are written in Swift and exported with `@c`; only `objc_msgSend`,
forwarding and the `$`-named data symbols are C and assembly. Blocks are
classes built inside libSystem's `_NSConcrete*Block` storage, which the
runtime reaches through the loader's `lookup_symbol`.

**Objective-C classes in Swift.** `PerryObjCInterop` exposes Swift classes
to Objective-C. An `@ObjCClass` class inherits from the class of its
Objective-C superclass, rooted at `NSObject`, and an instance stands for one
Objective-C object, holding a reference to it. Its `@ObjCMethod` and
`@ObjCClassMethod` functions implement selectors, with `self` as the
receiver and Swift values as arguments and results:

```swift
@ObjCClass("NSMutableString")
public class NSMutableString: NSString {
    @ObjCMethod("appendString:")
    func append(_ other: String) { storage.value += other }
}

NSMutableString.defineObjCClass()
```

The macro generates a C-convention thunk per method and
`registerObjCMethods(_:)`, which installs them, and rejects selectors whose
argument count does not match at compile time. `defineObjCClass(_:)` creates
the class in the runtime (in the provider's exported `_OBJC_CLASS_$_…`
storage when it has some), installs its methods and any extra registrations,
and registers it.

`@ObjCCategory` adds methods to a class that already exists, from an
extension of its wrapper, as an Objective-C category does:

```swift
@ObjCCategory("Additions")
public extension NSString {
    @ObjCMethod("lastPathComponent")
    func lastPathComponent() -> String { Paths.lastComponent(value) }
}

NSString.addObjCCategoryAdditions()
```

Swift does not let subclasses override methods declared in extensions, so a
category's functions take Swift names its class's subclasses do not use.

The same attributes call Objective-C from Swift. A method function without a
body sends its selector, and `@ObjCProperty` sends a property's getter and
setter, each through `objc_msgSend` cast to the method's C signature:

```swift
extension NSObject {
    @ObjCMethod("description")
    func describedByObject() -> String?

    @ObjCClassMethod("new")
    static func new() -> Self

    @ObjCProperty(getter: "isProxy", readonly: true)
    var isProxy: Bool
}
```

`@ObjCClass` and `@ObjCCategory` register only the functions with bodies.

`@ObjCConstants` exports a type's `static let` constants as the data symbols
Objective-C code reads, such as `NSString *const NSCocoaErrorDomain`:

```swift
@ObjCConstants
enum RunLoopModes {
    static let NSDefaultRunLoopMode = "kCFRunLoopDefaultMode"
    static let kCFRunLoopDefaultMode = NSDefaultRunLoopMode   // the same object
}
```

Swift cannot define a data symbol by name, so providers may export
`perry_provider_symbol`: while images bind, the loader asks it for imports
the provider does not define as ELF symbols, and it returns a slot for each
constant and storage for each class (`_OBJC_CLASS_$_UIResponder`). At
startup the provider fills the slots and builds its classes in that
storage, before any Mach-O code runs.

`@ObjCWrapper` wraps a class another library defines, such as Foundation's
classes in UIKit: it names the class, for casts and class methods, and its
methods have no body, so they call the class's:

```swift
@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle")
    static func main() -> NSBundle
}
```

`PerryProviderPlugin` writes a provider's `perry_provider_startup` and
`perry_provider_symbol`. It scans the module for `@ObjCClass`,
`@ObjCCategory` and `@ObjCConstants` declarations and generates a startup
that defines the classes (superclasses first), adds the categories and
exports the constants. A class that overrides
`didDefineObjCClass(_:)` in its body gets it called with the new class, for
set-up such as variadic methods or shared instances; a category declared
with `addedAtStartup: false` is a method set that classes register
themselves. The provider adds its own steps as top-level functions:

```swift
func providerWillStart(_ info: perry_startup_info) -> Bool  // before; false stops startup
func providerDidStart(_ info: perry_startup_info)           // after
```

Values cross through the `ObjCValue` protocol, which gives each Swift type
its C representation, its type encoding and Objective-C's ownership rules:
numbers and pointers pass as they are, `String` becomes an `NSString`,
wrappers pass their object, and results of `alloc`, `new`, `copy` and `init`
methods are owned. `NSObject` in the runtime and every Foundation class are
written this way.

**Foundation** is written in Swift as a client of libobjc's C API, which it
looks up through the loader at startup, so it shares the one runtime rather
than linking a copy. Its classes are built with `objc_initializeClassPair`
in storage exported under Mach-O names (`_OBJC_CLASS_$_NSString`,
`___CFConstantStringClassReference`), and each method is a Swift function
with C calling conventions. Objects keep their Swift state in one extra
word, which wraps a swift-foundation value where one exists (`NSDate`
holds a `Date` from FoundationEssentials). String and number literals are static objects the compiler emits;
their classes read them in place, including constant `@[…]` and `@{…}`
literals and CoreFoundation's boolean objects. Variadic methods and `NSLog` receive
Apple's stack-slot arguments through two-instruction assembly entry points,
and a Swift formatter handles `%@` and passes other conversions to glibc.

**UIKit** is written the same way, as a client of libobjc and of
Foundation, which it calls through `@ObjCWrapper` classes. It has no C
part: its classes live in storage handed out through
`perry_provider_symbol`, and its objects keep their Swift state in a table
per class until they are deallocated. `UIApplicationMain` follows UIKit's
launch order, which current SDKs require to include scenes, and then runs
the main run loop.

**Licensing.** The loader is written from Apple's published Mach-O format
descriptions. It does not use code from Machismo (GPL-3.0), so Perry stays
MIT.
