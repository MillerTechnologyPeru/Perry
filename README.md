# Perry
 
Run iOS and macOS apps on Linux, natively.
 
Perry loads prebuilt Mach-O binaries into a Linux process and binds their
imports to Linux shared libraries ("providers") that implement Apple's
libraries and frameworks behind the Darwin ABI. There is no CPU emulation
and no Darwin kernel layer: an app's own code runs on the host CPU, and
everything it calls is ordinary Linux code, mostly written in Swift.
 
> Frameworks are Linux ELF code; only the ABI boundary is Darwin.
 
## What runs
 
| Mach-O binary | Linux host | Loader | Notes |
| --- | --- | --- | --- |
| arm64 iOS and macOS | arm64 | `perry` | C, Objective-C, C++, Swift and SwiftUI |
| armv7 and armv6 iOS | arm64 with AArch32 at EL0 | `perry32` | C, Objective-C and C++; iOS 2 through 10; no Swift |
| x86_64 macOS | x86_64 | `perry` | AppKit apps and games |
| i386 macOS | x86_64 | `perry32` | Cocoa, Carbon and QuickTime era apps and games |
 
`perry` reads a program's architectures and hands 32-bit ones to `perry32`
(beside it, or at `$PERRY32`). arm64e and FairPlay-encrypted binaries are
rejected with a clear error, so App Store apps must be decrypted first.

The [compatibility database](https://millertechnologyperu.github.io/Perry/compatibility/)
lists the apps and games tested so far and how far each one gets.
 
## Frameworks
 
Providers are named by convention: `UIKit.framework/UIKit` maps to
`libPerryUIKit.so`, `/usr/lib/libSystem.B.dylib` to `libPerrySystem.so`.
 
| Area | Provided | Built on |
| --- | --- | --- |
| System | libSystem, libobjc, libdispatch, libc++, CommonCrypto, libcompression, unified logging, Mach ports | glibc, Linux libdispatch, LLVM libc++ built as Apple's, OpenSSL |
| Foundation | Foundation and CoreFoundation, toll-free bridged; CFNetwork and `NSURLSession`; Bonjour | swift-foundation, ICU, swift-corelibs `URLSession` over libcurl, Avahi |
| Swift | Swift apps; Combine; SwiftUI; CryptoKit, WidgetKit, ActivityKit, AppIntents, StoreKit and other Swift-only frameworks | OpenCombine, OpenSwiftUI |
| UIKit | Views, controls, Auto Layout, storyboards and nibs, table and collection views (compositional layouts, diffable data sources), navigation, search, text, scroll physics, touch, keyboard and game pad input | QuartzCore compositor on SDL3 |
| AppKit | Windows, menus, nibs (keyed, NIBArchive and typedstream), documents, bindings, tables and outlines, toolbars, text views, Auto Layout; Carbon, QuickTime and AGL for pre-Cocoa games | The same compositor on SDL3 |
| Graphics | CoreGraphics, CoreText, CoreImage, ImageIO, QuartzCore, asset catalogs, SF Symbols | Silica over Cairo, FreeType, Fontconfig, libpng, libjpeg-turbo, giflib, libwebp, libheif |
| GPU | OpenGL ES 1, 2 and 3, desktop OpenGL, GLKit; Metal and MetalKit; SceneKit, SpriteKit, GameplayKit; OpenCL | The host's GL drivers; Vulkan through metal2vulkan |
| Media | AVFoundation, AVKit, AudioToolbox, CoreAudio, OpenAL, MediaPlayer, VideoToolbox, CoreMedia, CoreVideo | GStreamer, OpenAL Soft |
| Web | `WKWebView`, `SFSafariViewController`, `ASWebAuthenticationSession`; JavaScriptCore | WPE WebKit, WebKitGTK's JavaScriptCore |
| Data | Core Data, SQLite, libxml2, zlib, bzip2, Expat, xar, iconv | CoreModel, and Linux's builds of the same libraries behind ABI thunks |
| Security | Keychain, keys, certificates, trust evaluation, Secure Transport, LocalAuthentication | swift-crypto, swift-certificates |
| Location and maps | CoreLocation, MapKit on iOS and macOS, SwiftUI `Map` | GeoClue, MapLibre |
| Devices | CoreBluetooth, GameController (MFi), IOKit's HID manager, CoreTelephony, SystemConfiguration | BlueZ over D-Bus, SDL3 |
| Services | GameKit, StoreKit, CloudKit, UserNotifications, CoreSpotlight, Intents, CallKit, PushKit, CarPlay, WatchConnectivity and others | Local stand-ins: no Apple account, store or push service |
| Steam | `libsteam_api.dylib` | The Linux Steam client's `steamclient.so` |
| Math | Accelerate: vDSP, vForce, vImage, BLAS, LAPACK | OpenBLAS |
 
## Quick start
 
On arm64 or x86_64 Linux with Swift 6.4:
 
```sh
swift build
.build/debug/perry path/to/App.app [arguments...]
```
 
The `Dockerfile` (Debian 13) lists the system libraries the providers bind
to, including SQLite 3.54 built with Apple's options and libc++ built with
Apple's ABI choices. To build and test in that image, from a Mac or Linux
host of either architecture:
 
```sh
Scripts/docker-test.sh [swift test arguments...]
```
 
### 32-bit programs
 
`perry32` and its providers are a second build for a 32-bit target:
 
- armv7 iOS: `Scripts/build-armv7-*.sh`, described in
  [Documentation/armv7.md](Documentation/armv7.md)
- i386 macOS: `Scripts/build-i386-*.sh`
### Metal
 
Metal runs on Vulkan 1.3 through `libmetal2vulkan.so`, a separate library
that the Metal provider opens at run time. Shaders are compiled from Metal
source on demand; `Scripts/compile-metal-sources.sh` and
`Scripts/extract-unity-metal-sources.py` prepare them ahead of time. See
[Documentation/Plans/metal-on-vulkan.md](Documentation/Plans/metal-on-vulkan.md).
 
## Usage
 
```sh
perry [--report] [--strict] <executable | App.app> [arguments...]
```
 
- `--report` loads and binds without running, then prints dependencies,
  unresolved and weak-missing imports by library, and the Objective-C
  classes, protocols and selectors the program refers to. This is the API
  to-do list for an app.
- `--strict` fails on the first unresolved non-weak import.
Each app gets a home directory at `~/.perry/Containers/<bundle id>`.
 
| Variable | Effect |
| --- | --- |
| `PERRY_SWIFT_RUNTIME` | Directory with Swift runtime and frameworks, compiled on macOS against Darwin Swift |
| `PERRY_LIBRARY_PATH` | Extra directories to search for providers |
| `PERRY_CONTAINER` | The app's home directory |
| `PERRY_DOCUMENTS`, `PERRY_LIBRARY`, `PERRY_CACHES`, `PERRY_PREFERENCES`, `PERRY_TMP` | Keep those container directories elsewhere, as a port keeps saves beside it |
| `PERRY_DEVICE_MODEL`, `PERRY_OS_VERSION` | The device and system version reported to the app |
| `PERRY_UIKIT_SCREEN`, `PERRY_UIKIT_DISPLAY_SCALE`, `PERRY_UIKIT_ORIENTATION` | Screen size, scale and orientation |
| `PERRY_UIKIT_GAMEPAD_TOUCH` | Play touch games with a game pad |
| `PERRY_LOCATION` | A fixed location for CoreLocation |
| `PERRY_UNIMPLEMENTED=continue` | An unresolved function reports itself once and returns 0 |
| `PERRY_OBJC_UNRECOGNIZED=continue` | Likewise for unrecognized selectors |
| `PERRY_TRACE=load,bind,init` | Trace loading (`all` for everything) |
| `PERRY_CRASH_REPORT=1` | Print registers and frames on a fatal signal |
| `PERRY_PROFILE=<path>` | Sample the main thread's stacks; `Scripts/perry-profile.py` reports them |
 
`perry --help` lists the rest, and most providers have a
`PERRY_<FRAMEWORK>_TRACE` variable of their own.
 
`DYLD_INSERT_LIBRARIES` loads Mach-O libraries with the program, as dyld
does.
 
## How it works
 
**Loader.** `perry` maps Mach-O images itself: chained fixups and classic
dyld opcodes, two-level namespaces, export tries with re-exports,
`@rpath`, initializers, thread-local variables, C++ unwinding and run-time
loading. Images are placed from 4 GB up, below 2^47, because Darwin's
runtimes keep pointers in 47 bits.
 
**Providers.** A provider exports ELF symbols under the exact Mach-O names
(`_printf`, `_OBJC_CLASS_$_UIView`), so binding is a `dlsym` by name, and
only symbols the provider itself defines count. A Darwin name can never
bind to an unrelated glibc symbol by accident.
 
**ABI at the boundary.** Where Darwin and Linux disagree, a provider
converts: variadic arguments (on the stack on Apple's arm64), `errno`
numbering, struct layouts (`stat`, `dirent`, `FILE`, pthread types, socket
addresses), flag values, and on armv7 the alignment and register rules
described in [Documentation/armv7.md](Documentation/armv7.md). Functions
whose ABI is identical are a single branch to the Linux one.
 
**Objective-C.** `libPerryobjc` is an Objective-C runtime written in Swift,
with `objc_msgSend` in assembly. It reads the metadata clang and ld64 emit
and handles categories, protocols, `+load`, ARC, weak references,
exceptions and forwarding.
 
**Frameworks in Swift.** Foundation, UIKit, AppKit and the rest are Swift
code that defines Objective-C classes through macros, with no Objective-C
compiler involved:
 
```swift
@ObjCClass("NSMutableString")
public class NSMutableString: NSString {
    @ObjCMethod("appendString:")
    func append(_ other: String) { storage.value += other }
}
```
 
**Wrapped C libraries.** Libraries that exist on both systems (libxml2,
zlib, SQLite and others) bind to the Linux build, with thunks only where
the ABI differs.
 
<!-- TODO: move the current README's per-framework design notes (Foundation,
     libdispatch, URL loading, Security, Core Data, UIKit, wrapped libraries,
     the macro reference) to Documentation/Design.md and link it here. -->
 
## Testing
 
Tests build Mach-O fixtures with upstream LLVM's `clang` and `ld64.lld`
(`$PERRY_LLVM_BIN`), and are skipped without them. Fixture apps under
`Tests/Fixtures/Darwin` are built on a Mac against the real SDK, where
their output is recorded with Apple's frameworks; Perry's output must
match it byte for byte.
 
```sh
Scripts/build-darwin-fixtures.sh   # on a Mac
Scripts/docker-test.sh --filter DarwinFixtureTests
```
 
## Limits
 
- No arm64e and no encrypted binaries
- No Swift on 32-bit; SwiftUI is OpenSwiftUI, which covers part of Apple's
- Services that need Apple's servers (the App Store, Game Center, iCloud,
  push, Siri) answer as signed out or unavailable
- Coverage is driven by the apps brought up so far, so an untested app
  will usually hit missing API first; `--report` shows what
## Related projects
 
- [PureSwift](https://github.com/PureSwift) provides Silica, Cairo, SDL,
  CoreModel and other packages Perry builds on.
  
## License
 
MIT. The loader is written from Apple's published Mach-O format
descriptions. `libmetal2vulkan` is LGPL and stays a separate, replaceable library.
