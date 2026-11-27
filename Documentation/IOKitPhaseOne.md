# IOKit Phase 1 validation

Validated on 2026-11-27 with Debian 13 ARM64 in Parallels, Swift 6.4.2,
and Darwin ARM64 executables compiled with the macOS SDK.

| Check | Result |
| --- | --- |
| Isolated PerryIOKit build with macro and export generator | Passed |
| Strict Darwin IOKit ABI fixture | Passed: UUID, model, en0 MAC, power snapshot, assertion create/release |
| Native logind idle inhibitor | Appeared while held and disappeared after release |
| HardwareKit Linux tests, including private D-Bus and real logind | 48 passed |
| AppKit initialization and IOKit identity lookup | Passed |
| SwiftUI Text construction | Overlay built and Text metadata resolved; blocked by Darwin Swift runtime libc++ dependency |
| Electron startup (OpenMTP ARM64) | Blocked during binding: unresolved `_freopen` in libSystem; several framework providers unavailable |

Electron's dependency report also lists missing IOKit APIs including
`IOServiceOpen`, `IOConnectCallMethod`, `IOConnectCallStructMethod`,
`IOHIDDeviceCreate`, report access/callbacks, and `IOPMCopyCPUPowerStatus`.
Several belong to Phases 2 and 3. The plan's Electron milestone therefore
requires functionality beyond Phase 1's registry and power-source surface.

The VM exposes no battery, UPS, or temperature sensors. Those mappings have
filesystem-fixture coverage, not live-hardware validation here. AppKit coverage
is initialization and an identity query, not a rendered UI. The full Perry
package and SwiftUI/Electron startup milestone are not yet validated.

## Reproduction

On macOS, run `sh Scripts/build-iokit-fixtures.sh`. Copy the resulting
`.build/iokit-fixtures/iokit_*` executables to the ARM64 Linux host.
Set these paths to the rebuilt IOKit provider, baseline Perry products,
Linux Swift toolchain, and Darwin Swift runtime:

```sh
export PERRY_LIBRARY_PATH="$IOKIT_PRODUCTS:$PERRY_PRODUCTS"
export LD_LIBRARY_PATH="$SWIFT_TOOLCHAIN/usr/lib/swift/linux"
"$PERRY_PRODUCTS/perry" --strict ./iokit_phase1
"$PERRY_PRODUCTS/perry" --strict ./iokit_appkit
PERRY_SWIFT_RUNTIME="$DARWIN_SWIFT_RUNTIME" \
    "$PERRY_PRODUCTS/perry" --strict ./iokit_swiftui
```

The core fixture holds its assertion for eight seconds, releases it, and
remains alive for four more seconds. During that interval,
`systemd-inhibit --list --no-pager` should show and then remove the reason
`Perry Phase 1 smoke test` with `WHAT=idle` and `MODE=block`.

Run HardwareKit's optional Linux integration tests with:

```sh
dbus-run-session -- env HARDWAREKIT_DBUS_TEST_BUS=1 HARDWAREKIT_LOGIND_TEST=1 swift test
```

The logind test requires the system bus and permission to inhibit idle sleep.
It also checks release before asynchronous Inhibit replies arrive.
Inhibition is acquired asynchronously: an assertion handle alone does not
confirm that the service accepted it. No policy changes or root privileges
were needed for idle inhibition on this VM.

## Remaining work

Resolve the remaining SwiftUI runtime symbols, Electron framework/loader
dependencies, and IOKit HID/user-client APIs, then rerun startup checks. Validate batteries
and thermal sensors on hardware exposing them before claiming live coverage.

## SwiftUI overlay follow-up

The overlay built on macOS with `Scripts/build-swiftui.sh`, using the native
SwiftPM build system to keep ARM target flags out of host macro compilations.
The output is an ARM64 Darwin (iOS-targeted) SwiftUI framework with 1,176 ABI
aliases and exported `_$s7SwiftUI4TextVN` metadata. The script also creates the
versioned framework path used by the macOS probe.

After deployment to Linux, the strict probe loads this framework and proceeds
to a missing libc++ symbol in the Darwin Swift runtime:
`__ZNSt3__112__next_primeEm`. It also reports missing Combine, CoreTransferable,
Symbols, MobileGestalt, CoreImage, Spatial, and LocationEssentials dependencies.
The overlay build is complete; SwiftUI runtime execution is not yet passing.

## Complete ARM64 overlay build and libc++

All ARM64 steps in `Scripts/build-swift-overlays.sh` have now built on macOS,
including Foundation, optimized SwiftUI, Combine, and the five SwiftUI
cross-import frameworks. Foundation uses the native SwiftPM build system to
separate target objects from host macros. The MapKit, StoreKit,
AuthenticationServices, and AVKit cross-import scripts now read SwiftUI's
modules from that build layout.

`Scripts/build-libcxx.sh` builds Darwin ARM64 libc++ with libc++abi statically
included, using a pinned Swift LLVM revision and Xcode's iOS SDK. Its output
is `libc++.1.dylib`, with install name `/usr/lib/libc++.1.dylib`; it exports
`__ZNSt3__112__next_primeEm` and `___cxa_throw`.

```sh
Scripts/build-swift-overlays.sh
Scripts/build-libcxx.sh
```

The output directory is `.build/perry-swift-runtime`. Validation confirmed
all 68 expected Mach-O libraries (67 overlays/frameworks plus libc++) are
ARM64, along with ten Darwin-library aliases. These are iOS-targeted Darwin
libraries built on macOS for the ARM64 Perry runtime; the x86_64 overlay set
was not built in this run.

The complete directory was copied to the Linux VM. With a loader rebuilt
from current sources and this directory added to `PERRY_LIBRARY_PATH`, the
strict SwiftUI probe gets past `__next_prime` and stops at:

```text
perry: error: .../libswiftCore.dylib: unresolved symbol __ZdlPvSt19__type_descriptor_t from <weak>
```

It also reports unavailable `libSpatial.dylib`, `libMobileGestalt.dylib`, and
CoreTransferable. The build milestone is complete; SwiftUI execution still
requires runtime compatibility work.

## SwiftUI dependency and libc++ compatibility fixes

The libc++ build now includes LLVM's Apple vendor allocation shims as a tracked
CMake link dependency. All ten typed new/delete exports are present, including
`__ZdlPvSt19__type_descriptor_t`. SwiftUI no longer links MobileGestalt, since
its built objects do not import any of that library's symbols. The ARM64 bulk
overlay build now supplies CoreTransferable and the empty `libSpatial.dylib`
load dependency (the SDK's libSpatial stub has no exports).

CoreTransferable supplies the protocol metadata, Never witnesses and URL
conformance imported by this SwiftUI build. Its representation implementation
is deliberately limited; see `Darwin/CoreTransferable/README.md` for supported
operations and exclusions. Three native Swift Testing cases pass: URL data
round-trip, invalid UTF-8 rejection, and directional conversion capabilities.

PerrySystem now supports process-local 32/64-bit ulock compare-and-wait,
wake-one/wake-all and relative microsecond timeouts. It rejects unsupported
shared/ownership/cancellation modes. Additional libc++ imports are supplied
through the existing Darwin stdio adapters: locale-format varargs, wide FILE
operations, long-double conversions, message catalogs, copyfile state lifecycle,
and utimensat's Darwin flag/time-sentinel translation.

`sh Scripts/build-iokit-fixtures.sh` also builds `ulock` and `libcxx_compat`.
Both produce the same successful output natively on macOS and under the
current ARM64 Linux loader with rebuilt PerrySystem and Darwin libc++:

```text
ulock: mismatch, timeout, wake-all, wake-one, and address isolation passed
libc++: 42
```

The libc++ probe exercises hash-table allocation, atomic waiting, formatted and
wide-character I/O, timestamps, copyfile state allocation and string streams.
Use the same environment as the IOKit fixtures, adding the Darwin runtime
directory to `PERRY_LIBRARY_PATH`, and run each executable with `perry --strict`.
The full SwiftUI probe remains a separate check; passing the C++ tests does not
establish SwiftUI startup or rendering support.

For the final Linux rerun, the loader and PerrySystem, Perryobjc, PerryNetwork,
and PerryFoundation providers were rebuilt from current source. Foundation's
swift-cmark dependency used the Dockerfile's pinned revision in a local build
prefix. The strict SwiftUI probe now stops at:

```text
perry: error: .../libswiftos.dylib: unresolved symbol _OBJC_CLASS_$_OS_os_workgroup from /usr/lib/libSystem.B.dylib
```

There are no unavailable-library warnings for Spatial, MobileGestalt or
CoreTransferable. Report-only loading lists 154 unresolved import entries in
this VM's mixed provider set (some other providers remain prebuilt), down from
576 before refreshing providers and adding these fixes. This is an import
count, not a count of distinct missing APIs. Workgroup support is the next
strict blocker; the report also includes UIKit/CoreGraphics and other framework
symbols. The original dependency fixes and C++ execution probes pass, but the
full SwiftUI smoke test still does not pass.
