# CoreData

Perry's Swift overlay of Core Data: Core Data's error codes as
`CocoaError.Code` values (under their current names, the deprecated ones
ending in `Error` and `CocoaError`'s capitalized Swift 3 ones), the
userInfo of its errors as `CocoaError` properties, and fetching and
counting with a fetch request's result type, as the Swift 5.0 overlay
Xcode ships as a file had them, which a runtime directory made for an
x86_64 Mac app used to take. Beside them is the API newer than that
overlay that Perry's apps have needed: running blocks on a context's
queue from async code (`perform(schedule:_:)`, `ScheduledTaskType`,
`performAndWait` returning the block's result), which was
`Darwin/CoreDataAdditions` (`libswiftCoreDataAdditions.dylib`, now not
needed; one left in a runtime directory is only searched after this
overlay), and the untyped `fetch(_:)` returning `[Any]`.

Core Data's Swift API has since moved into the framework itself (its
`CoreData.swiftmodule` is in `CoreData.framework`, and the SDK's
`libswiftCoreData.tbd` lists no Swift symbols), so the 5.0 overlay is what
`libswiftCoreData.dylib` must still export; the rest of the framework's
Swift API (store and attribute types, the notifications' Swift names,
the context's notification payloads) isn't here. The declarations
of the additions are the framework interface's, for its ABI.

It is compiled as the module `CoreData` over the SDK's Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreData <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftCoreData` symbol
programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftCoreData.tbd`: nothing is missing.
