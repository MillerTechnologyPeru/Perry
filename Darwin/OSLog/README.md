# OSLog

Perry's Swift overlay of OSLog, written for Perry from the API in the iOS
SDK's `OSLog.swiftinterface`: `OSLogStore.getEntries(with:at:matching:)`,
a store's entries as a Swift sequence over its Objective-C enumerator, and
`OSLogMessageComponent.Argument`, a message argument's value by its
category. It replaces the iOS Simulator's `libswiftOSLog.dylib`, which a
runtime directory for iOS apps used to take.

    Scripts/build-overlay.sh OSLog <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftOSLog` symbol
programs built against the overlay reference. `Scripts/check-overlay.sh`
finds nothing missing against the simulator's library (the iOS SDK's
`libswiftOSLog.tbd` re-exports the framework and lists none of its own).

An argument whose data or string can't be decoded is `.undefined`, as its
category says nothing about it then.
