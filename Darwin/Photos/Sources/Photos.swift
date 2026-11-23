// Photos' Swift API, over the Objective-C methods its headers refine for
// Swift: project change requests taking Swift collections, cloud and local
// identifier mappings as Results, persistent change fetch results as
// sequences, a resource's size as an Int, and the iOS 26 and 27 additions
// (reference image info, background upload extensions).

import CloudKit
import ExtensionFoundation
import Foundation

// MARK: - Project change requests

@available(macOS 10.13, *)
extension PHProjectChangeRequest {
    /// Removes the assets of a collection from the project.
    @available(macOS 10.14, *)
    public func removeAssets<T>(_ assets: T) where T: Collection, T.Element == PHAsset {
        __removeAssets(Array(assets) as NSArray)
    }

    /// Removes the assets of a fetch result from the project.
    @available(macOS 10.14, *)
    public func removeAssets(_ assets: PHFetchResult<PHAsset>) {
        __removeAssets(assets)
    }
}

// MARK: - Change details

@available(iOS 8.0, tvOS 10.0, macOS 10.13, *)
extension PHChange {
    /// The changes to an object, nil if it didn't change.
    public func changeDetails<T>(for object: T) -> PHObjectChangeDetails<T>? where T: PHObject {
        __changeDetails(for: object).map { unsafeDowncast($0, to: PHObjectChangeDetails<T>.self) }
    }

    /// The changes to a fetch result's objects, nil if none changed.
    public func changeDetails<T>(for fetchResult: PHFetchResult<T>) -> PHFetchResultChangeDetails<T>? where T: PHObject {
        __changeDetails(for: unsafeDowncast(fetchResult, to: PHFetchResult<AnyObject>.self))
            .map { unsafeDowncast($0, to: PHFetchResultChangeDetails<T>.self) }
    }

    /// The changes to a fetch result's objects, nil if none changed.
    public func changeDetails(for fetchResult: PHFetchResult<AnyObject>) -> PHFetchResultChangeDetails<PHObject>? {
        __changeDetails(for: fetchResult)
    }
}

// MARK: - Cloud identifiers

@available(iOS 15, tvOS 15, macOS 12, *)
@available(watchOS, unavailable)
extension PHPhotoLibrary {
    /// The cloud identifier of each local identifier, or why there is none.
    public func cloudIdentifierMappings(forLocalIdentifiers localIdentifiers: [String]) -> [String: Result<PHCloudIdentifier, any Error>] {
        __cloudIdentifierMappings(forLocalIdentifiers: localIdentifiers).mapValues { mapping in
            if let identifier = mapping.cloudIdentifier {
                return .success(identifier)
            }
            return .failure(mapping.error ?? PHPhotosError(.identifierNotFound))
        }
    }

    /// The local identifier of each cloud identifier, or why there is none.
    public func localIdentifierMappings(for cloudIdentifiers: [PHCloudIdentifier]) -> [PHCloudIdentifier: Result<String, any Error>] {
        results(of: __localIdentifierMappings(for: cloudIdentifiers))
    }

    /// The local identifier of each cloud identifier synced through iCloud
    /// Photos, without matching media content, or why there is none.
    @available(iOS 27, tvOS 27, macOS 27, visionOS 27, *)
    @available(watchOS, unavailable)
    public func localIdentifierMappings(forSynced cloudIdentifiers: [PHCloudIdentifier]) -> [PHCloudIdentifier: Result<String, any Error>] {
        results(of: __localIdentifierMappings(forSyncedCloudIdentifiers: cloudIdentifiers))
    }

    private func results(of mappings: [PHCloudIdentifier: __PHLocalIdentifierMapping]) -> [PHCloudIdentifier: Result<String, any Error>] {
        mappings.mapValues { mapping in
            if let identifier = mapping.localIdentifier {
                return .success(identifier)
            }
            return .failure(mapping.error ?? PHPhotosError(.identifierNotFound))
        }
    }
}

// MARK: - Persistent changes

@available(iOS 16, macOS 13, tvOS 16, *)
@available(watchOS, unavailable)
extension PHPersistentChangeFetchResult: Sequence {
    /// Iterates the changes of a fetch result, in order. The changes are
    /// enumerated when the iterator is made, as the fetch result can only
    /// be enumerated with a block.
    final public class Iterator: IteratorProtocol {
        public typealias Element = PHPersistentChange

        private var changes: [PHPersistentChange] = []
        private var index = 0

        public init(fetchResult: PHPersistentChangeFetchResult) {
            var changes: [PHPersistentChange] = []
            fetchResult.__enumerateChanges { change, _ in
                changes.append(change)
            }
            self.changes = changes
        }

        final public func next() -> Element? {
            guard index < changes.count else { return nil }
            defer { index += 1 }
            return changes[index]
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(fetchResult: self)
    }

    @available(macOS 13, iOS 16, tvOS 16, *)
    @available(watchOS, unavailable)
    public typealias Element = Iterator.Element
}

// MARK: - Asset resources

@available(iOS 27, tvOS 27, macOS 27, visionOS 27, *)
@available(watchOS, unavailable)
extension PHAssetResourceManager {
    /// The CloudKit asset iCloud Photos stores the resource's data as.
    /// This needs a library that uses iCloud Photos, which no library
    /// here does, so the request fails as Photos fails it for such a
    /// library, with PHPhotosError.requestNotSupportedForAsset.
    public func exportedAssetID(for resource: PHAssetResource) async throws -> CKAsset.ExportedAssetID {
        try Task.checkCancellation()
        throw PHPhotosError(.requestNotSupportedForAsset)
    }
}

@available(iOS 27, tvOS 27, macOS 27, visionOS 27, *)
@available(watchOS, unavailable)
extension PHAssetResource {
    /// The size of the resource in bytes, nil while it isn't known.
    public var dataSize: Int? {
        __dataSize?.intValue
    }
}

// MARK: - Reference images

/// Whether an image file or a photo holds Apple Reference Image data.
/// Its format is not published, so none is recognized here: the info
/// answers false, which tells an app to hide its reference image controls.
@available(iOS 27.0, macOS 27.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
public class PHReferenceImageInfo: @unchecked Sendable {
    private let source: ImageSource

    /// An info of a HEIC, JPEG or DNG file.
    public init(fileURL: URL) {
        source = .file(fileURL)
    }

    /// An info of a photo of the library.
    public init(asset: PHAsset) {
        source = .asset(asset)
    }

    /// Whether the image holds Apple Reference Image data: never known here.
    public var imageContainsReferenceImageData: Bool {
        false
    }

    deinit {}
}

@available(iOS 27.0, macOS 27.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension PHReferenceImageInfo {
    /// Whether the image's provenance was processed: not here.
    @_spi(Private)
    public var isProvenanceProcessed: Bool {
        false
    }
}

/// Where an info's image is.
private enum ImageSource {
    case file(URL)
    case asset(PHAsset)
}

/// Photos' private info of an image's provenance data, the counterpart of
/// PHReferenceImageInfo: no provenance data is recognized here.
@_spi(Private)
@available(iOS 27.0, macOS 27.0, *)
public class PHAssetProvenanceInfo: @unchecked Sendable {
    private let source: ImageSource

    public init(fileURL: URL) {
        source = .file(fileURL)
    }

    public init(asset: PHAsset) {
        source = .asset(asset)
    }

    /// Whether the image holds provenance data: never known here.
    public var imageContainsProvenanceData: Bool {
        false
    }

    /// Whether the image's provenance was processed: not here.
    public var isProvenanceProcessed: Bool {
        false
    }

    deinit {}
}

// MARK: - Background resource upload extensions

/// What a background upload extension's processing came to.
@available(iOS 26.1, macOS 27.0, macCatalyst 27.0, *)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
public enum PHBackgroundResourceUploadProcessingResult: Int {
    case failure
    case processing
    case completed

    public init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .failure
        case 1: self = .processing
        case 2: self = .completed
        default: return nil
        }
    }

    @available(macOS 27.0, iOS 26.1, macCatalyst 27.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @available(visionOS, unavailable)
    public typealias RawValue = Int

    public var rawValue: Int {
        switch self {
        case .failure: 0
        case .processing: 1
        case .completed: 2
        }
    }
}

@available(iOS 26.1, macOS 27.0, macCatalyst 27.0, *)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension PHBackgroundResourceUploadProcessingResult: Equatable {}

@available(iOS 26.1, macOS 27.0, macCatalyst 27.0, *)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension PHBackgroundResourceUploadProcessingResult: Hashable {}

/// iOS 26.1's background upload extension.
@available(iOS, introduced: 26.1, deprecated: 27.0, message: "Adopt PHBackgroundResourceUploadJobExtension instead")
@available(macOS, unavailable)
@available(macCatalyst, unavailable)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
public protocol PHBackgroundResourceUploadExtension: AppExtension {
    func process() -> PHBackgroundResourceUploadProcessingResult
    func notifyTermination()
}

/// The background upload extension of iOS and macOS 27.
@available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
public protocol PHBackgroundResourceUploadJobExtension: AppExtension {
    func processJobs() async -> PHBackgroundResourceUploadProcessingResult
    func willTerminate() async
}

/// The configuration of Photos' upload extensions. Photos talks to its
/// extensions over a private XPC interface no host here offers, so the
/// configuration accepts no connection.
@available(iOS 26.1, macOS 27.0, *)
private struct UploadExtensionConfiguration: AppExtensionConfiguration {
    nonisolated func accept(connection: NSXPCConnection) -> Bool {
        false
    }
}

@available(iOS, introduced: 26.1, deprecated: 27.0, message: "Adopt PHBackgroundResourceUploadJobExtension instead")
@available(macOS, unavailable)
@available(macCatalyst, unavailable)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension PHBackgroundResourceUploadExtension {
    public var configuration: some AppExtensionConfiguration {
        UploadExtensionConfiguration()
    }
}

@available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
@available(watchOS, unavailable)
extension PHBackgroundResourceUploadJobExtension {
    public var configuration: some AppExtensionConfiguration {
        UploadExtensionConfiguration()
    }
}
