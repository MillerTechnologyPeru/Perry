# Combine

Perry's Combine.framework: OpenCombine, built as the Swift module `Combine`
for iOS arm64 with library evolution, so apps built against Apple's Combine
bind to it by the same Swift symbols. `Scripts/build-combine.sh` builds it on
a Mac into the Swift runtime directory (`PERRY_SWIFT_RUNTIME`), where the
loader finds `Combine.framework/Combine` and loads it as a Mach-O image.

## Sources

- `Sources` and `Helpers`: OpenCombine (https://github.com/OpenCombine/OpenCombine)
  at 1c6f02c, without its `.gyb` templates (the generated files are kept).
- `Publishers/Publishers.CombineLatest.swift` and `Publishers/Publishers.Merge.swift`:
  the OpenSwiftUIProject fork (https://github.com/OpenSwiftUIProject/OpenCombine)
  at 5ea4600; upstream has neither.

Both are MIT licensed; see `LICENSE`.

## Changes for Apple's ABI

Apple's interface (the iOS SDK's `Combine.swiftinterface`) is the reference:

- `OpenCombine.` qualifiers are `Combine.`.
- Types Apple declares `@frozen` or `@_fixed_layout` are declared so.
- `@inlinable` is removed: apps already carry Apple's inlinable code, and
  only need the `@usableFromInline` declarations it calls.
- `Result.Publisher` and `Optional.Publisher` are nested as Apple nests them,
  not in OpenCombine's `OCombine` namespaces.

Compare the exported Swift symbols with the SDK's `Combine.tbd` to find what
is still missing.
