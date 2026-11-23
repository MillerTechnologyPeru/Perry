# Contacts

Perry's Swift overlay of Contacts: `CNError`'s affected records, record
identifiers and key paths, and `CNContact` as `Identifiable` with its
descriptions, written for Perry from the API in the macOS SDK's
`Contacts.swiftinterface` files (the overlay's in `usr/lib/swift` and the
framework's own). It replaces the Swift 5.0 overlay Xcode ships as a file,
which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `Contacts` over the SDK's headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Contacts <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay and the SDK's
`libswiftContacts.tbd` (which only re-exports the framework) reports
nothing missing.

`CNContact.id` is the UUID a store identifier starts with; for an
identifier that isn't one, a UUID made from its bytes (the same one each
time). `description` and `debugDescription` are Objective-C overrides
added to `CNContact`, as the framework's interface declares them: the
class, address, identifier and the names that were fetched.
