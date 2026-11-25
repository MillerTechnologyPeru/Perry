# Plan: SDK symbol coverage and generated stubs

2026-11-25

## Goal

Know, for every public framework in the macOS and iOS SDKs, which of its
symbols Perry provides and which it doesn't, and generate the missing ones
an app needs as stubs written for Perry. Foundation and AppKit come first;
the same tools then cover UIKit and the other 330 frameworks.

A symbol here is anything a compiled program can reach by name:

- C functions and data (`NSLog`, `NSApplicationDidFinishLaunchingNotification`).
- Objective-C classes (`_OBJC_CLASS_$_NSToolbar`), their metaclasses and
  exported ivar offsets (`_OBJC_IVAR_$_…`).
- Objective-C methods and property accessors, by class and selector. These
  are not in any symbol table; a program reaches them by message send.
- Protocols, which a program's class list adopts by name.
- Swift symbols (`$s…`), now exported by the frameworks themselves
  (Foundation.framework exports 14,794 of them, AppKit.framework 7,330).

Enum cases, macros, typealiases and struct layouts are compile-time only and
need no export; the scan records them only to type method signatures.

## What there is today

| Piece | What it does |
|---|---|
| `perry --report` (`Sources/PerryLoaderCore/report.c`) | Per app: each import resolved, unresolved or weak-missing, and each Objective-C class the app references. No selectors. |
| Loader unresolved stubs (`symbols.c`, "Unresolved stubs") | A call to a missing C import reports its name and aborts; `PERRY_UNIMPLEMENTED=continue` reports it once and returns 0. |
| `Runtime.notForwarded` (`PerryObjCRuntime/Runtime.swift`) | An unrecognized selector is fatal; `PERRY_OBJC_UNRECOGNIZED=continue` reports it once per class and selector and answers zero (zeroed memory for a struct return). |
| `Scripts/check-overlay.sh` | Lists Swift symbols a reference dylib or `.tbd` exports that one of Perry's overlays doesn't. |
| `PerryProviderGenerator` | Already parses every `@ObjCClass`, `@ObjCCategory`, `@ObjCProtocol` and `@ObjCConstants` in a provider to write its start-up. |

What Perry covers now, measured against the macOS 27.2 SDK (names only, so
an implemented method may still be incomplete):

| | Foundation | AppKit |
|---|---|---|
| Classes in the headers | 273, 224 in Perry (82%) | 322, 180 (56%) |
| Classes in the `.tbd` (no leading `_`) | 386, 207 | 593, 160 |
| Methods in the headers | 2,702, 2,054 by name (76%) | 4,317, 1,435 (33%) |
| Property getters | 1,608, 1,185 (74%) | 3,139, 1,558 (50%) |
| Property setters | 552, 452 (82%) | 1,842, 962 (52%) |
| C functions and data in the `.tbd` | 1,067, 471 (44%) | 2,525, 439 (17%) |

The iOS 27.2 Foundation `.tbd` has 319 classes and 819 C exports; UIKit's is
a shell re-exporting UIKitCore and the private frameworks, so its scan reads
the re-exported documents.

Numbers came from `clang -extract-api` over each framework's headers and a
parse of the `.tbd` stubs; the scripts below make them repeatable.

## Decisions

- **The public SDK only.** Inputs are the SDK's headers, `.tbd` stubs and
  `.swiftinterface` files. No framework binaries, no private headers, no
  class dumps. Private API an app calls is found by the app scan and
  written by hand, as now.
- **Names and signatures, never Apple's text.** Generated stubs carry the
  declaration's name, selector, types and availability, written for Perry,
  like the overlays in `Darwin/`. Header comments are never copied.
- **SDK dumps stay out of the repository.** The scan's JSON goes to
  `.build/sdk-scan/`. What is committed is the tools, the generated stubs
  and a short coverage summary.
- **Stubs where needed, not everywhere.** A stub changes what a program
  sees: `respondsToSelector:`, `NSClassFromString` and a weak import's
  address all start answering yes, and code that checks for new API takes
  the new path. So stubs are generated for symbols real apps use, ranked by
  how many use them, never wholesale for a framework.
- **Swift tools, like `extract-symbols`.** Pure Swift with Foundation, so
  diffing and generation run on the Duet 3 and the other Linux hosts. Only
  the SDK scan needs the SDK: on a Mac with Xcode, or in perry-dev
  (`Scripts/docker-darwin.sh`), whose clang must support `-extract-api`.

## Phase 0: the SDK scan

`Scripts/sdk-scan/` (a Swift script package), subcommand `scan`:

    sdk-scan scan --sdk <SDK path> --framework Foundation --out .build/sdk-scan/macosx27.2/Foundation.json

For each framework it writes one manifest:

1. **Exports**, from the `.tbd`: per target (x86_64, arm64e; armv7 and
   i386 from older SDKs later), every C symbol, Objective-C class, ivar,
   EH type and Swift symbol, dropping `$ld$` directives. Re-exported
   libraries are followed, so UIKit's manifest is UIKitCore's public part.
2. **Declarations**, from `clang -extract-api` over every header in
   `Headers/` (all of them as inputs; the umbrella alone yields nothing):
   classes with superclasses and adopted protocols, protocols, methods and
   properties (class and instance, getter and setter names from the
   declaration, readonly), functions, variables, and their types,
   availability and deprecation per platform. Categories attach to the
   class they extend, whichever framework declares them (AppKit adds to
   `NSString` and `NSAttributedString`).
3. **Swift API**, from the `.swiftinterface` of the framework module when
   there is one: each declaration and its mangled name, which
   `check-overlay.sh`'s demangling already pairs with the `.tbd`.

Each entry records which headers and which SDK it came from, so macOS and
iOS manifests merge into one view of a framework with per-platform
availability. Perry's Foundation serves both, so the iOS-only and
macOS-only parts are both visible.

Done when: Foundation and AppKit manifests from macOS 27.2 and the
Foundation manifest from iOS 27.2 reproduce the numbers above.

**Status (2026-11-25): done.** `Scripts/sdk-scan` is its own SwiftPM
package with no dependencies:

    swift build -c release --package-path Scripts/sdk-scan
    Scripts/sdk-scan/.build/release/sdk-scan scan --sdk "$(xcrun --sdk macosx --show-sdk-path)" \
        --framework Foundation --framework AppKit
    Scripts/sdk-scan/.build/release/sdk-scan summary .build/sdk-scan/*/*.json

It reproduces the classes (273 and 386 for Foundation, 322 and 593 for
AppKit; 319 in iOS Foundation's `.tbd`) and the C exports (1,073 and
2,535; 819 on iOS). Two numbers differ from the table, for good reasons:

- Header methods are 2,799 for Foundation and 4,468 for AppKit, not 2,702
  and 4,317: `--emit-extension-symbol-graphs` keeps the categories a
  framework adds to classes declared elsewhere (Foundation's on
  `NSObject`, AppKit's on `NSString` and `NSAttributedString`), which the
  first measurement lost.
- The table's 1,067 and 2,525 C names counted ones with a leading
  underscore of their own (`_NSConcrete…` in C), private by convention;
  without them there are 918 and 2,190 (692 on iOS).

UIKit's own `.tbd` document exports nothing: its 2,111 classes and 4,584 C
names are in UIKitCore and six other libraries it re-exports, which the
manifest keeps as their own documents. A scan takes 9 to 16 seconds per
framework, most of it in `swift-symbolgraph-extract`; a manifest is 6 to
11 MB.

Its 17 tests pass on the Mac and on Linux (the HP laptop). With
`SDK_SCAN_CLANG` set to the Swift 6.4.2 toolchain's clang, the end-to-end
scan of the fake SDK also runs on Linux, so a full scan can run off the
Mac from a copy of the SDK.

Not recorded yet: whether a protocol's method is `@optional` (the symbol
graph doesn't say; Phase 5 needs it and will read it from the header at
the declaration's line), and the category's name for a category member.

## Phase 1: what Perry provides

Two inventories, written in the same shape as the SDK manifest:

1. **Static**, from `PerryProviderGenerator --manifest <out.json>`: the
   generator already sees every `@ObjCClass`, `@ObjCMethod`,
   `@ObjCClassMethod`, `@ObjCCategory`, `@ObjCProtocol` and
   `@ObjCConstants` declaration; it also lists `@c` and `@DarwinC` names
   (written with their leading `_`, as in `@c(_NSStringFromClass)`) and the
   `#if` platform each is under. This replaces the regex counts above.
2. **Running**, from a `PERRY_DUMP_RUNTIME=<file>` switch in
   PerryObjCRuntime: after the providers start, every registered class with
   its superclass, protocols and method lists, and every exported provider
   symbol. It catches what the static view misses: methods added at
   start-up, classes built with `objc_allocateClassPair`, providers' own
   `providerSymbol` lookups.

Swift symbols come from `nm` on the built overlays, as `check-overlay.sh`
does now.

Done when: both inventories for PerryFoundation and PerryAppKit agree,
apart from what the running one adds, and list the 207 and 160 classes.

## Phase 2: the coverage diff

`sdk-scan diff <SDK manifests> <Perry inventory>` writes, per framework:

- missing classes, with their superclass and whether Perry has the
  superclass (a subclass can only be stubbed under one it has);
- missing methods and accessors per class Perry has;
- missing C functions and data;
- missing protocols;
- missing Swift symbols (the `check-overlay.sh` list, grouped by type);
- **mismatches**: a class whose superclass differs from the SDK's, a
  property Perry declares read-write that is readonly, a method Perry
  registers on a different class than the SDK declares it on.

Output is JSON for the next phases and a Markdown summary, one table per
framework like the one above, committed as
`Documentation/sdk-coverage.md` and regenerated by the same command.
Deprecated and unavailable-on-the-platform declarations are counted
apart, since most are never needed.

## Phase 3: what apps need

Coverage alone says nothing about priority. The app scan does:

1. **Extend `perry --report`** with `objc-selector-referenced` lines, from
   each image's `__objc_selrefs`, and `objc-protocol-referenced`, from
   `__objc_protorefs` and its classes' protocol lists. Selectors carry no
   class, so the diff pairs each with every SDK class that declares it.
   Also `objc-superclass` for each of the app's classes whose superclass is
   an SDK class: the ones a missing class or ivar breaks at load.
2. **`sdk-scan demand <report>...`** reads many reports and ranks every
   missing symbol by how many apps reference it, then by how many images.
3. **The corpus**: the Mac apps already brought up (TextMate, NetNewsWire,
   MacDown, BBEdit, Discovery, the Mac app queue) and the decrypted IPAs
   for Foundation on iOS, run with `perry --report` on any host.

A referenced selector is not a called one. Runs with
`PERRY_UNIMPLEMENTED=continue` (Phase 4) give the called set, and that
outranks references.

Done when: one ranked list for Foundation and AppKit from at least ten Mac
apps and twenty IPAs.

## Phase 4: runtime support for stubs

Before generating any, give stubs one behaviour across C and Objective-C:

- **Unrecognized selectors already continue** with
  `PERRY_OBJC_UNRECOGNIZED=continue` (`Runtime.notForwarded`), reported
  once per class and selector, as the loader's C stubs are with
  `PERRY_UNIMPLEMENTED=continue`. Phase 3's called set comes from runs
  with both.
- **A stub trace.** `PERRY_TRACE=stub` reports each generated stub the
  first time it runs; `PERRY_UNIMPLEMENTED=abort` makes generated stubs
  fatal too, for finding where an app depends on one.
- **`Stubs.called(_:)`** in PerryObjCInterop, the one call every generated
  body makes: the trace, the abort switch, and a count for the report.

## Phase 5: generating Foundation and AppKit stubs

`sdk-scan stubs --demand <ranked list> --top N --framework AppKit` writes
Swift into the provider, one file per class or file group:
`Sources/PerryAppKit/Stubs/<Class>.swift`, each headed as generated, with
the command that made it. Hand-written code always wins: a symbol Perry
gains by hand drops out of the next generation, and a generated file is
deleted once it has none left.

What gets generated, by kind:

| Missing | Generated |
|---|---|
| Class whose superclass Perry has | `@ObjCClass` with the SDK's superclass and protocols, the referenced methods below, and `init`/`initWithCoder:` that call super. Lets an app's subclasses and nib objects load. |
| Class whose superclass is missing too | The superclass first, recursively, up to one Perry has. |
| Method or accessor on a class Perry has | `@ObjCMethod` in an extension, typed from the header, body `Stubs.called` and the neutral value: `nil`, `0`, `NO`, a zero struct, `self` for an `init…` that returns `instancetype`; a setter stores into an associated value so the getter returns it. |
| Exported ivar offset | Only reported: an ivar has to be a real stored property, written by hand. |
| C function | `@c(_Name)` with the neutral value, under the same rules. |
| String constant | An `@ObjCConstants` entry. Its value defaults to the constant's own name, which most of Foundation's and AppKit's are; ones whose value isn't are checked on a Mac against the running system before commit and listed in the generator's exceptions. |
| Protocol | `@ObjCProtocol` with its methods, required and optional. |

Every generated declaration says it is a stub, in two places, so none is
mistaken for an implementation:

- a doc comment on the declaration: `/// Stub, to be implemented: …`, with
  what it returns until then (`returns nil`, `stores the value only`);
- the body's first statement, `Stubs.called("-[NSFoo bar:]")`, which
  doubles as the marker `grep -rn Stubs.called Sources` lists as the
  stubs left to implement.

Replacing a stub by hand means deleting both; a declaration with either
left counts as a stub in the coverage summary, not as implemented.

Types map the way Perry's hand-written providers already do: `NSString *`
as `String?`, objects as `NSObject?` or Perry's own class, `SEL` as
`ObjCSelector?`, blocks and other pointers as `UnsafeMutableRawPointer?`,
geometry and the structs `DarwinCMacro.swift` lists as themselves. A
signature the map can't type is skipped and reported, never guessed.

Not every neutral value is safe. The generator takes an allowlist of
families where doing nothing is right on Perry (accessibility, Touch Bar,
Handoff and user activities, haptics, services menu, spell checking,
printing panels) and generates the rest only with `--all`. A method that
must do something (drawing, layout, events, data) is reported for a hand
implementation instead.

Order: AppKit classes apps subclass or put in nibs, then AppKit methods by
demand, then Foundation's C functions and constants, then Foundation
methods. One class or file per commit, one PR per batch.

## Phase 6: the rest of the SDKs

The same commands per framework, in order of demand from Phase 3:

1. Foundation on iOS (its iOS-only API), then UIKit (UIKitCore's public
   part), against PerryUIKit.
2. The frameworks with a Perry provider already: Core Graphics, Quartz
   Core, Core Data, AVFoundation, Core Location, Security, StoreKit, Game
   Kit, MapKit, WebKit, and the rest of `Sources/Perry*`.
3. Frameworks with none: generated as a new provider only when the demand
   list shows apps linking them non-weakly, since a missing framework now
   fails at load where a stubbed one would run.
4. Older SDKs for perry32 and the 32-bit loaders (iOS 9 for armv7, Mac OS X
   10.6 for i386 and ppc), whose API has since been removed.
5. Swift API in the frameworks themselves (AppKit.framework's diffable
   data sources, `NSViewController.ViewLoading`, the macOS 26 and 27
   notification messages): generated as Swift source from the
   `.swiftinterface` declarations, so the compiler produces the mangled
   names, keeping every `@frozen` attribute and stored property exactly as
   the interface declares them or values pass garbled.

## Testing

- `Scripts/sdk-scan/Tests/SDKScanTests`: a small fake SDK (a framework with two headers, a
  `.tbd`, a category in another framework) checked into Tests as fixtures;
  scan, diff and stub output compared with expected JSON and Swift.
- The generated providers build on the Duet 3 and the Chromebook with
  `--build-system native`, like any provider.
- A Darwin fixture (`Scripts/build-darwin-fixtures.sh`) that subclasses a
  stubbed AppKit class, calls a stubbed method and a stubbed C function,
  and checks the neutral results and the trace lines.
- Regression runs of the apps that work today (TextMate, NetNewsWire,
  MacDown, LightBlue, Govee) after each batch, since a stub can send an
  app down a code path it never took before.

## Risks and open items

- **Feature checks.** `respondsToSelector:`, `NSClassFromString` and weak
  imports answer yes once stubbed. The allowlist and per-app regression
  runs are the guard; a generated stub can be marked hidden from
  `respondsToSelector:` if an app shows it matters.
- **`init` stubs.** Returning `self` from an initializer whose class keeps
  state in ivars leaves them zero; returning `nil` breaks callers that
  don't check. The generator returns `self` and the trace shows which.
- **Selector ambiguity.** A selector referenced by an app is paired with
  every SDK class declaring it, which over-counts demand for common names
  (`setTitle:`). The called set from `continue` runs corrects it.
- **Constant values.** Defaulting to the constant's name is wrong for some;
  the check runs on a Mac and only its results are committed.
- **`-extract-api` off the Mac.** The Swift 6.4.2 toolchain's clang has
  it (the tests pass with it on Linux); `swift-symbolgraph-extract` off
  the Mac is untested.
- **Committing the coverage summary.** It lists Apple's API names in bulk;
  if that is not wanted, it stays in `.build/` with the manifests.
