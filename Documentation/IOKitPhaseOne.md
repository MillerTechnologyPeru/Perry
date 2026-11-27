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
| SwiftUI Text construction | Blocked: SwiftUI framework and Text metadata unavailable |
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

Provide the missing SwiftUI runtime, Electron framework/loader dependencies,
and IOKit HID/user-client APIs, then rerun startup checks. Validate batteries
and thermal sensors on hardware exposing them before claiming live coverage.
