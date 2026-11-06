# Perry
Cross Platform Darwin App Loader and Runtime

Perry runs prebuilt arm64 iOS (and macOS) Mach-O binaries natively on arm64
Linux, without CPU emulation. The loader maps Mach-O images in-process and
binds their imports to Linux libraries ("providers") that implement the
Darwin ABI. Frameworks are Linux ELF code; only the ABI boundary is Darwin.

## Status

The loader runs C and Objective-C iOS binaries and `.app` bundles that use
libSystem, libobjc, libdispatch, a first subset of Foundation, CFNetwork's URL loading, Core Data and the start of UIKit.

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
  `NSXMLParser`, `NSPredicate` and `NSExpression` (format parsing,
  printing and evaluation), `NSSortDescriptor`, key-value coding with collection
  operators and structures, key-value observing (Darwin's
  `NSKVONotifying_` subclasses with setters for any argument type, each
  option, dependent keys, key paths through other objects, manual and
  to-many notifications), `NSRegularExpression` (over ICU, as Darwin's) and
  `NSTextCheckingResult`, `NSScanner`, `NSAttributedString` and
  `NSMutableAttributedString`, Markdown as Foundation imports it (over
  swift-cmark, Swift's cmark-gfm: presentation intents, inline presentation
  intents, links, images, tables, list delimiters, source positions and
  `^[…](…)` attributes, for `initWithMarkdownString:` and the localized
  attributed strings SwiftUI's `Text` reads), `NSURLComponents` and `NSURLQueryItem`,
  `NSIndexSet`, `NSOrderedSet`, `NSCountedSet`, `NSCache`, `NSLock`,
  `NSRecursiveLock`, `NSCondition`, `NSOperation`,
  `NSBlockOperation` and `NSOperationQueue` (dependencies, priorities,
  cancellation, concurrency limits, barriers, asynchronous operations,
  the main queue), `NSTimeZone`, `NSLocale`, `NSCalendar`,
  `NSDateComponents`, `NSDateFormatter`, `NSISO8601DateFormatter` and
  `NSNumberFormatter`,
  `NSPropertyListSerialization` (writing XML and binary as CoreFoundation
  writes them; reading XML, binary and OpenStep), `NSKeyedArchiver` and
  `NSKeyedUnarchiver` (binary and XML archives, app classes'
  `NSSecureCoding`, conditional objects, cycles), `NSLog`; `%s` reads bytes
  as Mac OS Roman, as on Darwin
- Bonjour over Avahi's compatibility library (`libdns_sd`, loaded at run
  time, talking to avahi-daemon): `NSNetService` and `NSNetServiceBrowser`
  with publishing, browsing, resolution (hosts, ports, addresses as
  Darwin's sockaddrs, TXT records) and Darwin's delegate order and error
  dictionaries; and CFNetwork's `CFNetService`, `CFNetServiceBrowser` and
  `CFNetServiceMonitor`, asynchronous on their scheduled run loops or
  blocking without a client, as on Darwin
- CoreFoundation, toll-free bridged to Foundation's classes: `CFArray`,
  `CFDictionary` and `CFSet` (with CoreFoundation's callbacks, the bridged
  classes; with the program's own or none, collections of any pointers),
  `CFString` (encodings, formats, searching, mutation, percent escapes,
  `CFStringTransform`), `CFNumber`, `CFBoolean`, `CFData`, `CFDate`,
  `CFURL`, `CFUUID`, `CFError`, `CFCharacterSet`, `CFTimeZone`,
  `CFLocale`, `CFBundle`, `CFPreferences` (over the user defaults) and
  Darwin's type IDs
- C libraries over Linux's builds of the same libraries, with thunks for
  Darwin's variadic ABI: libxml2 (`libPerryxml2`, which KissXML runs on),
  zlib, bzip2, Expat, iconv, and SQLite 3.54 built with Apple's options
- JavaScriptCore (`libPerryJavaScriptCore`): the C API, which is
  WebKitGTK's JavaScriptCore itself; and the Objective-C API on it:
  `JSVirtualMachine`, `JSContext` with exceptions and the exception
  handler, `JSValue` with conversions both ways, properties, calling and
  constructing, blocks as JavaScript functions with the current context,
  this and arguments, objects and classes exported through `JSExport`
  (and `JSExportAs`), and `JSManagedValue`
- Accelerate (`libPerryAccelerate`): vDSP's arithmetic, reductions,
  conversions, matrices, correlation, windows and Fourier transforms with
  Apple's scaling and packing; vForce; vImage's buffers, channel
  operations, conversions, reflections, rotations and scaling; BLAS and
  LAPACK from OpenBLAS
- libcompression (`libPerrycompression`): Apple's API over zlib, liblzma,
  LZ4, Brotli and LZFSE, reading what Apple's encoders write
- CommonCrypto, in libSystem: digests, HMAC, `CCCrypt` and `CCCryptor`
  (AES, DES, 3DES, CAST, RC4, RC2, Blowfish in each mode), PBKDF2, AES key
  wrap and random bytes
- BSD sockets with Darwin's ABI: socket addresses, options, message flags,
  `getaddrinfo`, `sendmsg` and `recvmsg` with their control messages,
  `select` and `poll`, converted to and from Linux's
- POSIX with Darwin's ABI: pthread mutexes, conditions, read-write locks
  and once with Darwin's sizes and static initializers; `open`, `openat`
  and `fcntl` (variadic on Darwin) with their flags and file locks;
  `stat`, `struct dirent` and the `*at` functions; clocks and Mach time;
  `mmap`, `uname` (reporting an iPhone, or `PERRY_DEVICE_MODEL`) and
  `sysconf`
- URL loading (`libPerryCFNetwork`, which Foundation re-exports):
  `NSURLSession` with data, upload and download tasks, completion handlers
  and delegates on their delegate queue, redirects, timeouts and
  cancellation; `NSURLRequest`, `NSMutableURLRequest`, `NSURLResponse`,
  `NSHTTPURLResponse`, `NSURLSessionConfiguration`, `NSHTTPCookie` and
  `NSHTTPCookieStorage`; `NSURLConnection` with synchronous and
  asynchronous requests and delegates on the run loop or a queue;
  `NSURLProtocol` subclasses, registered or in a configuration, for
  sessions and connections, with request properties and redirects; HTTP
  Basic challenges for session and connection delegates, with
  `NSURLProtectionSpace`, `NSURLCredential`, `NSURLCredentialStorage` and
  each disposition
- Uniform type identifiers (`libPerryUniformTypeIdentifiers`, which
  MobileCoreServices and CoreServices map to): `UTType` with iOS's system
  types, lookups by filename extension and MIME type, conformance, the
  app's exported and imported types and dynamic types; MobileCoreServices'
  `UTTypeCreatePreferredIdentifierForTag` family and `kUTType` constants
- User notifications (`libPerryUserNotifications`): content, sounds,
  time interval and calendar triggers with their next dates, requests,
  actions and categories, all secure-coded; a notification center that
  grants authorization, fires pending requests when their triggers say
  and hands them to its delegate on the main queue
- Security (`libPerrySecurity`): `SecRandomCopyBytes`; the keychain's
  generic and internet passwords, keys and certificates (`SecItemAdd`,
  `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`) with iOS's
  attributes, defaults, uniqueness and errors; RSA and P-256/384/521 keys
  with every signature, encryption, key exchange and ECIES algorithm
  Security names, in Apple's key formats; certificates; trust evaluation
  with SSL and basic policies, anchors and verify dates
- Grand Central Dispatch (`libPerrydispatch`, which libSystem re-exports):
  serial, concurrent, global and main queues, sync, async, barriers,
  `dispatch_after`, `dispatch_apply`, queue-specific data, target queues,
  suspension and inactive queues, groups, semaphores, sources (timers,
  data, reads, writes and signals), `dispatch_block_create` blocks and
  `dispatch_data`; the main queue runs on the main thread from the main
  run loop or `dispatch_main`
- Unified logging, in the same library: `os_log_create` and `os_log` at
  each level, with the argument buffers clang builds read against the
  format (`%{public}`, `%{BOOL}d`, `%{errno}d`, objects), written to
  standard error as NSLog writes; signposts and activities
- UIKit (`libPerryUIKit`), headless so far: `UIApplicationMain` with the
  app delegate's launch callbacks, the scene lifecycle from the Info.plist's
  scene manifest (`UIWindowScene`, `UISceneSession`,
  `UISceneConfiguration`), application and scene states, launch
  notifications; `UIView` geometry, hierarchy, callbacks, coordinate
  conversion and layout passes; `UIWindow` with its scene, root view
  controller and key window; `UIViewController` view loading; the
  responder chain from a view to the app delegate; `NSStringFromCGRect`
- Core Data (`libPerryCoreData`), over CoreModel: compiled `.momd`
  models and programmatic ones, `NSManagedObject` subclasses with
  `@dynamic` accessors generated from their declared properties, SQLite
  and in-memory stores (other store types, such as binary and XML, are
  kept in memory), contexts with insertion, deletion and its delete rules,
  validation, saving, rollback, merging and private queues, fetch requests
  with predicates, sorting, limits and counts, and `NSPersistentContainer`
- CoreGraphics (`libPerryCoreGraphics`): geometry and affine transforms;
  images from bytes in each 8-bit format, cropping, color spaces, colors
  and data providers; bitmap contexts drawn through Silica's Cairo
  renderer: paths (lines, curves, arcs, ellipses, rounded rects), winding
  and even-odd fills, strokes with caps, joins and dashes, clipping,
  transforms, linear and radial gradients, shadows, transparency layers,
  blend modes, images and text; `CGPath`; and ImageIO, which the loader
  maps here: image sources reading PNG, JPEG (with orientation), GIF, WebP
  and HEIC with their properties and thumbnails, and destinations writing
  PNG, JPEG and animated GIF
- AVFoundation (`libPerryAVFoundation`), played through GStreamer:
  `AVAudioPlayer` and `AVAudioSession`; `AVPlayer` and `AVPlayerItem`,
  made with a URL or with an `AVURLAsset`, whose values load in the
  background, with its video track, `AVMutableComposition` standing for
  the asset put in it, and resource loader delegates, through which an
  engine serves a movie kept inside its own data files;
  `AVPlayerItemVideoOutput`, whose frames are BGRA `CVPixelBuffer`s; and,
  as the loader maps them here, CoreMedia's `CMTime` arithmetic and format
  descriptions, CoreVideo's pixel buffers and OpenGL ES texture caches
  (the pixels are uploaded to a new texture), and MediaToolbox. A movie's
  sound plays to the system's output: assets have no audio tracks, and
  there are no audio taps, asset readers or Metal textures.
  `PERRY_AVFOUNDATION_TRACE` traces it
- Steamworks (`libPerrysteam_api`, for the `libsteam_api.dylib` games ship):
  `SteamAPI_Init` and the interfaces' accessors over the running Linux
  Steam client's `steamclient.so` (`~/.steam/sdkarm64`, or
  `$PERRY_STEAMCLIENT`), whose C++ interfaces games call directly;
  callbacks and call results through `SteamAPI_RunCallbacks`, and manual
  dispatch. The app ID comes from `SteamAppId` or `steam_appid.txt`.
  `PERRY_STEAM_TRACE` traces it

Not yet supported: arm64e, thread-local variables (`__thread_vars`),
`dlopen` from Mach-O code, Objective-C exceptions, most of Foundation
(run loop input sources, string localization, the other formatters,
key-value observing),
`dispatch_io` and dispatch workloops,
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
| `Sources/PerryDispatch` | `libPerrydispatch.so`: libdispatch over Linux's (Swift) |
| `Sources/CPerryDispatch` | Linux libdispatch's C API under other names, and Darwin libdispatch's exported data (C) |
| `Sources/PerryFoundation` | `libPerryFoundation.so`: Foundation and CoreFoundation (Swift) |
| `Sources/CPerryFoundation` | Foundation's exported class storage and variadic entry points (C, assembly) |
| `Sources/PerryCFNetwork` | `libPerryCFNetwork.so`: NSURLSession and the URL loading classes (Swift) |
| `Sources/PerryURLLoading` | URL loading over swift-corelibs-foundation's URLSession, for PerryCFNetwork (Swift) |
| `Sources/PerrySecurity` | `libPerrySecurity.so`: Security over swift-crypto and swift-certificates (Swift) |
| `Sources/CPerrySecurity` | `kSecRandomDefault`, the one export Swift cannot define (C) |
| `Sources/PerryJavaScriptCore` | `libPerryJavaScriptCore.so`: JavaScriptCore's Objective-C API over WebKitGTK's JavaScriptCore (Swift) |
| `Sources/CJavaScriptCore`, `Sources/CPerryJavaScriptCore` | WebKitGTK's JavaScriptCore headers, and the call that passes arguments to exported methods and blocks (assembly) |
| `Sources/PerryAccelerate` | `libPerryAccelerate.so`: vDSP, vForce and vImage, and OpenBLAS's BLAS and LAPACK (C) |
| `Sources/PerryUserNotifications` | `libPerryUserNotifications.so`: notification content, triggers, requests and the center (Swift) |
| `Sources/PerryUniformTypeIdentifiers` | `libPerryUniformTypeIdentifiers.so`: UTType, MobileCoreServices' UTType functions and the type database (Swift) |
| `Sources/PerryCoreData` | `libPerryCoreData.so`: Core Data over CoreModel and its SQLite store (Swift) |
| `Sources/PerryUIKit` | `libPerryUIKit.so`: UIKit (Swift) |
| `Sources/PerryXML2` | `libPerryxml2.so`: libxml2, Linux's with Darwin ABI thunks (C, assembly) |
| `Sources/PerryZ`, `PerryBZ2`, `PerryExpat`, `PerrySQLite3`, `PerryIconv` | zlib, bzip2, Expat, SQLite and iconv over Linux's (C, assembly) |
| `Sources/PerryCompression` | `libPerrycompression.so`: libcompression (C) |
| `Sources/CPerryWrapped` | Symbol lookup and variadic thunk macros the wrapped libraries share |
| `Sources/PerryCoreGraphics` | `libPerryCoreGraphics.so`: CoreGraphics geometry, images, bitmap contexts and paths, and ImageIO (Swift) |
| `Sources/Silica`, `Sources/SilicaCairo` | Silica, CoreGraphics' drawing model over Cairo, copied from [PureSwift/Silica](https://github.com/PureSwift/Silica) (MIT) with the changes marked `Perry:` (Swift) |
| `Sources/CPerryImageIO` | ImageIO's codecs over libpng, libjpeg-turbo, giflib, libwebp and libheif (C) |
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
A fixture's `.xcdatamodeld` is compiled with `momc` into both apps. A
fixture with an `Entitlements.plist` records its output from the iOS
Simulator instead, built with the entitlements in `__TEXT,__entitlements`
as Xcode puts them and run with `simctl spawn`: the keychain needs them,
and the simulator's keychain is iOS's, apart from the Mac's.
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
- `DYLD_INSERT_LIBRARIES` loads Mach-O libraries (paths separated by colons) with the
  program, as dyld does; their initializers run before the program's.

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

Numbers are exported too, their bits in the constant's 8 bytes: integer
types (`const int64_t NSURLSessionTransferSizeUnknown`), `Double` or
`CGFloat`, and `Float` in the low four bytes:

```swift
@ObjCConstants
enum SessionNumbers {
    static let NSURLSessionTransferSizeUnknown: Int64 = -1
    static let NSURLSessionTaskPriorityHigh: Float = 0.75
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

**libdispatch** runs its work on Linux's libdispatch, the one the Swift
toolchain ships. Darwin's dispatch objects are Objective-C objects, which
ARC code retains and releases, so each Perry queue, group, semaphore,
source and data object is an instance of an `OS_dispatch_*` class holding
the Linux object it stands for; the main queue, `DISPATCH_QUEUE_CONCURRENT`
and `dispatch_data_empty` are static objects the headers' macros take the
address of. Only the `_f` variants of Linux's API are called: Darwin
blocks are copied with Darwin's `_Block_copy` and run through a function,
in an autorelease pool as Darwin's worker threads drain one per item, so
they never reach Linux's blocks runtime. Sources keep their handlers and
context in Swift state that their Linux context points to, and
`dispatch_block_create` makes Darwin heap blocks. The main run loop drains
the main queue through the hooks CoreFoundation uses on Darwin, waiting in
`poll()` on the eventfd Linux's libdispatch signals; `dispatch_main` does
the same without a run loop. libSystem re-exports libdispatch as on
Darwin: the loader looks for a symbol libSystem lacks in libdispatch,
loading it then, and libdispatch brings libobjc with it.

`NSOperationQueue` is built on libdispatch, as Darwin's is: a queue starts
each ready operation, highest priority first and within its concurrency
limit, on a global dispatch queue, or on the main dispatch queue for
`+mainQueue`. Operations' state is read through their messages, so
subclasses' `-isReady` and `-isFinished` apply, and an asynchronous
operation's `-didChangeValueForKey:@"isFinished"` tells its queue it has
finished, the one part of key-value observing Perry has.

Time zones, locales, calendars and date components wrap swift-foundation's
`TimeZone`, `Locale`, `Calendar` and `DateComponents`, the implementation
Darwin's Foundation uses. The formatters work as CoreFoundation's do on
Darwin, over ICU's C API (`udat`, `udatpg`, `unum`): each keeps its
settings and opens an ICU formatter from them. The ICU is the Swift
toolchain's, swift-foundation's build of Apple's ICU, so calendars and
formatters share one copy and Apple's data. The current locale comes from
`LANG`, or is `en_US`, an iOS device's own, when that names none, and time
zone abbreviations are English short names ("EST") as on Darwin.

**URL loading** maps `NSURLSession` to Swift's `URLSession`, from
swift-corelibs-foundation's FoundationNetworking, which runs on libcurl.
PerryURLLoading alone imports that Foundation and wraps its requests,
responses, cookies, configurations, sessions and tasks in types of its
own, so the CFNetwork provider defining `NSURLSession` and its companions
never sees corelibs' classes of the same names. A session's delegate and
its tasks' completion handlers run on its delegate queue, an
`NSOperationQueue`: each event corelibs delivers hops there and waits,
which keeps events in order and a download's file in place until its
handler returns. Delegates' completion handlers are Darwin blocks made
from Swift closures. Where corelibs differs from Darwin, Darwin wins:
status code phrases, suggested file names, session-only cookies, request
equality, and a task's state and byte counts by the time it completes.
Foundation re-exports CFNetwork as on Darwin, so the provider loads only
when a program uses it. `NSURLConnection` runs on the same `URLSession`: its
delegate hears from it on the run loop of the thread that made or started
it, through `-performSelector:onThread:withObject:waitUntilDone:`, or on its
delegate queue, first with `connection:willSendRequest:redirectResponse:`
for the original request, and nothing after `-cancel`.

**Security** runs on swift-crypto, CryptoKit's API with its own BoringSSL,
and swift-certificates. Elliptic-curve keys are CryptoKit's P-256, P-384
and P-521 keys in X9.63 form, as Apple's external representation is;
digest variants sign through a `Digest` carrying the caller's bytes. RSA's
encodings (PKCS #1 v1.5 and PSS signatures, PKCS #1 v1.5, OAEP and raw
encryption) are written out over the two raw operations, the private one
by BoringSSL's blinded blind-signing operation and the public one by a
Montgomery exponentiation, so every RSA algorithm Security names works
rather than the subset `_CryptoExtras` offers. ECIES follows Apple's
construction: an ephemeral key, the X9.63 KDF over the shared secret, and
AES-GCM. Trust evaluation runs swift-certificates' verifier and reports
failures with Security's codes: a host name mismatch when the chain alone
verifies, an expired or not-yet-valid certificate, or an untrusted chain.
The keychain keeps items in a JSON file under `~/Library/Keychains` (or
`$PERRY_KEYCHAIN`), locked while each call reads and writes it. Keys,
certificates, trusts and policies are Objective-C objects, so `CFRetain`,
`CFRelease`, `CFEqual` and `CFGetTypeID` work on them.

**Core Data** is a client of libobjc and Foundation too, and keeps its
data in [CoreModel](https://github.com/PureSwift/CoreModel): it reads a
compiled model with Foundation's `NSKeyedUnarchiver`, converts it to a
CoreModel model, and saves each context's changes to a CoreModel store,
`SQLiteDatabase` for SQLite and `InMemoryModelStorage` for every other
type. Fetch requests become CoreModel fetch requests, their `NSPredicate`
converted to CoreModel's predicate. Accessors for a subclass's `@dynamic`
properties are added when a coordinator takes the model, typed from the
property's declaration, which the runtime reads from the class's
property lists. As on Darwin, deletions propagate when changes are
processed, before a fetch or save, and errors' descriptions that their
user info lacks come from a user info value provider.

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
