# XCTest

Perry's Swift overlay of XCTest for Mac apps' tests: the `XCTAssert` family,
`XCTFail`, `XCTUnwrap`, `XCTSkip` and its conditions, expected failures,
`XCTIssue` (the Swift value of XCTest's `XCTIssue` class), activities,
waiting on expectations from async code, async teardown blocks,
`XCTKeyPathExpectation` and typing a key with modifiers into an
`XCUIElement`. It is written for Perry from the API in the platform's
`XCTest.swiftmodule/x86_64-apple-macos.swiftinterface` (which Xcode builds
into `libXCTestSwiftSupport.dylib`) and replaces the Swift 5.0 overlay
`libswiftXCTest.dylib` Xcode ships as a file.

It is compiled as the module `XCTest` over XCTest's Objective-C headers, as
Apple builds its overlays. XCTest isn't in the SDK but in the platform's
`Developer/Library/Frameworks`, which `swiftc-flags` points the compiler and
linker at (the selected Xcode's), and links XCTest outside the shared
cache (`-not_for_dyld_shared_cache`), as it isn't in it:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh XCTest <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay (Xcode has no
`libswiftXCTest.tbd`) reports nothing missing. Against
`libXCTestSwiftSupport.dylib`, which programs built with today's Xcode link
instead, about 470 symbols are missing: its Swift Testing interop
(`Test.Case`, `SwiftTestingTestCase`…), the private `XCUIDevice`
registration and `accommodate…` calls, screenshot attachments and the
`Codable`/`CaseIterable` conformances of XCUIAutomation's enums, none of
which the interface declares.

How it works: an assertion that fails is recorded on the test case running
(`_XCTCurrentTestCase`, exported but undeclared, through `@_silgen_name`)
by XCTest's `_XCTPreformattedFailureHandler`, with the same messages as the
Objective-C macros (`XCTAssertEqual failed: ("1") is not equal to ("2")`);
an error thrown by an assertion's expressions is recorded as unexpected.
`XCTSkip` is the error XCTest skips a test for: domain `XCTestErrorDomain`,
code 106, and user info asking it to be ignored with an
`XCTSkippedTestContext` (XCTest's own class, made through the runtime, as
no header declares it).

Differences from Apple's:

- the Objective-C exceptions an assertion's expressions raise aren't caught
  (Swift can't catch them), so they end the test as XCTest's own handler
  sees them;
- `runActivity(named:block:)` calls XCTest's `+runActivityNamed:block:`;
  where activities are disallowed XCTest records that as a failure (Apple's
  overlay stops the process);
- the async `fulfillment(of:timeout:enforceOrder:)` waits with an
  `XCTWaiter` on the caller's thread, as the synchronous `wait(for:)` does;
- `XCTKeyPathExpectation`'s asynchronous filters run in a `Task` and
  fulfill the expectation when they return true.
