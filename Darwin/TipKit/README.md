# TipKit

Perry's `TipKit.framework`: the Swift API apps declare their tips with (the
`Tip` protocol, rules, events, parameters, options, actions, `Tips.configure`
and `TipUIView`). Nothing is stored and no tip is ever eligible, so tips stay
pending and their views show nothing.
`Scripts/build-framework.sh TipKit` builds it on a Mac into the Swift runtime
directory (`PERRY_SWIFT_RUNTIME`), where the loader finds it.

Declarations follow the iOS SDK's TipKit interface, so apps built against
Apple's bind to them by the same symbols. The SwiftUI views and modifiers
(`TipView`, `popoverTip`, view styles), `TipGroup` and the collection view
classes aren't here yet.
