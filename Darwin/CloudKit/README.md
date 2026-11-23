# CloudKit

Perry's Swift overlay of CloudKit: records and record values as Swift
types, the identifiers' Swift initializers, the operations' per-item and
operation `Result` blocks, `CKDatabase`'s and `CKContainer`'s async and
`Result`-based fetches and changes, configured databases and containers,
subscriptions, shares (with `CKShareTransferRepresentation` and
`NSItemProvider` registration) and `CKSyncEngine`, written for Perry from
the API in the macOS SDK's `CloudKit.swiftinterface`. It replaces the
Swift 5.0 overlay Xcode ships as a file, which a runtime directory made for
an x86_64 Mac app used to take.

It is compiled as the module `CloudKit` over the SDK's headers, and works
over the Objective-C API the headers and API notes keep for Swift (the
`__` names): CloudKit's classes and operations do the work.

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CloudKit <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay reports nothing
missing. Against the SDK's `libswiftCloudKit.tbd` (the framework's own
Swift symbols) it reports about 2,000, none of them of a declaration of
the public interface: Apple-private SPI and the framework's internals,
such as `CKSyncEngine`'s asset fetching (`FetchAssetsOptions`,
`PendingAssetSync`, `Event.FetchedAsset`), its private configuration
(`delegatePrivate`, `apsMachServiceName`, push topics, XPC activity
criteria), `SendChangesContext.syncPhase`, `CKRecordZone.Reference`,
`CKAsset.ID`/`Signature`, `CKRecord.FetchConfiguration`, server
timestamps, feature sets and device capabilities, session acquisition,
`APSConnection` notifications, the private `CKError`
members (`underlyingError`, `movedDestinationID`, …), and the setters and
memberwise initializers of change values whose public interface is
read-only. The `@_alwaysEmitIntoClient` functions (`record(for:)`,
`save(_:)`, `allRecordZones()`, …) have no symbols; the
`@usableFromInline` ones they call are all here.

How things are done here:

- `configuredWith(configuration:group:body:)` runs the body with the same
  database or container; the operations this overlay makes in it (its
  fetches and modifications) get the configuration and group, through a
  task-local value (thread-local for the synchronous form). Calls the body
  makes straight to the Objective-C API don't.
- `CKSyncEngine`'s Objective-C delegate methods are synchronous, so each
  waits on a semaphore for the Swift delegate's async method.
- `CKShareTransferRepresentation` and `ExportedShare` hand the share over
  as its URL (`.url` data), made when it is asked for.
- `CKAsset.ExportedAssetID` is decoded and encoded as its identifier;
  `CKAsset(importing:)` can't reach an exported asset's data (no service
  exports one here) and makes an asset of an empty file.
- `NSItemProvider.registerCKShare` calls the Objective-C methods through
  their implementations, as they have the same Swift names.
