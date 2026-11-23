# Photos

Perry's Swift overlay of Photos: project change requests taking Swift
collections, `PHChange`'s change details, cloud and local identifier
mappings as `Result`s, `PHPersistentChangeFetchResult` as a `Sequence`,
`PHAssetResource.dataSize`, and the iOS 26 and 27 additions
(`PHReferenceImageInfo`, the background resource upload extensions and
their result), written for Perry from the API in the macOS SDK's
`Photos.swiftinterface`. It replaces the Swift 5.0 overlay Xcode ships as a
file, which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `Photos` over the SDK's headers (and imports
CloudKit and ExtensionFoundation, whose types its API uses):

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Photos <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay reports nothing
missing; against the SDK's `libswiftPhotos.tbd` (the framework's own Swift
symbols) it reports 35, all Apple-private SPI with no public declaration
and Objective-C behind them that the headers don't declare:

- `PHAssetResourceFetchResult` as a `Collection` and its `Iterator` (no
  such class in the headers);
- `PHAssetChangeRequest.undoDeleteAssets(_:)`,
  `PHAssetCollectionChangeRequest.undoDeleteAssetCollections(_:)` and
  `PHCollectionListChangeRequest.undoDeleteCollectionLists(_:)`;
- `PHPhotoLibrary.reserveCloudIdentifiers(objectType:count:)`,
  `allReservedCloudIdentifiers(objectType:)`, both
  `cancelReservedCloudIdentifiers` and
  `cloudIdentifierMappings(forLocalIdentifiers:excludeUnsyncedItems:)`.

The private `PHAssetProvenanceInfo` and
`PHReferenceImageInfo.isProvenanceProcessed`, pure Swift, are provided as
`@_spi(Private)`.

What can't work here: Apple Reference Image and provenance data have no
published format, so `imageContainsReferenceImageData` (and the provenance
info) answer false, which tells an app to hide its controls;
`PHAssetResourceManager.exportedAssetID(for:)` needs a library that uses
iCloud Photos and fails as Photos does for one that doesn't, with
`PHPhotosError.requestNotSupportedForAsset`; the upload extensions'
configuration accepts no connection, as no host here talks Photos'
private XPC protocol to them.
