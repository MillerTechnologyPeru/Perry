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
  `NSUserDefaults`, `NSFileManager`, `NSValue`, `NSCharacterSet`,
  `NSXMLParser`, `NSLog`, and the CFString functions KissXML uses
  (`CFStringTransform` with `kCFStringTransformToXMLHex`,
  `CFStringTrimWhitespace`); `%s` reads bytes as Mac OS Roman, as on Darwin
- C libraries over Linux's builds of the same libraries, with thunks for
  Darwin's variadic ABI: libxml2 (`libPerryxml2`, which KissXML runs on),
  zlib, bzip2, Expat, iconv, and SQLite 3.54 built with Apple's options
- libcompression (`libPerrycompression`): Apple's API over zlib, liblzma,
  LZ4, Brotli and LZFSE, reading what Apple's encoders write
- CommonCrypto, in libSystem: digests, HMAC, `CCCrypt` and `CCCryptor`
  (AES, DES, 3DES, CAST, RC4, RC2, Blowfish in each mode), PBKDF2, AES key
  wrap and random bytes
- `dispatch_once`
- UIKit (`libPerryUIKit`), headless so far: `UIApplicationMain` with the
  app delegate's launch callbacks, the scene lifecycle from the Info.plist's
  scene manifest (`UIWindowScene`, `UISceneSession`,
  `UISceneConfiguration`), application and scene states, launch
  notifications; `UIView` geometry, hierarchy, callbacks, coordinate
  conversion and layout passes; `UIWindow` with its scene, root view
  controller and key window; `UIViewController` view loading; the
  responder chain from a view to the app delegate; `NSStringFromCGRect`
- CoreGraphics (`libPerryCoreGraphics`): geometry constants and functions
  (`CGRectZero`, `CGRectIntersection`, `CGRectInset`…)

Not yet supported: arm64e, thread-local variables (`__thread_vars`),
`dlopen` from Mach-O code, Objective-C exceptions, most of Foundation
(operation queues, GCD, run loop input sources, formatters, localization),
most of UIKit (drawing, events, controls, appearance callbacks), Swift.

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
| `Sources/PerryXML2` | `libPerryxml2.so`: libxml2, Linux's with Darwin ABI thunks (C, assembly) |
| `Sources/PerryZ`, `PerryBZ2`, `PerryExpat`, `PerrySQLite3`, `PerryIconv` | zlib, bzip2, Expat, SQLite and iconv over Linux's (C, assembly) |
| `Sources/PerryCompression` | `libPerrycompression.so`: libcompression (C) |
| `Sources/CPerryWrapped` | Symbol lookup and variadic thunk macros the wrapped libraries share |
| `Sources/PerryCoreGraphics` | `libPerryCoreGraphics.so`: CoreGraphics geometry (Swift) |
| `Sources/CPerryCoreGraphics` | CoreGraphics' exported constants (C) |
| `Sources/CPerryGeometry` | `CGPoint`, `CGSize`, `CGRect` as C structs, shared by providers |
| `Sources/PerryObjCInterop` | `@ObjCClass`, `@ObjCCategory`, `@ObjCProtocol`, `@ObjCConstants`, `@ObjCMethod` and `@ObjCProperty`: Objective-C classes and protocols in Swift, and calls into Objective-C |
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
Linux image (Debian 13) with Swift 6.4 and Debian's LLVM, the C libraries
the providers bind to, SQLite 3.54 and LZFSE, then runs `swift build` and
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
that use UIKit are built for Mac Catalyst, which runs iOS's UIKit. A
fixture's `dependencies` file names third-party sources by git URL and
commit, such as KissXML for Scribe; the script clones them into `.build`.
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
non-variadic arguments narrower than 8 bytes, which Apple packs; functions
that take them read the packed slot as one argument
(`CCCryptorCreateWithMode`).

**Wrapped C libraries.** Some Darwin libraries are mapped onto the Linux
build of the same library rather than reimplemented. `CPerryWrapped` is
what they share: the lookup below, and the `VARIADIC` and `VA_LIST`
assembler macros for their thunks. box64 does this for
x86 code with a list of every function and its signature: each call
crosses from emulated to native code through a generated wrapper, and
functions that take callbacks get hand-written wrappers that swap guest
function pointers for native trampolines from a fixed pool. Perry runs
the app's code natively, so only the ABI differences need code.
`libPerryxml2` (for `/usr/lib/libxml2.2.dylib`) binds each import to Linux's
libxml2 through `perry_provider_symbol`, which `dlsym`s the name and accepts
only symbols libxml2 itself defines. The iOS SDK's libxml2 (2.9.13) and
Debian's (2.9.14) share their public structs, which apps such as KissXML
walk directly. The exceptions are variadic: `PerryXML2/thunks.S` gives
`xmlStrPrintf` and the text writer's `…Format…` functions Darwin entry
points that build an AAPCS64 `va_list` over Darwin's stack arguments, and
their `…V…` forms one over Darwin's `va_list` pointer. Generic error
handlers, which libxml2 calls back with variadic arguments, get native
trampolines from a pool of eight, as in box64: each formats the message
and calls the Darwin handler with `"%s"` and the text, its way.
`xmlGenericError` reads back the Darwin handler. Variadic callbacks
elsewhere (SAX handler and validation context fields, the schema and
Relax-NG error setters) are not bridged yet.

The others work the same way. zlib (`libPerryz`) needs a thunk only for
`gzprintf`; bzip2 (`libPerrybz2`) and Expat (`libPerryexpat`) none. SQLite
(`libPerrysqlite3`) binds to SQLite 3.54.0, the SDK's version, which the
Docker image builds as `libperry-sqlite3` with the compile options of
Apple's that change behaviour (`PRAGMA compile_options` on a Mac lists
them); `sqlite3_open` and its variants also turn on what Apple's opens
every connection with: defensive mode, legacy `ALTER TABLE` and fast
secure delete. Its formatting functions have `va_list` forms to thunk to;
`sqlite3_config`, `sqlite3_db_config`, `sqlite3_vtab_config` and
`sqlite3_test_control` do not, but take only integers and pointers, so
their thunks forward Darwin's stack slots as words, which the callee reads
as it would have read Linux's registers. iconv (`libPerryiconv`) is part of
glibc on Linux, so it defines `iconv_open`, `iconv`, `iconv_close` and
`iconvctl` itself over glibc's rather than binding any libc name.

libcompression and CommonCrypto are Apple's own APIs, so Perry implements
them. `libPerrycompression` writes and reads each format: raw DEFLATE,
XZ, raw LZ4 and LZ4 in Apple's `bv41` blocks, Brotli and LZFSE, with
Darwin's truncation results. CommonCrypto lives in libSystem: its digests
and HMAC are implemented to fit the contexts callers allocate at Apple's
sizes, and its ciphers use OpenSSL's EVP interface, loaded on first use,
with CommonCrypto's lenient PKCS#7 removal (the last byte's count,
unchecked) rather than OpenSSL's.

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

`@ObjCProtocol` makes an Objective-C protocol a Swift protocol. Its
requirements name their selectors with `@ObjCRequired` or `@ObjCOptional`:

```swift
@ObjCProtocol("UIWindowSceneDelegate")
protocol UIWindowSceneDelegate: UISceneDelegate {
    @ObjCOptional("window")
    func window() -> UIWindow?
}
```

The macro generates `AnyUIWindowSceneDelegate`, a class that conforms by
sending each requirement's message to the object it wraps, whatever its
class; an optional method is sent only if the object implements it, and
one that returns a value returns an Optional, nil otherwise. It also
generates default implementations of the optional requirements, so a Swift
class implements only those it needs, and the protocol's registration. A
protocol may refine one other; its `Any` class inherits the other's. The
provider's generated startup registers the protocols with the runtime
(`objc_allocateProtocol`) and adds them to the `@ObjCClass` classes that
adopt them, so `conformsToProtocol:` answers as on Darwin:

```swift
@ObjCClass("UIView")
open class UIView: UIResponder, UICoordinateSpace { … }
```

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
`NSXMLParser` is built, as Darwin's is, over libxml2's SAX2 callbacks, on
Linux's libxml2: delegates see the events Darwin's parser sends, with text
split where libxml2 splits it, declared entities resolved but not
substituted, and the parse stopped by the first error.

**UIKit** is written the same way, as a client of libobjc and of
Foundation, which it calls through `@ObjCWrapper` classes. It has no C
part: its classes live in storage handed out through
`perry_provider_symbol`, and its objects keep their Swift state in a table
per class until they are deallocated. `UIApplicationMain` follows UIKit's
launch order, which current SDKs require to include scenes, and then runs
the main run loop. Views send their hierarchy callbacks as messages, so
subclasses' overrides run, in UIKit's order: `willMoveToWindow:` down the
subtree, `didMoveToWindow` back up. A window installs its root view
controller's view when it becomes visible, inside the `UITransitionView`
and `UIDropShadowView` UIKit puts there. Geometry types are C structs, so
a `CGRect` passes in four floating-point registers as clang passes it.

**Licensing.** The loader is written from Apple's published Mach-O format
descriptions. It does not use code from Machismo (GPL-3.0), so Perry stays
MIT.
